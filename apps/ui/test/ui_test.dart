/// Виджет-тесты интерфейса (M5): сценарий ответственного целиком.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perechen_ui/src/app.dart';
import 'package:perechen_ui/src/models/models.dart';
import 'package:perechen_ui/src/api/api_client.dart';
import 'package:perechen_ui/src/screens/settings_screen.dart';
import 'package:perechen_ui/src/screens/version_screen.dart';
import 'package:perechen_ui/src/screens/versions_screen.dart';
import 'package:perechen_ui/src/util/formatting.dart';
import 'package:perechen_ui/src/util/link_opener.dart';
import 'package:perechen_ui/src/widgets/badges.dart';
import 'package:perechen_ui/src/widgets/record_editor.dart';

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

      expect(
        find.text('Перечень нежелательных организаций (272-ФЗ)'),
        findsOneWidget,
      );
      // Логотип стоит в заголовке, а не в карточках версий.
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(Card), matching: find.byType(Image)),
        findsNothing,
      );
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
      expect(find.textContaining('проверка в 06:00'), findsOneWidget);
      expect(find.text('требуют проверки'), findsOneWidget);
    });

    testWidgets('полоса состояния: даты целиком, расписание — с подсказкой',
        (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      // Даты и время видны полностью, без многоточия. Ищем вместе с
      // подписью: «Скачано: 14.08.2026 06:00» есть ещё и в карточке версии.
      expect(
        find.textContaining('Последняя проверка: 14.08.2026 06:00'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Следующий запуск: 15.08.2026 06:00'),
        findsOneWidget,
      );

      // Папка выгрузки живёт на экране настроек, в шапке её нет.
      expect(find.textContaining('Папка CDI'), findsNothing);
      expect(find.textContaining('/mnt/cdi/inbox'), findsNothing);

      // Расписание ужимается и показывается целиком при наведении.
      expect(find.byType(EllipsisCell), findsOneWidget);
    });

    testWidgets('кнопка в шапке запускает проверку сайта', (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Проверить сейчас'));
      await tester.pumpAndSettle();

      expect(api.checkNowCalls, 1);
      expect(find.textContaining('Найдена новая версия'), findsOneWidget);

      // Отдельной кнопки «Проверить сейчас» больше нет: список обновляется
      // сам, поэтому кнопка в шапке одна.
      expect(find.widgetWithText(FilledButton, 'Проверить сейчас'), findsNothing);
      expect(find.byTooltip('Обновить'), findsNothing);
    });

    testWidgets('список сам обновляется без действий пользователя',
        (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();
      final afterOpen = api.calls.where((c) => c == 'versions').length;

      api.setVersions([versionJson(status: 'PUBLISHED')]);
      await tester.pump(versionsAutoRefreshInterval);
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c == 'versions').length,
        greaterThan(afterOpen),
      );
      expect(find.text('опубликована'), findsOneWidget);

      // Таймер снимается вместе с экраном, иначе тест не завершится.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('плашка счётчика открывает перечень с этим фильтром',
        (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('требуют проверки'));
      await tester.pumpAndSettle();

      expect(find.byType(VersionScreen), findsOneWidget);
      expect(api.lastFilter, 'review');
    });

    testWidgets('плашка «всего» открывает перечень без фильтра',
        (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('всего'));
      await tester.pumpAndSettle();

      expect(find.byType(VersionScreen), findsOneWidget);
      expect(api.lastFilter, 'all');
    });

    for (final (label, filter) in const [
      ('новых', 'new'),
      ('изменённых', 'changed'),
    ]) {
      testWidgets('плашка «$label» ведёт в перечень «$filter»',
          (tester) async {
        useDesktopSurface(tester);
        final api = FakeApi();
        await tester.pumpWidget(PerechenApp(api: api));
        await tester.pumpAndSettle();

        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        expect(find.byType(VersionScreen), findsOneWidget);
        expect(api.lastFilter, filter);
      });
    }

    testWidgets('плашка с нулём заблокирована', (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      // В обвязке «исключённых» и «с правками» — по нулю.
      final chip = tester.widget<CounterChip>(
        find.widgetWithText(CounterChip, 'исключённых'),
      );
      expect(chip.enabled, isFalse);

      await tester.tap(find.text('исключённых'));
      await tester.pumpAndSettle();

      expect(find.byType(VersionScreen), findsNothing,
          reason: 'по пустому перечню переходить некуда');
      expect(find.byType(VersionsScreen), findsOneWidget);
    });

    testWidgets('плашки без подсказок при наведении', (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.text('требуют проверки'),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );
    });

    testWidgets('кнопка скачивания ведёт на целевой CSV версии',
        (tester) async {
      useDesktopSurface(tester);
      openedLinks.clear();
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.download).first);
      await tester.pumpAndSettle();

      expect(openedLinks, [
        'http://localhost/api/versions/1/export.csv',
      ]);
    });

    testWidgets('нажатие по карточке открывает версию', (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();

      // Отдельной кнопки-стрелки нет: открывает сама карточка.
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      await tester.tap(find.textContaining('Данные от 14.08.2026'));
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
      // Отдельного ряда фильтров нет: активный фильтр подсвечен на плашке.
      final chip = tester.widget<CounterChip>(
        find.widgetWithText(CounterChip, 'новых'),
      );
      expect(chip.selected, isTrue);
      final all = tester.widget<CounterChip>(
        find.widgetWithText(CounterChip, 'всего'),
      );
      expect(all.selected, isFalse);
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

    testWidgets('длинное наименование обрезается и всплывает целиком',
        (tester) async {
      const longName = 'Международная ассоциация содействия развитию '
          'независимых исследований общественного мнения и права';
      await pumpVersion(tester, records: [recordJson(nameRus: longName)]);

      final cell = tester.widget<Text>(find.text(longName));
      expect(cell.maxLines, 1);
      expect(cell.overflow, TextOverflow.ellipsis);
      expect(
        find.ancestor(
          of: find.text(longName),
          matching: find.byType(Tooltip),
        ),
        findsOneWidget,
        reason: 'обрезанное значение должно показываться при наведении',
      );
    });

    testWidgets('короткое наименование подсказкой не сопровождается',
        (tester) async {
      const shortName = 'Фонд';
      await pumpVersion(tester, records: [recordJson(nameRus: shortName)]);

      expect(
        find.ancestor(
          of: find.text(shortName),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );
    });

    testWidgets('строка записи умещается в одну строку', (tester) async {
      await pumpVersion(tester, records: [
        recordJson(confidence: 'review', isNew: true),
      ]);

      // Бейджи стоят рядом с наименованием, а не отдельной строкой под ним.
      final rowHeight = tester.getSize(find.byType(RecordRow).first).height;
      expect(rowHeight, lessThan(80));
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

    testWidgets('плашка «требуют проверки» перезапрашивает записи',
        (tester) async {
      final api = await pumpVersion(tester);
      await tester.tap(find.widgetWithText(CounterChip, 'требуют проверки'));
      await tester.pumpAndSettle();

      expect(api.lastFilter, 'review');
      final chip = tester.widget<CounterChip>(
        find.widgetWithText(CounterChip, 'требуют проверки'),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('отдельного ряда фильтров больше нет', (tester) async {
      await pumpVersion(tester);

      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(CounterChip), findsNWidgets(6));
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

      // Таблица со столбцами.
      for (final column in ['Время', 'Событие', 'Версия', 'Подробности']) {
        expect(find.text(column), findsOneWidget, reason: column);
      }
      expect(find.text('1'), findsOneWidget, reason: 'номер версии');
      expect(find.text('—'), findsOneWidget, reason: 'событие без версии');
    });

    testWidgets('строки журнала никуда не ведут', (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.pumpAndSettle();

      await tester.tap(find.text('создана версия'));
      await tester.pumpAndSettle();

      // Журнал — отчёт, а не навигация: остаёмся на том же экране.
      expect(find.byType(VersionScreen), findsNothing);
      expect(find.text('Журнал событий'), findsOneWidget);
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
      expect(
        noteTitle('homoglyph_fixed'),
        'буква была набрана не тем алфавитом — исправлено',
      );
      expect(
        noteTitle('char_not_in_cp1251'),
        'символ не переносится в целевой файл — исправьте вручную',
      );
      expect(noteTitle('unknown_note'), 'unknown_note');
    });

    test('расписание cron человеческим языком', () {
      expect(cronTitle('0 6 * * *'), 'в 06:00');
      expect(cronTitle('30 20 * * *'), 'в 20:30');
      expect(cronTitle('0 6,18 * * *'), 'в 06:00 и 18:00');
      expect(cronTitle('0 6 * * 1-5'), 'по будням в 06:00');
      expect(cronTitle('0 9 * * 0,6'), 'по выходным в 09:00');
      expect(cronTitle('15 7 * * 1'), 'по понедельникам в 07:15');
      expect(cronTitle('0 6 1 * *'), '1-го числа в 06:00');
      expect(cronTitle('*/15 * * * *'), 'каждые 15 минут');
      expect(cronTitle('0 */4 * * *'), 'каждые 4 часа');
    });

    test('неразобранное расписание показывается как есть', () {
      // Лучше сырое выражение, чем неверное обещание про время запуска.
      expect(cronTitle('0 6 * *'), '0 6 * *');
      expect(cronTitle('0 6 15 1 3'), '0 6 15 1 3');
      expect(cronTitle('чепуха'), 'чепуха');
      expect(cronTitle('0 6 * 3 *'), '0 6 * 3 *');
    });

    test('уведомление о проверке не повторяет само себя', () {
      // Сервер шлёт и статус, и сообщение — у «новой версии нет» они
      // совпадают, и в подсказке получалось «Новой версии нет. новой версии
      // нет».
      final same = CheckResultInfo.fromJson({
        'status': 'noChange',
        'message': 'новой версии нет',
        'versionId': 1,
      });
      expect(same.summary, 'Новой версии нет');

      final detailed = CheckResultInfo.fromJson({
        'status': 'error',
        'message': 'сайт не ответил за 60 с',
        'versionId': null,
      });
      expect(detailed.summary, 'Ошибка проверки. сайт не ответил за 60 с');

      final empty = CheckResultInfo.fromJson({
        'status': 'newVersion',
        'message': '',
        'versionId': 2,
      });
      expect(empty.summary, 'Найдена новая версия');
    });

    test('журнал событий читается без JSON', () {
      expect(
        eventDetails('check_started', {'trigger': 'cron'}),
        'запуск по расписанию',
      );
      expect(
        eventDetails('download_ok', {'bytes': 43079, 'attempts': 1}),
        'получено 42 КБ',
      );
      expect(
        eventDetails('download_ok', {'bytes': 43079, 'attempts': 3}),
        'получено 42 КБ, попыток: 3',
      );
      expect(
        eventDetails('version_created', {
          'actualityDate': '2026-08-14T17:28:00+03:00',
          'counters': {'total': 390, 'new': 2, 'excluded': 0, 'review': 21},
        }),
        'данные от 14.08.2026 17:28 · 390 записей · новых: 2 · '
        'требуют проверки: 21',
      );
      expect(
        eventDetails('no_new_version', {
          'actualityDate': '2026-08-14T17:28:00+03:00',
        }),
        'дата актуальности прежняя: 14.08.2026',
      );
      expect(
        eventDetails('correction_saved', {
          'orgKey': '260-р__2025-03-03',
          'fields': ['name_add'],
          'author': 'admin',
        }),
        'наименование (доп.) · автор: admin',
      );
      expect(
        eventDetails('settings_changed', {
          'author': 'admin',
          'changed': ['downloadCron', 'cdiDropDir'],
        }),
        'расписание проверки, папка выгрузки · автор: admin',
      );
      expect(
        eventDetails('published', {
          'fileName': 'perechen_organizatsij_272_FZ_2026_08_14.csv',
          'rows': 390,
          'cdiPath': '/mnt/cdi/inbox/perechen.csv',
        }),
        'perechen_organizatsij_272_FZ_2026_08_14.csv · 390 строк',
      );
      expect(
        eventDetails('email_sent', {
          'kind': 'new_version',
          'subject': 'Перечень 272-ФЗ: новая версия',
          'to': ['a@corp.example', 'b@corp.example'],
        }),
        'Перечень 272-ФЗ: новая версия → a@corp.example, b@corp.example',
      );
    });

    test('неизвестное событие показывается парами, а не JSON', () {
      expect(
        eventDetails('что-то новое', {'stage': 'x', 'count': 2}),
        'stage: x · count: 2',
      );
      // Пустая нагрузка — пустая строка, а не «подтвердил: ».
      expect(eventDetails('version_confirmed', const {}), '');
      expect(
        eventDetails('version_confirmed', const {'actor': 'admin'}),
        'подтвердил: admin',
      );
    });

    test('часовой пояс', () {
      expect(timeZoneTitle('Europe/Moscow'), 'МСК');
      expect(timeZoneTitle('UTC'), 'UTC');
    });
  });

  group('настройки', () {
    // Поле ищем по подписи: значение может совпасть с подсказкой (hint),
    // и тогда поиск по тексту находит один и тот же TextField дважды.
    Finder fieldByLabel(String label) =>
        find.widgetWithText(TextField, label);

    String valueOf(WidgetTester tester, String label) =>
        tester.widget<TextField>(fieldByLabel(label)).controller!.text;

    Future<FakeApi> pumpSettings(
      WidgetTester tester, {
      Map<String, dynamic>? payload,
    }) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      if (payload != null) api.settingsJson = payload;
      await tester.pumpWidget(PerechenApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('пункт меню открывает экран настроек', (tester) async {
      final api = await pumpSettings(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Настройки'), findsOneWidget);
      expect(api.calls, contains('settings'));
    });

    testWidgets('показывает действующие адрес и папку', (tester) async {
      await pumpSettings(tester);

      expect(
        valueOf(tester, 'Страница перечня на сайте Минюста'),
        'https://minjust.example/perechen/',
      );
      expect(valueOf(tester, 'Папка для целевого CSV'), '/mnt/cdi/inbox');

      // Прямая ссылка на файл правится только в конфигурации службы.
      expect(find.text('Прямая ссылка на файл (xlsx)'), findsNothing);
      // Пояснений и подсказок в форме нет — только подписи полей.
      expect(find.textContaining('Откуда служба забирает'), findsNothing);
      expect(find.textContaining('Запуск в'), findsNothing);
    });

    testWidgets('расписание правится', (tester) async {
      final api = await pumpSettings(tester);

      expect(valueOf(tester, 'Проверка сайта'), '0 6 * * *');
      expect(valueOf(tester, 'Авто-публикация'), '0 20 * * *');

      await tester.enterText(fieldByLabel('Проверка сайта'), '30 7 * * 1-5');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(api.lastSavedSettings, {'downloadCron': '30 7 * * 1-5'});
    });

    testWidgets('правка адреса уходит на сервер', (tester) async {
      final api = await pumpSettings(tester);

      await tester.enterText(
        fieldByLabel('Страница перечня на сайте Минюста'),
        'https://new.example/perechen/',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(api.lastSavedSettings, {
        'minjustPageUrl': 'https://new.example/perechen/',
      });
      expect(find.text('Настройки сохранены'), findsOneWidget);
    });

    testWidgets('правка папки выгрузки уходит на сервер', (tester) async {
      final api = await pumpSettings(tester);

      await tester.enterText(
        fieldByLabel('Папка для целевого CSV'),
        '/mnt/cdi/new-inbox',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(api.lastSavedSettings, {'cdiDropDir': '/mnt/cdi/new-inbox'});
    });

    testWidgets('без изменений запрос не отправляется', (tester) async {
      final api = await pumpSettings(tester);

      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(api.calls, isNot(contains('saveSettings')));
      expect(find.text('Изменений нет'), findsOneWidget);
    });

    testWidgets('ошибка проверки показывается у своего поля', (tester) async {
      final api = await pumpSettings(tester);
      api.settingsFailWith = ApiException(
        400,
        'адрес должен начинаться с http:// или https://',
        field: 'minjustPageUrl',
      );

      await tester.enterText(
        fieldByLabel('Страница перечня на сайте Минюста'),
        'minjust.example/perechen/',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(
        find.text('адрес должен начинаться с http:// или https://'),
        findsOneWidget,
      );
    });

    testWidgets('изменённая настройка показывает значение из конфигурации',
        (tester) async {
      await pumpSettings(
        tester,
        payload: settingsPayload(
          cdiDropDir: '/mnt/cdi/new-inbox',
          cdiDropDirFromConfig: '/mnt/cdi/inbox',
          cdiDropDirOverridden: true,
          updatedAt: '2026-08-25T10:00:00+03:00',
          updatedBy: 'admin',
        ),
      );

      expect(
        find.textContaining('В конфигурации службы: /mnt/cdi/inbox'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Последнее изменение: 25.08.2026 10:00'),
        findsOneWidget,
      );
      expect(find.text('Вернуть из конфигурации'), findsOneWidget);
    });

    testWidgets('«Вернуть из конфигурации» отправляет сброс', (tester) async {
      final api = await pumpSettings(
        tester,
        payload: settingsPayload(
          cdiDropDir: '/mnt/cdi/new-inbox',
          cdiDropDirFromConfig: '/mnt/cdi/inbox',
          cdiDropDirOverridden: true,
        ),
      );

      await tester.tap(find.text('Вернуть из конфигурации'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('снова будет действовать значение из'),
        findsOneWidget,
      );

      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(api.lastSavedSettings, {'cdiDropDir': null});
    });

    testWidgets('«Отменить изменения» возвращает поля к загруженным',
        (tester) async {
      final api = await pumpSettings(tester);

      await tester.enterText(
        fieldByLabel('Папка для целевого CSV'),
        '/tmp/other',
      );
      await tester.tap(find.text('Отменить изменения'));
      await tester.pumpAndSettle();

      expect(valueOf(tester, 'Папка для целевого CSV'), '/mnt/cdi/inbox');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(api.calls, isNot(contains('saveSettings')));
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

    testWidgets('маршрут /settings открывает экран настроек', (tester) async {
      useDesktopSurface(tester);
      final api = FakeApi();
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (settings) => PerechenApp.generateRoute(
          const RouteSettings(name: '/settings'),
          api,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });
}
