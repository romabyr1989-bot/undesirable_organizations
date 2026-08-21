/// Генерация целевого CSV (п. 4 ТЗ).
///
/// Формат строго по эталону: cp1251 без BOM, разделитель `;`, CRLF в конце
/// каждой строки (включая последнюю), первый заголовок пустой.
library;

import 'dart:typed_data';

import '../config/core_config.dart';
import '../models/record.dart';
import '../util/ru_date.dart';
import '../util/text.dart';
import 'cp1251.dart';

/// Предупреждение генератора CSV (Р-6).
class CsvWarning {
  const CsvWarning({
    required this.code,
    required this.message,
    this.orgKey,
    this.field,
  });

  static const escaped = 'csv_escaped_value';
  static const charReplaced = 'csv_char_replaced';

  final String code;
  final String message;
  final String? orgKey;
  final RecordField? field;

  Map<String, Object?> toJson() => {
        'code': code,
        'message': message,
        'orgKey': orgKey,
        'field': field?.id,
      };

  @override
  String toString() => message;
}

/// Результат генерации файла.
class CsvBuildResult {
  CsvBuildResult({
    required this.fileName,
    required this.bytes,
    required this.rowCount,
    required this.warnings,
  });

  final String fileName;
  final Uint8List bytes;
  final int rowCount;
  final List<CsvWarning> warnings;
}

class CsvWriter {
  const CsvWriter({
    this.config = const CoreConfig(),
    this.encoder = const Cp1251Encoder(),
  });

  static const separator = ';';
  static const lineEnding = '\r\n';

  /// Префикс имени целевого файла (п. 4 ТЗ).
  static const fileNamePrefix = 'perechen_organizatsij_272_FZ_';

  final CoreConfig config;
  final Cp1251Encoder encoder;

  /// Имя целевого файла по дате актуальности данных (ячейка A2).
  static String fileNameFor(DateTime actualityDate) =>
      '$fileNamePrefix${formatFileNameDate(actualityDate)}.csv';

  /// Собирает целевой файл.
  ///
  /// [records] должны быть отсортированы так, как они идут в первоисточнике.
  CsvBuildResult build({
    required DateTime actualityDate,
    required List<ParsedRecord> records,
  }) =>
      _build(
        actualityDate: actualityDate,
        // Р-1: исчезнувшие строки в целевой файл не добавляем.
        rows: records
            .where((record) => !record.isExcluded)
            .map((record) => (
                  record,
                  RecordField.values.map(record.value).toList(),
                ))
            .toList(),
      );

  /// Собирает файл из «сырых» строк (порядок значений = порядок колонок).
  ///
  /// Используется при публикации из БД, чтобы не пересобирать модели.
  CsvBuildResult buildFromRows({
    required DateTime actualityDate,
    required List<List<String>> rows,
  }) =>
      _build(
        actualityDate: actualityDate,
        rows: rows.map((row) => (null as ParsedRecord?, row)).toList(),
      );

  CsvBuildResult _build({
    required DateTime actualityDate,
    required List<(ParsedRecord?, List<String>)> rows,
  }) {
    final warnings = <CsvWarning>[];
    final text = StringBuffer();

    text
      ..write(_row(RecordField.values.map((f) => f.header).toList(),
          warnings: warnings))
      ..write(lineEnding);

    var rowCount = 0;
    for (final (record, rawValues) in rows) {
      final values = rawValues.map(_prepare).toList();
      text
        ..write(_row(values, warnings: warnings, record: record))
        ..write(lineEnding);
      rowCount++;
    }

    final encoded = encoder.encode(text.toString());
    for (final replacement in encoded.replacements) {
      warnings.add(CsvWarning(
        code: CsvWarning.charReplaced,
        message: 'символ "${replacement.original}" отсутствует в cp1251, '
            'заменён на "${replacement.replacement}"',
      ));
    }

    return CsvBuildResult(
      fileName: fileNameFor(actualityDate),
      bytes: encoded.bytes,
      rowCount: rowCount,
      warnings: warnings,
    );
  }

  String _prepare(String value) {
    if (!config.trimValues) return value;
    return normalizeSpaces(value, collapse: config.collapseInnerSpaces);
  }

  String _row(
    List<String> values, {
    required List<CsvWarning> warnings,
    ParsedRecord? record,
  }) {
    final cells = <String>[];
    for (var index = 0; index < values.length; index++) {
      cells.add(_escape(
        values[index],
        warnings: warnings,
        record: record,
        field: index < RecordField.values.length
            ? RecordField.values[index]
            : null,
      ));
    }
    return cells.join(separator);
  }

  String _escape(
    String value, {
    required List<CsvWarning> warnings,
    ParsedRecord? record,
    RecordField? field,
  }) {
    final needsQuoting = value.contains(separator) ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (config.csvQuoteMode == CsvQuoteMode.always) {
      return '"${value.replaceAll('"', '""')}"';
    }
    if (!needsQuoting) return value;
    warnings.add(CsvWarning(
      code: CsvWarning.escaped,
      message: 'значение содержит служебные символы и экранировано '
          'по RFC 4180: "$value"',
      orgKey: record?.orgKey,
      field: field,
    ));
    return '"${value.replaceAll('"', '""')}"';
  }
}
