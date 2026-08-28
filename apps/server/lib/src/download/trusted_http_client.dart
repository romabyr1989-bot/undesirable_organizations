/// HTTP-клиент, доверяющий дополнительным сертификатам из комплекта поставки.
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
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/app_config.dart';
import '../util/logging.dart';

class TrustedHttpClient {
  const TrustedHttpClient._();

  /// Файл сертификатов, который удалось подключить. `null` — работает только
  /// системное хранилище. Попадает в журнал запуска и в вывод `paths`.
  static String? loadedFrom;

  /// Собирает клиент для загрузки файла перечня.
  ///
  /// Отсутствие файла — не ошибка: в контуре, где цепочка приходит целиком,
  /// хватает системного хранилища.
  static http.Client create(AppConfig config, AppLogger logger) {
    final path = config.caBundleFile;
    if (path.isEmpty) return http.Client();
    if (!File(path).existsSync()) {
      logger.debug('файла доверенных сертификатов нет, берём системные', {
        'path': path,
      });
      return http.Client();
    }
    try {
      final context = SecurityContext(withTrustedRoots: true)
        ..setTrustedCertificates(path);
      loadedFrom = path;
      logger.info('подключены доверенные сертификаты', {'path': path});
      return IOClient(HttpClient(context: context));
    } on TlsException catch (error) {
      // Битый или пустой файл не должен ронять службу: без него загрузка
      // может и заработать, а вот упавший сервис не сделает ничего.
      logger.error('файл доверенных сертификатов не прочитан', {
        'path': path,
        'error': '$error',
      });
      return http.Client();
    }
  }
}
