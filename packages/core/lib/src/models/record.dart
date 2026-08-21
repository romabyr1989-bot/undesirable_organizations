/// Модели целевой записи (строка целевого CSV + метаданные), п. 4-5 ТЗ.
library;

import 'parsed.dart';
import 'source.dart';

/// Поля целевого файла (п. 4 ТЗ). Порядок значений = порядок колонок CSV.
enum RecordField {
  /// 1. Номер по порядку (заголовок пустой).
  targetNo('target_no', ''),

  /// 2. Номер и дата распоряжения Минюста России о включении в перечень.
  inclOrder('incl_order',
      'Номер и дата распоряжения Минюста России о включении в перечень'),

  /// 3. Реквизиты решения Генпрокуратуры о признании нежелательной.
  gpDecision(
      'gp_decision',
      'Реквизиты решения Генеральной прокуратуры Российской Федерации '
          'о признании деятельности организации нежелательной'),

  /// 4. Наименование (рус).
  nameRus(
      'name_rus',
      'Наименование иностранной или международной неправительственной '
          'организации (рус)'),

  /// 5. Наименование (доп.).
  nameAdd(
      'name_add',
      'Наименование иностранной или международной неправительственной '
          'организации (доп.)'),

  /// 6. Страна регистрации.
  country('country', 'Страна регистрации'),

  /// 7. Номер и дата распоряжения Минюста России об исключении из перечня.
  exclOrder('excl_order',
      'Номер и дата распоряжения Минюста России об исключении из перечня'),

  /// 8. Реквизиты решения Генпрокуратуры об отмене решения.
  gpCancel(
      'gp_cancel',
      'Реквизиты решения Генеральной прокуратуры Российской Федерации '
          'об отмене решения');

  const RecordField(this.id, this.header);

  /// Идентификатор поля в API/БД/правках.
  final String id;

  /// Заголовок колонки в целевом CSV.
  final String header;

  static RecordField? byId(String id) {
    for (final field in RecordField.values) {
      if (field.id == id) return field;
    }
    return null;
  }
}

/// Запись версии: целевые значения + следы разбора и правок.
class ParsedRecord {
  ParsedRecord({
    required this.orgKey,
    required this.rowNum,
    required this.values,
    required this.confidence,
    required this.notes,
    required this.sourceRow,
    this.parsedName,
    this.isNew = false,
    this.isChanged = false,
    this.isExcluded = false,
    Map<RecordField, String>? autoValues,
    Set<RecordField>? editedFields,
    this.staleCorrections = const [],
    this.previousRawName,
  })  : autoValues = Map<RecordField, String>.unmodifiable(
            autoValues ?? Map<RecordField, String>.from(values)),
        editedFields =
            Set<RecordField>.unmodifiable(editedFields ?? <RecordField>{});

  /// Стабильный ключ записи между версиями (FR-3).
  final String orgKey;

  /// Номер строки первоисточника.
  final int rowNum;

  /// Итоговые значения целевых полей (с учётом ручных правок).
  final Map<RecordField, String> values;

  /// Значения строго автоматического разбора (до применения правок).
  final Map<RecordField, String> autoValues;

  /// Поля, перекрытые ручной правкой (FR-4).
  final Set<RecordField> editedFields;

  /// Правки, «протухшие» из-за смены сырого наименования (FR-4).
  final List<StaleCorrection> staleCorrections;

  final Confidence confidence;

  /// Коды сработавших неоднозначных веток разбора.
  final List<String> notes;

  /// Сырая строка первоисточника.
  final SourceRow sourceRow;

  /// Детали разбора наименования (кандидаты) — для UI.
  final ParsedName? parsedName;

  /// Запись появилась в этой версии.
  final bool isNew;

  /// Изменилась любая исходная колонка.
  final bool isChanged;

  /// Запись исчезла из первоисточника (в CSV не попадает, Р-1).
  final bool isExcluded;

  /// Прошлое значение сырого наименования (для отображения diff в UI).
  final String? previousRawName;

  String value(RecordField field) => values[field] ?? '';

  /// Строка целевого CSV в порядке колонок.
  List<String> toTargetRow() =>
      RecordField.values.map((f) => value(f)).toList(growable: false);

  ParsedRecord copyWith({
    Map<RecordField, String>? values,
    Set<RecordField>? editedFields,
    List<StaleCorrection>? staleCorrections,
    Confidence? confidence,
    List<String>? notes,
    bool? isNew,
    bool? isChanged,
    bool? isExcluded,
    String? previousRawName,
  }) =>
      ParsedRecord(
        orgKey: orgKey,
        rowNum: rowNum,
        values: values ?? Map<RecordField, String>.from(this.values),
        autoValues: autoValues,
        editedFields: editedFields ?? this.editedFields,
        staleCorrections: staleCorrections ?? this.staleCorrections,
        confidence: confidence ?? this.confidence,
        notes: notes ?? this.notes,
        sourceRow: sourceRow,
        parsedName: parsedName,
        isNew: isNew ?? this.isNew,
        isChanged: isChanged ?? this.isChanged,
        isExcluded: isExcluded ?? this.isExcluded,
        previousRawName: previousRawName ?? this.previousRawName,
      );

  Map<String, Object?> toJson() => {
        'orgKey': orgKey,
        'rowNum': rowNum,
        'values': {
          for (final entry in values.entries) entry.key.id: entry.value,
        },
        'autoValues': {
          for (final entry in autoValues.entries) entry.key.id: entry.value,
        },
        'editedFields': editedFields.map((f) => f.id).toList(),
        'staleCorrections': staleCorrections.map((c) => c.toJson()).toList(),
        'confidence': confidence.name,
        'notes': notes,
        'sourceRow': sourceRow.toJson(),
        'rawName': sourceRow.rawName,
        'previousRawName': previousRawName,
        'isNew': isNew,
        'isChanged': isChanged,
        'isExcluded': isExcluded,
        'candidates':
            parsedName?.candidates.map((c) => c.toJson()).toList() ?? const [],
      };
}

/// Правка, отвязавшаяся от текущего наименования (FR-4).
class StaleCorrection {
  StaleCorrection({
    required this.field,
    required this.value,
    required this.author,
    required this.createdAt,
  });

  final RecordField field;
  final String value;
  final String author;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'field': field.id,
        'value': value,
        'author': author,
        'createdAt': createdAt.toIso8601String(),
      };
}
