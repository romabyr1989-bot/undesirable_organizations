/// Работа с датами первоисточника: `DD.MM.YYYY`, Excel-даты, ISO.
library;

final _ddmmyyyy = RegExp(r'^(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4})');
final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

String _two(int value) => value.toString().padLeft(2, '0');

/// Формат первоисточника и целевого файла: `DD.MM.YYYY`.
String formatRuDate(DateTime date) =>
    '${_two(date.day)}.${_two(date.month)}.${date.year}';

/// `YYYY-MM-DD` — для ключей и API.
String formatIsoDate(DateTime date) =>
    '${date.year}-${_two(date.month)}-${_two(date.day)}';

/// `YYYY_MM_DD` — для имени целевого файла (п. 4 ТЗ).
String formatFileNameDate(DateTime date) =>
    '${date.year}_${_two(date.month)}_${_two(date.day)}';

/// Разбирает дату из текста (`DD.MM.YYYY`, `YYYY-MM-DD`), либо null.
DateTime? parseRuDate(String? value) {
  if (value == null) return null;
  final text = value.trim();
  if (text.isEmpty) return null;
  final ru = _ddmmyyyy.firstMatch(text);
  if (ru != null) {
    final day = int.parse(ru.group(1)!);
    final month = int.parse(ru.group(2)!);
    final year = int.parse(ru.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }
  final iso = _isoDate.firstMatch(text);
  if (iso != null) {
    return DateTime(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  return null;
}

/// Нормализует значение ячейки-даты к тексту `DD.MM.YYYY`.
///
/// Даты приходят и текстом, и Excel-датой (п. 3 ТЗ: парсер должен быть
/// устойчив к типам ячеек). Нераспознанное значение возвращается как есть.
String normalizeDateCell(Object? value) {
  if (value == null) return '';
  if (value is DateTime) return formatRuDate(value);
  final text = value.toString().trim();
  if (text.isEmpty) return '';
  final parsed = parseRuDate(text);
  return parsed == null ? text : formatRuDate(parsed);
}
