/// Загрузчик файла-первоисточника (FR-1, решение Р-5).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../config/runtime_settings.dart';
import '../util/logging.dart';

class DownloadResult {
  DownloadResult({
    required this.bytes,
    required this.url,
    required this.sha256,
    required this.attempts,
  });

  final Uint8List bytes;
  final String url;
  final String sha256;
  final int attempts;
}

class DownloadException implements Exception {
  DownloadException(this.message, {this.attempts = 0, this.lastError});

  final String message;
  final int attempts;
  final Object? lastError;

  @override
  String toString() => 'DownloadException: $message '
      '(попыток: $attempts${lastError == null ? '' : ', причина: $lastError'})';
}

class Downloader {
  Downloader({
    required this.config,
    required this.settings,
    http.Client? client,
    AppLogger? logger,
    Future<void> Function(Duration)? sleep,
  })  : _client = client ?? http.Client(),
        _logger = logger ?? AppLogger(),
        _sleep = sleep ?? Future<void>.delayed;

  final AppConfig config;

  /// Адреса первоисточника: ответственный меняет их в UI.
  final RuntimeSettings settings;
  final http.Client _client;
  final AppLogger _logger;
  final Future<void> Function(Duration) _sleep;

  Map<String, String> get _headers => {'User-Agent': config.userAgent};

  /// Скачивает xlsx с ретраями (1, 5, 15 минут по умолчанию).
  ///
  /// [maxAttempts] ограничивает число попыток сверх настройки: расписание
  /// ретраев рассчитано на ночную задачу, которой некуда спешить, и для
  /// кнопки «Проверить сейчас» не годится — там человек ждёт ответа.
  Future<DownloadResult> download({int? maxAttempts}) async {
    Object? lastError;
    var attempts = config.httpRetries < 1 ? 1 : config.httpRetries;
    if (maxAttempts != null && maxAttempts < attempts) {
      attempts = maxAttempts < 1 ? 1 : maxAttempts;
    }
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final url = await resolveExportUrl();
        _logger.info('скачиваем файл перечня', {'url': url, 'attempt': attempt});
        final response = await _client
            .get(Uri.parse(url), headers: _headers)
            .timeout(config.httpTimeout);
        if (response.statusCode != 200) {
          throw DownloadException(
            'сайт вернул код ${response.statusCode}',
            attempts: attempt,
          );
        }
        final bytes = Uint8List.fromList(response.bodyBytes);
        if (bytes.length < 1024) {
          throw DownloadException(
            'файл подозрительно мал (${bytes.length} байт)',
            attempts: attempt,
          );
        }
        return DownloadResult(
          bytes: bytes,
          url: url,
          sha256: sha256.convert(bytes).toString(),
          attempts: attempt,
        );
      } catch (error) {
        lastError = error;
        _logger.warning('попытка скачивания не удалась', {
          'attempt': attempt,
          'error': '$error',
        });
        if (attempt < attempts) {
          final delayIndex = attempt - 1;
          final delay = delayIndex < config.retryDelays.length
              ? config.retryDelays[delayIndex]
              : config.retryDelays.isEmpty
                  ? const Duration(minutes: 1)
                  : config.retryDelays.last;
          await _sleep(delay);
        }
      }
    }
    throw DownloadException(
      'не удалось скачать файл перечня',
      attempts: attempts,
      lastError: lastError,
    );
  }

  /// Определяет URL файла экспорта: из конфига либо парсингом страницы (Р-5).
  Future<String> resolveExportUrl() async {
    final exportUrl = settings.minjustExportUrl;
    if (exportUrl.isNotEmpty) return exportUrl;

    final pageUri = Uri.parse(settings.minjustPageUrl);
    final response =
        await _client.get(pageUri, headers: _headers).timeout(config.httpTimeout);
    if (response.statusCode != 200) {
      throw DownloadException(
        'страница перечня вернула код ${response.statusCode}',
      );
    }
    final document = html_parser.parse(utf8.decode(response.bodyBytes));

    final candidates = <String>[];
    for (final element in document.querySelectorAll(config.exportLinkSelector)) {
      final href = element.attributes['href'];
      if (href != null && href.isNotEmpty) candidates.add(href);
    }
    if (candidates.isEmpty) {
      for (final element in document.querySelectorAll('a')) {
        final href = element.attributes['href'] ?? '';
        final text = element.text.toLowerCase();
        if (href.toLowerCase().contains('.xlsx') ||
            href.toLowerCase().contains('export') ||
            text.contains('экспорт') ||
            text.contains('xlsx')) {
          candidates.add(href);
        }
      }
    }
    if (candidates.isEmpty) {
      throw DownloadException(
        'на странице перечня не найдена ссылка на файл экспорта '
        '(селектор "${config.exportLinkSelector}")',
      );
    }
    final preferred = candidates.firstWhere(
      (href) => href.toLowerCase().contains('.xlsx'),
      orElse: () => candidates.first,
    );
    return pageUri.resolve(preferred).toString();
  }

  void close() => _client.close();
}
