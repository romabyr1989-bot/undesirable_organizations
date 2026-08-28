/// Оркестрация процесса «проверка -> версия -> письмо -> публикация» (п. 7 ТЗ).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:perechen_core/perechen_core.dart';

import '../config/app_config.dart';
import '../db/database.dart';
import '../download/downloader.dart';
import '../mail/notifier.dart';
import '../scheduler/cron.dart';
import '../util/logging.dart';
import '../util/moscow_time.dart';
import 'publisher.dart';

/// Чем закончилась проверка сайта.
enum CheckStatus {
  /// Найдена и разобрана новая версия.
  newVersion,

  /// Новой версии нет.
  noChange,

  /// Файл изменился, а дата актуальности — нет (FR-2).
  contentChangedSameDate,

  /// Ошибка скачивания или разбора.
  error,
}

class CheckOutcome {
  CheckOutcome({
    required this.status,
    this.version,
    this.message = '',
    this.counters,
  });

  final CheckStatus status;
  final PerechenVersion? version;
  final String message;
  final VersionCounters? counters;

  Map<String, Object?> toJson() => {
        'status': status.name,
        'message': message,
        'versionId': version?.id,
        'actualityDate': version == null
            ? null
            : MoscowTime.format(version!.actualityDate),
        'counters': counters?.toJson() ?? version?.counters.toJson(),
      };
}

/// Откуда взялся файл, из которого создана версия.
///
/// Различие не косметическое: версия из комплекта — это стартовые данные при
/// установке, а не находка ночной проверки. По ней не рассылают писем и её не
/// записывают как «последнюю проверку сайта».
enum _VersionSource { site, bundle }

class VersionService {
  VersionService({
    required this.config,
    required this.db,
    required this.downloader,
    required this.notifier,
    required this.publisher,
    required this.countries,
    AppLogger? logger,
    DateTime Function()? clock,
  })  : _logger = logger ?? AppLogger(),
        _clock = clock ?? MoscowTime.now;

  final AppConfig config;
  final AppDatabase db;
  final Downloader downloader;
  final Notifier notifier;
  final Publisher publisher;
  final CountryRegistry countries;
  final AppLogger _logger;
  final DateTime Function() _clock;

  static const _lastCheckKey = 'last_check_at';
  static const _lastCheckStatusKey = 'last_check_status';
  static const _unavailableStreakKey = 'unavailable_streak';

  PerechenPipeline get pipeline =>
      PerechenPipeline(countries: countries, config: config.core);

  DateTime? get lastCheckAt {
    final value = db.meta(_lastCheckKey);
    return value == null ? null : MoscowTime.parse(value);
  }

  String? get lastCheckStatus => db.meta(_lastCheckStatusKey);

  /// Полный цикл проверки сайта (cron и кнопка «Проверить сейчас»).
  ///
  /// [maxAttempts] ограничивает ретраи загрузки: по кнопке из интерфейса
  /// достаточно одной попытки, иначе ответственный ждёт ответа минутами,
  /// не понимая, работает что-нибудь или нет.
  Future<CheckOutcome> checkNow({
    String trigger = 'manual',
    int? maxAttempts,
  }) async {
    db.addEvent(EventType.checkStarted, payload: {'trigger': trigger});
    final startedAt = _clock();

    final DownloadResult download;
    try {
      download = await downloader.download(maxAttempts: maxAttempts);
    } catch (error) {
      return _handleDownloadFailure(error, startedAt);
    }

    db
      ..setMeta(_unavailableStreakKey, '0')
      ..addEvent(EventType.downloadOk, payload: {
        'url': download.url,
        'bytes': download.bytes.length,
        'sha256': download.sha256,
        'attempts': download.attempts,
      });

    final savedPath = _saveDownload(download.bytes, startedAt);

    SourceParseResult parsed;
    try {
      parsed = const SourceParser().parseBytes(download.bytes);
    } on SourceStructureException catch (error) {
      return _handleParseFailure(error, savedPath, download, startedAt);
    }

    final actualityDate = parsed.document.actualityDate;
    final existing = db.versionByActualityDate(actualityDate);
    final latest = db.latestVersion();

    if (existing != null) {
      return _handleSameActualityDate(
        existing: existing,
        parsed: parsed,
        download: download,
        savedPath: savedPath,
        startedAt: startedAt,
      );
    }

    if (latest != null && !actualityDate.isAfter(latest.actualityDate)) {
      _finishCheck(startedAt, 'no_change');
      db.addEvent(EventType.noNewVersion, payload: {
        'actualityDate': MoscowTime.format(actualityDate),
        'latestActualityDate': MoscowTime.format(latest.actualityDate),
      });
      await notifier.noChanges(
        checkedAt: startedAt,
        lastActuality: latest.actualityDate,
      );
      return CheckOutcome(
        status: CheckStatus.noChange,
        version: latest,
        message: 'новой версии нет',
      );
    }

    return _createVersion(
      parsed: parsed,
      download: download,
      savedPath: savedPath,
      previousVersion: latest,
      startedAt: startedAt,
    );
  }

  /// Загружает в пустую базу файл перечня, приложенный к комплекту.
  ///
  /// Иначе после установки ответственный открывает интерфейс и видит пустой
  /// список — до первой ночной проверки или до нажатия «Проверить сейчас».
  ///
  /// Срабатывает один раз: если версии в базе уже есть, файл не трогается.
  /// Возвращает `null`, когда делать нечего или файл негоден.
  Future<CheckOutcome?> seedFromBundle() async {
    if (db.latestVersion() != null) return null;
    final path = config.seedFile;
    if (path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;

    final startedAt = _clock();
    final Uint8List bytes;
    try {
      bytes = file.readAsBytesSync();
    } on FileSystemException catch (error) {
      _logger.error('стартовый файл перечня не прочитан', {
        'path': path,
        'error': '$error',
      });
      return null;
    }

    final SourceParseResult parsed;
    try {
      parsed = const SourceParser().parseBytes(bytes);
    } on SourceStructureException catch (error) {
      // Негодный файл в комплекте — не повод не запускаться: сервис поднимется
      // с пустой базой и наполнит её сам по расписанию.
      _logger.error('стартовый файл перечня не разобран', {
        'path': path,
        'error': '$error',
      });
      return null;
    }

    return _createVersion(
      parsed: parsed,
      download: DownloadResult(
        bytes: bytes,
        url: path,
        sha256: sha256.convert(bytes).toString(),
        attempts: 0,
      ),
      savedPath: _saveDownload(bytes, startedAt),
      previousVersion: null,
      startedAt: startedAt,
      source: _VersionSource.bundle,
    );
  }

  Future<CheckOutcome> _createVersion({
    required SourceParseResult parsed,
    required DownloadResult download,
    required String savedPath,
    required PerechenVersion? previousVersion,
    required DateTime startedAt,
    _VersionSource source = _VersionSource.site,
  }) async {
    final actualityDate = parsed.document.actualityDate;
    final versionId = db.insertVersion(
      actualityDate: actualityDate,
      downloadedAt: startedAt,
      fileSha256: download.sha256,
      sourcePath: savedPath,
      status: VersionStatus.downloading,
    );

    final renamedPath = _renameDownload(savedPath, actualityDate);
    db.updateVersion(versionId, sourcePath: renamedPath);

    final result = _buildVersion(
      versionId: versionId,
      document: parsed.document,
      previousVersion: previousVersion,
      warnings: parsed.warnings,
    );

    final version = db.versionById(versionId)!;
    db.addEvent(
      EventType.versionCreated,
      payload: {
        'actualityDate': MoscowTime.format(actualityDate),
        'counters': result.counters.toJson(),
        'warnings': parsed.warnings,
        if (source == _VersionSource.bundle) 'source': 'комплект поставки',
      },
      versionId: versionId,
    );

    // Стартовые данные — не результат проверки сайта: отмечать ими время
    // последней проверки нельзя, иначе индикатор в интерфейсе врёт. Писем по
    // ним тоже не шлют: рассылать при установке нечего, да и SMTP на свежей
    // машине ещё не настроен.
    if (source == _VersionSource.site) {
      _finishCheck(startedAt, 'new_version');
      await notifier.newVersionFound(
        version: version,
        addedRecords: result.records.where((r) => r.isNew).toList(),
        excludedRecords: result.excluded,
        autoPublishDeadline: _nextAutoPublishAt(),
        warnings: parsed.warnings,
      );
    }

    return CheckOutcome(
      status: CheckStatus.newVersion,
      version: version,
      counters: result.counters,
      message: source == _VersionSource.bundle
          ? 'загружены стартовые данные '
              '(${MoscowTime.format(actualityDate)})'
          : 'создана версия ${MoscowTime.format(actualityDate)}',
    );
  }

  /// Разбирает документ, применяет правки, считает diff и сохраняет в БД.
  PipelineResult _buildVersion({
    required int versionId,
    required SourceDocument document,
    required PerechenVersion? previousVersion,
    List<String> warnings = const [],
  }) {
    final previousRows = previousVersion == null
        ? const <SourceRow>[]
        : db.sourceRowsOf(previousVersion.id);

    final result = pipeline.runOnDocument(
      document,
      previousRows: previousRows,
      corrections: db.activeCorrections(),
      warnings: warnings,
    );

    db
      // при пересборке версии старые строки не должны оставаться
      ..clearVersionRecords(versionId)
      ..saveSourceRows(versionId, document.rows)
      ..saveParsedRecords(versionId, [...result.records, ...result.excluded])
      ..updateVersion(
        versionId,
        status: VersionStatus.pendingReview,
        counters: result.counters,
      );

    for (final record in result.records) {
      if (record.staleCorrections.isEmpty) continue;
      db.markCorrectionsStale(
        record.orgKey,
        record.staleCorrections.map((c) => c.field).toList(),
      );
    }
    return result;
  }

  Future<CheckOutcome> _handleSameActualityDate({
    required PerechenVersion existing,
    required SourceParseResult parsed,
    required DownloadResult download,
    required String savedPath,
    required DateTime startedAt,
  }) async {
    // Сравниваем данные, а не байты файла: реестр Минюста собирает xlsx на
    // каждый запрос и штампует в него время генерации, поэтому sha256 файла
    // различается даже у двух скачиваний подряд. Байтовый хэш остаётся в
    // журнале для аудита, но критерием изменений быть не может.
    final previousDataHash = sourceDataHash(db.sourceRowsOf(existing.id));
    final currentDataHash = parsed.document.dataHash;

    if (previousDataHash == currentDataHash) {
      _finishCheck(startedAt, 'no_change');
      db.addEvent(
        EventType.noNewVersion,
        payload: {'actualityDate': MoscowTime.format(existing.actualityDate)},
        versionId: existing.id,
      );
      await notifier.noChanges(
        checkedAt: startedAt,
        lastActuality: existing.actualityDate,
      );
      return CheckOutcome(
        status: CheckStatus.noChange,
        version: existing,
        message: 'новой версии нет',
      );
    }

    // FR-2: содержимое изменилось, дата актуальности — нет.
    db.addEvent(
      EventType.contentChangedSameDate,
      payload: {
        'actualityDate': MoscowTime.format(existing.actualityDate),
        'previousDataSha256': previousDataHash,
        'currentDataSha256': currentDataHash,
        // Хэши файлов различаются на каждом скачивании, поэтому они здесь
        // только для аудита.
        'previousFileSha256': existing.fileSha256,
        'currentFileSha256': download.sha256,
      },
      versionId: existing.id,
    );

    if (!existing.isPublished) {
      final previous = _previousVersionFor(existing);
      _buildVersion(
        versionId: existing.id,
        document: parsed.document,
        previousVersion: previous,
        warnings: parsed.warnings,
      );
      db.updateVersion(
        existing.id,
        status: VersionStatus.pendingReview,
        errorText: 'файл изменился без смены даты актуальности, '
            'версия пересобрана ${MoscowTime.format(startedAt)}',
        sourcePath: _renameDownload(savedPath, existing.actualityDate),
      );
    }

    _finishCheck(startedAt, 'content_changed_same_date');
    await notifier.contentChangedWithoutDate(
      actualityDate: existing.actualityDate,
      previousDataSha: previousDataHash,
      currentDataSha: currentDataHash,
    );

    return CheckOutcome(
      status: CheckStatus.contentChangedSameDate,
      version: db.versionById(existing.id),
      message: 'файл изменился без смены даты актуальности',
    );
  }

  Future<CheckOutcome> _handleDownloadFailure(
    Object error,
    DateTime startedAt,
  ) async {
    final streak = (int.tryParse(db.meta(_unavailableStreakKey) ?? '0') ?? 0) + 1;
    db
      ..setMeta(_unavailableStreakKey, '$streak')
      ..addEvent(EventType.downloadFailed, payload: {
        'error': '$error',
        'streak': streak,
      });
    _finishCheck(startedAt, 'error');
    _logger.error('не удалось скачать файл перечня', {'error': '$error'});

    await notifier.failure(
      reason: 'файл перечня не скачался',
      details: '$error',
    );
    if (streak >= config.unavailableEscalateDays) {
      await notifier.unavailableEscalation(days: streak, lastError: '$error');
    }
    return CheckOutcome(
      status: CheckStatus.error,
      message: 'не удалось скачать файл: $error',
    );
  }

  Future<CheckOutcome> _handleParseFailure(
    SourceStructureException error,
    String savedPath,
    DownloadResult download,
    DateTime startedAt,
  ) async {
    _logger.error('структура файла не распознана', {'error': '$error'});
    int? versionId;
    try {
      // Ошибочная версия сохраняется для аудита; дата актуальности неизвестна,
      // поэтому в ключ идёт момент скачивания.
      versionId = db.insertVersion(
        actualityDate: startedAt,
        downloadedAt: startedAt,
        fileSha256: download.sha256,
        sourcePath: savedPath,
        status: VersionStatus.error,
      );
      db.updateVersion(
        versionId,
        errorText: '${error.message}${error.details == null ? '' : ' — '
            '${error.details}'}',
      );
    } catch (_) {
      versionId = null;
    }

    db.addEvent(
      EventType.parseFailed,
      payload: {
        'error': error.message,
        'details': error.details,
        'file': savedPath,
      },
      versionId: versionId,
    );
    _finishCheck(startedAt, 'error');

    await notifier.failure(
      reason: 'структура файла не распознана',
      details: '${error.message}. Файл сохранён: $savedPath',
      versionId: versionId,
    );

    return CheckOutcome(
      status: CheckStatus.error,
      version: versionId == null ? null : db.versionById(versionId),
      message: error.message,
    );
  }

  /// Подтверждение ответственным: публикация целевого файла (FR-5).
  Future<PublishResult> confirm(int versionId, String actor) async {
    db
      ..updateVersion(versionId, status: VersionStatus.confirmed)
      ..addEvent(
        EventType.versionConfirmed,
        payload: {'actor': actor},
        versionId: versionId,
      );
    return publisher.publish(versionId, actor: actor, auto: false);
  }

  /// Авто-публикация неподтверждённых версий по расписанию (FR-5).
  Future<List<PublishResult>> autoPublishPending() async {
    final pending = [
      ...db.versionsWithStatus(VersionStatus.pendingReview),
      ...db.versionsWithStatus(VersionStatus.parsed),
    ];
    final results = <PublishResult>[];
    for (final version in pending) {
      db.updateVersion(version.id, status: VersionStatus.autoPublished);
      try {
        final result = publisher.publish(
          version.id,
          actor: 'auto',
          auto: true,
        );
        results.add(result);
        await notifier.autoPublished(
          version: result.version,
          fileName: result.fileName,
        );
      } on PublishException catch (error) {
        db
          ..updateVersion(
            version.id,
            status: VersionStatus.error,
            errorText: error.message,
          )
          ..addEvent(
            EventType.error,
            payload: {'stage': 'auto_publish', 'error': error.message},
            versionId: version.id,
          );
        await notifier.failure(
          reason: 'авто-публикация не выполнена',
          details: error.message,
          versionId: version.id,
        );
      }
    }
    return results;
  }

  /// Сохранение ручной правки и пересборка затронутой записи (FR-4).
  Map<String, Object?> saveCorrection({
    required int versionId,
    required String orgKey,
    required Map<String, String> values,
    required String author,
  }) {
    final sourceRow = _sourceRow(versionId, orgKey);
    if (sourceRow == null) {
      throw ArgumentError('запись $orgKey не найдена в версии $versionId');
    }
    final hash = sourceRow.sourceNameHash;
    final applied = <String>[];
    values.forEach((fieldId, value) {
      final field = RecordField.byId(fieldId);
      if (field == null) return;
      db.saveCorrection(
        orgKey: orgKey,
        field: field,
        value: value,
        sourceNameHash: hash,
        author: author,
      );
      applied.add(field.id);
    });
    db.addEvent(
      EventType.correctionSaved,
      payload: {'orgKey': orgKey, 'fields': applied, 'author': author},
      versionId: versionId,
    );
    return _reparseRecord(versionId, orgKey, sourceRow);
  }

  /// Возврат поля к автоматическому разбору (FR-4).
  Map<String, Object?> revertCorrection({
    required int versionId,
    required String orgKey,
    required List<String> fields,
    required String author,
  }) {
    final sourceRow = _sourceRow(versionId, orgKey);
    if (sourceRow == null) {
      throw ArgumentError('запись $orgKey не найдена в версии $versionId');
    }
    for (final fieldId in fields) {
      final field = RecordField.byId(fieldId);
      if (field == null) continue;
      db.revertCorrection(orgKey, field);
    }
    db.addEvent(
      EventType.correctionReverted,
      payload: {'orgKey': orgKey, 'fields': fields, 'author': author},
      versionId: versionId,
    );
    return _reparseRecord(versionId, orgKey, sourceRow);
  }

  Map<String, Object?> _reparseRecord(
    int versionId,
    String orgKey,
    SourceRow sourceRow,
  ) {
    final mapper = pipeline.mapper;
    const applier = CorrectionApplier();
    final corrections = db.activeCorrections()[orgKey] ?? const [];
    final stored = db.recordOf(versionId, orgKey);
    final record = applier.apply(mapper.map(sourceRow), corrections).copyWith(
          isNew: (stored?['isNew'] as bool?) ?? false,
          isChanged: (stored?['isChanged'] as bool?) ?? false,
          isExcluded: (stored?['isExcluded'] as bool?) ?? false,
          previousRawName: stored?['previousRawName'] as String?,
        );
    db.saveParsedRecords(versionId, [record]);
    _refreshCounters(versionId);
    return db.recordOf(versionId, orgKey)!;
  }

  void _refreshCounters(int versionId) {
    final version = db.versionById(versionId);
    if (version == null) return;
    db.updateVersion(
      versionId,
      counters: VersionCounters(
        total: db.countRecords(versionId, RecordFilter.all),
        added: db.countRecords(versionId, RecordFilter.isNew),
        excluded: db.countRecords(versionId, RecordFilter.excluded),
        changed: db.countRecords(versionId, RecordFilter.changed),
        review: db.countRecords(versionId, RecordFilter.review),
        edited: db.countRecords(versionId, RecordFilter.edited),
      ),
    );
  }

  /// Повторный прогон парсера по уже скачанному файлу версии (п. 12 ТЗ).
  Future<CheckOutcome> reparse(int versionId) async {
    final version = db.versionById(versionId);
    if (version == null) {
      return CheckOutcome(
        status: CheckStatus.error,
        message: 'версия $versionId не найдена',
      );
    }
    final file = File(version.sourcePath);
    if (!file.existsSync()) {
      return CheckOutcome(
        status: CheckStatus.error,
        message: 'файл версии не найден: ${version.sourcePath}',
      );
    }
    final parsed = const SourceParser().parseBytes(file.readAsBytesSync());
    final result = _buildVersion(
      versionId: versionId,
      document: parsed.document,
      previousVersion: _previousVersionFor(version),
      warnings: parsed.warnings,
    );
    return CheckOutcome(
      status: CheckStatus.newVersion,
      version: db.versionById(versionId),
      counters: result.counters,
      message: 'версия пересобрана',
    );
  }

  PerechenVersion? _previousVersionFor(PerechenVersion version) {
    final all = db.listVersions(limit: 1000);
    for (final candidate in all) {
      if (candidate.id == version.id) continue;
      if (candidate.status == VersionStatus.error) continue;
      if (candidate.actualityDate.isBefore(version.actualityDate)) {
        return candidate;
      }
    }
    return null;
  }

  SourceRow? _sourceRow(int versionId, String orgKey) {
    for (final row in db.sourceRowsOf(versionId)) {
      if (orgKeyOf(row) == orgKey) return row;
    }
    return null;
  }

  String _saveDownload(Uint8List bytes, DateTime startedAt) {
    final directory = Directory(config.downloadsDir);
    if (!directory.existsSync()) directory.createSync(recursive: true);
    // `2026-08-20_18-46-14` — без смещения пояса: все даты сервиса московские.
    final stamp = MoscowTime.format(startedAt)
        .substring(0, 19)
        .replaceAll(':', '-')
        .replaceAll('T', '_');
    final file = File(p.join(directory.path, 'export_$stamp.xlsx'));
    file.writeAsBytesSync(bytes, flush: true);
    return file.path;
  }

  /// Добавляет дату актуальности в имя сохранённого файла (FR-1).
  String _renameDownload(String path, DateTime actualityDate) {
    final file = File(path);
    if (!file.existsSync()) return path;
    final name = p.basename(path).replaceFirst(
          'export_',
          'export_${formatFileNameDate(actualityDate)}_',
        );
    final target = p.join(p.dirname(path), name);
    if (target == path) return path;
    try {
      return file.renameSync(target).path;
    } catch (_) {
      return path;
    }
  }

  void _finishCheck(DateTime startedAt, String status) {
    db
      ..setMeta(_lastCheckKey, MoscowTime.format(startedAt))
      ..setMeta(_lastCheckStatusKey, status);
  }

  /// Ближайшее время авто-публикации (для письма и индикатора в UI).
  DateTime _nextAutoPublishAt() {
    try {
      return CronSchedule.parse(config.autoPublishCron).nextRunAfter(_clock());
    } on FormatException {
      return _clock().add(const Duration(hours: 12));
    }
  }
}
