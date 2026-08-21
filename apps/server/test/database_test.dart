/// Тесты хранилища (FR-7): схема, версии, записи, правки, журнал.
library;

import 'package:perechen_core/perechen_core.dart';
import 'package:perechen_server/src/db/database.dart';
import 'package:test/test.dart';

SourceRow buildRow({
  String ordinal = '1',
  String number = '1076-р',
  String date = '29.07.2015',
  String name = 'Test (Тест) (США)',
  String status = 'Включена',
}) =>
    SourceRow(rowNum: 4, cells: [
      ordinal,
      date,
      number,
      '28.07.2015',
      name,
      '',
      '',
      '',
      '',
      status,
    ]);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('схема создаётся и версия схемы записана', () {
    expect(db.meta('schema_version'), '${AppDatabase.schemaVersion}');
  });

  group('версии', () {
    test('создание, поиск и обновление', () {
      final id = db.insertVersion(
        actualityDate: DateTime(2026, 8, 14, 17, 28),
        downloadedAt: DateTime(2026, 8, 14, 6, 0),
        fileSha256: 'abc',
        sourcePath: '/tmp/export.xlsx',
        status: VersionStatus.downloading,
      );

      final version = db.versionById(id)!;
      expect(version.actualityDate, DateTime(2026, 8, 14, 17, 28));
      expect(version.status, VersionStatus.downloading);

      db.updateVersion(
        id,
        status: VersionStatus.pendingReview,
        counters: const VersionCounters(total: 390, added: 2, review: 5),
      );
      final updated = db.versionById(id)!;
      expect(updated.status, VersionStatus.pendingReview);
      expect(updated.counters.total, 390);
      expect(updated.counters.added, 2);
      expect(updated.counters.review, 5);
    });

    test('версия ищется по дате актуальности (идемпотентность проверки)', () {
      final date = DateTime(2026, 8, 14, 17, 28);
      db.insertVersion(
        actualityDate: date,
        downloadedAt: date,
        fileSha256: 'abc',
        sourcePath: 'x',
        status: VersionStatus.parsed,
      );
      expect(db.versionByActualityDate(date), isNotNull);
      expect(db.versionByActualityDate(DateTime(2026, 8, 13)), isNull);
    });

    test('последняя версия выбирается по дате актуальности, ошибки пропускаются',
        () {
      db.insertVersion(
        actualityDate: DateTime(2026, 8, 1),
        downloadedAt: DateTime(2026, 8, 1),
        fileSha256: 'a',
        sourcePath: 'a',
        status: VersionStatus.published,
      );
      final errorId = db.insertVersion(
        actualityDate: DateTime(2026, 8, 20),
        downloadedAt: DateTime(2026, 8, 20),
        fileSha256: 'b',
        sourcePath: 'b',
        status: VersionStatus.error,
      );
      expect(db.latestVersion()!.actualityDate, DateTime(2026, 8, 1));
      expect(
        db.latestVersion(excludeErrors: false)!.id,
        errorId,
      );
    });
  });

  group('записи', () {
    late int versionId;

    setUp(() {
      versionId = db.insertVersion(
        actualityDate: DateTime(2026, 8, 14),
        downloadedAt: DateTime(2026, 8, 14),
        fileSha256: 'abc',
        sourcePath: 'x',
        status: VersionStatus.parsed,
      );
    });

    test('сырые строки сохраняются и читаются без потерь', () {
      final rows = [buildRow(), buildRow(ordinal: '2', number: '1777-р')];
      db.saveSourceRows(versionId, rows);
      final restored = db.sourceRowsOf(versionId);
      expect(restored, hasLength(2));
      expect(restored.first.cells, rows.first.cells);
      expect(restored.first.rowNum, 4);
    });

    test('разобранные записи фильтруются по признакам', () {
      final mapper = RecordMapper(
        nameParser: NameParser(countries: CountryRegistry.empty()),
      );
      final base = mapper.map(buildRow());
      db
        ..saveSourceRows(versionId, [buildRow()])
        ..saveParsedRecords(versionId, [
          base.copyWith(isNew: true),
          mapper
              .map(buildRow(ordinal: '2', number: '1777-р'))
              .copyWith(isChanged: true, confidence: Confidence.review),
          mapper
              .map(buildRow(ordinal: '3', number: '1778-р'))
              .copyWith(isExcluded: true),
        ]);

      expect(db.recordsOf(versionId), hasLength(2)); // без исчезнувших
      expect(db.recordsOf(versionId, filter: RecordFilter.isNew), hasLength(1));
      expect(
        db.recordsOf(versionId, filter: RecordFilter.changed),
        hasLength(1),
      );
      expect(
        db.recordsOf(versionId, filter: RecordFilter.excluded),
        hasLength(1),
      );
      expect(db.recordsOf(versionId, filter: RecordFilter.review), hasLength(1));
    });

    test('поиск идёт и по сырой строке первоисточника', () {
      final mapper = RecordMapper(
        nameParser: NameParser(countries: CountryRegistry.empty()),
      );
      final row = buildRow(name: 'Unique Organization (Уникальная) (США)');
      db
        ..saveSourceRows(versionId, [row])
        ..saveParsedRecords(versionId, [mapper.map(row)]);
      expect(db.recordsOf(versionId, search: 'unique'), hasLength(1));
      expect(db.recordsOf(versionId, search: 'нет такого'), isEmpty);
    });

    test('целевые строки отдаются в порядке первоисточника', () {
      final mapper = RecordMapper(
        nameParser: NameParser(countries: CountryRegistry.empty()),
      );
      final rows = [
        SourceRow(rowNum: 5, cells: buildRow(ordinal: '2').cells),
        SourceRow(rowNum: 4, cells: buildRow(number: '1000-р').cells),
      ];
      db.saveParsedRecords(versionId, rows.map(mapper.map).toList());
      final target = db.targetRowsOf(versionId);
      expect(target, hasLength(2));
      expect(target.first[1], contains('1000-р'));
    });
  });

  group('правки (FR-4)', () {
    test('активной остаётся последняя правка поля, история не затирается', () {
      db
        ..saveCorrection(
          orgKey: 'k',
          field: RecordField.country,
          value: 'США',
          sourceNameHash: 'h1',
          author: 'ivanov',
        )
        ..saveCorrection(
          orgKey: 'k',
          field: RecordField.country,
          value: 'Соединенные Штаты Америки',
          sourceNameHash: 'h1',
          author: 'petrov',
        );

      final active = db.activeCorrections()['k']!;
      expect(active, hasLength(1));
      expect(active.single.value, 'Соединенные Штаты Америки');
      expect(db.correctionHistory('k'), hasLength(2));
    });

    test('отмена правки убирает её из активных, но не из истории', () {
      db
        ..saveCorrection(
          orgKey: 'k',
          field: RecordField.nameRus,
          value: 'Правка',
          sourceNameHash: 'h1',
          author: 'ivanov',
        )
        ..revertCorrection('k', RecordField.nameRus);
      expect(db.activeCorrections()['k'], isNull);
      expect(db.correctionHistory('k'), hasLength(1));
    });

    test('правки помечаются протухшими', () {
      db
        ..saveCorrection(
          orgKey: 'k',
          field: RecordField.nameRus,
          value: 'Правка',
          sourceNameHash: 'h1',
          author: 'ivanov',
        )
        ..markCorrectionsStale('k', [RecordField.nameRus]);
      expect(db.correctionHistory('k').single['isStale'], isTrue);
    });
  });

  group('журнал событий', () {
    test('события пишутся и читаются в обратном порядке', () {
      db
        ..addEvent(EventType.checkStarted, payload: {'trigger': 'cron'})
        ..addEvent(EventType.downloadOk, payload: {'bytes': 100});
      final events = db.listEvents();
      expect(events.first.type, EventType.downloadOk);
      expect(events.first.payload['bytes'], 100);
      expect(events.last.payload['trigger'], 'cron');
      expect(db.listEvents(type: EventType.checkStarted), hasLength(1));
    });
  });
}
