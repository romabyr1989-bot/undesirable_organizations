/// Тесты экрана «Настройки»: адрес первоисточника и папка выгрузки правятся
/// из UI без перезапуска службы.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:perechen_server/src/config/runtime_settings.dart';
import 'package:perechen_server/src/db/database.dart';
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
    ],
  );

  Map<String, String> auth() => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('admin:secret'))}',
        'Content-Type': 'application/json; charset=utf-8',
      };

  Future<Map<String, Object?>> getSettings() async {
    final response =
        await client.get(baseUri.resolve('api/settings'), headers: auth());
    expect(response.statusCode, HttpStatus.ok);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
  }

  Future<http.Response> putSettings(Map<String, Object?> body) => client.put(
        baseUri.resolve('api/settings'),
        headers: auth(),
        body: jsonEncode(body),
      );

  Map<String, Object?> field(Map<String, Object?> settings, String name) =>
      (settings[name]! as Map).cast<String, Object?>();

  setUp(() async {
    harness = TestHarness.create(responses: [sourceFile]);
    await harness.app.start();
    baseUri = harness.app.address!;
  });

  tearDown(() async {
    await harness.dispose();
  });

  group('чтение настроек', () {
    test('без правок отдаёт значения из конфигурации', () async {
      final settings = await getSettings();

      final exportUrl = field(settings, 'minjustExportUrl');
      expect(exportUrl['value'], 'https://minjust.example/export.xlsx');
      expect(exportUrl['fromConfig'], 'https://minjust.example/export.xlsx');
      expect(exportUrl['overridden'], isFalse);

      final cdi = field(settings, 'cdiDropDir');
      expect(cdi['value'], harness.config.cdiDropDir);
      expect(cdi['overridden'], isFalse);

      expect(settings['updatedAt'], isNull);
      expect(settings['updatedBy'], isNull);
    });

    test('после правки показывает и действующее значение, и конфигурацию',
        () async {
      await putSettings({'minjustExportUrl': 'https://new.example/list.xlsx'});

      final exportUrl = field(await getSettings(), 'minjustExportUrl');
      expect(exportUrl['value'], 'https://new.example/list.xlsx');
      expect(exportUrl['fromConfig'], 'https://minjust.example/export.xlsx');
      expect(exportUrl['overridden'], isTrue);
    });
  });

  group('адрес первоисточника', () {
    test('правка применяется к следующей загрузке без перезапуска', () async {
      final response =
          await putSettings({'minjustExportUrl': 'https://new.example/list.xlsx'});
      expect(response.statusCode, HttpStatus.ok);

      harness.requestedUrls.clear();
      await harness.app.service.checkNow(trigger: 'test');

      expect(harness.requestedUrls, contains('https://new.example/list.xlsx'));
    });

    test('пустая ссылка переводит на разбор страницы перечня', () async {
      harness.serve([
        '<html><body><a href="https://minjust.example/from-page.xlsx">'
            'Экспорт</a></body></html>',
        sourceFile,
      ]);
      await putSettings({
        'minjustExportUrl': '',
        'minjustPageUrl': 'https://minjust.example/perechen/',
      });

      harness.requestedUrls.clear();
      await harness.app.service.checkNow(trigger: 'test');

      expect(harness.requestedUrls.first, 'https://minjust.example/perechen/');
      expect(
        harness.requestedUrls,
        contains('https://minjust.example/from-page.xlsx'),
      );
    });

    test('адрес без схемы отклоняется', () async {
      final response = await putSettings({'minjustExportUrl': 'minjust.ru/f.xlsx'});

      expect(response.statusCode, HttpStatus.badRequest);
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      expect(body['field'], 'minjustExportUrl');
      expect('${body['error']}', contains('http'));

      final exportUrl = field(await getSettings(), 'minjustExportUrl');
      expect(exportUrl['value'], 'https://minjust.example/export.xlsx',
          reason: 'отклонённая правка не должна ничего менять');
    });

    test('оба адреса пустыми быть не могут', () async {
      final response = await putSettings({
        'minjustExportUrl': '',
        'minjustPageUrl': '',
      });

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        '${(jsonDecode(utf8.decode(response.bodyBytes)) as Map)['error']}',
        contains('хотя бы один адрес'),
      );
    });
  });

  group('папка выгрузки', () {
    test('правка меняет, куда попадёт CSV при публикации', () async {
      final newDir = Directory('${harness.tempDir.path}/cdi-new');

      final response = await putSettings({'cdiDropDir': newDir.path});
      expect(response.statusCode, HttpStatus.ok);
      expect(newDir.existsSync(), isTrue,
          reason: 'папку создаём сразу, чтобы проверить доступность');

      await harness.app.service.checkNow(trigger: 'test');
      final version = harness.db.latestVersion()!;
      harness.app.service.confirm(version.id, 'tester');

      final published = newDir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(published, hasLength(1));
      expect(published.single, endsWith('.csv'));
    });

    test('относительный путь отклоняется', () async {
      final response = await putSettings({'cdiDropDir': 'cdi/inbox'});

      expect(response.statusCode, HttpStatus.badRequest);
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      expect(body['field'], 'cdiDropDir');
      expect('${body['error']}', contains('полный путь'));
    });

    test('пустое значение отклоняется', () async {
      final response = await putSettings({'cdiDropDir': '   '});

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        '${(jsonDecode(utf8.decode(response.bodyBytes)) as Map)['error']}',
        contains('укажите папку'),
      );
    });

    test('недоступная папка отклоняется с причиной', () async {
      // Файл вместо папки: создать каталог по этому пути нельзя.
      final blocker = File('${harness.tempDir.path}/not-a-dir')
        ..writeAsStringSync('');

      final response = await putSettings({'cdiDropDir': blocker.path});

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        '${(jsonDecode(utf8.decode(response.bodyBytes)) as Map)['error']}',
        anyOf(contains('не удалось создать'), contains('нельзя записывать')),
      );
    });

    test('/api/health показывает действующую папку', () async {
      final newDir = '${harness.tempDir.path}/cdi-health';
      await putSettings({'cdiDropDir': newDir});

      final response =
          await client.get(baseUri.resolve('api/health'), headers: auth());
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;

      expect(body['cdiDropDir'], newDir);
    });
  });

  group('расписание', () {
    test('правка применяется к планировщику без перезапуска', () async {
      final before = harness.app.scheduler.jobs
          .firstWhere((job) => job.name == 'download')
          .schedule
          .toString();
      expect(before, '0 6 * * *');

      final response = await putSettings({'downloadCron': '30 7 * * 1-5'});
      expect(response.statusCode, HttpStatus.ok);

      final after = harness.app.scheduler.jobs
          .firstWhere((job) => job.name == 'download')
          .schedule;
      expect(after.toString(), '30 7 * * 1-5');
      expect(after.matches(DateTime(2026, 8, 25, 7, 30)), isTrue,
          reason: 'вторник 07:30 — рабочий день');
      expect(after.matches(DateTime(2026, 8, 25, 6, 0)), isFalse);
    });

    test('расписание авто-публикации тоже меняется', () async {
      await putSettings({'autoPublishCron': '0 21 * * *'});

      final job = harness.app.scheduler.jobs
          .firstWhere((job) => job.name == 'auto-publish');
      expect(job.schedule.toString(), '0 21 * * *');
    });

    test('/api/health показывает действующее расписание', () async {
      await putSettings({'downloadCron': '15 5 * * *'});

      final response =
          await client.get(baseUri.resolve('api/health'), headers: auth());
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;

      expect(body['downloadCron'], '15 5 * * *');
    });

    test('негодное выражение отклоняется, планировщик не трогаем', () async {
      final response = await putSettings({'downloadCron': '99 6 * * *'});

      expect(response.statusCode, HttpStatus.badRequest);
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
      expect(body['field'], 'downloadCron');

      final job = harness.app.scheduler.jobs
          .firstWhere((job) => job.name == 'download');
      expect(job.schedule.toString(), '0 6 * * *');
    });

    test('пустое расписание отклоняется', () async {
      final response = await putSettings({'autoPublishCron': '  '});

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        '${(jsonDecode(utf8.decode(response.bodyBytes)) as Map)['error']}',
        contains('укажите расписание'),
      );
    });

    test('число полей проверяется', () async {
      final response = await putSettings({'downloadCron': '0 6 * *'});

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        '${(jsonDecode(utf8.decode(response.bodyBytes)) as Map)['error']}',
        contains('5 полей'),
      );
    });

    test('сброс возвращает расписание из конфигурации', () async {
      await putSettings({'downloadCron': '30 7 * * *'});
      await putSettings({'downloadCron': null});

      final settings = await getSettings();
      expect(field(settings, 'downloadCron')['value'], '0 6 * * *');
      expect(field(settings, 'downloadCron')['overridden'], isFalse);
      expect(
        harness.app.scheduler.jobs
            .firstWhere((job) => job.name == 'download')
            .schedule
            .toString(),
        '0 6 * * *',
      );
    });
  });

  group('доступ', () {
    test('CORS разрешает PUT — UI на отдельном порту при разработке', () async {
      final response = await client.get(
        baseUri.resolve('api/settings'),
        headers: {...auth(), 'Origin': 'http://localhost:5000'},
      );

      expect(
        response.headers['access-control-allow-methods'],
        contains('PUT'),
      );
    });

    test('без авторизации настройки не отдаются', () async {
      final response = await client.get(baseUri.resolve('api/settings'));

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('без авторизации настройки не меняются', () async {
      final response = await client.put(
        baseUri.resolve('api/settings'),
        body: jsonEncode({'cdiDropDir': '/tmp/hacked'}),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(harness.db.meta(RuntimeSettings.cdiDropDirKey), isNull);
    });
  });

  group('сброс и журнал', () {
    test('null возвращает значение из конфигурации', () async {
      await putSettings({'minjustExportUrl': 'https://new.example/list.xlsx'});

      final response = await putSettings({'minjustExportUrl': null});
      expect(response.statusCode, HttpStatus.ok);

      final exportUrl = field(await getSettings(), 'minjustExportUrl');
      expect(exportUrl['value'], 'https://minjust.example/export.xlsx');
      expect(exportUrl['overridden'], isFalse);
    });

    test('поле, которого нет в теле, не меняется', () async {
      await putSettings({'minjustExportUrl': 'https://new.example/list.xlsx'});
      await putSettings({'cdiDropDir': '${harness.tempDir.path}/cdi-other'});

      final settings = await getSettings();
      expect(
        field(settings, 'minjustExportUrl')['value'],
        'https://new.example/list.xlsx',
      );
    });

    test('неизвестная настройка отклоняется', () async {
      final response = await putSettings({'smtpHost': 'mail.example'});

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        '${(jsonDecode(utf8.decode(response.bodyBytes)) as Map)['error']}',
        contains('неизвестные настройки'),
      );
    });

    test('изменение попадает в журнал и запоминает автора', () async {
      await putSettings({'minjustExportUrl': 'https://new.example/list.xlsx'});

      final events = harness.db.listEvents(type: EventType.settingsChanged);
      expect(events, hasLength(1));
      expect(events.single.payload['author'], 'admin');
      expect(events.single.payload['changed'], contains('minjustExportUrl'));

      final settings = await getSettings();
      expect(settings['updatedBy'], 'admin');
      expect(settings['updatedAt'], isNotNull);
    });

    test('правка хранится в БД и переживает пересоздание настроек', () async {
      await putSettings({'minjustExportUrl': 'https://new.example/list.xlsx'});

      // Новый экземпляр читает ту же БД — как после перезапуска службы.
      final reopened = RuntimeSettings(
        config: harness.config,
        db: harness.db,
      );

      expect(reopened.minjustExportUrl, 'https://new.example/list.xlsx');
      expect(
        harness.db.meta(RuntimeSettings.exportUrlKey),
        'https://new.example/list.xlsx',
      );
    });
  });
}
