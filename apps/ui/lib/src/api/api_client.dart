/// Клиент REST API сервиса (п. 8.6 ТЗ).
///
/// UI раздаётся тем же сервером, что и API, поэтому базовый адрес по
/// умолчанию — относительный, а Basic Auth браузер подставляет сам.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.field = ''});

  final int statusCode;
  final String message;

  /// Настройка или поле, к которому относится ошибка (если сервер уточнил).
  final String field;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Интерфейс, чтобы экраны можно было тестировать без сети.
abstract class PerechenApi {
  Future<HealthInfo> health();

  Future<List<VersionSummary>> versions();

  Future<VersionSummary> version(int id);

  Future<List<RecordItem>> records(
    int versionId, {
    String filter = 'all',
    String search = '',
  });

  Future<RecordItem> saveCorrection(
    int versionId,
    String orgKey,
    Map<String, String> values,
  );

  Future<RecordItem> revertCorrection(
    int versionId,
    String orgKey,
    List<String> fields,
  );

  Future<PublishResultInfo> confirm(int versionId);

  Future<CheckResultInfo> checkNow();

  Future<List<EventItem>> events({int limit = 200});

  /// Настройки: адреса первоисточника и папка выгрузки.
  Future<AppSettings> settings();

  /// Сохраняет настройки.
  ///
  /// Ключ со значением `null` возвращает значение из конфигурации службы;
  /// ключа нет — настройка не меняется.
  Future<AppSettings> saveSettings(Map<String, String?> changes);

  /// Ссылка на скачивание целевого CSV.
  Uri exportUri(int versionId);
}

class ApiClient implements PerechenApi {
  ApiClient({Uri? baseUri, http.Client? client})
      : baseUri = baseUri ?? Uri.base,
        _client = client ?? http.Client();

  final Uri baseUri;
  final http.Client _client;

  @override
  Uri exportUri(int versionId) => baseUri.resolve(
        // Адрес выгрузки постоянный, а содержимое меняется после ручных
        // правок. Метка времени не даёт браузеру отдать сохранённую копию —
        // сервер лишний параметр игнорирует.
        'api/versions/$versionId/export.csv'
        '?t=${DateTime.now().millisecondsSinceEpoch}',
      );

  @override
  Future<HealthInfo> health() async =>
      HealthInfo.fromJson(await _get('api/health'));

  @override
  Future<List<VersionSummary>> versions() async {
    final payload = await _get('api/versions');
    return (payload['versions'] as List? ?? const [])
        .map((e) => VersionSummary.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<VersionSummary> version(int id) async =>
      VersionSummary.fromJson(await _get('api/versions/$id'));

  @override
  Future<List<RecordItem>> records(
    int versionId, {
    String filter = 'all',
    String search = '',
  }) async {
    final query = <String, String>{
      'filter': filter,
      if (search.trim().isNotEmpty) 'search': search.trim(),
    };
    final payload = await _get(
      'api/versions/$versionId/records',
      query: query,
    );
    return (payload['records'] as List? ?? const [])
        .map((e) => RecordItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<RecordItem> saveCorrection(
    int versionId,
    String orgKey,
    Map<String, String> values,
  ) async {
    final payload = await _patch(
      'api/records/$versionId/${Uri.encodeComponent(orgKey)}',
      {'values': values},
    );
    return RecordItem.fromJson(payload);
  }

  @override
  Future<RecordItem> revertCorrection(
    int versionId,
    String orgKey,
    List<String> fields,
  ) async {
    final payload = await _patch(
      'api/records/$versionId/${Uri.encodeComponent(orgKey)}',
      {'revert': fields},
    );
    return RecordItem.fromJson(payload);
  }

  @override
  Future<PublishResultInfo> confirm(int versionId) async =>
      PublishResultInfo.fromJson(await _post('api/versions/$versionId/confirm'));

  @override
  Future<CheckResultInfo> checkNow() async =>
      CheckResultInfo.fromJson(await _post('api/jobs/check-now'));

  @override
  Future<List<EventItem>> events({int limit = 200}) async {
    final payload = await _get('api/events', query: {'limit': '$limit'});
    return (payload['events'] as List? ?? const [])
        .map((e) => EventItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<AppSettings> settings() async =>
      AppSettings.fromJson(await _get('api/settings'));

  @override
  Future<AppSettings> saveSettings(Map<String, String?> changes) async =>
      AppSettings.fromJson(await _put('api/settings', changes));

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final uri = baseUri.resolve(path).replace(
          queryParameters: query.isEmpty ? null : query,
        );
    return _decode(await _client.get(uri, headers: _headers));
  }

  Future<Map<String, dynamic>> _post(String path) async =>
      _decode(await _client.post(baseUri.resolve(path), headers: _headers));

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, Object?> body,
  ) async =>
      _decode(await _client.put(
        baseUri.resolve(path),
        headers: _headers,
        body: jsonEncode(body),
      ));

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, Object?> body,
  ) async =>
      _decode(await _client.patch(
        baseUri.resolve(path),
        headers: _headers,
        body: jsonEncode(body),
      ));

  Map<String, String> get _headers => const {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      };

  Map<String, dynamic> _decode(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 400) {
      String message = body;
      String field = '';
      try {
        final payload = jsonDecode(body) as Map;
        message = '${payload['error'] ?? body}';
        field = '${payload['field'] ?? ''}';
      } catch (_) {
        // тело не json — показываем как есть
      }
      throw ApiException(response.statusCode, message, field: field);
    }
    if (body.isEmpty) return <String, dynamic>{};
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }
}
