/// Тесты мэппинга полей, ключа записи, правок и diff (п. 5, FR-3, FR-4).
library;

import 'package:perechen_core/perechen_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  late RecordMapper mapper;

  setUp(() {
    mapper = RecordMapper(nameParser: buildNameParser());
  });

  group('мэппинг колонок (п. 5)', () {
    test('номер и дата распоряжения о включении', () {
      final record = mapper.map(sourceRow());
      expect(record.value(RecordField.inclOrder), '№ 1076-р от 29.07.2015');
    });

    test('реквизиты решения Генпрокуратуры — только дата (Р-2)', () {
      final record = mapper.map(sourceRow());
      expect(record.value(RecordField.gpDecision), 'от 28.07.2015');
    });

    test('GP_DECISION_FORMAT=with_number меняет формат в одном месте', () {
      final withNumber = RecordMapper(
        nameParser: buildNameParser(),
        config: const CoreConfig(
          gpDecisionFormat: GpDecisionFormat.withNumber,
        ),
      );
      expect(
        withNumber.gpRequisites('28.07.2015', number: '1'),
        '№ 1 от 28.07.2015',
      );
      expect(mapper.gpRequisites('28.07.2015', number: '1'), 'от 28.07.2015');
    });

    test('пустые части реквизитов дают пустое значение', () {
      final record = mapper.map(sourceRow(
        inclusionNumber: '',
        inclusionDate: '',
        gpDecisionDate: '',
      ));
      expect(record.value(RecordField.inclOrder), '');
      expect(record.value(RecordField.gpDecision), '');
    });

    test('колонки 6 и 10 первоисточника в целевой файл не переносятся', () {
      final record = mapper.map(sourceRow(
        publicationDate: '30.07.2015',
        status: 'Включена',
      ));
      expect(record.toTargetRow(), hasLength(8));
      expect(record.toTargetRow().contains('30.07.2015'), isFalse);
      expect(record.toTargetRow().contains('Включена'), isFalse);
    });

    test('целевые колонки исключения заполняются при их наличии (Р-1)', () {
      final record = mapper.map(sourceRow(
        exclusionDate: '15.01.2024',
        exclusionNumber: '25-р',
        gpCancelDate: '10.01.2024',
        status: 'Исключена',
      ));
      expect(record.value(RecordField.exclOrder), '№ 25-р от 15.01.2024');
      expect(record.value(RecordField.gpCancel), 'от 10.01.2024');
    });

    test('пустые колонки исключения при статусе «Включена»', () {
      final record = mapper.map(sourceRow());
      expect(record.value(RecordField.exclOrder), '');
      expect(record.value(RecordField.gpCancel), '');
    });
  });

  group('org_key (FR-3)', () {
    test('ключ строится из номера и даты включения', () {
      expect(orgKeyOf(sourceRow()), '1076-р__2015-07-29');
    });

    test('ключ не зависит от № п/п и наименования', () {
      final first = orgKeyOf(sourceRow(ordinal: '1', rawName: 'A (Б)'));
      final second = orgKeyOf(sourceRow(ordinal: '17', rawName: 'C (Д)'));
      expect(first, second);
    });

    test('при пустом номере — fallback на хэш наименования', () {
      final key = orgKeyOf(sourceRow(inclusionNumber: '', rawName: 'Fund (Фонд)'));
      expect(key, startsWith('name-'));
      expect(
        key,
        orgKeyOf(sourceRow(
          inclusionNumber: '',
          inclusionDate: '01.01.2020',
          rawName: 'Fund  (Фонд)',
        )),
      );
    });
  });

  group('ручные правки (FR-4)', () {
    const applier = CorrectionApplier();

    test('правка перекрывает автоматический разбор', () {
      final row = sourceRow(rawName: 'Test Fund («Тестовый фонд») (США)');
      final record = mapper.map(row);
      final corrected = applier.apply(record, [
        CorrectionInput(
          field: RecordField.nameRus,
          value: 'Тестовый фонд (проверено)',
          sourceNameHash: row.sourceNameHash,
          author: 'ivanov',
          createdAt: DateTime(2026, 8, 14),
        ),
      ]);
      expect(corrected.value(RecordField.nameRus), 'Тестовый фонд (проверено)');
      expect(corrected.autoValues[RecordField.nameRus], 'Тестовый фонд');
      expect(corrected.editedFields, contains(RecordField.nameRus));
      expect(corrected.confidence, Confidence.ok);
    });

    test('при смене сырого наименования правка становится stale', () {
      final oldRow = sourceRow(rawName: 'Test Fund («Тестовый фонд») (США)');
      final newRow = sourceRow(
        rawName: 'Test Fund International («Тестовый фонд») (США)',
      );
      final record = mapper.map(newRow);
      final corrected = applier.apply(record, [
        CorrectionInput(
          field: RecordField.nameRus,
          value: 'Тестовый фонд (проверено)',
          sourceNameHash: oldRow.sourceNameHash,
          author: 'ivanov',
          createdAt: DateTime(2026, 8, 14),
        ),
      ]);
      expect(corrected.value(RecordField.nameRus), 'Тестовый фонд');
      expect(corrected.editedFields, isEmpty);
      expect(corrected.staleCorrections, hasLength(1));
      expect(corrected.staleCorrections.first.value, 'Тестовый фонд (проверено)');
      expect(corrected.confidence, Confidence.review);
      expect(corrected.notes, contains('stale_correction'));
    });

    test('правки применяются к нескольким полям сразу', () {
      final row = sourceRow();
      final record = mapper.map(row);
      final corrected = applier.apply(record, [
        CorrectionInput(
          field: RecordField.country,
          value: 'Соединенные Штаты Америки',
          sourceNameHash: row.sourceNameHash,
          author: 'ivanov',
          createdAt: DateTime(2026, 8, 14),
        ),
        CorrectionInput(
          field: RecordField.nameAdd,
          value: 'Test Organization',
          sourceNameHash: row.sourceNameHash,
          author: 'ivanov',
          createdAt: DateTime(2026, 8, 14),
        ),
      ]);
      expect(corrected.value(RecordField.country), 'Соединенные Штаты Америки');
      expect(corrected.value(RecordField.nameAdd), 'Test Organization');
      expect(corrected.editedFields, hasLength(2));
    });
  });

  group('diff версий (FR-3)', () {
    late VersionDiffer differ;

    setUp(() {
      differ = VersionDiffer(mapper: mapper);
    });

    List<ParsedRecord> mapAll(List<SourceRow> rows) =>
        rows.map(mapper.map).toList();

    test('новые, изменённые и исчезнувшие записи', () {
      final previous = [
        sourceRow(ordinal: '1', inclusionNumber: '1-р', rawName: 'A (А)'),
        sourceRow(ordinal: '2', inclusionNumber: '2-р', rawName: 'B (Б)'),
        sourceRow(ordinal: '3', inclusionNumber: '3-р', rawName: 'C (В)'),
      ];
      final current = [
        sourceRow(ordinal: '1', inclusionNumber: '1-р', rawName: 'A (А)'),
        sourceRow(
            ordinal: '2', inclusionNumber: '2-р', rawName: 'B International (Б)'),
        sourceRow(ordinal: '3', inclusionNumber: '4-р', rawName: 'D (Г)'),
      ];

      final result = differ.diff(
        currentRecords: mapAll(current),
        previousRows: previous,
      );

      expect(result.counters.total, 3);
      expect(result.counters.added, 1);
      expect(result.counters.changed, 1);
      expect(result.counters.excluded, 1);

      final changed = result.records.firstWhere((r) => r.isChanged);
      expect(changed.orgKey, '2-р__2015-07-29');
      expect(changed.previousRawName, 'B (Б)');

      expect(result.excluded.single.orgKey, '3-р__2015-07-29');
      expect(result.excluded.single.isExcluded, isTrue);
    });

    test('первая версия: новых записей нет', () {
      final result = differ.diff(
        currentRecords: mapAll([sourceRow()]),
        previousRows: const [],
      );
      expect(result.counters.added, 0);
      expect(result.records.single.isNew, isFalse);
    });

    test('изменение любой исходной колонки помечает запись changed', () {
      final previous = [sourceRow(status: 'Включена')];
      final current = [sourceRow(status: 'Исключена')];
      final result = differ.diff(
        currentRecords: mapAll(current),
        previousRows: previous,
      );
      expect(result.counters.changed, 1);
      expect(result.records.single.previousRawName, isNull);
    });

    test('исчезнувшие записи не попадают в целевой CSV (Р-1)', () {
      final result = differ.diff(
        currentRecords: mapAll([sourceRow(inclusionNumber: '1-р')]),
        previousRows: [sourceRow(inclusionNumber: '2-р')],
      );
      final csv = const CsvWriter().build(
        actualityDate: DateTime(2026, 8, 14),
        records: [...result.records, ...result.excluded],
      );
      expect(csv.rowCount, 1);
    });
  });

  group('ExclusionPolicy (Р-1)', () {
    const policy = ExclusionPolicy();

    test('строка со статусом «Включена» и пустыми колонками 7-9 — активная', () {
      expect(policy.isExcludedInSource(sourceRow()), isFalse);
    });

    test('заполненная колонка 7 означает исключение', () {
      expect(
        policy.isExcludedInSource(sourceRow(exclusionDate: '15.01.2024')),
        isTrue,
      );
    });

    test('статус, отличный от «Включена», означает исключение', () {
      expect(policy.isExcludedInSource(sourceRow(status: 'Исключена')), isTrue);
    });

    test('пустой статус не считается исключением', () {
      expect(policy.isExcludedInSource(sourceRow(status: '')), isFalse);
    });
  });
}
