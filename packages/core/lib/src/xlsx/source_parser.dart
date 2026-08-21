/// Разбор файла-первоисточника в [SourceDocument] (п. 3 ТЗ).
library;

import 'dart:typed_data';

import '../models/source.dart';
import '../util/ru_date.dart';
import '../util/text.dart';
import 'xlsx_reader.dart';

/// Ожидаемое устройство листа первоисточника.
class SourceLayout {
  const SourceLayout({
    this.sheetName = 'Лист 1',
    this.titleRow = 1,
    this.actualityRow = 2,
    this.headerRow = 3,
    this.firstDataRow = 4,
    this.columnCount = SourceRow.columnCount,
  });

  final String sheetName;
  final int titleRow;
  final int actualityRow;
  final int headerRow;
  final int firstDataRow;
  final int columnCount;

  /// Колонки, значения которых нормализуются к `DD.MM.YYYY`.
  static const dateColumns = <int>{2, 4, 6, 7, 9};

  /// Обязательные маркеры заголовков колонок (в нижнем регистре).
  /// Первые пять — критичные: без них файл считается нераспознанным.
  static const headerMarkers = <int, List<String>>{
    1: ['п/п'],
    2: ['дата', 'включении'],
    3: ['номер', 'включении'],
    4: ['дата', 'прокуратур'],
    5: ['наименование'],
    6: ['обнародования'],
    7: ['дата', 'исключении'],
    8: ['номер', 'исключении'],
    9: ['отмене'],
    10: ['статус'],
  };

  static const criticalColumns = <int>{1, 2, 3, 4, 5};
}

/// Результат разбора первоисточника вместе с некритичными замечаниями.
class SourceParseResult {
  SourceParseResult({required this.document, required this.warnings});

  final SourceDocument document;

  /// Некритичные расхождения (например, изменился текст заголовка колонки 10).
  final List<String> warnings;
}

/// Парсер первоисточника.
class SourceParser {
  const SourceParser({this.layout = const SourceLayout()});

  final SourceLayout layout;

  /// Разбирает байты xlsx-файла.
  SourceParseResult parseBytes(Uint8List bytes) {
    final XlsxWorkbook workbook;
    try {
      workbook = XlsxWorkbook.decode(bytes);
    } on XlsxFormatException catch (error) {
      throw SourceStructureException(
        'файл не читается как xlsx',
        details: error.message,
      );
    }
    final sheet = workbook.sheetByName(layout.sheetName) ?? workbook.first;
    if (sheet == null) {
      throw SourceStructureException('в книге нет ни одного листа');
    }
    return parseSheet(sheet);
  }

  /// Разбирает конкретный лист.
  SourceParseResult parseSheet(XlsxSheet sheet) {
    final warnings = <String>[];

    final title = _stringAt(sheet, layout.titleRow, 1);
    if (title.isEmpty) {
      warnings.add('пустой заголовок в A${layout.titleRow}');
    }

    final actualityDate = _readActualityDate(sheet);
    final headers = _readHeaders(sheet, warnings);
    final rows = _readRows(sheet);

    if (rows.isEmpty) {
      throw SourceStructureException(
        'в файле нет строк данных',
        details: 'ожидались строки начиная с ${layout.firstDataRow}',
      );
    }

    return SourceParseResult(
      document: SourceDocument(
        actualityDate: actualityDate,
        title: title,
        headers: headers,
        rows: rows,
      ),
      warnings: warnings,
    );
  }

  DateTime _readActualityDate(XlsxSheet sheet) {
    final cell = sheet.cell(layout.actualityRow, 1);
    if (cell == null || cell.isEmpty) {
      throw SourceStructureException(
        'в ячейке A${layout.actualityRow} нет даты актуальности данных',
      );
    }
    final dateValue = cell.dateValue;
    if (dateValue != null) return dateValue;

    final number = cell.numberValue;
    if (number != null && number > 1000) {
      return excelSerialToDateTime(number);
    }

    final text = normalizeSpaces(cell.stringValue ?? '');
    final parsed = _parseDateTimeText(text);
    if (parsed != null) return parsed;

    throw SourceStructureException(
      'не удалось разобрать дату актуальности данных',
      details: 'A${layout.actualityRow} = "$text"',
    );
  }

  static DateTime? _parseDateTimeText(String text) {
    final date = parseRuDate(text);
    if (date == null) return null;
    final time = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(text);
    if (time == null) return date;
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(time.group(1)!),
      int.parse(time.group(2)!),
      int.parse(time.group(3) ?? '0'),
    );
  }

  List<String> _readHeaders(XlsxSheet sheet, List<String> warnings) {
    final headers = <String>[];
    for (var column = 1; column <= layout.columnCount; column++) {
      headers.add(normalizeSpaces(_stringAt(sheet, layout.headerRow, column)));
    }

    final mismatches = <int>[];
    SourceLayout.headerMarkers.forEach((column, markers) {
      if (column > headers.length) {
        mismatches.add(column);
        return;
      }
      final header = headers[column - 1].toLowerCase();
      final matches = markers.every(header.contains);
      if (!matches) mismatches.add(column);
    });

    final criticalMismatches =
        mismatches.where(SourceLayout.criticalColumns.contains).toList();
    if (criticalMismatches.isNotEmpty) {
      throw SourceStructureException(
        'структура файла не распознана: не совпали заголовки колонок '
        '${criticalMismatches.join(", ")}',
        details: headers.join(' | '),
      );
    }
    for (final column in mismatches) {
      warnings.add(
        'заголовок колонки $column не совпал с ожидаемым: '
        '"${headers[column - 1]}"',
      );
    }
    return headers;
  }

  List<SourceRow> _readRows(XlsxSheet sheet) {
    final rows = <SourceRow>[];
    final maxRow = sheet.maxRow;
    for (var rowIndex = layout.firstDataRow; rowIndex <= maxRow; rowIndex++) {
      final cells = <String>[];
      for (var column = 1; column <= layout.columnCount; column++) {
        final cell = sheet.cell(rowIndex, column);
        final value = SourceLayout.dateColumns.contains(column)
            ? normalizeDateCell(cell?.value)
            : _cellText(cell);
        cells.add(value);
      }
      final isEmpty = cells.every((value) => value.trim().isEmpty);
      if (isEmpty) continue;
      rows.add(SourceRow(rowNum: rowIndex, cells: cells));
    }
    return rows;
  }

  static String _cellText(XlsxCell? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is DateTime) return formatRuDate(value);
    if (value is double) {
      return value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();
    }
    return normalizeSpaces(value.toString(), collapse: false);
  }

  static String _stringAt(XlsxSheet sheet, int row, int column) =>
      _cellText(sheet.cell(row, column));
}
