/// Модель ручной правки (FR-4: приоритет человека).
library;

import 'record.dart';

/// Ручная правка целевого поля записи.
///
/// Правка хранится отдельно от автоматического разбора и переживает смену
/// версий файла: при сборке новой версии она перекрывает автоматический
/// разбор, если сырое наименование не изменилось (см. [isApplicableTo]).
class Correction {
  Correction({
    required this.id,
    required this.orgKey,
    required this.field,
    required this.value,
    required this.sourceNameHash,
    required this.author,
    required this.createdAt,
    this.isStale = false,
  });

  final int id;

  /// Ключ записи (`{номер}__{дата в ISO}`).
  final String orgKey;

  /// Целевое поле.
  final RecordField field;

  /// Значение, введённое человеком.
  final String value;

  /// SHA-1 сырого наименования на момент правки.
  final String sourceNameHash;

  final String author;
  final DateTime createdAt;

  /// Правка помечена «протухшей»: сырое наименование изменилось.
  final bool isStale;

  /// Применима ли правка к записи с текущим хэшем наименования.
  bool isApplicableTo(String currentSourceNameHash) =>
      sourceNameHash == currentSourceNameHash;

  Correction copyWith({bool? isStale}) => Correction(
        id: id,
        orgKey: orgKey,
        field: field,
        value: value,
        sourceNameHash: sourceNameHash,
        author: author,
        createdAt: createdAt,
        isStale: isStale ?? this.isStale,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'orgKey': orgKey,
        'field': field.id,
        'value': value,
        'sourceNameHash': sourceNameHash,
        'author': author,
        'createdAt': createdAt.toIso8601String(),
        'isStale': isStale,
      };
}
