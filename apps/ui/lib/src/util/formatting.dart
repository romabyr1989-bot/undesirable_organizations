/// Форматирование значений для интерфейса.
library;

/// `2026-08-14T17:28:00+03:00` -> `14.08.2026 17:28`.
String formatMoscowDateTime(String? value) {
  if (value == null || value.isEmpty) return '—';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final moscow = parsed.isUtc ? parsed.add(const Duration(hours: 3)) : parsed;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(moscow.day)}.${two(moscow.month)}.${moscow.year} '
      '${two(moscow.hour)}:${two(moscow.minute)}';
}

/// `2026-08-14T17:28:00+03:00` -> `14.08.2026`.
String formatMoscowDate(String? value) {
  final full = formatMoscowDateTime(value);
  return full.length >= 10 ? full.substring(0, 10) : full;
}

/// Русское склонение: 1 запись, 2 записи, 5 записей.
String plural(int count, String one, String few, String many) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  if (mod100 >= 11 && mod100 <= 14) return '$count $many';
  if (mod10 == 1) return '$count $one';
  if (mod10 >= 2 && mod10 <= 4) return '$count $few';
  return '$count $many';
}

/// Человеческое описание пометки разбора.
String noteTitle(String note) => switch (note) {
      'translit_dropped' => 'исключён транслит русского наименования',
      'translit_kept' => 'перенесён транслит (другой латиницы нет)',
      'transcription_dropped' => 'исключена транскрипция иностранного названия',
      'transcription_kept' => 'перенесена транскрипция (другой кириллицы нет)',
      'abbreviation_dropped' => 'исключена аббревиатура',
      'other_script_dropped' => 'исключён фрагмент на ином алфавите',
      'other_script_only' => 'наименование только на ином алфавите',
      'ambiguous_length' => 'несколько равнозначных кандидатов',
      'country_not_found' => 'похоже на страну, но её нет в справочнике',
      'country_missing' => 'страна в наименовании не указана',
      'renamed' => 'учтено переименование организации',
      'empty_name' => 'наименование не распознано',
      'duplicate_dropped' => 'исключён дубль наименования',
      'no_latin_name' => 'нет наименования на латинице',
      'no_cyrillic_name' => 'нет наименования на кириллице',
      'stale_correction' => 'ручная правка отвязалась от наименования',
      _ => note,
    };

/// Расписание cron человеческим языком.
///
/// `0 6 * * *` -> `в 06:00`, `0 6 * * 1-5` -> `по будням в 06:00`,
/// `*/15 * * * *` -> `каждые 15 минут`, `0 6,18 * * *` -> `в 06:00 и 18:00`.
///
/// Выражение, которое не удалось разобрать, возвращается как есть: лучше
/// показать сырое расписание, чем соврать про время запуска.
String cronTitle(String cron) {
  final parts = cron.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return cron;
  final [minute, hour, dayOfMonth, month, dayOfWeek] = parts;

  final everyMinutes = RegExp(r'^\*/(\d+)$').firstMatch(minute);
  if (everyMinutes != null &&
      hour == '*' &&
      dayOfMonth == '*' &&
      month == '*' &&
      dayOfWeek == '*') {
    final step = int.parse(everyMinutes.group(1)!);
    return 'каждые ${plural(step, 'минуту', 'минуты', 'минут')}';
  }

  final everyHours = RegExp(r'^\*/(\d+)$').firstMatch(hour);
  if (everyHours != null &&
      _isNumber(minute) &&
      dayOfMonth == '*' &&
      month == '*' &&
      dayOfWeek == '*') {
    final step = int.parse(everyHours.group(1)!);
    return 'каждые ${plural(step, 'час', 'часа', 'часов')}';
  }

  if (!_isNumber(minute)) return cron;
  final hours = hour.split(',');
  if (hours.any((h) => !_isNumber(h))) return cron;

  final times = hours
      .map((h) => '${_two(int.parse(h))}:${_two(int.parse(minute))}')
      .join(' и ');
  final days = _cronDays(dayOfMonth, month, dayOfWeek);
  if (days == null) return cron;
  return days.isEmpty ? 'в $times' : '$days в $times';
}

/// `Europe/Moscow` -> `МСК`. Прочие зоны показываем как есть.
String timeZoneTitle(String zone) =>
    zone == 'Europe/Moscow' ? 'МСК' : zone;

/// Дни запуска словами. Пустая строка — каждый день, `null` — не разобрали.
String? _cronDays(String dayOfMonth, String month, String dayOfWeek) {
  if (month != '*') return null;
  if (dayOfWeek == '*' && dayOfMonth == '*') return '';
  if (dayOfWeek != '*' && dayOfMonth != '*') return null;

  if (dayOfWeek != '*') {
    if (dayOfWeek == '1-5') return 'по будням';
    if (dayOfWeek == '0,6' || dayOfWeek == '6,0' || dayOfWeek == '6,7') {
      return 'по выходным';
    }
    final days = dayOfWeek.split(',');
    if (days.any((d) => !_isNumber(d))) return null;
    final names = days.map((d) => _weekDay(int.parse(d))).toList();
    if (names.any((name) => name == null)) return null;
    return 'по ${names.join(' и ')}';
  }

  if (!_isNumber(dayOfMonth)) return null;
  return '$dayOfMonth-го числа';
}

/// Дательный падеж множественного числа: «по понедельникам».
String? _weekDay(int day) => switch (day) {
      0 || 7 => 'воскресеньям',
      1 => 'понедельникам',
      2 => 'вторникам',
      3 => 'средам',
      4 => 'четвергам',
      5 => 'пятницам',
      6 => 'субботам',
      _ => null,
    };

bool _isNumber(String value) =>
    value.isNotEmpty && int.tryParse(value) != null;

String _two(int value) => value.toString().padLeft(2, '0');
