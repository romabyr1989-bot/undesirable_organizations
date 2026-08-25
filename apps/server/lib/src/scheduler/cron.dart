/// Планировщик с cron-выражениями, работающий строго по московскому времени.
///
/// Своя реализация вместо пакета `cron` выбрана из-за требования п. 2 ТЗ:
/// часовой пояс расписаний задаётся явно и не зависит от локали хоста.
library;

import 'dart:async';

import '../util/moscow_time.dart';

/// Разобранное cron-выражение из пяти полей:
/// `минута час день месяц день_недели`.
class CronSchedule {
  CronSchedule._(
    this.expression,
    this._minutes,
    this._hours,
    this._daysOfMonth,
    this._months,
    this._daysOfWeek,
  );

  final String expression;
  final Set<int> _minutes;
  final Set<int> _hours;
  final Set<int> _daysOfMonth;
  final Set<int> _months;
  final Set<int> _daysOfWeek;

  /// Разбирает выражение вида `0 6 * * *`.
  static CronSchedule parse(String expression) {
    final parts = expression.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) {
      throw FormatException(
        'cron-выражение должно содержать 5 полей: "$expression"',
      );
    }
    return CronSchedule._(
      expression,
      _parseField(parts[0], 0, 59),
      _parseField(parts[1], 0, 23),
      _parseField(parts[2], 1, 31),
      _parseField(parts[3], 1, 12),
      _parseField(parts[4], 0, 6, normalize: (value) => value % 7),
    );
  }

  static Set<int> _parseField(
    String field,
    int min,
    int max, {
    int Function(int)? normalize,
  }) {
    final values = <int>{};
    for (final part in field.split(',')) {
      final stepMatch = RegExp(r'^(.+)/(\d+)$').firstMatch(part);
      final step = stepMatch == null ? 1 : int.parse(stepMatch.group(2)!);
      final range = stepMatch == null ? part : stepMatch.group(1)!;

      int from;
      int to;
      if (range == '*') {
        from = min;
        to = max;
      } else if (range.contains('-')) {
        final bounds = range.split('-');
        from = int.parse(bounds[0]);
        to = int.parse(bounds[1]);
      } else {
        from = int.parse(range);
        to = from;
      }
      for (var value = from; value <= to; value += step) {
        final normalized = normalize == null ? value : normalize(value);
        if (normalized < min || normalized > max) {
          throw FormatException('значение вне диапазона в "$field"');
        }
        values.add(normalized);
      }
    }
    return values;
  }

  /// Совпадает ли расписание с указанной минутой московского времени.
  bool matches(DateTime moscowTime) =>
      _minutes.contains(moscowTime.minute) &&
      _hours.contains(moscowTime.hour) &&
      _daysOfMonth.contains(moscowTime.day) &&
      _months.contains(moscowTime.month) &&
      _daysOfWeek.contains(moscowTime.weekday % 7);

  /// Ближайший следующий запуск после [from] (для индикатора в UI).
  DateTime nextRunAfter(DateTime from) {
    var candidate = DateTime(
      from.year,
      from.month,
      from.day,
      from.hour,
      from.minute,
    ).add(const Duration(minutes: 1));
    for (var i = 0; i < 366 * 24 * 60; i++) {
      if (matches(candidate)) return candidate;
      candidate = candidate.add(const Duration(minutes: 1));
    }
    throw StateError('не удалось вычислить следующий запуск: $expression');
  }

  @override
  String toString() => expression;
}

/// Задача планировщика.
class CronJob {
  CronJob({
    required this.name,
    required this.schedule,
    required this.action,
  });

  final String name;

  /// Меняется на ходу: расписание правится в UI без перезапуска службы.
  CronSchedule schedule;

  final Future<void> Function() action;

  DateTime? lastRunAt;
}

/// Планировщик: тикает раз в 20 секунд и запускает задачи, чьё расписание
/// совпало с текущей минутой (каждая минута — не более одного запуска).
class CronScheduler {
  CronScheduler({
    DateTime Function()? clock,
    this.tick = const Duration(seconds: 20),
    this.onError,
  }) : _clock = clock ?? MoscowTime.now;

  final DateTime Function() _clock;
  final Duration tick;
  final void Function(CronJob job, Object error, StackTrace stackTrace)? onError;

  final List<CronJob> _jobs = <CronJob>[];
  Timer? _timer;
  final Set<String> _running = <String>{};

  List<CronJob> get jobs => List.unmodifiable(_jobs);

  void addJob(CronJob job) => _jobs.add(job);

  /// Меняет расписание задачи (правка настроек в UI).
  ///
  /// Возвращает `false`, если задачи с таким именем нет.
  bool reschedule(String jobName, CronSchedule schedule) {
    for (final job in _jobs) {
      if (job.name != jobName) continue;
      job.schedule = schedule;
      return true;
    }
    return false;
  }

  void start() {
    _timer ??= Timer.periodic(tick, (_) => runDue());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Проверяет расписания и запускает подошедшие задачи.
  Future<void> runDue() async {
    final now = _clock();
    final minute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    for (final job in _jobs) {
      if (!job.schedule.matches(minute)) continue;
      if (job.lastRunAt == minute) continue;
      if (_running.contains(job.name)) continue;
      job.lastRunAt = minute;
      _running.add(job.name);
      try {
        await job.action();
      } catch (error, stackTrace) {
        onError?.call(job, error, stackTrace);
      } finally {
        _running.remove(job.name);
      }
    }
  }

  /// Ближайший запуск любой из задач.
  DateTime? get nextRunAt {
    final now = _clock();
    DateTime? nearest;
    for (final job in _jobs) {
      final next = job.schedule.nextRunAfter(now);
      if (nearest == null || next.isBefore(nearest)) nearest = next;
    }
    return nearest;
  }
}
