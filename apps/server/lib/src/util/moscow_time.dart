/// Время сервиса: все расписания и даты — в `Europe/Moscow` (п. 2 ТЗ).
///
/// Москва не переходит на летнее время с 2014 года, смещение постоянное
/// UTC+3, поэтому пояс задаётся явным смещением, без внешней базы часовых
/// поясов и без зависимости от настроек хоста.
library;

class MoscowTime {
  const MoscowTime._();

  /// Смещение `Europe/Moscow` относительно UTC.
  static const offset = Duration(hours: 3);

  static const zoneName = 'Europe/Moscow';

  /// Текущее московское время (как «наивный» DateTime).
  static DateTime now() => toMoscow(DateTime.now().toUtc());

  /// UTC -> московское время («наивный» DateTime без флага UTC: работаем с
  /// компонентами даты и времени, пояс задаётся явно смещением [offset]).
  static DateTime toMoscow(DateTime utc) {
    final shifted = utc.toUtc().add(offset);
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
      shifted.millisecond,
    );
  }

  /// Московское время -> UTC.
  static DateTime toUtc(DateTime moscow) =>
      DateTime.utc(
        moscow.year,
        moscow.month,
        moscow.day,
        moscow.hour,
        moscow.minute,
        moscow.second,
        moscow.millisecond,
      ).subtract(offset);

  /// Строка вида `2026-08-14T17:28:00+03:00` для логов и API.
  static String format(DateTime moscow) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${moscow.year}-${two(moscow.month)}-${two(moscow.day)}'
        'T${two(moscow.hour)}:${two(moscow.minute)}:${two(moscow.second)}'
        '+03:00';
  }

  /// Разбор строки, ранее записанной [format] (или ISO без смещения).
  static DateTime parse(String value) {
    final parsed = DateTime.parse(value);
    return parsed.isUtc ? toMoscow(parsed) : parsed;
  }
}
