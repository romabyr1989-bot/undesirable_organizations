/// Тесты прокси для исходящих запросов.
///
/// В закрытом контуре наружу пускают только через прокси, а Dart не читает
/// `http_proxy` из окружения — адрес задаётся параметром `HTTP_PROXY`.
library;

import 'package:perechen_server/src/config/app_config.dart';
import 'package:perechen_server/src/download/trusted_http_client.dart';
import 'package:perechen_server/src/util/logging.dart';
import 'package:test/test.dart';

void main() {
  group('разбор адреса прокси', () {
    test('пусто — работаем напрямую', () {
      expect(TrustedHttpClient.parseProxy(''), isNull);
      expect(TrustedHttpClient.parseProxy('   '), isNull);
    });

    test('host:port без схемы', () {
      final proxy = TrustedHttpClient.parseProxy('mcafee.corp.example:8080')!;
      expect(proxy.host, 'mcafee.corp.example');
      expect(proxy.port, 8080);
      expect(proxy.hasCredentials, isFalse);
    });

    test('полный адрес со схемой', () {
      final proxy =
          TrustedHttpClient.parseProxy('http://mcafee.corp.example:3128')!;
      expect(proxy.host, 'mcafee.corp.example');
      expect(proxy.port, 3128);
    });

    test('без порта берётся 8080', () {
      final proxy = TrustedHttpClient.parseProxy('http://proxy.corp.example')!;
      expect(proxy.port, TrustedHttpClient.defaultProxyPort);
    });

    test('логин и пароль', () {
      final proxy = TrustedHttpClient.parseProxy(
        'http://ivanov:s3cret@proxy.corp.example:8080',
      )!;
      expect(proxy.username, 'ivanov');
      expect(proxy.password, 's3cret');
      expect(proxy.hasCredentials, isTrue);
    });

    test('пароль не попадает в журнал', () {
      final proxy = TrustedHttpClient.parseProxy(
        'http://ivanov:s3cret@proxy.corp.example:8080',
      )!;
      expect(proxy.display, isNot(contains('s3cret')));
      expect(proxy.display, 'ivanov@proxy.corp.example:8080');
    });

    test('мусор не роняет разбор', () {
      expect(TrustedHttpClient.parseProxy('http://'), isNull);
      expect(TrustedHttpClient.parseProxy(':::'), isNull);
    });
  });

  group('конфигурация', () {
    test('HTTP_PROXY читается из окружения и файла', () {
      final config = AppConfig.load(
        environment: {'HTTP_PROXY': 'proxy.corp.example:8080'},
      );
      expect(config.httpProxy, 'proxy.corp.example:8080');
    });

    test('запасной вариант — переменные в нижнем регистре', () {
      // Их задают в контуре, где наружу только через прокси.
      final config = AppConfig.load(
        environment: {'https_proxy': 'http://proxy.corp.example:8080'},
      );
      expect(config.httpProxy, 'http://proxy.corp.example:8080');
    });

    test('по умолчанию прокси нет', () {
      expect(AppConfig.load(environment: const {}).httpProxy, isEmpty);
    });
  });

  group('сборка клиента', () {
    test('без прокси и без сертификатов клиент создаётся', () {
      final config = AppConfig.load(environment: const {
        'CA_BUNDLE_FILE': '',
      });
      final client =
          TrustedHttpClient.create(config, AppLogger(minLevel: LogLevel.error));
      addTearDown(client.close);
      expect(TrustedHttpClient.proxy, isNull);
    });

    test('с прокси клиент создаётся и запоминает адрес', () {
      final config = AppConfig.load(environment: const {
        'CA_BUNDLE_FILE': '',
        'HTTP_PROXY': 'proxy.corp.example:8080',
      });
      final client =
          TrustedHttpClient.create(config, AppLogger(minLevel: LogLevel.error));
      addTearDown(client.close);
      expect(TrustedHttpClient.proxy?.host, 'proxy.corp.example');
      expect(TrustedHttpClient.proxy?.port, 8080);
    });
  });
}
