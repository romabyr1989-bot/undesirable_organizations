/// Тесты разбора наименований (п. 6 ТЗ).
///
/// Обязательные кейсы из п. 6.2 — реальные строки эталонного файла.
library;

import 'package:perechen_core/perechen_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

class _Case {
  const _Case(
    this.title,
    this.input, {
    required this.nameRus,
    required this.nameAdd,
    required this.country,
    this.confidence = Confidence.ok,
  });

  final String title;
  final String input;
  final String nameRus;
  final String nameAdd;
  final String country;
  final Confidence confidence;
}

void main() {
  late NameParser parser;

  setUp(() {
    parser = buildNameParser();
  });

  group('п. 6.2 — обязательные кейсы', () {
    const cases = <_Case>[
      _Case(
        'кириллица в кавычках + латиница в скобках',
        '«Национальный фонд в поддержку демократии» '
            '(The National Endowment for Democracy)',
        nameRus: 'Национальный фонд в поддержку демократии',
        nameAdd: 'The National Endowment for Democracy',
        country: '',
      ),
      _Case(
        'кириллица без кавычек + латиница в скобках',
        'Институт Открытое Общество Фонд Содействия (OSI Assistance Foundation)',
        nameRus: 'Институт Открытое Общество Фонд Содействия',
        nameAdd: 'OSI Assistance Foundation',
        country: '',
      ),
      _Case(
        'разный регистр в кириллице',
        'Фонд Открытое общество (Open Society Foundation)',
        nameRus: 'Фонд Открытое общество',
        nameAdd: 'Open Society Foundation',
        country: '',
      ),
      _Case(
        'правило 11: короткая латиница — дубль длинной',
        'Free Russia Foundation (Free Russia) (Фонд «Свободная Россия») (США)',
        nameRus: 'Фонд Свободная Россия',
        nameAdd: 'Free Russia Foundation',
        country: 'США',
      ),
      _Case(
        'правило 11: Atlantic council',
        'Atlantic council of the United States (Atlantic council) '
            '(«Атлантический совет») (США)',
        nameRus: 'Атлантический совет',
        nameAdd: 'Atlantic council of the United States',
        country: 'США',
      ),
      _Case(
        'правило 9: аббревиатура EPDE исключается',
        'European Platform for Democratic Elections (EPDE) '
            '(Европейская Платформа за Демократические Выборы) '
            '(Федеративная Республика Германия)',
        nameRus: 'Европейская Платформа за Демократические Выборы',
        nameAdd: 'European Platform for Democratic Elections',
        country: 'Федеративная Республика Германия',
      ),
      _Case(
        'правило 9: аббревиатура GMF исключается',
        'The German Marshall Fund of the United States (GMF) '
            '(Германский фонд Маршалла Соединенных Штатов) (США)',
        nameRus: 'Германский фонд Маршалла Соединенных Штатов',
        nameAdd: 'The German Marshall Fund of the United States',
        country: 'США',
      ),
      _Case(
        'страна после запятой в конце строки',
        'The Remembrance Society (Remembrance society, TRS, «Общество памяти»), '
            'Соединенные Штаты Америки',
        nameRus: 'Общество памяти',
        nameAdd: 'The Remembrance Society',
        country: 'Соединенные Штаты Америки',
      ),
      _Case(
        'два похожих кириллических наименования — берём длинное',
        'Associazione dei Russi Liberi in Italia '
            '(«Ассоциация свободных россиян Италии», '
            '«Ассоциация свободных россиян в Италии»), Итальянская Республика',
        nameRus: 'Ассоциация свободных россиян в Италии',
        nameAdd: 'Associazione dei Russi Liberi in Italia',
        country: 'Итальянская Республика',
      ),
      _Case(
        'аббревиатура + транслит + переименование (кейс review)',
        'OR (Otkrytaya Rossia) («Открытая Россия») (Великобритания) '
            '(с 08.11.2017 – HUMAN RIGHTS PROJECT MANAGEMENT)',
        nameRus: 'Открытая Россия',
        nameAdd: 'HUMAN RIGHTS PROJECT MANAGEMENT',
        country: 'Великобритания',
        confidence: Confidence.review,
      ),
    ];

    for (final testCase in cases) {
      test(testCase.title, () {
        final parsed = parser.parse(testCase.input);
        expect(parsed.nameRus, testCase.nameRus, reason: 'поле (рус)');
        expect(parsed.nameAdd, testCase.nameAdd, reason: 'поле (доп.)');
        expect(parsed.country, testCase.country, reason: 'страна регистрации');
        expect(parsed.confidence, testCase.confidence,
            reason: 'confidence, пометки: ${parsed.notes}');
      });
    }
  });

  group('правила п. 6 по отдельности', () {
    test('правило 1: кавычки любого вида исключаются', () {
      final parsed = parser.parse('«Фонд “Тест”» (\'Test Fund\')');
      expect(parsed.nameRus, 'Фонд Тест');
      expect(parsed.nameAdd, 'Test Fund');
    });

    test('правило 2: содержимое скобок — отдельные кандидаты', () {
      final parsed = parser.parse('Alpha Institute (Институт Альфа) (США)');
      expect(parsed.nameRus, 'Институт Альфа');
      expect(parsed.nameAdd, 'Alpha Institute');
      expect(parsed.country, 'США');
    });

    test('правило 3: кириллица в (рус), латиница в (доп.)', () {
      final parsed = parser.parse('Совет мира (Peace Council)');
      expect(parsed.nameRus, 'Совет мира');
      expect(parsed.nameAdd, 'Peace Council');
    });

    test('правило 4: дублирование словосочетаний исключается', () {
      final parsed = parser.parse(
        'Global Rights Foundation (Global Rights Foundation) '
        '(«Фонд глобальных прав», «Фонд глобальных прав»)',
      );
      expect(parsed.nameAdd, 'Global Rights Foundation');
      expect(parsed.nameRus, 'Фонд глобальных прав');
    });

    test('правило 5: транслит исключается при наличии другой латиницы', () {
      final parsed = parser.parse(
        'Open Russia Movement (Otkrytaya Rossia) («Открытая Россия»)',
      );
      expect(parsed.nameAdd, 'Open Russia Movement');
      expect(parsed.nameRus, 'Открытая Россия');
      expect(parsed.notes, contains(ParseNote.translitDropped));
      expect(parsed.confidence, Confidence.review);
    });

    test('правило 5: транслит переносится, если другой латиницы нет', () {
      final parsed = parser.parse('Otkrytaya Rossia («Открытая Россия»)');
      expect(parsed.nameAdd, 'Otkrytaya Rossia');
      expect(parsed.nameRus, 'Открытая Россия');
    });

    test('правило 6: транскрипция исключается при наличии другой кириллицы',
        () {
      final parsed = parser.parse(
        'Freedom House («Фридом Хаус», «Дом свободы») (США)',
      );
      expect(parsed.nameAdd, 'Freedom House');
      expect(parsed.nameRus, 'Дом свободы');
      expect(parsed.notes, contains(ParseNote.transcriptionDropped));
      expect(parsed.confidence, Confidence.review);
    });

    test('правила 7-8: страна переносится без преобразований', () {
      final parsed = parser.parse(
        'Test Fund («Тестовый фонд»), Федеративная Республика Германия',
      );
      expect(parsed.country, 'Федеративная Республика Германия');
    });

    test('правило 8: страна в скобках в конце', () {
      final parsed = parser.parse('Test Fund («Тестовый фонд») (Украина)');
      expect(parsed.country, 'Украина');
    });

    test('правило 9: аббревиатуры не переносятся', () {
      final parsed = parser.parse(
        'International Republican Institute (IRI, МРИ) '
        '(«Международный республиканский институт»)',
      );
      expect(parsed.nameAdd, 'International Republican Institute');
      expect(parsed.nameRus, 'Международный республиканский институт');
      expect(parsed.notes, contains(ParseNote.abbreviationDropped));
    });

    test('правило 10: части не на кириллице и не на латинице исключаются', () {
      final parsed = parser.parse(
        'Ελληνικό Ίδρυμα («Греческий фонд») (Греция)',
      );
      expect(parsed.nameRus, 'Греческий фонд');
      expect(parsed.nameAdd, '');
      expect(parsed.notes, contains(ParseNote.otherScriptDropped));
      expect(parsed.confidence, Confidence.review);
    });

    test('Р-4: наименование только на прочем алфавите — оба поля пустые', () {
      final parsed = parser.parse('Ελληνικό Ίδρυμα Δημοκρατίας');
      expect(parsed.nameRus, '');
      expect(parsed.nameAdd, '');
      expect(parsed.confidence, Confidence.review);
    });

    test('правило 11: из двух латинских берём длинное', () {
      final parsed = parser.parse(
        'The Remembrance Society (Remembrance society) («Общество памяти»)',
      );
      expect(parsed.nameAdd, 'The Remembrance Society');
    });
  });

  group('устойчивость разбора', () {
    test('организационно-правовая форма не отрывается запятой', () {
      final parsed = parser.parse(
        'Project Harmony, Inc. (PH International) («Прожект Хармони, Инк.») '
        '(Соединенные Штаты Америки)',
      );
      // Висящая точка убирается очисткой (п. 6.1, шаг 5), сама форма
      // «Inc» остаётся частью наименования и не отрывается запятой.
      expect(parsed.nameAdd, 'Project Harmony, Inc');
      expect(parsed.country, 'Соединенные Штаты Америки');
    });

    test('страна в скобках вместе с наименованием', () {
      final parsed = parser.parse(
        'RUHelp («РУХелп», Великое Герцогство Люксембург)',
      );
      expect(parsed.country, 'Великое Герцогство Люксембург');
      expect(parsed.nameAdd, 'RUHelp');
    });

    test('город рядом со страной не попадает в наименование', () {
      final parsed = parser.parse(
        '«Международная федерация транспортных рабочих» '
        '(«International Transport Workers Federation»), Великобритания, Лондон',
      );
      expect(parsed.country, 'Великобритания');
      expect(parsed.nameRus, 'Международная федерация транспортных рабочих');
    });

    test('точка с запятой делит кандидатов даже внутри кавычек', () {
      final parsed = parser.parse(
        '«RISE Moldova» (Asociaţia Obştească «Associaţia Reporterilor '
        'de Investigaţie ši Securitate Editorială din Moldova; '
        '«Ассоциация репортеров-расследователей и редакционной '
        'безопасности»), Республика Молдова',
      );
      expect(
        parsed.nameRus,
        'Ассоциация репортеров-расследователей и редакционной безопасности',
      );
      expect(parsed.nameAdd, startsWith('Asociaţia Obştească'));
      expect(parsed.nameAdd, isNot(contains(';')));
      expect(parsed.country, 'Республика Молдова');
    });

    test('пустая строка не ломает разбор', () {
      final parsed = parser.parse('');
      expect(parsed.nameRus, '');
      expect(parsed.nameAdd, '');
      expect(parsed.country, '');
      expect(parsed.confidence, Confidence.review);
      expect(parsed.notes, contains(ParseNote.emptyName));
    });

    test('вложенные скобки и незакрытые кавычки', () {
      final parsed = parser.parse(
        '«Гражданское сетевое движение «Мир. Прогресс. Права человека» '
        '(«Гражданское сетевое (общественное, демократическое) движение '
        '«Мир. Прогресс. Права человека»)',
      );
      expect(parsed.nameRus, isNotEmpty);
      expect(parsed.nameRus, contains('Мир. Прогресс. Права человека'));
    });

    test('справочник стран загружен', () {
      expect(loadCountries().length, greaterThan(100));
    });
  });
}
