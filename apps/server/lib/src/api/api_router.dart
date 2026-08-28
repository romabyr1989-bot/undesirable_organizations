/// REST API для Flutter UI (FR-6) + раздача собранного веб-интерфейса.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:perechen_core/perechen_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import '../config/app_config.dart';
import '../config/runtime_settings.dart';
import '../db/database.dart';
import '../scheduler/cron.dart';
import '../service/publisher.dart';
import '../service/version_service.dart';
import '../util/logging.dart';
import '../util/moscow_time.dart';

class ApiServer {
  ApiServer({
    required this.config,
    required this.settings,
    required this.db,
    required this.service,
    required this.publisher,
    AppLogger? logger,
    this.scheduler,
  }) : _logger = logger ?? AppLogger();

  final AppConfig config;

  /// Настройки, которые ответственный меняет на экране «Настройки».
  final RuntimeSettings settings;

  final AppDatabase db;
  final VersionService service;
  final Publisher publisher;
  final CronScheduler? scheduler;
  final AppLogger _logger;

  /// Полный обработчик: логирование -> CORS -> Basic Auth -> маршруты.
  Handler get handler => const Pipeline()
      .addMiddleware(_logRequests())
      .addMiddleware(_cors())
      .addMiddleware(_basicAuth())
      .addHandler(_routes());

  Handler _routes() {
    final router = Router()
      ..get('/api/health', _health)
      ..get('/api/versions', _listVersions)
      ..get('/api/versions/<id|[0-9]+>', _versionCard)
      ..get('/api/versions/<id|[0-9]+>/records', _versionRecords)
      ..get('/api/versions/<id|[0-9]+>/export.csv', _exportCsv)
      ..post('/api/versions/<id|[0-9]+>/confirm', _confirm)
      ..post('/api/versions/<id|[0-9]+>/reparse', _reparse)
      ..patch('/api/records/<versionId|[0-9]+>/<orgKey|.+>', _patchRecord)
      ..post('/api/jobs/check-now', _checkNow)
      ..get('/api/settings', _getSettings)
      ..put('/api/settings', _putSettings)
      ..get('/api/events', _events)
      ..get('/api/corrections/<orgKey|.+>', _correctionHistory);

    final uiDirectory = Directory(config.uiDir);
    if (!uiDirectory.existsSync()) {
      return (Request request) async {
        final response = await router.call(request);
        if (response.statusCode == 404 &&
            !request.url.path.startsWith('api/')) {
          return Response.notFound(
            'Веб-интерфейс не собран: каталог "${config.uiDir}" отсутствует. '
            'Соберите его командой "flutter build web" (см. README).',
          );
        }
        return response;
      };
    }

    final staticHandler = createStaticHandler(
      config.uiDir,
      defaultDocument: 'index.html',
    );
    final indexHandler =
        createFileHandler(p.join(config.uiDir, 'index.html'));

    // Интерфейс обновляется вместе со службой, а адреса файлов постоянные:
    // без запрета браузер продолжает показывать предыдущую сборку. Валидаторы
    // (Last-Modified) остаются, поэтому неизменённые файлы отдаются как 304.
    Response noCache(Response response) => response.change(
          headers: {'Cache-Control': 'no-cache, must-revalidate'},
        );

    /// Точка входа дополнительно просит браузер выбросить всё, что он
    /// сохранил по этому адресу: у тех, кто открывал сервис до отключения
    /// служебного воркера, он продолжает отдавать прежнюю сборку, и обычная
    /// перезагрузка это не лечит.
    Response resetStorage(Response response) => response.change(
          headers: {'Clear-Site-Data': '"cache", "storage"'},
        );

    return (Request request) async {
      if (request.url.path.startsWith('api/')) return router.call(request);
      final isEntryPoint =
          request.url.path.isEmpty || request.url.path == 'index.html';
      final response = noCache(await staticHandler(request));
      if (isEntryPoint && response.statusCode == HttpStatus.ok) {
        return resetStorage(response);
      }
      if (response.statusCode == 404) {
        // SPA: неизвестные пути отдаём в index.html.
        return resetStorage(noCache(await indexHandler(
          Request('GET', request.requestedUri.replace(path: '/')),
        )));
      }
      return response;
    };
  }

  // ------------------------------------------------------------ endpoints

  Response _health(Request request) {
    final lastCheck = service.lastCheckAt;
    final nextRun = scheduler?.nextRunAt;
    final latest = db.latestVersion();
    return _json({
      'status': 'ok',
      'now': MoscowTime.format(MoscowTime.now()),
      'timeZone': MoscowTime.zoneName,
      'lastCheckAt': lastCheck == null ? null : MoscowTime.format(lastCheck),
      'lastCheckStatus': service.lastCheckStatus,
      'nextRunAt': nextRun == null ? null : MoscowTime.format(nextRun),
      'downloadCron': settings.downloadCron,
      'autoPublishCron': settings.autoPublishCron,
      'cdiDropDir': settings.cdiDropDir,
      'latestVersionId': latest?.id,
      'latestActualityDate':
          latest == null ? null : MoscowTime.format(latest.actualityDate),
    });
  }

  Response _listVersions(Request request) => _json({
        'versions': db.listVersions().map(_versionJson).toList(),
      });

  Response _versionCard(Request request, String id) {
    final version = db.versionById(int.parse(id));
    if (version == null) return _notFound('версия не найдена');
    return _json(_versionJson(version));
  }

  Response _versionRecords(Request request, String id) {
    final versionId = int.parse(id);
    if (db.versionById(versionId) == null) {
      return _notFound('версия не найдена');
    }
    final query = request.url.queryParameters;
    final records = db.recordsOf(
      versionId,
      filter: RecordFilter.byId(query['filter']),
      search: query['search'],
      limit: int.tryParse(query['limit'] ?? '') ?? 5000,
      offset: int.tryParse(query['offset'] ?? '') ?? 0,
    );
    return _json({
      'versionId': versionId,
      'filter': RecordFilter.byId(query['filter']).id,
      'total': records.length,
      'records': records,
    });
  }

  Response _exportCsv(Request request, String id) {
    final versionId = int.parse(id);
    try {
      final csv = publisher.buildCsv(versionId);
      // В папку CDI уходит cp1251 (п. 4 ТЗ) — так ждёт скрипт загрузки.
      // Человеку отдаём тот же файл в UTF-8 с BOM: иначе Excel, Numbers и
      // просмотрщики на macOS читают cp1251 как UTF-8 и показывают кашу.
      final text = const Cp1251Encoder().decode(csv.bytes);
      return Response.ok(
        utf8.encode('\u{FEFF}$text'),
        headers: {
          'Content-Type': 'text/csv; charset=utf-8',
          'Content-Disposition': 'attachment; filename="${csv.fileName}"',
          // Адрес выгрузки постоянный, а содержимое меняется после ручных
          // правок — браузер не должен отдавать сохранённую копию.
          'Cache-Control': 'no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
      );
    } on PublishException catch (error) {
      return _notFound(error.message);
    }
  }

  Future<Response> _confirm(Request request, String id) async {
    final versionId = int.parse(id);
    final actor = _actorOf(request);
    try {
      final result = await service.confirm(versionId, actor);
      return _json({
        'status': 'published',
        'fileName': result.fileName,
        'rows': result.rowCount,
        'cdiPath': result.cdiPath,
        'warnings': result.warnings.map((w) => w.toJson()).toList(),
        'version': _versionJson(result.version),
      });
    } on PublishException catch (error) {
      return _error(HttpStatus.conflict, error.message);
    }
  }

  Future<Response> _reparse(Request request, String id) async {
    final outcome = await service.reparse(int.parse(id));
    return _json(outcome.toJson());
  }

  Future<Response> _patchRecord(
    Request request,
    String versionId,
    String orgKey,
  ) async {
    final body = await request.readAsString();
    final payload = body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(body) as Map<String, Object?>;
    final actor = _actorOf(request);
    final decodedKey = Uri.decodeComponent(orgKey);

    try {
      if (payload['revert'] is List) {
        final fields = (payload['revert']! as List<Object?>)
            .map((e) => '$e')
            .toList();
        return _json(service.revertCorrection(
          versionId: int.parse(versionId),
          orgKey: decodedKey,
          fields: fields,
          author: actor,
        ));
      }
      final rawValues = payload['values'];
      if (rawValues is! Map) {
        return _error(
          HttpStatus.badRequest,
          'ожидается объект {"values": {"name_rus": "..."}} '
          'или {"revert": ["name_rus"]}',
        );
      }
      final values = <String, String>{
        for (final entry in rawValues.entries) '${entry.key}': '${entry.value}',
      };
      final unknown = values.keys.where((k) => RecordField.byId(k) == null);
      if (unknown.isNotEmpty) {
        return _error(
          HttpStatus.badRequest,
          'неизвестные поля: ${unknown.join(", ")}',
        );
      }
      return _json(service.saveCorrection(
        versionId: int.parse(versionId),
        orgKey: decodedKey,
        values: values,
        author: actor,
      ));
    } on ArgumentError catch (error) {
      return _notFound('${error.message}');
    }
  }

  Future<Response> _checkNow(Request request) async {
    // Одна попытка: ретраи по 1 и 5 минут рассчитаны на ночную задачу,
    // а здесь ответа ждёт человек перед экраном.
    final outcome = await service.checkNow(trigger: 'manual', maxAttempts: 1);
    return _json(outcome.toJson());
  }

  Response _events(Request request) {
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 200;
    return _json({
      'events': db.listEvents(limit: limit).map((e) => e.toJson()).toList(),
    });
  }

  Response _correctionHistory(Request request, String orgKey) => _json({
        'orgKey': Uri.decodeComponent(orgKey),
        'corrections': db.correctionHistory(Uri.decodeComponent(orgKey)),
      });

  // ------------------------------------------------------------- helpers

  Map<String, Object?> _versionJson(PerechenVersion version) => {
        'id': version.id,
        'actualityDate': MoscowTime.format(version.actualityDate),
        'downloadedAt': MoscowTime.format(version.downloadedAt),
        'status': version.status.id,
        'counters': version.counters.toJson(),
        'errorText': version.errorText,
        'fileSha256': version.fileSha256,
        'publishedAt': version.publishedAt == null
            ? null
            : MoscowTime.format(version.publishedAt!),
        'publishedFileName': version.publishedFileName,
        'confirmedBy': version.confirmedBy,
        'targetFileName': CsvWriter.fileNameFor(version.actualityDate),
      };

  String _actorOf(Request request) =>
      (request.context['user'] as String?) ?? 'anonymous';

  /// Действующие настройки и то, что записано в конфигурации.
  Response _getSettings(Request request) => _json(settings.toJson());

  /// Правка настроек (экран «Настройки»).
  ///
  /// Тело: `{"minjustExportUrl": "https://...", "cdiDropDir": "/mnt/cdi"}`.
  /// Поле со значением `null` — вернуть значение из конфигурации; поле,
  /// которого нет в теле, не меняется.
  Future<Response> _putSettings(Request request) async {
    final body = await request.readAsString();
    final Object? decoded = body.isEmpty ? <String, Object?>{} : jsonDecode(body);
    if (decoded is! Map) {
      return _error(
        HttpStatus.badRequest,
        'ожидается объект с настройками, например '
        '{"minjustExportUrl": "https://minjust.gov.ru/.../export.xlsx"}',
      );
    }
    final changes = <String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    };
    try {
      final updated = settings.update(changes, author: _actorOf(request));
      return _json(updated);
    } on SettingsException catch (error) {
      return _json(
        {'error': error.message, 'field': error.field},
        status: HttpStatus.badRequest,
      );
    }
  }

  Response _json(Object? payload, {int status = HttpStatus.ok}) => Response(
        status,
        body: jsonEncode(payload),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );

  Response _notFound(String message) =>
      _error(HttpStatus.notFound, message);

  Response _error(int status, String message) =>
      _json({'error': message}, status: status);

  Middleware _logRequests() => (Handler inner) => (Request request) async {
        final started = DateTime.now();
        final response = await inner(request);
        _logger.info('http', {
          'method': request.method,
          'path': '/${request.url.path}',
          'status': response.statusCode,
          'ms': DateTime.now().difference(started).inMilliseconds,
        });
        return response;
      };

  /// CORS для разработки: Flutter Web на отдельном порту.
  Middleware _cors() => (Handler inner) => (Request request) async {
        final origin = request.headers['origin'];
        final headers = <String, String>{
          if (origin != null) 'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Credentials': 'true',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, OPTIONS',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type',
        };
        if (request.method == 'OPTIONS') {
          return Response.ok(null, headers: headers);
        }
        final response = await inner(request);
        return response.change(headers: headers);
      };

  /// Basic Auth (Р-7): сервис рассчитан на внутренний периметр.
  Middleware _basicAuth() => (Handler inner) => (Request request) async {
        if (request.method == 'OPTIONS') return inner(request);
        final header = request.headers['authorization'];
        if (header != null && header.toLowerCase().startsWith('basic ')) {
          try {
            final decoded =
                utf8.decode(base64Decode(header.substring(6).trim()));
            final separator = decoded.indexOf(':');
            final user = decoded.substring(0, separator);
            final password = decoded.substring(separator + 1);
            if (user == config.basicAuthUser &&
                password == config.basicAuthPassword) {
              return inner(request.change(context: {'user': user}));
            }
          } catch (_) {
            // некорректный заголовок — обрабатываем как отсутствие доступа
          }
        }
        return Response(
          HttpStatus.unauthorized,
          body: jsonEncode({'error': 'требуется авторизация'}),
          headers: {
            // Значение заголовка — только ASCII (требование HTTP).
            'WWW-Authenticate': 'Basic realm="Perechen 272-FZ", charset="UTF-8"',
            'Content-Type': 'application/json; charset=utf-8',
          },
        );
      };
}
