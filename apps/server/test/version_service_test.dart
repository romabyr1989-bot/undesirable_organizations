/// Сценарные тесты сервиса (M2-M3): проверка сайта, версии, diff, правки,
/// публикация в папку CDI, письма.
library;

import 'dart:io';

import 'package:perechen_core/perechen_core.dart';
import 'package:perechen_server/src/db/database.dart';
import 'package:perechen_server/src/service/version_service.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late TestHarness harness;

  tearDown(() async => harness.dispose());

  final firstVersion = buildSourceXlsx(
    actualityDate: DateTime(2026, 8, 14, 17, 28),
    rows: [
      row(
        ordinal: '1',
        inclusionNumber: '1076-р',
        rawName: '«Национальный фонд в поддержку демократии» '
            '(The National Endowment for Democracy)',
      ),
      row(
        ordinal: '2',
        inclusionNumber: '1777-р',
        inclusionDate: '01.12.2015',
        gpDecisionDate: '26.11.2015',
        rawName: 'Институт Открытое Общество Фонд Содействия '
            '(OSI Assistance Foundation)',
      ),
      row(
        ordinal: '3',
        inclusionNumber: '1778-р',
        inclusionDate: '01.12.2015',
        gpDecisionDate: '26.11.2015',
        rawName: 'Фонд Открытое общество (Open Society Foundation)',
      ),
    ],
  );

  group('FR-1, FR-2: проверка сайта и определение версии', () {
    test('первая проверка создаёт версию и шлёт письмо', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      final outcome = await harness.app.service.checkNow();

      expect(outcome.status, CheckStatus.newVersion);
      expect(outcome.version!.actualityDate, DateTime(2026, 8, 14, 17, 28));
      expect(outcome.counters!.total, 3);
      expect(outcome.version!.status, VersionStatus.pendingReview);

      expect(harness.mail.sent, hasLength(1));
      final message = harness.mail.last!;
      expect(message.subject, contains('новая версия от 14.08.2026'));
      expect(message.text, contains('всего записей: 3'));
      expect(message.text, contains('http://ui.example/#/versions/'));
      expect(harness.mail.sent.single.recipients,
          ['otvetstvennyi@corp.example']);
    });

    test('повторная проверка того же файла: новой версии нет, письма нет',
        () async {
      harness = TestHarness.create(responses: [firstVersion]);
      await harness.app.service.checkNow();
      harness.mail.clear();

      final outcome = await harness.app.service.checkNow();
      expect(outcome.status, CheckStatus.noChange);
      expect(harness.mail.sent, isEmpty);
      expect(harness.db.listVersions(), hasLength(1));
    });

    test('NOTIFY_ON_NO_CHANGES=true включает письмо «изменений нет»', () async {
      harness = TestHarness.create(
        responses: [firstVersion],
        notifyOnNoChanges: true,
      );
      await harness.app.service.checkNow();
      harness.mail.clear();

      await harness.app.service.checkNow();
      expect(harness.mail.sent, hasLength(1));
      expect(harness.mail.last!.subject, contains('новой версии нет'));
    });

    test('более старая дата актуальности новую версию не создаёт', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      await harness.app.service.checkNow();

      harness.serve([
        buildSourceXlsx(
          actualityDate: DateTime(2026, 8, 1, 10),
          rows: [row(ordinal: '1', inclusionNumber: '1076-р', rawName: 'A (А)')],
        ),
      ]);
      final outcome = await harness.app.service.checkNow();
      expect(outcome.status, CheckStatus.noChange);
      expect(harness.db.listVersions(), hasLength(1));
    });

    test('источник пересобрал файл: байты другие, данные те же', () async {
      // Реестр Минюста отдаёт свежесобранный xlsx на каждый запрос и пишет в
      // него время генерации, поэтому sha256 файла различается даже у двух
      // скачиваний подряд. Критерий изменений — хэш данных, а не байтов:
      // иначе ежедневная проверка каждый раз считала бы файл изменившимся и
      // слала бы ответственному ложное письмо.
      final data = [
        row(ordinal: '1', inclusionNumber: '1076-р', rawName: 'A (А)'),
      ];
      final morning = buildSourceXlsx(
        actualityDate: DateTime(2026, 8, 14, 17, 28),
        rows: data,
        generatedAt: DateTime.utc(2026, 8, 17, 6, 28, 23),
      );
      final nextDay = buildSourceXlsx(
        actualityDate: DateTime(2026, 8, 14, 17, 28),
        rows: data,
        generatedAt: DateTime.utc(2026, 8, 20, 19, 16, 24),
      );
      expect(morning, isNot(orderedEquals(nextDay)),
          reason: 'байты файлов должны различаться');

      harness = TestHarness.create(responses: [morning]);
      await harness.app.service.checkNow();
      harness.mail.clear();

      harness.serve([nextDay]);
      final outcome = await harness.app.service.checkNow();

      expect(outcome.status, CheckStatus.noChange);
      expect(harness.db.listVersions(), hasLength(1));
      expect(
        harness.db.listEvents(type: EventType.contentChangedSameDate),
        isEmpty,
      );
      expect(harness.mail.sent, isEmpty, reason: 'ложного письма быть не должно');
    });

    test('файл изменился без смены даты актуальности (FR-2)', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      await harness.app.service.checkNow();
      harness.mail.clear();

      harness.serve([
        buildSourceXlsx(
          actualityDate: DateTime(2026, 8, 14, 17, 28),
          rows: [
            row(ordinal: '1', inclusionNumber: '1076-р', rawName: 'A (А) (США)'),
          ],
        ),
      ]);
      final outcome = await harness.app.service.checkNow();

      expect(outcome.status, CheckStatus.contentChangedSameDate);
      // версия пересобрана: в ней остались только строки нового файла
      expect(harness.db.recordsOf(outcome.version!.id), hasLength(1));
      expect(harness.db.sourceRowsOf(outcome.version!.id), hasLength(1));
      expect(harness.mail.last!.subject,
          contains('файл изменился без смены даты актуальности'));
      expect(
        harness.db.listEvents(type: EventType.contentChangedSameDate),
        hasLength(1),
      );
      expect(harness.db.listVersions(), hasLength(1));
    });

    test('скачанный оригинал сохраняется для аудита (FR-1)', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      await harness.app.service.checkNow();
      final downloads = Directory(harness.config.downloadsDir)
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .toList();
      expect(downloads, hasLength(1));
      expect(downloads.single, startsWith('export_2026_08_14_'));
      expect(downloads.single, endsWith('.xlsx'));
    });

    test('недоступность сайта: ошибка, письмо, эскалация через 3 суток',
        () async {
      harness = TestHarness.create(responses: [503]);
      for (var day = 1; day <= 3; day++) {
        harness.mail.clear();
        final outcome = await harness.app.service.checkNow();
        expect(outcome.status, CheckStatus.error);
      }
      // на третьи сутки — обычное письмо об ошибке + письмо-эскалация
      expect(harness.mail.sent, hasLength(2));
      expect(harness.mail.sent.last.message.subject, contains('недоступен'));
      expect(
        harness.db.listEvents(type: EventType.downloadFailed),
        hasLength(3),
      );
    });

    test('нераспознанная структура файла: ERROR, письмо, ничего не публикуется',
        () async {
      harness = TestHarness.create(responses: [
        buildSourceXlsx(
          actualityDate: DateTime(2026, 8, 14),
          rows: [row(ordinal: '1', inclusionNumber: '1-р', rawName: 'A (А)')],
          headers: [...sourceHeaders]..[4] = 'Что-то другое',
        ),
      ]);
      final outcome = await harness.app.service.checkNow();

      expect(outcome.status, CheckStatus.error);
      expect(outcome.version!.status, VersionStatus.error);
      expect(outcome.version!.errorText, contains('заголовки'));
      expect(harness.mail.last!.subject, contains('ОШИБКА'));
      expect(harness.cdiFiles, isEmpty);
    });
  });

  group('FR-3: diff версий', () {
    test('новые, изменённые и исчезнувшие записи попадают в счётчики и письмо',
        () async {
      harness = TestHarness.create(responses: [firstVersion]);
      await harness.app.service.checkNow();
      harness.mail.clear();

      harness.serve([
        buildSourceXlsx(
          actualityDate: DateTime(2026, 8, 20, 12),
          rows: [
            row(
              ordinal: '1',
              inclusionNumber: '1076-р',
              rawName: '«Национальный фонд в поддержку демократии» '
                  '(The National Endowment for Democracy)',
            ),
            row(
              ordinal: '2',
              inclusionNumber: '1777-р',
              inclusionDate: '01.12.2015',
              gpDecisionDate: '26.11.2015',
              rawName: 'Институт Открытое Общество Фонд Содействия '
                  '(OSI Assistance Foundation) (США)',
            ),
            row(
              ordinal: '3',
              inclusionNumber: '2000-р',
              inclusionDate: '05.05.2026',
              gpDecisionDate: '01.05.2026',
              rawName: 'New Organization («Новая организация») (Канада)',
            ),
          ],
        ),
      ]);

      final outcome = await harness.app.service.checkNow();
      expect(outcome.status, CheckStatus.newVersion);
      final counters = outcome.counters!;
      expect(counters.total, 3);
      expect(counters.added, 1);
      expect(counters.changed, 1);
      expect(counters.excluded, 1);

      final message = harness.mail.last!;
      expect(message.text, contains('Новая организация'));
      expect(message.text, contains('Фонд Открытое общество'));

      final versionId = outcome.version!.id;
      final newRecords =
          harness.db.recordsOf(versionId, filter: RecordFilter.isNew);
      expect(newRecords.single['orgKey'], '2000-р__2026-05-05');
      final excluded =
          harness.db.recordsOf(versionId, filter: RecordFilter.excluded);
      expect(excluded.single['orgKey'], '1778-р__2015-12-01');
      // Сырая строка исчезнувшей записи всё равно видна в UI.
      expect(excluded.single['rawName'], contains('Фонд Открытое общество'));
      final changed =
          harness.db.recordsOf(versionId, filter: RecordFilter.changed);
      expect(changed.single['orgKey'], '1777-р__2015-12-01');
      expect(changed.single['previousRawName'], isNotNull);
    });
  });

  group('FR-4: ручные правки', () {
    test('правка перекрывает разбор и переживает новую версию', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      final first = await harness.app.service.checkNow();
      final versionId = first.version!.id;

      harness.app.service.saveCorrection(
        versionId: versionId,
        orgKey: '1076-р__2015-07-29',
        values: {RecordField.country.id: 'Соединенные Штаты Америки'},
        author: 'ivanov',
      );

      final record =
          harness.db.recordOf(versionId, '1076-р__2015-07-29')!;
      expect(
        (record['values']! as Map)[RecordField.country.id],
        'Соединенные Штаты Америки',
      );
      expect(record['editedFields'], contains(RecordField.country.id));

      // новая версия с тем же сырым наименованием — правка применяется снова
      harness.serve([
        buildSourceXlsx(
          actualityDate: DateTime(2026, 9, 1, 9),
          rows: [
            row(
              ordinal: '1',
              inclusionNumber: '1076-р',
              rawName: '«Национальный фонд в поддержку демократии» '
                  '(The National Endowment for Democracy)',
            ),
          ],
        ),
      ]);
      final second = await harness.app.service.checkNow();
      final carried = harness.db
          .recordOf(second.version!.id, '1076-р__2015-07-29')!;
      expect(
        (carried['values']! as Map)[RecordField.country.id],
        'Соединенные Штаты Америки',
      );
      expect(second.counters!.edited, 1);
    });

    test('смена сырого наименования делает правку stale и требует проверки',
        () async {
      harness = TestHarness.create(responses: [firstVersion]);
      final first = await harness.app.service.checkNow();
      harness.app.service.saveCorrection(
        versionId: first.version!.id,
        orgKey: '1076-р__2015-07-29',
        values: {RecordField.nameRus.id: 'НФД (проверено вручную)'},
        author: 'ivanov',
      );

      harness.serve([
        buildSourceXlsx(
          actualityDate: DateTime(2026, 9, 1, 9),
          rows: [
            row(
              ordinal: '1',
              inclusionNumber: '1076-р',
              rawName: '«Национальный фонд в поддержку демократии-2» '
                  '(The National Endowment for Democracy) (США)',
            ),
          ],
        ),
      ]);
      final second = await harness.app.service.checkNow();
      final record =
          harness.db.recordOf(second.version!.id, '1076-р__2015-07-29')!;

      expect(
        (record['values']! as Map)[RecordField.nameRus.id],
        'Национальный фонд в поддержку демократии-2',
      );
      expect(record['confidence'], 'review');
      expect(record['staleCorrections'], hasLength(1));
      expect(harness.db.recordsOf(second.version!.id,
          filter: RecordFilter.review), isNotEmpty);
    });

    test('возврат к автоматическому разбору', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      final first = await harness.app.service.checkNow();
      final versionId = first.version!.id;

      harness.app.service.saveCorrection(
        versionId: versionId,
        orgKey: '1076-р__2015-07-29',
        values: {RecordField.nameRus.id: 'Ручное значение'},
        author: 'ivanov',
      );
      final reverted = harness.app.service.revertCorrection(
        versionId: versionId,
        orgKey: '1076-р__2015-07-29',
        fields: [RecordField.nameRus.id],
        author: 'ivanov',
      );
      expect(
        (reverted['values']! as Map)[RecordField.nameRus.id],
        'Национальный фонд в поддержку демократии',
      );
      expect(reverted['editedFields'], isEmpty);
      // история правок сохраняется полностью
      expect(
        harness.db.correctionHistory('1076-р__2015-07-29'),
        hasLength(1),
      );
    });
  });

  group('FR-5: публикация', () {
    test('подтверждение публикует файл в папку CDI', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      final outcome = await harness.app.service.checkNow();
      final result =
          await harness.app.service.confirm(outcome.version!.id, 'ivanov');

      expect(result.fileName, 'perechen_organizatsij_272_FZ_2026_08_14.csv');
      expect(harness.cdiFiles, [result.fileName]);
      expect(result.rowCount, 3);

      final content = harness.cdiFileContent(result.fileName);
      expect(content.split('\r\n').first.startsWith(';'), isTrue);
      expect(content, contains('№ 1076-р от 29.07.2015;от 28.07.2015'));
      expect(content.endsWith('\r\n'), isTrue);

      final version = harness.db.versionById(outcome.version!.id)!;
      expect(version.status, VersionStatus.published);
      expect(version.confirmedBy, 'ivanov');
      expect(version.publishedAt, isNotNull);

      // копия сохранена в архиве
      expect(
        File('${harness.config.publishedDir}/${result.fileName}').existsSync(),
        isTrue,
      );
    });

    test('во временных файлах ничего не остаётся (атомарная запись)', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      final outcome = await harness.app.service.checkNow();
      await harness.app.service.confirm(outcome.version!.id, 'ivanov');
      final leftovers = Directory(harness.cdiDir)
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((name) => name.contains('tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('повторная публикация идемпотентна', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      final outcome = await harness.app.service.checkNow();
      final first =
          await harness.app.service.confirm(outcome.version!.id, 'ivanov');
      final second =
          await harness.app.service.confirm(outcome.version!.id, 'ivanov');
      expect(second.fileName, first.fileName);
      expect(harness.cdiFiles, [first.fileName]);
    });

    test('авто-публикация неподтверждённой версии по расписанию', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      final outcome = await harness.app.service.checkNow();
      harness.mail.clear();

      final results = await harness.app.service.autoPublishPending();

      expect(results, hasLength(1));
      expect(harness.cdiFiles, ['perechen_organizatsij_272_FZ_2026_08_14.csv']);
      expect(harness.db.versionById(outcome.version!.id)!.confirmedBy, 'auto');
      expect(harness.mail.last!.subject, contains('авто-публикация'));
      expect(harness.db.listEvents(type: EventType.autoPublished), hasLength(1));
    });

    test('уже опубликованная версия повторно авто-публиковаться не будет',
        () async {
      harness = TestHarness.create(responses: [firstVersion]);
      final outcome = await harness.app.service.checkNow();
      await harness.app.service.confirm(outcome.version!.id, 'ivanov');
      final results = await harness.app.service.autoPublishPending();
      expect(results, isEmpty);
    });

    test('правки попадают в опубликованный файл', () async {
      harness = TestHarness.create(responses: [firstVersion]);
      final outcome = await harness.app.service.checkNow();
      harness.app.service.saveCorrection(
        versionId: outcome.version!.id,
        orgKey: '1076-р__2015-07-29',
        values: {RecordField.country.id: 'Соединенные Штаты Америки'},
        author: 'ivanov',
      );
      final result =
          await harness.app.service.confirm(outcome.version!.id, 'ivanov');
      expect(
        harness.cdiFileContent(result.fileName),
        contains('Соединенные Штаты Америки'),
      );
    });
  });

  group('эталонный файл целиком', () {
    test('390 записей проходят конвейер и публикуются', () async {
      harness = TestHarness.create(responses: [referenceXlsx()]);
      final outcome = await harness.app.service.checkNow();
      expect(outcome.status, CheckStatus.newVersion);
      expect(outcome.counters!.total, 390);

      final result =
          await harness.app.service.confirm(outcome.version!.id, 'ivanov');
      expect(result.rowCount, 390);
      final content = harness.cdiFileContent(result.fileName);
      final lines = content.split('\r\n')..removeLast();
      expect(lines, hasLength(391));
      expect(harness.cdiFiles,
          ['perechen_organizatsij_272_FZ_2026_08_14.csv']);
    });

    test('перерасбор по сохранённому файлу даёт тот же результат', () async {
      harness = TestHarness.create(responses: [referenceXlsx()]);
      final outcome = await harness.app.service.checkNow();
      final reparsed = await harness.app.service.reparse(outcome.version!.id);
      expect(reparsed.counters!.total, 390);
      expect(reparsed.version!.status, VersionStatus.pendingReview);
    });
  });
}
