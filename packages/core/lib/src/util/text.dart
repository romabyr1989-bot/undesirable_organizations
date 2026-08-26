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

/// Пары «латиница → кириллица», неразличимые на глаз.
///
/// В первоисточнике встречаются слова, где одна буква набрана не тем
/// алфавитом: «Управлiння» с латинской `i`, «ОРГАНI3АЦIЯ» с латинской `I` и
/// цифрой `3`, «Transparеncy» с кириллической `е`. На вид всё в порядке, но в
/// целевом файле такие слова не находятся поиском и не сортируются.
const _latinToCyrillic = <String, String>{
  'A': 'А', 'B': 'В', 'C': 'С', 'E': 'Е', 'H': 'Н', 'I': 'І', 'K': 'К',
  'M': 'М', 'O': 'О', 'P': 'Р', 'T': 'Т', 'X': 'Х', 'Y': 'У',
  'a': 'а', 'c': 'с', 'e': 'е', 'i': 'і', 'o': 'о', 'p': 'р', 'x': 'х',
  'y': 'у', 'ï': 'ї', 'Ï': 'Ї',
  // Турецкую «Ç» в перечне пишут кириллической «Ҫ» (Ҫeҫen Kafkas...).
  'Ç': 'Ҫ', 'ç': 'ҫ',
};

final Map<String, String> _cyrillicToLatin = {
  for (final entry in _latinToCyrillic.entries) entry.value: entry.key,
};

/// Цифры, которыми в первоисточнике заменяют буквы («ОРГАНI3АЦIЯ»).
const _digitToCyrillic = <String, String>{'3': 'З', '0': 'О'};

bool _isCyrillic(String ch) =>
    (ch.compareTo('А') >= 0 && ch.compareTo('я') <= 0) ||
    'ЁёЄєІіЇїҐґЎўҪҫ'.contains(ch);

bool _isLatin(String ch) =>
    (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0) ||
    (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) ||
    'ÇçÏï'.contains(ch);

/// Приводит слово к одному алфавиту, если второй представлен в нём только
/// неразличимыми на глаз буквами.
///
/// Слово, где оба алфавита представлены собственными буквами («КрымSOS»),
/// не трогается: это осознанно двуязычное название.
String fixHomoglyphs(String value) {
  if (value.isEmpty) return value;
  final buffer = StringBuffer();
  final word = StringBuffer();

  void flushWord() {
    if (word.isEmpty) return;
    buffer.write(_fixWord(word.toString()));
    word.clear();
  }

  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    final isWordChar = _isLatin(ch) || _isCyrillic(ch) || _digitToCyrillic.containsKey(ch);
    if (isWordChar) {
      word.write(ch);
    } else {
      flushWord();
      buffer.write(ch);
    }
  }
  flushWord();
  return buffer.toString();
}

String _fixWord(String word) {
  var cyrillicOwn = 0;
  var latinOwn = 0;
  for (final rune in word.runes) {
    final ch = String.fromCharCode(rune);
    if (_isCyrillic(ch) && !_cyrillicToLatin.containsKey(ch)) cyrillicOwn++;
    if (_isLatin(ch) && !_latinToCyrillic.containsKey(ch)) latinOwn++;
  }
  // Ни одного однозначного алфавита или сразу оба — не вмешиваемся.
  if (cyrillicOwn == 0 && latinOwn == 0) return word;
  if (cyrillicOwn > 0 && latinOwn > 0) return word;

  final chars = word.split('');
  final toCyrillic = cyrillicOwn > 0;
  for (var i = 0; i < chars.length; i++) {
    final ch = chars[i];
    if (toCyrillic) {
      final letter = _latinToCyrillic[ch];
      if (letter != null) {
        chars[i] = letter;
        continue;
      }
      // Цифру заменяем буквой, только если она стоит между буквами.
      final digit = _digitToCyrillic[ch];
      final insideWord = i > 0 &&
          i < chars.length - 1 &&
          !_digitToCyrillic.containsKey(chars[i - 1]) &&
          !_digitToCyrillic.containsKey(chars[i + 1]);
      if (digit != null && insideWord) chars[i] = digit;
    } else {
      final letter = _cyrillicToLatin[ch];
      if (letter != null) chars[i] = letter;
    }
  }
  return chars.join();
}
