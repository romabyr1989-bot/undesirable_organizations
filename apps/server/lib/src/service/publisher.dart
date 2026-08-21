/// Генерация и публикация целевого CSV (FR-5).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:perechen_core/perechen_core.dart';

import '../config/app_config.dart';
import '../db/database.dart';
import '../util/logging.dart';
import '../util/moscow_time.dart';

class PublishResult {
  PublishResult({
    required this.version,
    required this.fileName,
    required this.cdiPath,
    required this.archivePath,
    required this.rowCount,
    required this.warnings,
  });

  final PerechenVersion version;
  final String fileName;
  final String cdiPath;
  final String archivePath;
  final int rowCount;
  final List<CsvWarning> warnings;
}

class PublishException implements Exception {
  PublishException(this.message);

  final String message;

  @override
  String toString() => 'PublishException: $message';
}

class Publisher {
  Publisher({
    required this.config,
    required this.db,
    AppLogger? logger,
  }) : _logger = logger ?? AppLogger();

  final AppConfig config;
  final AppDatabase db;
  final AppLogger _logger;

  CsvWriter get _writer => CsvWriter(config: config.core);

  /// Собирает целевой CSV версии из БД (для предпросмотра и публикации).
  CsvBuildResult buildCsv(int versionId) {
    final version = db.versionById(versionId);
    if (version == null) {
      throw PublishException('версия $versionId не найдена');
    }
    return _writer.buildFromRows(
      actualityDate: version.actualityDate,
      rows: db.targetRowsOf(versionId),
    );
  }

  /// Публикует версию: пишет файл в `CDI_DROP_DIR` атомарно (временный файл
  /// + rename) и складывает копию в `data/published/`.
  ///
  /// Повторная публикация той же версии идемпотентна.
  PublishResult publish(
    int versionId, {
    required String actor,
    required bool auto,
  }) {
    final version = db.versionById(versionId);
    if (version == null) {
      throw PublishException('версия $versionId не найдена');
    }
    if (version.status == VersionStatus.error) {
      throw PublishException('версия $versionId помечена ошибочной');
    }

    final csv = buildCsv(versionId);
    final archivePath = _writeArchiveCopy(csv);
    final cdiPath = _writeToCdi(csv);

    db
      ..updateVersion(
        versionId,
        status: VersionStatus.published,
        publishedAt: MoscowTime.now(),
        publishedFileName: csv.fileName,
        confirmedBy: actor,
      )
      ..addEvent(
        auto ? EventType.autoPublished : EventType.published,
        payload: {
          'fileName': csv.fileName,
          'rows': csv.rowCount,
          'cdiPath': cdiPath,
          'archivePath': archivePath,
          'actor': actor,
          'warnings': csv.warnings.length,
        },
        versionId: versionId,
      );

    _logger.info('версия опубликована', {
      'versionId': versionId,
      'fileName': csv.fileName,
      'rows': csv.rowCount,
      'auto': auto,
    });

    return PublishResult(
      version: db.versionById(versionId)!,
      fileName: csv.fileName,
      cdiPath: cdiPath,
      archivePath: archivePath,
      rowCount: csv.rowCount,
      warnings: csv.warnings,
    );
  }

  String _writeArchiveCopy(CsvBuildResult csv) {
    final directory = Directory(config.publishedDir);
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final file = File(p.join(directory.path, csv.fileName));
    file.writeAsBytesSync(csv.bytes, flush: true);
    return file.path;
  }

  /// Атомарная запись в папку CDI: временный файл рядом + rename.
  String _writeToCdi(CsvBuildResult csv) {
    final directory = Directory(config.cdiDropDir);
    if (!directory.existsSync()) {
      try {
        directory.createSync(recursive: true);
      } catch (error) {
        throw PublishException(
          'папка CDI недоступна (${config.cdiDropDir}): $error',
        );
      }
    }
    final targetPath = p.join(directory.path, csv.fileName);
    final temporaryPath = p.join(
      directory.path,
      '.${csv.fileName}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    final temporaryFile = File(temporaryPath);
    try {
      temporaryFile.writeAsBytesSync(csv.bytes, flush: true);
      _renameWithRetry(temporaryFile, targetPath);
    } catch (error) {
      if (temporaryFile.existsSync()) temporaryFile.deleteSync();
      throw PublishException('не удалось записать файл в CDI: $error');
    }
    return targetPath;
  }

  /// Переименование с несколькими попытками.
  ///
  /// Windows (в отличие от Linux в контейнере) не даёт заменить файл, пока
  /// его держит открытым другой процесс: если скрипт CDI как раз читает
  /// предыдущую выгрузку, замена падает с ошибкой совместного доступа.
  /// Несколько коротких попыток снимают эту гонку, атомарность сохраняется.
  void _renameWithRetry(File source, String targetPath) {
    const attempts = 5;
    const pause = Duration(milliseconds: 200);
    for (var attempt = 1;; attempt++) {
      try {
        source.renameSync(targetPath);
        return;
      } on FileSystemException catch (error) {
        if (attempt >= attempts) rethrow;
        _logger.warning('файл CDI занят, повтор', {
          'target': targetPath,
          'attempt': attempt,
          'error': '${error.osError ?? error.message}',
        });
        sleep(pause);
      }
    }
  }
}
