/// Байтовые тесты целевого CSV (п. 4 ТЗ, решение Р-6).
library;

import 'package:perechen_core/perechen_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

ParsedRecord buildRecord(Map<RecordField, String> values, {String key = 'k1'}) =>
    ParsedRecord(
      orgKey: key,
      rowNum: 4,
      values: values,
      confidence: Confidence.ok,
      notes: const [],
      sourceRow: sourceRow(),
    );

void main() {
  const encoder = Cp1251Encoder();

  group('формат файла', () {
    late CsvBuildResult result;

    setUp(() {
      result = const CsvWriter().build(
        actualityDate: DateTime(2026, 8, 14, 17, 28),
        records: [
          buildRecord({
            RecordField.targetNo: '1',
            RecordField.inclOrder: '№ 1076-р от 29.07.2015',
            RecordField.gpDecision: 'от 28.07.2015',
            RecordField.nameRus: 'Национальный фонд в поддержку демократии',
            RecordField.nameAdd: 'The National Endowment for Democracy',
            RecordField.country: '',
            RecordField.exclOrder: '',
            RecordField.gpCancel: '',
          }),
        ],
      );
    });

    test('имя файла — по дате актуальности из A2', () {
      expect(result.fileName, 'perechen_organizatsij_272_FZ_2026_08_14.csv');
    });

    test('кодировка cp1251 без BOM', () {
      expect(result.bytes.sublist(0, 3), isNot([0xEF, 0xBB, 0xBF]));
      // «Национальный» в cp1251 начинается с 0xCD (Н).
      final text = encoder.decode(result.bytes);
      expect(text, contains('Национальный фонд в поддержку демократии'));
      expect(result.bytes.every((b) => b <= 0xFF), isTrue);
    });

    test('разделитель «;», CRLF в конце каждой строки', () {
      final text = encoder.decode(result.bytes);
      expect(text.endsWith('\r\n'), isTrue);
      final lines = text.split('\r\n')..removeLast();
      expect(lines, hasLength(2));
      for (final line in lines) {
        expect(line.split(';'), hasLength(8));
        expect(line.contains('\n'), isFalse);
      }
    });

    test('первый заголовок пустой', () {
      final text = encoder.decode(result.bytes);
      final header = text.split('\r\n').first;
      expect(header.startsWith(';'), isTrue);
      expect(
        header,
        ';Номер и дата распоряжения Минюста России о включении в перечень;'
        'Реквизиты решения Генеральной прокуратуры Российской Федерации '
        'о признании деятельности организации нежелательной;'
        'Наименование иностранной или международной неправительственной '
        'организации (рус);'
        'Наименование иностранной или международной неправительственной '
        'организации (доп.);'
        'Страна регистрации;'
        'Номер и дата распоряжения Минюста России об исключении из перечня;'
        'Реквизиты решения Генеральной прокуратуры Российской Федерации '
        'об отмене решения',
      );
    });

    test('заголовок совпадает с эталонным файлом', () {
      final referenceHeader =
          encoder.decode(loadReferenceCsv()).split('\r\n').first;
      final ourHeader = encoder.decode(result.bytes).split('\r\n').first;
      expect(ourHeader, referenceHeader);
    });
  });

  group('экранирование (Р-6)', () {
    test('значение с «;» экранируется и даёт warning', () {
      final result = const CsvWriter().build(
        actualityDate: DateTime(2026, 8, 14),
        records: [
          buildRecord({
            RecordField.targetNo: '1',
            RecordField.nameRus: 'Фонд «А; Б»',
          }),
        ],
      );
      final text = encoder.decode(result.bytes);
      expect(text, contains('"Фонд «А; Б»"'));
      expect(
        result.warnings.where((w) => w.code == CsvWarning.escaped),
        isNotEmpty,
      );
    });

    test('кавычки удваиваются по RFC 4180', () {
      final result = const CsvWriter().build(
        actualityDate: DateTime(2026, 8, 14),
        records: [
          buildRecord({
            RecordField.targetNo: '1',
            RecordField.nameAdd: 'The "Best" Fund; Inc',
          }),
        ],
      );
      final text = encoder.decode(result.bytes);
      expect(text, contains('"The ""Best"" Fund; Inc"'));
    });

    test('обычные значения не экранируются', () {
      final result = const CsvWriter().build(
        actualityDate: DateTime(2026, 8, 14),
        records: [
          buildRecord({
            RecordField.targetNo: '1',
            RecordField.nameRus: 'Фонд Открытое общество',
          }),
        ],
      );
      final text = encoder.decode(result.bytes);
      expect(text, contains('1;;;Фонд Открытое общество;;;;'));
      expect(result.warnings.where((w) => w.code == CsvWarning.escaped),
          isEmpty);
    });

    test('CSV_QUOTE_MODE=always экранирует всё', () {
      final result = CsvWriter(
        config: const CoreConfig(csvQuoteMode: CsvQuoteMode.always),
      ).build(
        actualityDate: DateTime(2026, 8, 14),
        records: [
          buildRecord({
            RecordField.targetNo: '1',
            RecordField.nameRus: 'Фонд',
          }),
        ],
      );
      final text = encoder.decode(result.bytes);
      expect(text.split('\r\n')[1], '"1";"";"";"Фонд";"";"";"";""');
    });

    test('TRIM_VALUES=true убирает висящие пробелы', () {
      final result = const CsvWriter().build(
        actualityDate: DateTime(2026, 8, 14),
        records: [
          buildRecord({
            RecordField.targetNo: '1',
            RecordField.nameRus: '  Фонд  мира  ',
          }),
        ],
      );
      final text = encoder.decode(result.bytes);
      expect(text.split('\r\n')[1], '1;;;Фонд мира;;;;');
    });

    test('исчезнувшие записи в файл не попадают (Р-1)', () {
      final result = const CsvWriter().build(
        actualityDate: DateTime(2026, 8, 14),
        records: [
          buildRecord({RecordField.targetNo: '1'}),
          buildRecord({RecordField.targetNo: '2'}, key: 'k2')
              .copyWith(isExcluded: true),
        ],
      );
      expect(result.rowCount, 1);
    });
  });

  group('cp1251 и транслитерация (Р-6)', () {
    test('кириллица кодируется однобайтово', () {
      final encoded = encoder.encode('Фонд');
      expect(encoded.bytes, [0xD4, 0xEE, 0xED, 0xE4]);
      expect(encoded.replacements, isEmpty);
    });

    test('немецкие умляуты заменяются ближайшим аналогом', () {
      final encoded = encoder.encode('Björn Müller-Käse');
      expect(encoder.decode(encoded.bytes), 'Bjorn Muller-Kase');
      expect(encoded.replacements.map((r) => r.original), ['ö', 'ü', 'ä']);
    });

    test('чешская и латышская диакритика конвертируется без потери смысла', () {
      final encoded = encoder.encode('Člověk v tísni, Evaņģēlisko');
      expect(encoder.decode(encoded.bytes), 'Clovek v tisni, Evangelisko');
    });

    test('ß раскрывается в ss', () {
      final encoded = encoder.encode('Straße');
      expect(encoder.decode(encoded.bytes), 'Strasse');
    });

    test('украинские буквы есть в cp1251 без замен', () {
      final encoded = encoder.encode('Громадська органiзацiя «Їжак»');
      expect(encoded.replacements, isEmpty);
      expect(encoder.decode(encoded.bytes), 'Громадська органiзацiя «Їжак»');
    });

    test('символ без аналога заменяется на «?» с предупреждением', () {
      final encoded = encoder.encode('Фонд 東京');
      expect(encoder.decode(encoded.bytes), 'Фонд ??');
      expect(encoded.replacements, hasLength(2));
      expect(encoded.replacements.every((r) => r.isLossy), isTrue);
    });

    test('замены попадают в предупреждения генератора CSV', () {
      final result = const CsvWriter().build(
        actualityDate: DateTime(2026, 8, 14),
        records: [
          buildRecord({
            RecordField.targetNo: '1',
            RecordField.nameAdd: 'Heinrich-Böll-Stiftung',
          }),
        ],
      );
      expect(
        result.warnings.where((w) => w.code == CsvWarning.charReplaced),
        isNotEmpty,
      );
      expect(encoder.decode(result.bytes), contains('Heinrich-Boll-Stiftung'));
    });
  });
}
