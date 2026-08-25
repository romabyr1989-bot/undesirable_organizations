/// Модели данных UI (зеркало ответов REST API, п. 8.6 ТЗ).
library;

/// Целевые поля записи. Идентификаторы совпадают с серверными.
enum RecordField {
  targetNo('target_no', '№ п/п', editable: false),
  inclOrder('incl_order', 'Распоряжение о включении'),
  gpDecision('gp_decision', 'Решение Генпрокуратуры'),
  nameRus('name_rus', 'Наименование (рус)'),
  nameAdd('name_add', 'Наименование (доп.)'),
  country('country', 'Страна регистрации'),
  exclOrder('excl_order', 'Распоряжение об исключении'),
  gpCancel('gp_cancel', 'Решение об отмене');

  const RecordField(this.id, this.title, {this.editable = true});

  final String id;
  final String title;
  final bool editable;

  static RecordField? byId(String id) {
    for (final field in RecordField.values) {
      if (field.id == id) return field;
    }
    return null;
  }
}

class VersionCounters {
  const VersionCounters({
    this.total = 0,
    this.added = 0,
    this.excluded = 0,
    this.changed = 0,
    this.review = 0,
    this.edited = 0,
  });

  factory VersionCounters.fromJson(Map<String, dynamic> json) =>
      VersionCounters(
        total: _int(json['total']),
        added: _int(json['new']),
        excluded: _int(json['excluded']),
        changed: _int(json['changed']),
        review: _int(json['review']),
        edited: _int(json['edited']),
      );

  final int total;
  final int added;
  final int excluded;
  final int changed;
  final int review;
  final int edited;

  static int _int(Object? value) => value is num ? value.toInt() : 0;
}

class VersionSummary {
  VersionSummary({
    required this.id,
    required this.actualityDate,
    required this.downloadedAt,
    required this.status,
    required this.counters,
    required this.targetFileName,
    this.errorText,
    this.publishedAt,
    this.publishedFileName,
    this.confirmedBy,
  });

  factory VersionSummary.fromJson(Map<String, dynamic> json) => VersionSummary(
        id: json['id'] as int,
        actualityDate: json['actualityDate'] as String? ?? '',
        downloadedAt: json['downloadedAt'] as String? ?? '',
        status: json['status'] as String? ?? '',
        counters: VersionCounters.fromJson(
          (json['counters'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        targetFileName: json['targetFileName'] as String? ?? '',
        errorText: json['errorText'] as String?,
        publishedAt: json['publishedAt'] as String?,
        publishedFileName: json['publishedFileName'] as String?,
        confirmedBy: json['confirmedBy'] as String?,
      );

  final int id;
  final String actualityDate;
  final String downloadedAt;
  final String status;
  final VersionCounters counters;
  final String targetFileName;
  final String? errorText;
  final String? publishedAt;
  final String? publishedFileName;
  final String? confirmedBy;

  bool get isPublished => status == 'PUBLISHED';

  bool get isError => status == 'ERROR';

  /// Повторная публикация допустима (FR-5: операция идемпотентна),
  /// запрещена только для ошибочных версий.
  bool get canConfirm => !isError;

  String get statusTitle => switch (status) {
        'DOWNLOADING' => 'скачивается',
        'PARSED' => 'разобрана',
        'PENDING_REVIEW' => 'ждёт проверки',
        'CONFIRMED' => 'подтверждена',
        'AUTO_PUBLISHED' => 'авто-публикация',
        'PUBLISHED' => 'опубликована',
        'ERROR' => 'ошибка',
        _ => status,
      };
}

/// Протухшая правка (сырое наименование изменилось после её сохранения).
class StaleCorrection {
  StaleCorrection({
    required this.field,
    required this.value,
    required this.author,
    required this.createdAt,
  });

  factory StaleCorrection.fromJson(Map<String, dynamic> json) =>
      StaleCorrection(
        field: json['field'] as String? ?? '',
        value: json['value'] as String? ?? '',
        author: json['author'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
      );

  final String field;
  final String value;
  final String author;
  final String createdAt;
}

/// Кандидат-наименование из автоматического разбора (для раскрытия строки).
class ParseCandidate {
  ParseCandidate({
    required this.value,
    required this.kind,
    required this.excludedReason,
  });

  factory ParseCandidate.fromJson(Map<String, dynamic> json) => ParseCandidate(
        value: json['value'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        excludedReason: json['excludedReason'] as String?,
      );

  final String value;
  final String kind;
  final String? excludedReason;

  String get kindTitle => switch (kind) {
        'cyrillic' => 'кириллица',
        'latin' => 'латиница',
        'country' => 'страна',
        'abbreviation' => 'аббревиатура',
        'service' => 'служебное',
        'otherScript' => 'иной алфавит',
        'location' => 'география',
        'garbage' => 'мусор',
        _ => kind,
      };
}

class RecordItem {
  RecordItem({
    required this.orgKey,
    required this.rowNum,
    required this.values,
    required this.autoValues,
    required this.editedFields,
    required this.staleCorrections,
    required this.candidates,
    required this.notes,
    required this.confidence,
    required this.isNew,
    required this.isChanged,
    required this.isExcluded,
    required this.rawName,
    this.previousRawName,
  });

  factory RecordItem.fromJson(Map<String, dynamic> json) => RecordItem(
        orgKey: json['orgKey'] as String? ?? '',
        rowNum: (json['rowNum'] as num?)?.toInt() ?? 0,
        values: _stringMap(json['values']),
        autoValues: _stringMap(json['autoValues']),
        editedFields:
            (json['editedFields'] as List? ?? const []).map((e) => '$e').toSet(),
        staleCorrections: (json['staleCorrections'] as List? ?? const [])
            .map((e) =>
                StaleCorrection.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        candidates: (json['candidates'] as List? ?? const [])
            .map((e) =>
                ParseCandidate.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        notes: (json['notes'] as List? ?? const []).map((e) => '$e').toList(),
        confidence: json['confidence'] as String? ?? 'ok',
        isNew: json['isNew'] == true,
        isChanged: json['isChanged'] == true,
        isExcluded: json['isExcluded'] == true,
        rawName: json['rawName'] as String? ?? '',
        previousRawName: json['previousRawName'] as String?,
      );

  final String orgKey;
  final int rowNum;
  final Map<String, String> values;
  final Map<String, String> autoValues;
  final Set<String> editedFields;
  final List<StaleCorrection> staleCorrections;
  final List<ParseCandidate> candidates;
  final List<String> notes;
  final String confidence;
  final bool isNew;
  final bool isChanged;
  final bool isExcluded;
  final String rawName;
  final String? previousRawName;

  bool get needsReview => confidence == 'review';

  bool get hasEdits => editedFields.isNotEmpty;

  bool get hasStale => staleCorrections.isNotEmpty;

  String value(RecordField field) => values[field.id] ?? '';

  String autoValue(RecordField field) => autoValues[field.id] ?? '';

  static Map<String, String> _stringMap(Object? source) {
    if (source is! Map) return <String, String>{};
    return {
      for (final entry in source.entries) '${entry.key}': '${entry.value ?? ''}',
    };
  }
}

class HealthInfo {
  HealthInfo({
    required this.lastCheckAt,
    required this.lastCheckStatus,
    required this.nextRunAt,
    required this.downloadCron,
    required this.autoPublishCron,
    required this.cdiDropDir,
    required this.timeZone,
  });

  factory HealthInfo.fromJson(Map<String, dynamic> json) => HealthInfo(
        lastCheckAt: json['lastCheckAt'] as String?,
        lastCheckStatus: json['lastCheckStatus'] as String?,
        nextRunAt: json['nextRunAt'] as String?,
        downloadCron: json['downloadCron'] as String? ?? '',
        autoPublishCron: json['autoPublishCron'] as String? ?? '',
        cdiDropDir: json['cdiDropDir'] as String? ?? '',
        timeZone: json['timeZone'] as String? ?? '',
      );

  final String? lastCheckAt;
  final String? lastCheckStatus;
  final String? nextRunAt;
  final String downloadCron;
  final String autoPublishCron;
  final String cdiDropDir;
  final String timeZone;

  String get lastCheckTitle => switch (lastCheckStatus) {
        'new_version' => 'найдена новая версия',
        'no_change' => 'новой версии не было',
        'content_changed_same_date' => 'файл изменился без смены даты',
        'error' => 'ошибка',
        _ => 'проверок ещё не было',
      };
}

class EventItem {
  EventItem({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.payload,
    this.versionId,
  });

  factory EventItem.fromJson(Map<String, dynamic> json) => EventItem(
        id: json['id'] as int? ?? 0,
        timestamp: json['ts'] as String? ?? '',
        type: json['type'] as String? ?? '',
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        versionId: json['versionId'] as int?,
      );

  final int id;
  final String timestamp;
  final String type;
  final Map<String, dynamic> payload;
  final int? versionId;

  String get title => switch (type) {
        'check_started' => 'запущена проверка сайта',
        'download_ok' => 'файл скачан',
        'download_failed' => 'файл не скачался',
        'parse_failed' => 'структура файла не распознана',
        'version_created' => 'создана версия',
        'no_new_version' => 'новой версии нет',
        'content_changed_same_date' =>
          'файл изменился без смены даты актуальности',
        'correction_saved' => 'сохранена ручная правка',
        'correction_reverted' => 'правка отменена',
        'version_confirmed' => 'версия подтверждена',
        'published' => 'файл опубликован в CDI',
        'auto_published' => 'выполнена авто-публикация',
        'settings_changed' => 'изменены настройки',
        'email_sent' => 'отправлено письмо',
        'email_failed' => 'письмо не отправлено',
        'error' => 'ошибка',
        _ => type,
      };

  bool get isError =>
      type.contains('failed') || type == 'error';
}

class PublishResultInfo {
  PublishResultInfo({
    required this.fileName,
    required this.rows,
    required this.cdiPath,
    required this.warnings,
    required this.version,
  });

  factory PublishResultInfo.fromJson(Map<String, dynamic> json) =>
      PublishResultInfo(
        fileName: json['fileName'] as String? ?? '',
        rows: (json['rows'] as num?)?.toInt() ?? 0,
        cdiPath: json['cdiPath'] as String? ?? '',
        warnings: (json['warnings'] as List? ?? const [])
            .map((e) => '${(e as Map)['message']}')
            .toList(),
        version: VersionSummary.fromJson(
          (json['version'] as Map).cast<String, dynamic>(),
        ),
      );

  final String fileName;
  final int rows;
  final String cdiPath;
  final List<String> warnings;
  final VersionSummary version;
}

class CheckResultInfo {
  CheckResultInfo({
    required this.status,
    required this.message,
    required this.versionId,
  });

  factory CheckResultInfo.fromJson(Map<String, dynamic> json) =>
      CheckResultInfo(
        status: json['status'] as String? ?? '',
        message: json['message'] as String? ?? '',
        versionId: json['versionId'] as int?,
      );

  final String status;
  final String message;
  final int? versionId;

  String get title => switch (status) {
        'newVersion' => 'Найдена новая версия',
        'noChange' => 'Новой версии нет',
        'contentChangedSameDate' =>
          'Файл изменился без смены даты актуальности',
        'error' => 'Ошибка проверки',
        _ => status,
      };
}

/// Одна настройка: что действует сейчас и что записано в конфигурации службы.
class SettingValue {
  const SettingValue({
    this.value = '',
    this.fromConfig = '',
    this.overridden = false,
  });

  factory SettingValue.fromJson(Map<String, dynamic> json) => SettingValue(
        value: json['value'] as String? ?? '',
        fromConfig: json['fromConfig'] as String? ?? '',
        overridden: json['overridden'] as bool? ?? false,
      );

  /// Действующее значение.
  final String value;

  /// Значение из `config.yaml` или переменной окружения.
  final String fromConfig;

  /// Значение изменено в интерфейсе и перекрывает конфигурацию.
  final bool overridden;
}

/// Настройки, доступные ответственному на экране «Настройки».
class AppSettings {
  const AppSettings({
    this.minjustExportUrl = const SettingValue(),
    this.minjustPageUrl = const SettingValue(),
    this.cdiDropDir = const SettingValue(),
    this.downloadCron = const SettingValue(),
    this.autoPublishCron = const SettingValue(),
    this.timeZone = '',
    this.updatedAt,
    this.updatedBy,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    SettingValue read(String key) {
      final raw = json[key];
      return raw is Map
          ? SettingValue.fromJson(raw.cast<String, dynamic>())
          : const SettingValue();
    }

    return AppSettings(
      minjustExportUrl: read('minjustExportUrl'),
      minjustPageUrl: read('minjustPageUrl'),
      cdiDropDir: read('cdiDropDir'),
      downloadCron: read('downloadCron'),
      autoPublishCron: read('autoPublishCron'),
      timeZone: json['timeZone'] as String? ?? '',
      updatedAt: json['updatedAt'] as String?,
      updatedBy: json['updatedBy'] as String?,
    );
  }

  /// Прямая ссылка на xlsx. Пустая — адрес ищется на странице перечня.
  final SettingValue minjustExportUrl;

  /// Страница перечня на сайте Минюста.
  final SettingValue minjustPageUrl;

  /// Папка, из которой скрипт загрузки забирает целевой CSV.
  final SettingValue cdiDropDir;

  /// Расписание ежедневной проверки сайта.
  final SettingValue downloadCron;

  /// Расписание авто-публикации неподтверждённой версии.
  final SettingValue autoPublishCron;

  /// Часовой пояс, в котором работают расписания.
  final String timeZone;

  final String? updatedAt;
  final String? updatedBy;

  bool get hasOverrides =>
      minjustExportUrl.overridden ||
      minjustPageUrl.overridden ||
      cdiDropDir.overridden ||
      downloadCron.overridden ||
      autoPublishCron.overridden;
}
