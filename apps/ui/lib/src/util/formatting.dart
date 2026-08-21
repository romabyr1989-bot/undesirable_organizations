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
