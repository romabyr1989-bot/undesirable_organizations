/// Модели первоисточника (xlsx с сайта Минюста), п. 3 ТЗ.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../util/text.dart';

/// Одна строка данных первоисточника (10 колонок «как есть»).
class SourceRow {
  SourceRow({required this.rowNum, required List<String> cells})
      : cells = List<String>.unmodifiable([
          ...cells,
          if (cells.length < columnCount)
            ...List<String>.filled(columnCount - cells.length, ''),
        ]);

  /// Количество колонок первоисточника (п. 3 ТЗ).
  static const columnCount = 10;

  /// Номер строки на листе (1-based, данные начинаются с 4-й).
  final int rowNum;

  /// Сырые значения колонок 1..10.
  final List<String> cells;

  String cell(int oneBasedIndex) =>
      oneBasedIndex >= 1 && oneBasedIndex <= cells.length
          ? cells[oneBasedIndex - 1]
          : '';

  /// 1. Номер по порядку.
  String get ordinal => cell(1);

  /// 2. Дата распоряжения Минюста о включении в перечень.
  String get inclusionDate => cell(2);

  /// 3. Номер распоряжения Минюста о включении в перечень.
  String get inclusionNumber => cell(3);

  /// 4. Дата решения Генпрокуратуры о признании деятельности нежелательной.
  String get gpDecisionDate => cell(4);

  /// 5. Наименование организации (сырая строка, подлежит разбору).
  String get rawName => cell(5);

  /// 6. Дата обнародования информации (в целевой файл не переносится).
  String get publicationDate => cell(6);

  /// 7. Дата распоряжения Минюста об исключении из перечня.
  String get exclusionDate => cell(7);

  /// 8. Номер распоряжения Минюста об исключении из перечня.
  String get exclusionNumber => cell(8);

  /// 9. Дата решения Генпрокуратуры об отмене решения.
  String get gpCancelDate => cell(9);

  /// 10. Статус (в эталоне везде «Включена»).
  String get status => cell(10);

  /// Хэш сырого наименования — привязка ручных правок (FR-4).
  String get sourceNameHash => sourceNameHashOf(rawName);

  /// Хэш всей строки — детектор изменений при diff (FR-3).
  String get contentHash =>
      sha1.convert(utf8.encode(cells.join(String.fromCharCode(31)))).toString();

  Map<String, Object?> toJson() => {'rowNum': rowNum, 'cells': cells};

  static SourceRow fromJson(Map<String, Object?> json) => SourceRow(
        rowNum: (json['rowNum']! as num).toInt(),
        cells: (json['cells']! as List<Object?>).map((e) => '$e').toList(),
      );

  @override
  String toString() => 'SourceRow(#$rowNum, ${cells.join(" | ")})';
}

/// SHA-1 нормализованной сырой строки наименования (FR-4).
String sourceNameHashOf(String rawName) =>
    sha1.convert(utf8.encode(comparisonKey(rawName))).toString();

/// SHA-256 данных первоисточника: хэши строк, склеенные по порядку (FR-2).
///
/// Сравнивать версии по байтам скачанного файла нельзя: реестр Минюста
/// (`reestrs.minjust.gov.ru/rest/registry/<id>/export`) собирает xlsx на
/// каждый запрос и записывает в `docProps/core.xml` время генерации, поэтому
/// sha256 файла различается даже у двух скачиваний подряд. Хэш данных
/// зависит только от содержимого строк, служебные части файла на него не
/// влияют.
String sourceDataHash(Iterable<SourceRow> rows) => sha256
    .convert(utf8.encode(rows.map((row) => row.contentHash).join('\n')))
    .toString();

/// Разобранный документ первоисточника.
class SourceDocument {
  SourceDocument({
    required this.actualityDate,
    required this.title,
    required this.headers,
    required this.rows,
  });

  /// Дата актуальности данных из ячейки A2 (ключевая дата, п. 3 ТЗ).
  final DateTime actualityDate;

  /// Заголовок из A1.
  final String title;

  /// Заголовки колонок из строки 3.
  final List<String> headers;

  /// Строки данных (с 4-й строки листа).
  final List<SourceRow> rows;

  int get recordCount => rows.length;

  /// Хэш данных документа — критерий «содержимое изменилось» (FR-2).
  String get dataHash => sourceDataHash(rows);
}

/// Ошибка распознавания структуры файла-первоисточника (п. 3 ТЗ):
/// версия помечается ошибочной, отправляется письмо, ничего не публикуется.
class SourceStructureException implements Exception {
  SourceStructureException(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() => details == null
      ? 'SourceStructureException: $message'
      : 'SourceStructureException: $message ($details)';
}
