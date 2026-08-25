/// Тесты загрузчика (FR-1, решение Р-5).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perechen_server/src/config/app_config.dart';
import 'package:perechen_server/src/config/runtime_settings.dart';
import 'package:perechen_server/src/db/database.dart';
import 'package:perechen_server/src/download/downloader.dart';
import 'package:perechen_server/src/util/logging.dart';
import 'package:test/test.dart';

AppConfig configWith(Map<String, String> overrides) => AppConfig.load(
      environment: {
        'DATA_DIR': '/tmp/perechen-test',
        'RETRY_DELAYS_MIN': '0,0,0',
        ...overrides,
      },
    );

Uint8List fakeXlsx() => Uint8List.fromList(List<int>.filled(4096, 42));

void main() {
  final logger = AppLogger(minLevel: LogLevel.error);
  final delays = <Duration>[];

  setUp(delays.clear);

  Downloader build(AppConfig config, MockClient client) => Downloader(
        config: config,
        settings: RuntimeSettings(
          config: config,
          db: AppDatabase.memory(),
          logger: logger,
        ),
        client: client,
        logger: logger,
        sleep: (delay) async => delays.add(delay),
      );

  test('прямая ссылка из конфига используется как есть', () async {
    final requested = <String>[];
    final downloader = build(
      configWith({'MINJUST_EXPORT_URL': 'https://minjust.example/export.xlsx'}),
      MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes(fakeXlsx(), 200);
      }),
    );

    final result = await downloader.download();
    expect(requested, ['https://minjust.example/export.xlsx']);
    expect(result.bytes, hasLength(4096));
    expect(result.sha256, isNotEmpty);
    expect(result.attempts, 1);
  });

  test('ссылка ищется на странице по селектору (Р-5)', () async {
    const page = '''
      <html><body>
        <a href="/other.pdf">Другой документ</a>
        <div class="documents">
          <a href="/files/export.xlsx">Экспорт перечня</a>
        </div>
      </body></html>
    ''';
    final requested = <String>[];
    final downloader = build(
      configWith({
        'MINJUST_PAGE_URL': 'https://minjust.example/ru/pages/perechen/',
        'MINJUST_EXPORT_URL': '',
      }),
      MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.path.endsWith('.xlsx')) {
          return http.Response.bytes(fakeXlsx(), 200);
        }
        return http.Response(page, 200, headers: {
          'content-type': 'text/html; charset=utf-8',
        });
      }),
    );

    final result = await downloader.download();
    expect(result.url, 'https://minjust.example/files/export.xlsx');
    expect(requested.first, 'https://minjust.example/ru/pages/perechen/');
  });

  test('если селектор не сработал — ищем ссылку по тексту и расширению',
      () async {
    const page = '<html><body><a href="/f/EXPORT">Скачать в формате xlsx</a>'
        '</body></html>';
    final downloader = build(
      configWith({
        'MINJUST_PAGE_URL': 'https://minjust.example/perechen/',
        'MINJUST_EXPORT_URL': '',
        'EXPORT_LINK_SELECTOR': 'a.no-such-class',
      }),
      MockClient((request) async {
        if (request.url.path == '/f/EXPORT') {
          return http.Response.bytes(fakeXlsx(), 200);
        }
        return http.Response(page, 200, headers: {
          'content-type': 'text/html; charset=utf-8',
        });
      }),
    );
    final result = await downloader.download();
    expect(result.url, 'https://minjust.example/f/EXPORT');
  });

  test('нет ссылки на странице — ошибка загрузки', () async {
    final downloader = build(
      configWith({
        'MINJUST_PAGE_URL': 'https://minjust.example/perechen/',
        'MINJUST_EXPORT_URL': '',
      }),
      MockClient((request) async => http.Response(
            '<html><body>Ничего нет</body></html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          )),
    );
    await expectLater(downloader.download(), throwsA(isA<DownloadException>()));
  });

  test('ретраи: две неудачи, затем успех', () async {
    var attempt = 0;
    final downloader = build(
      configWith({
        'MINJUST_EXPORT_URL': 'https://minjust.example/export.xlsx',
        'RETRY_DELAYS_MIN': '1,5,15',
      }),
      MockClient((request) async {
        attempt++;
        if (attempt < 3) return http.Response('service unavailable', 503);
        return http.Response.bytes(fakeXlsx(), 200);
      }),
    );

    final result = await downloader.download();
    expect(result.attempts, 3);
    expect(delays, [const Duration(minutes: 1), const Duration(minutes: 5)]);
  });

  test('три неудачи подряд — исключение с числом попыток', () async {
    final downloader = build(
      configWith({'MINJUST_EXPORT_URL': 'https://minjust.example/export.xlsx'}),
      MockClient((request) async => http.Response('error', 500)),
    );

    await expectLater(
      downloader.download(),
      throwsA(
        isA<DownloadException>().having((e) => e.attempts, 'attempts', 3),
      ),
    );
  });

  test('подозрительно маленький файл считается ошибкой', () async {
    final downloader = build(
      configWith({'MINJUST_EXPORT_URL': 'https://minjust.example/export.xlsx'}),
      MockClient((request) async =>
          http.Response.bytes(utf8.encode('too small'), 200)),
    );
    await expectLater(downloader.download(), throwsA(isA<DownloadException>()));
  });

  test('User-Agent берётся из конфига', () async {
    String? sentAgent;
    final downloader = build(
      configWith({
        'MINJUST_EXPORT_URL': 'https://minjust.example/export.xlsx',
        'HTTP_USER_AGENT': 'TestAgent/9.9',
      }),
      MockClient((request) async {
        sentAgent = request.headers['User-Agent'];
        return http.Response.bytes(fakeXlsx(), 200);
      }),
    );
    await downloader.download();
    expect(sentAgent, 'TestAgent/9.9');
  });
}
