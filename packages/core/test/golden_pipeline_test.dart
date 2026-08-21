/// Golden-тест конвейера (п. 6.2 ТЗ).
///
/// На вход подаётся эталонный `reference/export.xlsx`, результат сверяется с
/// эталонным `reference/perechen_organizatsij_272_FZ_2025_03_03.csv`.
///
/// Расхождения с историческим эталоном, зафиксированные согласованными
/// решениями раздела 14 ТЗ:
///   * Р-2 — в эталоне у решений Генпрокуратуры есть номера
///     (`№1 от 28.07.2015`), в первоисточнике номеров нет: пишем только дату
///     (`от 28.07.2015`);
///   * Р-6 — в эталоне встречаются висящие пробелы
///     (`Национальный фонд в поддержку демократии `): считаем артефактом,
///     значения `trim()`-аем.
library;

import 'package:perechen_core/perechen_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Приводит поле эталона к согласованным правилам (Р-2 и Р-6).
String normalizeReferenceValue(int columnIndex, String value) {
  var result = value.trim().replaceAll(RegExp(r' {2,}'), ' ');
  if (columnIndex == 2 || columnIndex == 7) {
    // Реквизиты решения Генпрокуратуры: убираем исторический номер (Р-2).
    result = result.replaceFirst(RegExp(r'^№\s*\d+\s+'), '');
  }
  return result;
}

void main() {
  const encoder = Cp1251Encoder();

  late PipelineResult pipelineResult;
  late CsvBuildResult csv;
  late List<List<String>> ourRows;
  late List<List<String>> referenceRows;

  setUpAll(() {
    final pipeline = buildPipeline();
    pipelineResult = pipeline.run(xlsxBytes: loadReferenceXlsx());
    csv = pipeline.buildCsv(pipelineResult);
    ourRows = _rowsOf(encoder.decode(csv.bytes));
    referenceRows = _rowsOf(encoder.decode(loadReferenceCsv()));
  });

  group('конвейер на эталонных файлах', () {
    test('дата актуальности и имя файла', () {
      expect(pipelineResult.actualityDate, DateTime(2026, 8, 14, 17, 28));
      expect(csv.fileName, 'perechen_organizatsij_272_FZ_2026_08_14.csv');
    });

    test('все 390 записей первоисточника попали в файл', () {
      expect(pipelineResult.records, hasLength(390));
      expect(csv.rowCount, 390);
      expect(ourRows, hasLength(391)); // заголовок + записи
    });

    test('заголовок совпадает с эталоном байт в байт', () {
      expect(ourRows.first, referenceRows.first);
    });

    test('первые три строки совпадают с эталоном (с поправкой на Р-2 и Р-6)',
        () {
      for (var rowIndex = 1; rowIndex <= 3; rowIndex++) {
        final ourRow = ourRows[rowIndex];
        final referenceRow = referenceRows[rowIndex];
        expect(ourRow, hasLength(8));
        for (var column = 0; column < 8; column++) {
          expect(
            ourRow[column],
            normalizeReferenceValue(column, referenceRow[column]),
            reason: 'строка $rowIndex, колонка ${column + 1}',
          );
        }
      }
    });

    test('байтовый формат: cp1251, «;», CRLF, без BOM', () {
      expect(csv.bytes.sublist(0, 3), isNot([0xEF, 0xBB, 0xBF]));
      final text = encoder.decode(csv.bytes);
      expect(text.endsWith('\r\n'), isTrue);
      expect(text.contains('\n\n'), isFalse);
      final lines = text.split('\r\n')..removeLast();
      expect(lines, hasLength(391));
      for (final line in lines) {
        expect(_splitCsvLine(line), hasLength(8), reason: line);
      }
    });

    test('в первой версии нет «новых» записей, счётчики заполнены', () {
      expect(pipelineResult.counters.total, 390);
      expect(pipelineResult.counters.added, 0);
      expect(pipelineResult.counters.excluded, 0);
      expect(pipelineResult.counters.changed, 0);
    });

    test('доля записей, требующих проверки, разумна', () {
      final review = pipelineResult.counters.review;
      expect(review, lessThan(pipelineResult.records.length ~/ 3),
          reason: 'слишком много записей помечено review: $review');
    });

    test('у каждой записи есть хотя бы одно наименование', () {
      final empty = pipelineResult.records
          .where((r) =>
              r.value(RecordField.nameRus).isEmpty &&
              r.value(RecordField.nameAdd).isEmpty)
          .toList();
      expect(empty, isEmpty,
          reason: empty.map((r) => r.sourceRow.rawName).join(' | '));
    });

    test('страна распознана у большинства записей', () {
      final withCountry = pipelineResult.records
          .where((r) => r.value(RecordField.country).isNotEmpty)
          .length;
      expect(withCountry, greaterThan(330));
    });

    test('реквизиты распоряжений собраны по правилу «№ X от ДД.ММ.ГГГГ»', () {
      final pattern = RegExp(r'^№ \S+ от \d{2}\.\d{2}\.\d{4}$');
      for (final record in pipelineResult.records) {
        final value = record.value(RecordField.inclOrder);
        expect(pattern.hasMatch(value), isTrue, reason: value);
      }
    });

    test('колонки исключения пусты, пока все записи «Включена»', () {
      for (final record in pipelineResult.records) {
        expect(record.value(RecordField.exclOrder), '');
        expect(record.value(RecordField.gpCancel), '');
      }
    });

    test('org_key стабилен и уникален', () {
      final keys = pipelineResult.records.map((r) => r.orgKey).toSet();
      expect(keys, hasLength(pipelineResult.records.length));
      expect(pipelineResult.records.first.orgKey, '1076-р__2015-07-29');
    });
  });
}

List<List<String>> _rowsOf(String text) {
  final lines = text.split('\r\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines.map(_splitCsvLine).toList();
}

/// Разбор строки CSV с учётом экранирования RFC 4180.
List<String> _splitCsvLine(String line) {
  final result = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var index = 0; index < line.length; index++) {
    final char = line[index];
    if (char == '"') {
      if (inQuotes && index + 1 < line.length && line[index + 1] == '"') {
        buffer.write('"');
        index++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (char == ';' && !inQuotes) {
      result.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  result.add(buffer.toString());
  return result;
}
