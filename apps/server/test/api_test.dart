/// Интеграционные тесты REST API (FR-6, M4).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:perechen_core/perechen_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestHarness harness;
  late Uri baseUri;
  final client = http.Client();

  final sourceFile = buildSourceXlsx(
    actualityDate: DateTime(2026, 8, 14, 17, 28),
    rows: [
      row(
        ordinal: '1',
        inclusionNumber: '1076-р',
        rawName: '«Национальный фонд в поддержку демократии» '
            '(The National Endowment for Democracy)',
      ),
      row(
        ordinal: '2',
        inclusionNumber: '1777-р',
        inclusionDate: '01.12.2015',
        gpDecisionDate: '26.11.2015',
        rawName: 'Институт Открытое Общество Фонд Содействия '
            '(OSI Assistance Foundation) (США)',
      ),
    ],
  );

  Map<String, String> auth({String user = 'admin', String password = 'secret'}) =>
      {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$user:$password'))}',
      };

  Future<Map<String, Object?>> getJson(String path,
      {Map<String, String>? headers}) async {
    final response =
        await client.get(baseUri.resolve(path), headers: headers ?? auth());
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
  }

  setUp(() async {
    harness = TestHarness.create(responses: [sourceFile]);
    await harness.app.start();
    baseUri = harness.app.address!;
  });

  tearDown(() async {
    await harness.dispose();
  });

  group('авторизация (Р-7)', () {
    test('без заголовка — 401 и WWW-Authenticate', () async {
      final response = await client.get(baseUri.resolve('/api/health'));
      expect(response.statusCode, 401);
      expect(response.headers['www-authenticate'], contains('Basic'));
    });

    test('неверный пароль — 401', () async {
      final response = await client.get(
        baseUri.resolve('/api/health'),
        headers: auth(password: 'wrong'),
      );
      expect(response.statusCode, 401);
    });

    test('верные данные — 200', () async {
      final response =
          await client.get(baseUri.resolve('/api/health'), headers: auth());
      expect(response.statusCode, 200);
    });
  });

  group('GET /api/health', () {
    test('отдаёт состояние сервиса и расписания', () async {
      final health = await getJson('/api/health');
      expect(health['status'], 'ok');
      expect(health['timeZone'], 'Europe/Moscow');
      expect(health['downloadCron'], '0 6 * * *');
      expect(health['autoPublishCron'], '0 20 * * *');
      expect(health['lastCheckAt'], isNull);
      expect(health['nextRunAt'], isNotNull);
    });

    test('после проверки заполняется время последней проверки', () async {
      await client.post(baseUri.resolve('/api/jobs/check-now'), headers: auth());
      final health = await getJson('/api/health');
      expect(health['lastCheckAt'], isNotNull);
      expect(health['lastCheckStatus'], 'new_version');
      expect(health['latestVersionId'], isNotNull);
    });
  });

  group('версии и записи', () {
    late int versionId;

    setUp(() async {
      final response = await client.post(
        baseUri.resolve('/api/jobs/check-now'),
        headers: auth(),
      );
      final outcome =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      versionId = outcome['versionId']! as int;
    });

    test('POST /api/jobs/check-now создаёт версию', () async {
      final versions = await getJson('/api/versions');
      final list = versions['versions']! as List<Object?>;
      expect(list, hasLength(1));
      final version = list.single! as Map<String, Object?>;
      expect(version['status'], 'PENDING_REVIEW');
      expect(version['actualityDate'], '2026-08-14T17:28:00+03:00');
      expect(version['targetFileName'],
          'perechen_organizatsij_272_FZ_2026_08_14.csv');
      expect((version['counters']! as Map)['total'], 2);
    });

    test('GET /api/versions/{id} отдаёт карточку версии', () async {
      final version = await getJson('/api/versions/$versionId');
      expect(version['id'], versionId);
      expect(version['fileSha256'], isNotEmpty);
    });

    test('GET /api/versions/{id} на несуществующей версии — 404', () async {
      final response = await client.get(
        baseUri.resolve('/api/versions/9999'),
        headers: auth(),
      );
      expect(response.statusCode, 404);
    });

    test('GET /api/versions/{id}/records отдаёт разбор и сырую строку',
        () async {
      final payload = await getJson('/api/versions/$versionId/records');
      final records = payload['records']! as List<Object?>;
      expect(records, hasLength(2));
      final first = records.first! as Map<String, Object?>;
      expect(first['orgKey'], '1076-р__2015-07-29');
      expect((first['values']! as Map)['name_rus'],
          'Национальный фонд в поддержку демократии');
      expect((first['values']! as Map)['name_add'],
          'The National Endowment for Democracy');
      expect(first['rawName'], contains('Национальный фонд'));
      expect(first['candidates'], isNotEmpty);
    });

    test('фильтры и поиск', () async {
      final review = await getJson(
        '/api/versions/$versionId/records?filter=review',
      );
      expect(review['filter'], 'review');

      final search = await getJson(
        '/api/versions/$versionId/records?search=${Uri.encodeQueryComponent('OSI')}',
      );
      final found = search['records']! as List<Object?>;
      expect(found, hasLength(1));
      expect((found.single! as Map)['orgKey'], '1777-р__2015-12-01');
    });

    test('PATCH /api/records/{versionId}/{orgKey} сохраняет правку', () async {
      final response = await client.patch(
        baseUri.resolve('/api/records/$versionId/'
            '${Uri.encodeComponent('1076-р__2015-07-29')}'),
        headers: {...auth(), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'values': {'country': 'Соединенные Штаты Америки'},
        }),
      );
      expect(response.statusCode, 200);
      final record =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      expect((record['values']! as Map)['country'], 'Соединенные Штаты Америки');
      expect(record['editedFields'], contains('country'));

      final version = await getJson('/api/versions/$versionId');
      expect((version['counters']! as Map)['edited'], 1);
    });

    test('PATCH с revert возвращает автоматический разбор', () async {
      final path = '/api/records/$versionId/'
          '${Uri.encodeComponent('1076-р__2015-07-29')}';
      await client.patch(
        baseUri.resolve(path),
        headers: {...auth(), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'values': {'name_rus': 'Ручное значение'},
        }),
      );
      final response = await client.patch(
        baseUri.resolve(path),
        headers: {...auth(), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'revert': ['name_rus'],
        }),
      );
      final record =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      expect((record['values']! as Map)['name_rus'],
          'Национальный фонд в поддержку демократии');
      expect(record['editedFields'], isEmpty);
    });

    test('PATCH с неизвестным полем — 400', () async {
      final response = await client.patch(
        baseUri.resolve('/api/records/$versionId/'
            '${Uri.encodeComponent('1076-р__2015-07-29')}'),
        headers: {...auth(), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'values': {'unknown_field': 'x'},
        }),
      );
      expect(response.statusCode, 400);
    });

    test('GET /api/versions/{id}/export.csv отдаёт cp1251 и CRLF', () async {
      final response = await client.get(
        baseUri.resolve('/api/versions/$versionId/export.csv'),
        headers: auth(),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('windows-1251'));
      expect(
        response.headers['content-disposition'],
        contains('perechen_organizatsij_272_FZ_2026_08_14.csv'),
      );
      const encoder = Cp1251Encoder();
      final text = encoder.decode(response.bodyBytes);
      expect(text.startsWith(';Номер и дата распоряжения'), isTrue);
      expect(text.endsWith('\r\n'), isTrue);
      expect(response.bodyBytes.sublist(0, 3), isNot([0xEF, 0xBB, 0xBF]));
    });

    test('POST /api/versions/{id}/confirm публикует файл', () async {
      final response = await client.post(
        baseUri.resolve('/api/versions/$versionId/confirm'),
        headers: auth(),
      );
      expect(response.statusCode, 200);
      final payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      expect(payload['status'], 'published');
      expect(payload['fileName'],
          'perechen_organizatsij_272_FZ_2026_08_14.csv');
      expect(payload['rows'], 2);
      expect(harness.cdiFiles, [payload['fileName']]);
      expect(
        ((payload['version']! as Map)['status']),
        'PUBLISHED',
      );
    });

    test('GET /api/events отдаёт журнал', () async {
      final payload = await getJson('/api/events');
      final events = payload['events']! as List<Object?>;
      final types = events.map((e) => (e! as Map)['type']).toSet();
      expect(types, contains('check_started'));
      expect(types, contains('version_created'));
      expect(types, contains('download_ok'));
    });

    test('GET /api/corrections/{orgKey} отдаёт историю правок', () async {
      await client.patch(
        baseUri.resolve('/api/records/$versionId/'
            '${Uri.encodeComponent('1076-р__2015-07-29')}'),
        headers: {...auth(), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'values': {'country': 'США'},
        }),
      );
      final payload = await getJson(
        '/api/corrections/${Uri.encodeComponent('1076-р__2015-07-29')}',
      );
      final corrections = payload['corrections']! as List<Object?>;
      expect(corrections, hasLength(1));
      expect((corrections.single! as Map)['author'], 'admin');
    });

    test('POST /api/versions/{id}/reparse пересобирает версию', () async {
      final response = await client.post(
        baseUri.resolve('/api/versions/$versionId/reparse'),
        headers: auth(),
      );
      expect(response.statusCode, 200);
      final payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      expect((payload['counters']! as Map)['total'], 2);
    });
  });

  group('раздача UI', () {
    test('без собранного UI отдаётся понятное сообщение', () async {
      final response = await client.get(baseUri.resolve('/'), headers: auth());
      expect(response.statusCode, 404);
      expect(utf8.decode(response.bodyBytes), contains('flutter build web'));
    });
  });
}
