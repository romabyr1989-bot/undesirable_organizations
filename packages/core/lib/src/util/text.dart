/// Утилиты работы с текстом: нормализация пробелов, кавычек, скриптов.
library;

/// Кавычки всех видов, встречающиеся в перечне (правило 1 п. 6 ТЗ).
const quoteChars = <String>{
  '«', '»', '"', "'", '“', '”', '„', '‟',
  '‘', '’', '‚', '‛', '`', '´', '″', '′',
};

/// Пробельные символы, приводимые к обычному пробелу
/// (NBSP, узкие/широкие пробелы, переносы строк, служебные метки).
const spaceLikeChars = <String>{
  ' ', '\t', '\n', '\r',
  '\u00a0', '\u00ad', '\u2000', '\u2001', '\u2002', '\u2003',
  '\u2004', '\u2005', '\u2006', '\u2007', '\u2008', '\u2009',
  '\u200a', '\u200b', '\u202f', '\u205f', '\u3000', '\ufeff',
};

/// Приводит пробельные символы к обычному пробелу и (опционально) схлопывает
/// повторы. Схлопывание — отдельный флаг: в первоисточнике двойные пробелы
/// появляются из-за переносов строк исходного документа (см. Р-6).
String normalizeSpaces(String value, {bool collapse = true}) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(spaceLikeChars.contains(ch) ? ' ' : ch);
  }
  var result = buffer.toString();
  if (collapse) {
    result = result.replaceAll(RegExp(r' {2,}'), ' ');
  }
  return result.trim();
}

/// Удаляет кавычки любого вида из строки.
String stripQuotes(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    if (!quoteChars.contains(ch)) buffer.write(ch);
  }
  return buffer.toString();
}

/// Обрезает висящие знаки препинания по краям (п. 6.1, шаг 5 ТЗ).
String trimPunctuation(String value) {
  var result = normalizeSpaces(value, collapse: false);
  const trailing = ' ,;:.-–—·•*';
  const leading = ' ,;:·•*–—';
  while (result.isNotEmpty && trailing.contains(result[result.length - 1])) {
    result = result.substring(0, result.length - 1);
  }
  while (result.isNotEmpty && leading.contains(result[0])) {
    result = result.substring(1);
  }
  return result;
}

/// Полная очистка кандидата-наименования: кавычки, скобки-сироты, пробелы,
/// висящие знаки препинания.
String cleanupName(String value, {bool collapseSpaces = true}) {
  var result = stripQuotes(value);
  result = result.replaceAll(RegExp(r'[()\[\]{}]'), ' ');
  result = normalizeSpaces(result, collapse: collapseSpaces);
  result = trimPunctuation(result);
  return normalizeSpaces(result, collapse: collapseSpaces);
}

/// Ключ для сравнения строк «по смыслу»: регистр, кавычки, пробелы, «ё».
String comparisonKey(String value) {
  final cleaned = stripQuotes(value).toLowerCase().replaceAll('ё', 'е');
  final onlyLettersAndDigits =
      cleaned.replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ');
  return normalizeSpaces(onlyLettersAndDigits);
}

/// Является ли [inner] подстрокой [outer] с точки зрения сравнения по смыслу.
bool isSubstringOf(String inner, String outer) {
  final a = comparisonKey(inner);
  final b = comparisonKey(outer);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  return b.contains(a);
}

/// Расстояние Левенштейна (используется при сравнении транслитераций).
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  final current = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      var best = current[j] + 1;
      if (previous[j + 1] + 1 < best) best = previous[j + 1] + 1;
      if (previous[j] + cost < best) best = previous[j] + cost;
      current[j + 1] = best;
    }
    previous = List<int>.of(current);
  }
  return previous[b.length];
}

/// Похожесть строк в диапазоне 0..1 на базе расстояния Левенштейна.
double similarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen == 0) return 1;
  return 1 - levenshtein(a, b) / maxLen;
}
