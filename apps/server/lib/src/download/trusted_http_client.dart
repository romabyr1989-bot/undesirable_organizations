/// HTTP-клиент службы: доверенные сертификаты из комплекта и корпоративный
/// прокси.
///
/// Первоисточник (`reestrs.minjust.gov.ru`) присылает только свой сертификат и
/// не присылает промежуточный, которым тот подписан. Браузер такую цепочку
/// достраивает сам — тянет недостающее звено по ссылке внутри сертификата, —
/// а Dart этого не умеет, и проверка падает с `CERTIFICATE_VERIFY_FAILED`.
///
/// На площадке открыт единственный адрес Минюста, дотянуть звено оттуда
/// неоткуда, поэтому оно лежит в комплекте (`assets/ca-bundle.pem`).
/// Системное хранилище при этом сохраняется: файл к нему добавляется, а не
/// подменяет его.
///
/// Второе — прокси. В закрытом контуре наружу пускают только через него, а
/// Dart, в отличие от curl, переменные окружения `http_proxy` не читает; юнит
/// systemd их вдобавок и не наследует. Поэтому адрес задаётся параметром
/// `HTTP_PROXY` в конфигурации.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/app_config.dart';
import '../util/logging.dart';

/// Разобранный адрес прокси.
class ProxySpec {
  const ProxySpec({
    required this.host,
    required this.port,
    this.username = '',
    this.password = '',
  });

  final String host;
  final int port;
  final String username;
  final String password;

  bool get hasCredentials => username.isNotEmpty;

  /// Как показывать в журнале: пароль не печатаем.
  String get display =>
      hasCredentials ? '$username@$host:$port' : '$host:$port';

  @override
  String toString() => display;
}

class TrustedHttpClient {
  const TrustedHttpClient._();

  /// Порт прокси по умолчанию, если в адресе он не указан.
  static const defaultProxyPort = 8080;

  /// Файл сертификатов, который удалось подключить. `null` — работает только
  /// системное хранилище. Попадает в журнал запуска и в вывод `paths`.
  static String? loadedFrom;

  /// Прокси, через который идут запросы. `null` — напрямую.
  static ProxySpec? proxy;

  /// Разбирает значение `HTTP_PROXY`.
  ///
  /// Понимает `host:port`, `http://host:port` и `http://user:pass@host:port`.
  /// Пустая или неразборчивая строка — работаем напрямую.
  static ProxySpec? parseProxy(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final Uri uri;
    try {
      uri = Uri.parse(text.contains('://') ? text : 'http://$text');
    } on FormatException {
      return null;
    }
    if (uri.host.isEmpty) return null;
    final info = uri.userInfo;
    final separator = info.indexOf(':');
    return ProxySpec(
      host: uri.host,
      port: uri.hasPort ? uri.port : defaultProxyPort,
      username: info.isEmpty
          ? ''
          : (separator < 0 ? info : info.substring(0, separator)),
      password: separator < 0 ? '' : info.substring(separator + 1),
    );
  }

  /// Собирает клиент для загрузки файла перечня.
  ///
  /// Отсутствие файла сертификатов — не ошибка: в контуре, где цепочка
  /// приходит целиком, хватает системного хранилища.
  static http.Client create(AppConfig config, AppLogger logger) {
    final context = _securityContext(config, logger);
    proxy = parseProxy(config.httpProxy);
    if (context == null && proxy == null) return http.Client();

    final client = HttpClient(context: context);
    final spec = proxy;
    if (spec != null) {
      client.findProxy = (_) => 'PROXY ${spec.host}:${spec.port}';
      if (spec.hasCredentials) {
        final credentials =
            HttpClientBasicCredentials(spec.username, spec.password);
        client.addProxyCredentials(spec.host, spec.port, '', credentials);
        // Realm заранее неизвестен: доучиваем клиент по ответу прокси.
        client.authenticateProxy = (host, port, scheme, realm) async {
          client.addProxyCredentials(host, port, realm ?? '', credentials);
          return true;
        };
      }
      logger.info('запросы идут через прокси', {'proxy': spec.display});
    }
    return IOClient(client);
  }

  /// Контекст с сертификатами из комплекта. `null` — только системные.
  static SecurityContext? _securityContext(AppConfig config, AppLogger logger) {
    final path = config.caBundleFile;
    if (path.isEmpty) return null;
    if (!File(path).existsSync()) {
      logger.debug('файла доверенных сертификатов нет, берём системные', {
        'path': path,
      });
      return null;
    }
    try {
      final context = SecurityContext(withTrustedRoots: true)
        ..setTrustedCertificates(path);
      loadedFrom = path;
      logger.info('подключены доверенные сертификаты', {'path': path});
      return context;
    } on TlsException catch (error) {
      // Битый или пустой файл не должен ронять службу: без него загрузка
      // может и заработать, а вот упавший сервис не сделает ничего.
      logger.error('файл доверенных сертификатов не прочитан', {
        'path': path,
        'error': '$error',
      });
      return null;
    }
  }
}
