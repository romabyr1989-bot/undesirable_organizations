/// Минимальный, но устойчивый читатель xlsx (SpreadsheetML).
///
/// Своя реализация вместо готового пакета выбрана осознанно: нужен полный
/// контроль над типами ячеек (inlineStr / sharedString / число / дата) и над
/// распознаванием дат по стилю — от этого зависит ячейка A2 (дата
/// актуальности), ключевая для всего сервиса.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Значение ячейки: строка, число, дата или логическое значение.
class XlsxCell {
  XlsxCell({
    required this.row,
    required this.column,
    this.stringValue,
    this.numberValue,
    this.dateValue,
    this.boolValue,
  });

  /// Номер строки (1-based).
  final int row;

  /// Номер колонки (1-based).
  final int column;

  final String? stringValue;
  final double? numberValue;
  final DateTime? dateValue;
  final bool? boolValue;

  bool get isEmpty =>
      stringValue == null &&
      numberValue == null &&
      dateValue == null &&
      boolValue == null;

  /// Значение ячейки как объект (String / double / DateTime / bool / null).
  Object? get value => stringValue ?? dateValue ?? numberValue ?? boolValue;

  @override
  String toString() => 'XlsxCell(r$row c$column, $value)';
}

/// Лист книги.
class XlsxSheet {
  XlsxSheet({required this.name, required this.rows});

  final String name;

  /// Строки листа, индексируются номером строки (1-based).
  final Map<int, Map<int, XlsxCell>> rows;

  int get maxRow =>
      rows.keys.isEmpty ? 0 : rows.keys.reduce((a, b) => a > b ? a : b);

  int get maxColumn {
    var result = 0;
    for (final row in rows.values) {
      for (final column in row.keys) {
        if (column > result) result = column;
      }
    }
    return result;
  }

  XlsxCell? cell(int row, int column) => rows[row]?[column];
}

/// Книга xlsx.
class XlsxWorkbook {
  XlsxWorkbook(this.sheets);

  final List<XlsxSheet> sheets;

  XlsxSheet? sheetByName(String name) {
    for (final sheet in sheets) {
      if (sheet.name == name) return sheet;
    }
    return null;
  }

  XlsxSheet? get first => sheets.isEmpty ? null : sheets.first;

  /// Читает книгу из байтов xlsx-файла.
  static XlsxWorkbook decode(Uint8List bytes) => _XlsxDecoder(bytes).decode();
}

/// Ошибка чтения xlsx (битый архив, отсутствующие части и т. п.).
class XlsxFormatException implements Exception {
  XlsxFormatException(this.message);

  final String message;

  @override
  String toString() => 'XlsxFormatException: $message';
}

class _XlsxDecoder {
  _XlsxDecoder(this.bytes);

  final Uint8List bytes;

  late final Archive _archive;
  final List<String> _sharedStrings = <String>[];
  final Map<int, bool> _styleIsDate = <int, bool>{};
  bool _date1904 = false;

  XlsxWorkbook decode() {
    try {
      _archive = ZipDecoder().decodeBytes(bytes);
    } catch (error) {
      throw XlsxFormatException('не удалось прочитать zip-контейнер: $error');
    }
    _readSharedStrings();
    _readStyles();
    return XlsxWorkbook(_readSheets());
  }

  String? _fileContent(String path) {
    for (final file in _archive.files) {
      if (!file.isFile) continue;
      final name = file.name.startsWith('/') ? file.name.substring(1) : file.name;
      if (name == path) {
        return utf8.decode(file.content as List<int>, allowMalformed: true);
      }
    }
    return null;
  }

  void _readSharedStrings() {
    final content = _fileContent('xl/sharedStrings.xml');
    if (content == null) return;
    final document = XmlDocument.parse(content);
    for (final si in document.findAllElements('si')) {
      _sharedStrings.add(_textOf(si));
    }
  }

  /// Текст элемента `<si>` / `<is>`: собираем все `<t>`, пропуская фонетику.
  String _textOf(XmlElement element) {
    final buffer = StringBuffer();
    for (final t in element.findAllElements('t')) {
      final parent = t.parent;
      if (parent is XmlElement &&
          (parent.name.local == 'rPh' || parent.name.local == 'phoneticPr')) {
        continue;
      }
      buffer.write(t.innerText);
    }
    return buffer.toString();
  }

  void _readStyles() {
    final content = _fileContent('xl/styles.xml');
    if (content == null) return;
    final document = XmlDocument.parse(content);

    final customFormats = <int, String>{};
    for (final numFmt in document.findAllElements('numFmt')) {
      final id = int.tryParse(numFmt.getAttribute('numFmtId') ?? '');
      final code = numFmt.getAttribute('formatCode');
      if (id != null && code != null) customFormats[id] = code;
    }

    final cellXfs = document.findAllElements('cellXfs').firstOrNull;
    if (cellXfs == null) return;
    var index = 0;
    for (final xf in cellXfs.findElements('xf')) {
      final numFmtId = int.tryParse(xf.getAttribute('numFmtId') ?? '0') ?? 0;
      _styleIsDate[index] =
          _isDateFormat(numFmtId, customFormats[numFmtId]);
      index++;
    }
  }

  static bool _isDateFormat(int numFmtId, String? formatCode) {
    const builtInDateFormats = <int>{
      14, 15, 16, 17, 18, 19, 20, 21, 22, 27, 30, 36, //
      45, 46, 47, 50, 57, 58,
    };
    if (builtInDateFormats.contains(numFmtId)) return true;
    if (formatCode == null) return false;
    // Убираем экранированные и литеральные куски, затем ищем маркеры даты.
    final cleaned = formatCode
        .replaceAll(RegExp(r'\\.'), '')
        .replaceAll(RegExp(r'"[^"]*"'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '');
    return RegExp(r'[dmyhs]', caseSensitive: false).hasMatch(cleaned) &&
        !RegExp(r'^[#0.,%\s]*$').hasMatch(cleaned);
  }

  List<XlsxSheet> _readSheets() {
    final workbookXml = _fileContent('xl/workbook.xml');
    if (workbookXml == null) {
      throw XlsxFormatException('в архиве нет xl/workbook.xml');
    }
    final workbook = XmlDocument.parse(workbookXml);
    final workbookPr = workbook.findAllElements('workbookPr').firstOrNull;
    _date1904 = (workbookPr?.getAttribute('date1904') ?? 'false') == 'true' ||
        (workbookPr?.getAttribute('date1904') ?? '0') == '1';

    final relationships = <String, String>{};
    final relsXml = _fileContent('xl/_rels/workbook.xml.rels');
    if (relsXml != null) {
      for (final rel in XmlDocument.parse(relsXml).findAllElements(
        'Relationship',
      )) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id != null && target != null) relationships[id] = target;
      }
    }

    final sheets = <XlsxSheet>[];
    var fallbackIndex = 0;
    for (final sheetElement in workbook.findAllElements('sheet')) {
      fallbackIndex++;
      final name = sheetElement.getAttribute('name') ?? 'Sheet$fallbackIndex';
      final relationshipId = sheetElement.getAttribute('id') ??
          sheetElement.getAttribute('r:id');
      var target = relationshipId == null ? null : relationships[relationshipId];
      target ??= 'worksheets/sheet$fallbackIndex.xml';
      final path = target.startsWith('/')
          ? target.substring(1)
          : (target.startsWith('xl/') ? target : 'xl/$target');
      final sheetXml = _fileContent(path);
      if (sheetXml == null) continue;
      sheets.add(_readSheet(name, sheetXml));
    }
    return sheets;
  }

  XlsxSheet _readSheet(String name, String sheetXml) {
    final document = XmlDocument.parse(sheetXml);
    final rows = <int, Map<int, XlsxCell>>{};
    var currentRow = 0;
    for (final rowElement in document.findAllElements('row')) {
      currentRow = int.tryParse(rowElement.getAttribute('r') ?? '') ??
          (currentRow + 1);
      var currentColumn = 0;
      final cells = <int, XlsxCell>{};
      for (final cellElement in rowElement.findElements('c')) {
        final reference = cellElement.getAttribute('r');
        currentColumn = reference == null
            ? currentColumn + 1
            : _columnOf(reference) ?? (currentColumn + 1);
        final cell = _readCell(cellElement, currentRow, currentColumn);
        if (cell != null) cells[currentColumn] = cell;
      }
      if (cells.isNotEmpty) rows[currentRow] = cells;
    }
    return XlsxSheet(name: name, rows: rows);
  }

  XlsxCell? _readCell(XmlElement element, int row, int column) {
    final type = element.getAttribute('t') ?? 'n';
    final styleIndex = int.tryParse(element.getAttribute('s') ?? '');
    switch (type) {
      case 'inlineStr':
        final inline = element.findElements('is').firstOrNull;
        final text = inline == null ? '' : _textOf(inline);
        return XlsxCell(row: row, column: column, stringValue: text);
      case 's':
        final index = int.tryParse(
            element.findElements('v').firstOrNull?.innerText ?? '');
        final text = (index != null && index < _sharedStrings.length)
            ? _sharedStrings[index]
            : '';
        return XlsxCell(row: row, column: column, stringValue: text);
      case 'str':
        return XlsxCell(
          row: row,
          column: column,
          stringValue: element.findElements('f').isEmpty
              ? (element.findElements('v').firstOrNull?.innerText ?? '')
              : (element.findElements('v').firstOrNull?.innerText ?? ''),
        );
      case 'b':
        final raw = element.findElements('v').firstOrNull?.innerText;
        if (raw == null) return null;
        return XlsxCell(row: row, column: column, boolValue: raw == '1');
      case 'e':
        return XlsxCell(
          row: row,
          column: column,
          stringValue: element.findElements('v').firstOrNull?.innerText ?? '',
        );
      default:
        final raw = element.findElements('v').firstOrNull?.innerText;
        if (raw == null || raw.isEmpty) return null;
        final number = double.tryParse(raw);
        if (number == null) {
          return XlsxCell(row: row, column: column, stringValue: raw);
        }
        final isDate = styleIndex != null && (_styleIsDate[styleIndex] ?? false);
        if (isDate) {
          return XlsxCell(
            row: row,
            column: column,
            numberValue: number,
            dateValue: excelSerialToDateTime(number, date1904: _date1904),
          );
        }
        return XlsxCell(row: row, column: column, numberValue: number);
    }
  }

  /// Номер колонки из ссылки вида `AB12`.
  static int? _columnOf(String reference) {
    var result = 0;
    for (final unit in reference.codeUnits) {
      if (unit >= 0x41 && unit <= 0x5A) {
        result = result * 26 + (unit - 0x40);
      } else if (unit >= 0x61 && unit <= 0x7A) {
        result = result * 26 + (unit - 0x60);
      } else {
        break;
      }
    }
    return result == 0 ? null : result;
  }
}

/// Excel-серийная дата в [DateTime] (локальное время без сдвига).
DateTime excelSerialToDateTime(double serial, {bool date1904 = false}) {
  final epoch = date1904 ? DateTime(1904) : DateTime(1899, 12, 30);
  final milliseconds = (serial * Duration.millisecondsPerDay).round();
  return epoch.add(Duration(milliseconds: milliseconds));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
