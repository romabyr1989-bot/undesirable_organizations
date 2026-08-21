/// Тесты чтения первоисточника (п. 3 ТЗ).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:perechen_core/perechen_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Собирает минимальный xlsx с заданными строками (для негативных кейсов).
Uint8List buildXlsx({
  required List<List<String>> rows,
  String sheetName = 'Лист 1',
  String? actualityCellValue,
  bool actualityAsNumber = false,
}) {
  final buffer = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main"><sheetData>');
  var rowIndex = 0;
  for (final row in rows) {
    rowIndex++;
    buffer.write('<row r="$rowIndex">');
    var columnIndex = 0;
    for (final cell in row) {
      columnIndex++;
      final reference = '${String.fromCharCode(64 + columnIndex)}$rowIndex';
      if (rowIndex == 2 && columnIndex == 1 && actualityAsNumber) {
        buffer.write('<c r="$reference" s="1" t="n"><v>$cell</v></c>');
      } else {
        final escaped = cell
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;');
        buffer.write('<c r="$reference" t="inlineStr"><is><t>$escaped</t>'
            '</is></c>');
      }
    }
    buffer.write('</row>');
  }
  buffer.write('</sheetData></worksheet>');

  final archive = Archive();
  void addFile(String name, String content) {
    final bytes = utf8Encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addFile(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.'
        'openxmlformats.org/package/2006/content-types"/>',
  );
  addFile(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.'
        'openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.'
        'openxmlformats.org/officeDocument/2006/relationships"><workbookPr '
        'date1904="false"/><sheets><sheet name="$sheetName" r:id="rId1" '
        'sheetId="1"/></sheets></workbook>',
  );
  addFile(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://'
        'schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Target="worksheets/sheet1.xml" Type="http://'
        'schemas.openxmlformats.org/officeDocument/2006/relationships/'
        'worksheet"/></Relationships>',
  );
  addFile(
    'xl/styles.xml',
    '<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.'
        'openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1">'
        '<numFmt numFmtId="164" formatCode="dd.MM.yyyy HH:mm:ss"/></numFmts>'
        '<cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="164" '
        'applyNumberFormat="true"/></cellXfs></styleSheet>',
  );
  addFile('xl/worksheets/sheet1.xml', buffer.toString());
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded!);
}

List<int> utf8Encode(String value) => utf8.encode(value);

const headerRow = <String>[
  '№ п/п',
  'Дата распоряжения Минюста России о включении в перечень',
  'Номер распоряжения Минюста России о включении в перечень',
  'Дата принятия решения Генеральной прокуратурой Российской Федерации '
      'о признании деятельности организации нежелательной',
  'Наименование организации',
  'Дата обнародования информации',
  'Дата распоряжения Минюста России об исключении из перечня',
  'Номер распоряжения Минюста России об исключении из перечня',
  'Дата принятия решения Генеральной прокуратурой Российской Федерации '
      'об отмене решения',
  'Статус',
];

void main() {
  group('эталонный export.xlsx', () {
    late SourceParseResult result;

    setUpAll(() {
      result = const SourceParser().parseBytes(loadReferenceXlsx());
    });

    test('дата актуальности берётся из A2', () {
      expect(result.document.actualityDate, DateTime(2026, 8, 14, 17, 28));
    });

    test('в файле 390 записей', () {
      expect(result.document.recordCount, 390);
    });

    test('колонки читаются как есть', () {
      final first = result.document.rows.first;
      expect(first.ordinal, '1');
      expect(first.inclusionDate, '29.07.2015');
      expect(first.inclusionNumber, '1076-р');
      expect(first.gpDecisionDate, '28.07.2015');
      expect(first.rawName,
          '«Национальный фонд в поддержку демократии» '
          '(The National Endowment for Democracy)');
      expect(first.status, 'Включена');
    });

    test('замечаний по заголовкам нет', () {
      expect(result.warnings, isEmpty);
    });
  });

  group('устойчивость к типам ячеек', () {
    test('дата актуальности как Excel-число', () {
      final bytes = buildXlsx(
        rows: [
          ['Реестр'],
          ['46248.72777777778'],
          headerRow,
          ['1', '29.07.2015', '1076-р', '28.07.2015', 'Test', '', '', '', '',
              'Включена'],
        ],
        actualityAsNumber: true,
      );
      final parsed = const SourceParser().parseBytes(bytes);
      expect(parsed.document.actualityDate.year, 2026);
      expect(parsed.document.actualityDate.month, 8);
      expect(parsed.document.actualityDate.day, 14);
    });

    test('дата актуальности текстом', () {
      final bytes = buildXlsx(rows: [
        ['Реестр'],
        ['03.03.2025 10:15:00'],
        headerRow,
        ['1', '29.07.2015', '1076-р', '28.07.2015', 'Test', '', '', '', '',
            'Включена'],
      ]);
      final parsed = const SourceParser().parseBytes(bytes);
      expect(parsed.document.actualityDate, DateTime(2025, 3, 3, 10, 15));
    });

    test('нет даты в A2 — структура не распознана', () {
      final bytes = buildXlsx(rows: [
        ['Реестр'],
        [''],
        headerRow,
        ['1', '29.07.2015', '1076-р', '28.07.2015', 'Test', '', '', '', '',
            'Включена'],
      ]);
      expect(
        () => const SourceParser().parseBytes(bytes),
        throwsA(isA<SourceStructureException>()),
      );
    });

    test('не совпали заголовки — структура не распознана', () {
      final broken = [...headerRow]..[4] = 'Что-то другое';
      final bytes = buildXlsx(rows: [
        ['Реестр'],
        ['14.08.2026 17:28:00'],
        broken,
        ['1', '29.07.2015', '1076-р', '28.07.2015', 'Test', '', '', '', '',
            'Включена'],
      ]);
      expect(
        () => const SourceParser().parseBytes(bytes),
        throwsA(isA<SourceStructureException>()),
      );
    });

    test('изменение некритичного заголовка — только предупреждение', () {
      final tweaked = [...headerRow]..[9] = 'Состояние';
      final bytes = buildXlsx(rows: [
        ['Реестр'],
        ['14.08.2026 17:28:00'],
        tweaked,
        ['1', '29.07.2015', '1076-р', '28.07.2015', 'Test', '', '', '', '',
            'Включена'],
      ]);
      final parsed = const SourceParser().parseBytes(bytes);
      expect(parsed.warnings, hasLength(1));
      expect(parsed.document.recordCount, 1);
    });

    test('пустые строки пропускаются', () {
      final bytes = buildXlsx(rows: [
        ['Реестр'],
        ['14.08.2026 17:28:00'],
        headerRow,
        ['1', '29.07.2015', '1076-р', '28.07.2015', 'Test', '', '', '', '',
            'Включена'],
        ['', '', '', '', '', '', '', '', '', ''],
        ['2', '01.12.2015', '1777-р', '26.11.2015', 'Test 2', '', '', '', '',
            'Включена'],
      ]);
      final parsed = const SourceParser().parseBytes(bytes);
      expect(parsed.document.recordCount, 2);
      expect(parsed.document.rows.last.ordinal, '2');
    });
  });

  group('нормализация дат', () {
    test('Excel-дата приводится к DD.MM.YYYY', () {
      expect(normalizeDateCell(DateTime(2015, 7, 29)), '29.07.2015');
    });

    test('текстовая дата остаётся DD.MM.YYYY', () {
      expect(normalizeDateCell('29.07.2015'), '29.07.2015');
    });

    test('однозначные день и месяц дополняются нулями', () {
      expect(normalizeDateCell('1.2.2020'), '01.02.2020');
    });

    test('пустая ячейка — пустая строка', () {
      expect(normalizeDateCell(null), '');
      expect(normalizeDateCell(''), '');
    });
  });
}
