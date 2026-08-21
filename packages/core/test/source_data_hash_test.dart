/// Тесты хэша данных первоисточника (FR-2).
///
/// Критерий «содержимое изменилось» должен зависеть только от строк, а не от
/// байтов файла: реестр Минюста собирает xlsx на каждый запрос и записывает в
/// него время генерации, поэтому байтовый sha256 различается всегда.
library;

import 'package:perechen_core/perechen_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('sourceDataHash', () {
    test('одинаковые строки дают одинаковый хэш', () {
      final first = [sourceRow(ordinal: '1'), sourceRow(ordinal: '2')];
      final second = [sourceRow(ordinal: '1'), sourceRow(ordinal: '2')];
      expect(sourceDataHash(first), sourceDataHash(second));
    });

    test('позиция строки на листе на хэш не влияет', () {
      // Строку могли сдвинуть добавлением пустой строки выше: данные те же.
      final before = [sourceRow(rowNum: 4, ordinal: '1')];
      final after = [sourceRow(rowNum: 9, ordinal: '1')];
      expect(sourceDataHash(before), sourceDataHash(after));
    });

    test('изменение любой ячейки меняет хэш', () {
      final base = [sourceRow()];
      expect(
        sourceDataHash([sourceRow(rawName: 'Другое наименование')]),
        isNot(sourceDataHash(base)),
      );
      expect(
        sourceDataHash([sourceRow(status: 'Исключена')]),
        isNot(sourceDataHash(base)),
      );
      expect(
        sourceDataHash([sourceRow(exclusionNumber: '132-р')]),
        isNot(sourceDataHash(base)),
      );
    });

    test('порядок строк учитывается', () {
      final straight = [sourceRow(ordinal: '1'), sourceRow(ordinal: '2')];
      final reversed = [sourceRow(ordinal: '2'), sourceRow(ordinal: '1')];
      expect(sourceDataHash(straight), isNot(sourceDataHash(reversed)));
    });

    test('добавление и удаление строки меняют хэш', () {
      final one = [sourceRow(ordinal: '1')];
      final two = [sourceRow(ordinal: '1'), sourceRow(ordinal: '2')];
      expect(sourceDataHash(one), isNot(sourceDataHash(two)));
    });

    test('пустой список не роняет расчёт', () {
      expect(sourceDataHash(const <SourceRow>[]), isNotEmpty);
    });
  });

  group('SourceDocument.dataHash', () {
    test('считается по строкам документа', () {
      final rows = [sourceRow(ordinal: '1'), sourceRow(ordinal: '2')];
      final document = SourceDocument(
        actualityDate: DateTime(2026, 8, 14, 17, 28),
        title: 'Реестр иностранных и международных организаций',
        headers: const ['№ п/п'],
        rows: rows,
      );
      expect(document.dataHash, sourceDataHash(rows));
    });

    test('заголовок листа и дата актуальности на хэш данных не влияют', () {
      // Дата актуальности сравнивается отдельно (FR-2), а заголовок A1 —
      // служебная часть файла, как и время генерации в docProps.
      final rows = [sourceRow()];
      final first = SourceDocument(
        actualityDate: DateTime(2026, 8, 14, 17, 28),
        title: 'Реестр',
        headers: const ['№ п/п'],
        rows: rows,
      );
      final second = SourceDocument(
        actualityDate: DateTime(2026, 8, 20, 22, 16),
        title: 'Реестр иностранных и международных организаций',
        headers: const ['№ п/п'],
        rows: rows,
      );
      expect(first.dataHash, second.dataHash);
    });
  });
}
