/// Хранилище сервиса (FR-7).
///
/// SQLite через пакет `sqlite3`. Схема намеренно простая (TEXT/INTEGER, без
/// специфичных для SQLite типов), чтобы её можно было перенести на PostgreSQL:
/// достаточно заменить `INTEGER PRIMARY KEY AUTOINCREMENT` на `SERIAL`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:perechen_core/perechen_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../util/moscow_time.dart';
import 'sqlite_library.dart';

/// Фильтры списка записей (FR-6).
enum RecordFilter {
  all('all'),
  isNew('new'),
  changed('changed'),
  excluded('excluded'),
  review('review'),
  edited('edited');

  const RecordFilter(this.id);

  final String id;

  static RecordFilter byId(String? id) => RecordFilter.values.firstWhere(
        (f) => f.id == id,
        orElse: () => RecordFilter.all,
      );
}

/// Событие журнала (п. 12 ТЗ, экран 3 UI).
class AppEvent {
  AppEvent({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.payload,
    this.versionId,
  });

  final int id;
  final DateTime timestamp;
  final String type;
  final Map<String, Object?> payload;
  final int? versionId;

  Map<String, Object?> toJson() => {
        'id': id,
        'ts': MoscowTime.format(timestamp),
        'type': type,
        'payload': payload,
        'versionId': versionId,
      };
}

/// Типы событий журнала.
class EventType {
  static const checkStarted = 'check_started';
  static const downloadOk = 'download_ok';
  static const downloadFailed = 'download_failed';
  static const parseFailed = 'parse_failed';
  static const versionCreated = 'version_created';
  static const noNewVersion = 'no_new_version';
  static const contentChangedSameDate = 'content_changed_same_date';
  static const correctionSaved = 'correction_saved';
  static const correctionReverted = 'correction_reverted';
  static const versionConfirmed = 'version_confirmed';
  static const published = 'published';
  static const autoPublished = 'auto_published';
  static const emailSent = 'email_sent';
  static const emailFailed = 'email_failed';
  static const error = 'error';
}

class AppDatabase {
  AppDatabase(this._db) {
    _db.execute('PRAGMA foreign_keys = ON;');
    _migrate();
  }

  /// Открывает файл БД (создавая каталог при необходимости).
  factory AppDatabase.open(String path) {
    SqliteLibrary.ensureConfigured();
    if (path != ':memory:') {
      final directory = Directory(File(path).parent.path);
      if (!directory.existsSync()) directory.createSync(recursive: true);
    }
    return AppDatabase(sqlite3.open(path));
  }

  /// БД в памяти (тесты).
  factory AppDatabase.memory() {
    SqliteLibrary.ensureConfigured();
    return AppDatabase(sqlite3.openInMemory());
  }

  final Database _db;

  /// Версия схемы; при изменении добавляется новая миграция.
  static const schemaVersion = 1;

  void close() => _db.dispose();

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS versions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actuality_date TEXT NOT NULL UNIQUE,
        downloaded_at TEXT NOT NULL,
        file_sha256 TEXT NOT NULL,
        source_path TEXT NOT NULL,
        status TEXT NOT NULL,
        counters_json TEXT NOT NULL DEFAULT '{}',
        error_text TEXT,
        published_at TEXT,
        published_file_name TEXT,
        confirmed_by TEXT
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS source_records (
        version_id INTEGER NOT NULL REFERENCES versions(id) ON DELETE CASCADE,
        org_key TEXT NOT NULL,
        row_num INTEGER NOT NULL,
        col1 TEXT NOT NULL DEFAULT '',
        col2 TEXT NOT NULL DEFAULT '',
        col3 TEXT NOT NULL DEFAULT '',
        col4 TEXT NOT NULL DEFAULT '',
        col5 TEXT NOT NULL DEFAULT '',
        col6 TEXT NOT NULL DEFAULT '',
        col7 TEXT NOT NULL DEFAULT '',
        col8 TEXT NOT NULL DEFAULT '',
        col9 TEXT NOT NULL DEFAULT '',
        col10 TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (version_id, org_key)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS parsed_records (
        version_id INTEGER NOT NULL REFERENCES versions(id) ON DELETE CASCADE,
        org_key TEXT NOT NULL,
        row_num INTEGER NOT NULL,
        target_no TEXT NOT NULL DEFAULT '',
        incl_order TEXT NOT NULL DEFAULT '',
        gp_decision TEXT NOT NULL DEFAULT '',
        name_rus TEXT NOT NULL DEFAULT '',
        name_add TEXT NOT NULL DEFAULT '',
        country TEXT NOT NULL DEFAULT '',
        excl_order TEXT NOT NULL DEFAULT '',
        gp_cancel TEXT NOT NULL DEFAULT '',
        confidence TEXT NOT NULL DEFAULT 'ok',
        notes_json TEXT NOT NULL DEFAULT '[]',
        auto_values_json TEXT NOT NULL DEFAULT '{}',
        edited_fields_json TEXT NOT NULL DEFAULT '[]',
        stale_json TEXT NOT NULL DEFAULT '[]',
        candidates_json TEXT NOT NULL DEFAULT '[]',
        is_new INTEGER NOT NULL DEFAULT 0,
        is_changed INTEGER NOT NULL DEFAULT 0,
        is_excluded INTEGER NOT NULL DEFAULT 0,
        -- сырое наименование дублируется здесь: у исчезнувших записей строки
        -- в source_records текущей версии нет, а показать её в UI надо
        raw_name TEXT NOT NULL DEFAULT '',
        previous_raw_name TEXT,
        PRIMARY KEY (version_id, org_key)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS corrections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        org_key TEXT NOT NULL,
        field TEXT NOT NULL,
        value TEXT NOT NULL,
        source_name_hash TEXT NOT NULL,
        author TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_stale INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1
      );
    ''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS corrections_org_key ON corrections(org_key);',
    );
    _db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts TEXT NOT NULL,
        type TEXT NOT NULL,
        payload_json TEXT NOT NULL DEFAULT '{}',
        version_id INTEGER
      );
    ''');
    _db.execute('CREATE INDEX IF NOT EXISTS events_ts ON events(ts);');
    setMeta('schema_version', '$schemaVersion');
  }

  // ---------------------------------------------------------------- meta

  String? meta(String key) {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?;', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setMeta(String key, String value) => _db.execute(
        'INSERT INTO meta(key, value) VALUES(?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value;',
        [key, value],
      );

  // ------------------------------------------------------------ versions

  /// Создаёт версию и возвращает её идентификатор.
  int insertVersion({
    required DateTime actualityDate,
    required DateTime downloadedAt,
    required String fileSha256,
    required String sourcePath,
    required VersionStatus status,
  }) {
    _db.execute(
      'INSERT INTO versions(actuality_date, downloaded_at, file_sha256, '
      'source_path, status) VALUES(?, ?, ?, ?, ?);',
      [
        MoscowTime.format(actualityDate),
        MoscowTime.format(downloadedAt),
        fileSha256,
        sourcePath,
        status.id,
      ],
    );
    return _db.lastInsertRowId;
  }

  void updateVersion(
    int id, {
    VersionStatus? status,
    VersionCounters? counters,
    String? errorText,
    DateTime? publishedAt,
    String? publishedFileName,
    String? confirmedBy,
    String? sourcePath,
  }) {
    final assignments = <String>[];
    final values = <Object?>[];
    if (status != null) {
      assignments.add('status = ?');
      values.add(status.id);
    }
    if (counters != null) {
      assignments.add('counters_json = ?');
      values.add(jsonEncode(counters.toJson()));
    }
    if (errorText != null) {
      assignments.add('error_text = ?');
      values.add(errorText);
    }
    if (publishedAt != null) {
      assignments.add('published_at = ?');
      values.add(MoscowTime.format(publishedAt));
    }
    if (publishedFileName != null) {
      assignments.add('published_file_name = ?');
      values.add(publishedFileName);
    }
    if (confirmedBy != null) {
      assignments.add('confirmed_by = ?');
      values.add(confirmedBy);
    }
    if (sourcePath != null) {
      assignments.add('source_path = ?');
      values.add(sourcePath);
    }
    if (assignments.isEmpty) return;
    values.add(id);
    _db.execute(
      'UPDATE versions SET ${assignments.join(', ')} WHERE id = ?;',
      values,
    );
  }

  PerechenVersion? versionById(int id) {
    final rows = _db.select('SELECT * FROM versions WHERE id = ?;', [id]);
    return rows.isEmpty ? null : _versionOf(rows.first);
  }

  PerechenVersion? versionByActualityDate(DateTime date) {
    final rows = _db.select(
      'SELECT * FROM versions WHERE actuality_date = ?;',
      [MoscowTime.format(date)],
    );
    return rows.isEmpty ? null : _versionOf(rows.first);
  }

  /// Последняя по дате актуальности успешно разобранная версия.
  PerechenVersion? latestVersion({bool excludeErrors = true}) {
    final where = excludeErrors ? "WHERE status <> 'ERROR'" : '';
    final rows = _db.select(
      'SELECT * FROM versions $where ORDER BY actuality_date DESC LIMIT 1;',
    );
    return rows.isEmpty ? null : _versionOf(rows.first);
  }

  List<PerechenVersion> listVersions({int limit = 100}) => _db
      .select(
        'SELECT * FROM versions ORDER BY actuality_date DESC LIMIT ?;',
        [limit],
      )
      .map(_versionOf)
      .toList();

  List<PerechenVersion> versionsWithStatus(VersionStatus status) => _db
      .select(
        'SELECT * FROM versions WHERE status = ? ORDER BY actuality_date;',
        [status.id],
      )
      .map(_versionOf)
      .toList();

  PerechenVersion _versionOf(Row row) => PerechenVersion(
        id: row['id']! as int,
        actualityDate: MoscowTime.parse(row['actuality_date']! as String),
        downloadedAt: MoscowTime.parse(row['downloaded_at']! as String),
        fileSha256: row['file_sha256']! as String,
        sourcePath: row['source_path']! as String,
        status: VersionStatus.byId(row['status']! as String),
        counters: VersionCounters.fromJson(
          jsonDecode(row['counters_json']! as String) as Map<String, Object?>,
        ),
        errorText: row['error_text'] as String?,
        publishedAt: row['published_at'] == null
            ? null
            : MoscowTime.parse(row['published_at']! as String),
        publishedFileName: row['published_file_name'] as String?,
        confirmedBy: row['confirmed_by'] as String?,
      );

  // ------------------------------------------------------- source records

  /// Удаляет строки версии перед её пересборкой (перерасбор, повторный разбор
  /// изменившегося файла с той же датой актуальности).
  void clearVersionRecords(int versionId) {
    _db
      ..execute('DELETE FROM source_records WHERE version_id = ?;', [versionId])
      ..execute('DELETE FROM parsed_records WHERE version_id = ?;', [versionId]);
  }

  void saveSourceRows(int versionId, List<SourceRow> rows) {
    final statement = _db.prepare(
      'INSERT OR REPLACE INTO source_records(version_id, org_key, row_num, '
      'col1, col2, col3, col4, col5, col6, col7, col8, col9, col10) '
      'VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?);',
    );
    try {
      _db.execute('BEGIN;');
      for (final row in rows) {
        statement.execute([
          versionId,
          orgKeyOf(row),
          row.rowNum,
          ...row.cells,
        ]);
      }
      _db.execute('COMMIT;');
    } catch (error) {
      _db.execute('ROLLBACK;');
      rethrow;
    } finally {
      statement.dispose();
    }
  }

  List<SourceRow> sourceRowsOf(int versionId) => _db
      .select(
        'SELECT * FROM source_records WHERE version_id = ? ORDER BY row_num;',
        [versionId],
      )
      .map(
        (row) => SourceRow(
          rowNum: row['row_num']! as int,
          cells: [
            for (var index = 1; index <= SourceRow.columnCount; index++)
              (row['col$index'] ?? '') as String,
          ],
        ),
      )
      .toList();

  // ------------------------------------------------------- parsed records

  void saveParsedRecords(int versionId, List<ParsedRecord> records) {
    final statement = _db.prepare(
      'INSERT OR REPLACE INTO parsed_records(version_id, org_key, row_num, '
      'target_no, incl_order, gp_decision, name_rus, name_add, country, '
      'excl_order, gp_cancel, confidence, notes_json, auto_values_json, '
      'edited_fields_json, stale_json, candidates_json, is_new, is_changed, '
      'is_excluded, raw_name, previous_raw_name) '
      'VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);',
    );
    try {
      _db.execute('BEGIN;');
      for (final record in records) {
        statement.execute([
          versionId,
          record.orgKey,
          record.rowNum,
          record.value(RecordField.targetNo),
          record.value(RecordField.inclOrder),
          record.value(RecordField.gpDecision),
          record.value(RecordField.nameRus),
          record.value(RecordField.nameAdd),
          record.value(RecordField.country),
          record.value(RecordField.exclOrder),
          record.value(RecordField.gpCancel),
          record.confidence.name,
          jsonEncode(record.notes),
          jsonEncode({
            for (final entry in record.autoValues.entries)
              entry.key.id: entry.value,
          }),
          jsonEncode(record.editedFields.map((f) => f.id).toList()),
          jsonEncode(record.staleCorrections.map((c) => c.toJson()).toList()),
          jsonEncode(
            record.parsedName?.candidates.map((c) => c.toJson()).toList() ??
                const [],
          ),
          record.isNew ? 1 : 0,
          record.isChanged ? 1 : 0,
          record.isExcluded ? 1 : 0,
          record.sourceRow.rawName,
          record.previousRawName,
        ]);
      }
      _db.execute('COMMIT;');
    } catch (error) {
      _db.execute('ROLLBACK;');
      rethrow;
    } finally {
      statement.dispose();
    }
  }

  /// Записи версии в виде json для API (вместе с сырой строкой).
  List<Map<String, Object?>> recordsOf(
    int versionId, {
    RecordFilter filter = RecordFilter.all,
    String? search,
    int limit = 5000,
    int offset = 0,
  }) {
    final where = StringBuffer('p.version_id = ?');
    final values = <Object?>[versionId];
    switch (filter) {
      case RecordFilter.all:
        where.write(' AND p.is_excluded = 0');
      case RecordFilter.isNew:
        where.write(' AND p.is_new = 1');
      case RecordFilter.changed:
        where.write(' AND p.is_changed = 1');
      case RecordFilter.excluded:
        where.write(' AND p.is_excluded = 1');
      case RecordFilter.review:
        where.write(" AND p.confidence = 'review' AND p.is_excluded = 0");
      case RecordFilter.edited:
        where.write(" AND p.edited_fields_json <> '[]' AND p.is_excluded = 0");
    }
    if (search != null && search.trim().isNotEmpty) {
      where.write(' AND (LOWER(p.name_rus) LIKE ? OR LOWER(p.name_add) LIKE ? '
          'OR LOWER(p.country) LIKE ? OR LOWER(p.raw_name) LIKE ? '
          'OR LOWER(p.incl_order) LIKE ?)');
      final pattern = '%${search.trim().toLowerCase()}%';
      values.addAll([pattern, pattern, pattern, pattern, pattern]);
    }
    values.addAll([limit, offset]);

    final rows = _db.select(
      'SELECT p.*, s.col10 AS source_status '
      'FROM parsed_records p '
      'LEFT JOIN source_records s '
      '  ON s.version_id = p.version_id AND s.org_key = p.org_key '
      'WHERE $where ORDER BY p.row_num LIMIT ? OFFSET ?;',
      values,
    );
    return rows.map(_recordJson).toList();
  }

  Map<String, Object?>? recordOf(int versionId, String orgKey) {
    final rows = _db.select(
      'SELECT p.*, s.col10 AS source_status '
      'FROM parsed_records p '
      'LEFT JOIN source_records s '
      '  ON s.version_id = p.version_id AND s.org_key = p.org_key '
      'WHERE p.version_id = ? AND p.org_key = ?;',
      [versionId, orgKey],
    );
    return rows.isEmpty ? null : _recordJson(rows.first);
  }

  /// Записи версии для генерации CSV (в порядке первоисточника).
  List<List<String>> targetRowsOf(int versionId) => _db
      .select(
        'SELECT target_no, incl_order, gp_decision, name_rus, name_add, '
        'country, excl_order, gp_cancel FROM parsed_records '
        'WHERE version_id = ? AND is_excluded = 0 ORDER BY row_num;',
        [versionId],
      )
      .map((row) => [
            row['target_no']! as String,
            row['incl_order']! as String,
            row['gp_decision']! as String,
            row['name_rus']! as String,
            row['name_add']! as String,
            row['country']! as String,
            row['excl_order']! as String,
            row['gp_cancel']! as String,
          ])
      .toList();

  Map<String, Object?> _recordJson(Row row) => {
        'orgKey': row['org_key'],
        'rowNum': row['row_num'],
        'values': {
          RecordField.targetNo.id: row['target_no'],
          RecordField.inclOrder.id: row['incl_order'],
          RecordField.gpDecision.id: row['gp_decision'],
          RecordField.nameRus.id: row['name_rus'],
          RecordField.nameAdd.id: row['name_add'],
          RecordField.country.id: row['country'],
          RecordField.exclOrder.id: row['excl_order'],
          RecordField.gpCancel.id: row['gp_cancel'],
        },
        'autoValues': jsonDecode(row['auto_values_json']! as String),
        'editedFields': jsonDecode(row['edited_fields_json']! as String),
        'staleCorrections': jsonDecode(row['stale_json']! as String),
        'candidates': jsonDecode(row['candidates_json']! as String),
        'notes': jsonDecode(row['notes_json']! as String),
        'confidence': row['confidence'],
        'isNew': (row['is_new']! as int) == 1,
        'isChanged': (row['is_changed']! as int) == 1,
        'isExcluded': (row['is_excluded']! as int) == 1,
        'rawName': row['raw_name'] ?? '',
        'previousRawName': row['previous_raw_name'],
        'sourceStatus': row['source_status'] ?? '',
      };

  int countRecords(int versionId, RecordFilter filter) {
    final rows = recordsOf(versionId, filter: filter, limit: 1000000);
    return rows.length;
  }

  // ---------------------------------------------------------- corrections

  /// Действующие правки, сгруппированные по `org_key` (FR-4).
  Map<String, List<CorrectionInput>> activeCorrections() {
    final result = <String, List<CorrectionInput>>{};
    final rows = _db.select(
      'SELECT c.* FROM corrections c '
      'WHERE c.is_active = 1 ORDER BY c.created_at;',
    );
    for (final row in rows) {
      final field = RecordField.byId(row['field']! as String);
      if (field == null) continue;
      final orgKey = row['org_key']! as String;
      result.putIfAbsent(orgKey, () => <CorrectionInput>[]).add(
            CorrectionInput(
              field: field,
              value: row['value']! as String,
              sourceNameHash: row['source_name_hash']! as String,
              author: row['author']! as String,
              createdAt: MoscowTime.parse(row['created_at']! as String),
            ),
          );
    }
    return result;
  }

  /// Сохраняет правку. История не затирается: прежние правки того же поля
  /// помечаются неактивными, но остаются в таблице (полный аудит, FR-4).
  int saveCorrection({
    required String orgKey,
    required RecordField field,
    required String value,
    required String sourceNameHash,
    required String author,
    DateTime? createdAt,
  }) {
    _db.execute(
      'UPDATE corrections SET is_active = 0 '
      'WHERE org_key = ? AND field = ? AND is_active = 1;',
      [orgKey, field.id],
    );
    _db.execute(
      'INSERT INTO corrections(org_key, field, value, source_name_hash, '
      'author, created_at, is_stale, is_active) VALUES(?,?,?,?,?,?,0,1);',
      [
        orgKey,
        field.id,
        value,
        sourceNameHash,
        author,
        MoscowTime.format(createdAt ?? MoscowTime.now()),
      ],
    );
    return _db.lastInsertRowId;
  }

  /// Отменяет действующую правку поля (возврат к автоматическому разбору).
  void revertCorrection(String orgKey, RecordField field) => _db.execute(
        'UPDATE corrections SET is_active = 0 '
        'WHERE org_key = ? AND field = ? AND is_active = 1;',
        [orgKey, field.id],
      );

  void markCorrectionsStale(String orgKey, List<RecordField> fields) {
    for (final field in fields) {
      _db.execute(
        'UPDATE corrections SET is_stale = 1 '
        'WHERE org_key = ? AND field = ? AND is_active = 1;',
        [orgKey, field.id],
      );
    }
  }

  List<Map<String, Object?>> correctionHistory(String orgKey) => _db
      .select(
        'SELECT * FROM corrections WHERE org_key = ? ORDER BY created_at DESC;',
        [orgKey],
      )
      .map((row) => {
            'id': row['id'],
            'orgKey': row['org_key'],
            'field': row['field'],
            'value': row['value'],
            'author': row['author'],
            'createdAt': row['created_at'],
            'isStale': (row['is_stale']! as int) == 1,
            'isActive': (row['is_active']! as int) == 1,
          })
      .toList();

  // --------------------------------------------------------------- events

  int addEvent(
    String type, {
    Map<String, Object?> payload = const {},
    int? versionId,
    DateTime? timestamp,
  }) {
    _db.execute(
      'INSERT INTO events(ts, type, payload_json, version_id) '
      'VALUES(?, ?, ?, ?);',
      [
        MoscowTime.format(timestamp ?? MoscowTime.now()),
        type,
        jsonEncode(payload),
        versionId,
      ],
    );
    return _db.lastInsertRowId;
  }

  List<AppEvent> listEvents({int limit = 200, String? type}) {
    final rows = type == null
        ? _db.select('SELECT * FROM events ORDER BY id DESC LIMIT ?;', [limit])
        : _db.select(
            'SELECT * FROM events WHERE type = ? ORDER BY id DESC LIMIT ?;',
            [type, limit],
          );
    return rows
        .map((row) => AppEvent(
              id: row['id']! as int,
              timestamp: MoscowTime.parse(row['ts']! as String),
              type: row['type']! as String,
              payload: jsonDecode(row['payload_json']! as String)
                  as Map<String, Object?>,
              versionId: row['version_id'] as int?,
            ))
        .toList();
  }
}
