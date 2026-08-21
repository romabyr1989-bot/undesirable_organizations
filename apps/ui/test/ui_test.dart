/// Виджет-тесты интерфейса (M5): сценарий ответственного целиком.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perechen_ui/src/app.dart';
import 'package:perechen_ui/src/screens/version_screen.dart';
import 'package:perechen_ui/src/screens/versions_screen.dart';
import 'package:perechen_ui/src/util/formatting.dart';
import 'package:perechen_ui/src/widgets/badges.dart';

import 'support/fake_api.dart';

/// Интерфейс рассчитан на десктопное окно: задаём его явно, иначе виджеты
/// не помещаются в тестовую поверхность 800x600 по умолчанию.
void useDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('экран версий', () {
    testWidgets('показывает версии, счётчики и здоровье сервиса',
        (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      expect(find.text('Перечень 272-ФЗ — версии'), findsOneWidget);
      expect(find.textContaining('Данные от 14.08.2026 17:28'), findsOneWidget);
      expect(find.text('ждёт проверки'), findsOneWidget);
      expect(
        find.text('perechen_organizatsij_272_FZ_2026_08_14.csv'),
        findsNothing,
      );
      expect(
        find.textContaining('Файл: perechen_organizatsij_272_FZ_2026_08_14'),
        findsOneWidget,
      );
      expect(find.textContaining('0 6 * * *'), findsOneWidget);
      expect(find.text('требуют проверки'), findsOneWidget);
    });

    testWidgets('кнопка «Проверить сейчас» дёргает API', (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Проверить сейчас'));
      await tester.pumpAndSettle();

      expect(api.checkNowCalls, 1);
      expect(find.textContaining('Найдена новая версия'), findsOneWidget);
    });

    testWidgets('переход на карточку версии', (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();

      expect(find.byType(VersionScreen), findsOneWidget);
      expect(find.textContaining('Версия от 14.08.2026'), findsOneWidget);
    });
  });

  group('экран версии', () {
    Future<FakeApi> pumpVersion(
      WidgetTester tester, {
      String filter = 'all',
      List<Map<String, dynamic>>? records,
    }) async {
      useDesktopSurface(tester);
      final api = FakeApi(records: records);
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (settings) => PerechenApp.generateRoute(
          RouteSettings(name: '/versions/1?filter=$filter'),
          api,
        ),
      ));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('ссылка из письма открывает фильтр «новые»', (tester) async {
      final api = await pumpVersion(tester, filter: 'new');
      expect(api.lastFilter, 'new');
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'новые'),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('таблица показывает разбор и бейджи', (tester) async {
      await pumpVersion(tester, records: [
        recordJson(isNew: true, confidence: 'review', notes: ['ambiguous_length']),
        recordJson(
          orgKey: '1777-р__2015-12-01',
          targetNo: '2',
          nameRus: 'Институт Открытое Общество Фонд Содействия',
          nameAdd: 'OSI Assistance Foundation',
          country: 'США',
        ),
      ]);

      expect(find.text('Национальный фонд в поддержку демократии'),
          findsOneWidget);
      expect(find.text('OSI Assistance Foundation'), findsOneWidget);
      expect(find.text('США'), findsOneWidget);
      expect(find.text('новая'), findsOneWidget);
      // «требует проверки» есть и среди фильтров — ищем именно бейдж записи.
      expect(
        find.descendant(
          of: find.byType(RecordBadges),
          matching: find.text('требует проверки'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('разворот строки показывает сырую строку и кандидатов',
        (tester) async {
      await pumpVersion(tester);
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();

      expect(find.text('Сырая строка первоисточника'), findsOneWidget);
      expect(
        find.textContaining('(The National Endowment for Democracy)'),
        findsWidgets,
      );
      expect(find.text('Как разобрал автомат'), findsOneWidget);
      expect(find.textContaining('аббревиатура: NED'), findsOneWidget);
      expect(find.text('Сохранить правку'), findsOneWidget);
    });

    testWidgets('ручная правка отправляется на сервер', (tester) async {
      final api = await pumpVersion(tester);
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Страна регистрации'),
        'Соединенные Штаты Америки',
      );
      await tester.tap(find.text('Сохранить правку'));
      await tester.pumpAndSettle();

      expect(api.lastSavedValues, {'country': 'Соединенные Штаты Америки'});
      expect(find.text('Правка сохранена'), findsOneWidget);
    });

    testWidgets('без изменений правка не отправляется', (tester) async {
      final api = await pumpVersion(tester);
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Сохранить правку'));
      await tester.pumpAndSettle();

      expect(api.lastSavedValues, isEmpty);
      expect(find.text('Изменений нет'), findsOneWidget);
    });

    testWidgets('возврат к авторазбору доступен только при наличии правки',
        (tester) async {
      await pumpVersion(tester, records: [
        recordJson(editedFields: ['country'], country: 'США'),
      ]);
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();

      // OutlinedButton.icon создаёт подкласс OutlinedButton, поэтому ищем
      // по предикату, а не по точному типу.
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Вернуть авторазбор'),
          matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
        ),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text('правка вручную'), findsOneWidget);
    });

    testWidgets('stale-правка показывается рядом для сравнения',
        (tester) async {
      await pumpVersion(tester, records: [
        recordJson(
          confidence: 'review',
          staleCorrections: [
            {
              'field': 'name_rus',
              'value': 'Старое ручное значение',
              'author': 'ivanov',
              'createdAt': '2026-08-01T10:00:00+03:00',
            },
          ],
        ),
      ]);
      expect(find.text('stale-правка'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();
      expect(
        find.text('Правка, отвязавшаяся от наименования'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Старое ручное значение'),
        findsOneWidget,
      );
    });

    testWidgets('изменённая запись показывает прошлое наименование',
        (tester) async {
      await pumpVersion(tester, records: [
        recordJson(
          isChanged: true,
          previousRawName: 'Старое наименование (Old name)',
        ),
      ]);
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();

      expect(find.text('Было в предыдущей версии'), findsOneWidget);
      expect(find.text('Старое наименование (Old name)'), findsOneWidget);
    });

    testWidgets('подтверждение публикует версию через диалог', (tester) async {
      final api = await pumpVersion(tester);

      await tester.tap(find.text('Подтвердить и передать в CDI'));
      await tester.pumpAndSettle();

      expect(find.text('Подтвердить и передать в CDI?'), findsOneWidget);
      expect(
        find.text('Файл: perechen_organizatsij_272_FZ_2026_08_14.csv'),
        findsOneWidget,
      );
      expect(find.textContaining('1 запись требует проверки'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Подтвердить'));
      await tester.pumpAndSettle();

      expect(api.confirmCalls, 1);
      expect(find.textContaining('Опубликовано:'), findsOneWidget);
      expect(find.text('опубликована'), findsOneWidget);
    });

    testWidgets('фильтр «требует проверки» перезапрашивает записи',
        (tester) async {
      final api = await pumpVersion(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'требует проверки'));
      await tester.pumpAndSettle();
      expect(api.lastFilter, 'review');
    });
  });

  group('журнал событий', () {
    testWidgets('показывает события и подсвечивает ошибки', (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.pumpAndSettle();

      expect(find.text('Журнал событий'), findsOneWidget);
      expect(find.text('создана версия'), findsOneWidget);
      expect(find.text('файл не скачался'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('вспомогательные функции', () {
    test('форматирование московского времени', () {
      expect(
        formatMoscowDateTime('2026-08-14T17:28:00+03:00'),
        '14.08.2026 17:28',
      );
      expect(formatMoscowDate('2026-08-14T17:28:00+03:00'), '14.08.2026');
      expect(formatMoscowDateTime(null), '—');
    });

    test('русское склонение', () {
      expect(plural(1, 'запись', 'записи', 'записей'), '1 запись');
      expect(plural(3, 'запись', 'записи', 'записей'), '3 записи');
      expect(plural(11, 'запись', 'записи', 'записей'), '11 записей');
      expect(plural(21, 'запись', 'записи', 'записей'), '21 запись');
    });

    test('человеческие описания пометок разбора', () {
      expect(noteTitle('translit_dropped'),
          'исключён транслит русского наименования');
      expect(noteTitle('unknown_note'), 'unknown_note');
    });
  });

  group('маршрутизация', () {
    testWidgets('неизвестный маршрут ведёт на список версий', (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (settings) => PerechenApp.generateRoute(
          const RouteSettings(name: '/unknown'),
          api,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(VersionsScreen), findsOneWidget);
    });
  });
}
