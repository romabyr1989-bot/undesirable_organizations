/// Тесты планировщика: cron-выражения и московское время (п. 2, 8.1 ТЗ).
library;

import 'package:perechen_server/src/scheduler/cron.dart';
import 'package:perechen_server/src/util/moscow_time.dart';
import 'package:test/test.dart';

void main() {
  group('разбор cron-выражений', () {
    test('ежедневно в 06:00 (значение по умолчанию DOWNLOAD_CRON)', () {
      final schedule = CronSchedule.parse('0 6 * * *');
      expect(schedule.matches(DateTime(2026, 8, 14, 6)), isTrue);
      expect(schedule.matches(DateTime(2026, 8, 14, 6, 1)), isFalse);
      expect(schedule.matches(DateTime(2026, 8, 14, 7)), isFalse);
    });

    test('ежедневно в 20:00 (AUTO_PUBLISH_CRON)', () {
      final schedule = CronSchedule.parse('0 20 * * *');
      expect(schedule.matches(DateTime(2026, 1, 1, 20)), isTrue);
      expect(schedule.matches(DateTime(2026, 1, 1, 19, 59)), isFalse);
    });

    test('шаги, списки и диапазоны', () {
      final schedule = CronSchedule.parse('*/15 8-10 * * 1,3');
      expect(schedule.matches(DateTime(2026, 8, 17, 8, 15)), isTrue); // пн
      expect(schedule.matches(DateTime(2026, 8, 19, 10, 45)), isTrue); // ср
      expect(schedule.matches(DateTime(2026, 8, 18, 8, 15)), isFalse); // вт
      expect(schedule.matches(DateTime(2026, 8, 17, 8, 7)), isFalse);
    });

    test('воскресенье как 0 и как 7', () {
      expect(
        CronSchedule.parse('0 6 * * 0').matches(DateTime(2026, 8, 16, 6)),
        isTrue,
      );
      expect(
        CronSchedule.parse('0 6 * * 7').matches(DateTime(2026, 8, 16, 6)),
        isTrue,
      );
    });

    test('некорректное выражение отвергается', () {
      expect(() => CronSchedule.parse('0 6 * *'), throwsFormatException);
      expect(() => CronSchedule.parse('61 6 * * *'), throwsFormatException);
    });

    test('следующий запуск считается корректно', () {
      final schedule = CronSchedule.parse('0 6 * * *');
      expect(
        schedule.nextRunAfter(DateTime(2026, 8, 14, 7, 30)),
        DateTime(2026, 8, 15, 6),
      );
      expect(
        schedule.nextRunAfter(DateTime(2026, 8, 14, 5, 59)),
        DateTime(2026, 8, 14, 6),
      );
    });
  });

  group('планировщик', () {
    test('задача запускается один раз в минуту срабатывания', () async {
      var now = DateTime(2026, 8, 14, 6);
      var runs = 0;
      final scheduler = CronScheduler(clock: () => now)
        ..addJob(CronJob(
          name: 'download',
          schedule: CronSchedule.parse('0 6 * * *'),
          action: () async => runs++,
        ));

      await scheduler.runDue();
      await scheduler.runDue();
      expect(runs, 1);

      now = DateTime(2026, 8, 15, 6);
      await scheduler.runDue();
      expect(runs, 2);
    });

    test('задача не запускается вне расписания', () async {
      var runs = 0;
      final scheduler = CronScheduler(clock: () => DateTime(2026, 8, 14, 7))
        ..addJob(CronJob(
          name: 'download',
          schedule: CronSchedule.parse('0 6 * * *'),
          action: () async => runs++,
        ));
      await scheduler.runDue();
      expect(runs, 0);
    });

    test('падение задачи не роняет планировщик', () async {
      Object? captured;
      final scheduler = CronScheduler(
        clock: () => DateTime(2026, 8, 14, 6),
        onError: (job, error, stackTrace) => captured = error,
      )..addJob(CronJob(
          name: 'boom',
          schedule: CronSchedule.parse('0 6 * * *'),
          action: () async => throw StateError('сломалось'),
        ));
      await scheduler.runDue();
      expect(captured, isA<StateError>());
    });
  });

  group('московское время', () {
    test('смещение +03:00 без перехода на летнее время', () {
      final utc = DateTime.utc(2026, 8, 14, 14, 28);
      expect(MoscowTime.toMoscow(utc), DateTime(2026, 8, 14, 17, 28));
      final winter = DateTime.utc(2026, 1, 14, 14, 28);
      expect(MoscowTime.toMoscow(winter), DateTime(2026, 1, 14, 17, 28));
    });

    test('форматирование и разбор совместимы', () {
      final moscow = DateTime(2026, 8, 14, 17, 28, 5);
      final text = MoscowTime.format(moscow);
      expect(text, '2026-08-14T17:28:05+03:00');
      expect(MoscowTime.parse(text), moscow);
    });
  });
}
