/// Транслитерация кириллицы в латиницу и эвристики распознавания
/// транслита/транскрипции (правила 5 и 6 п. 6 ТЗ).
library;

import '../util/text.dart';

const Map<String, String> _cyrToLat = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
  'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
  'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
  'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
  'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  // украинские и белорусские буквы
  'і': 'i', 'ї': 'yi', 'є': 'ye', 'ґ': 'g', 'ў': 'u',
};

/// Транслитерация кириллической строки в латиницу (практическая схема).
String translitCyrillicToLatin(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_cyrToLat[ch] ?? ch);
  }
  return buffer.toString();
}

/// Ключ для сравнения: только латинские буквы и цифры, без артиклей,
/// с приведением частых вариантов написания (kh/h, ya/ia, ck/k...).
String translitKey(String value) {
  var result = translitCyrillicToLatin(value).toLowerCase();
  result = result.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  final words = result
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_stopWords.contains(w))
      .map(_foldWord)
      .toList();
  return words.join(' ');
}

const _stopWords = <String>{
  'the', 'a', 'an', 'of', 'for', 'and', 'in', 'inc', 'ltd', 'llc', 'gmbh',
  'ev', 'e', 'v', 'zs', 'sa', 'bv', 'ag', 'as', 'ry', 'ou', 'mtu', 'sro',
};

/// Сворачивает частые различия транслитерации: kh->h, ya->a, iy->i, ss->s.
String _foldWord(String word) {
  var result = word;
  result = result.replaceAll('kh', 'h');
  result = result.replaceAll('ph', 'f');
  result = result.replaceAll('ck', 'k');
  result = result.replaceAll('ts', 's');
  result = result.replaceAll('yi', 'i');
  result = result.replaceAll('iy', 'i');
  result = result.replaceAll('ya', 'a');
  result = result.replaceAll('ye', 'e');
  result = result.replaceAll('yu', 'u');
  result = result.replaceAll('j', 'y');
  result = result.replaceAll('w', 'v');
  result = result.replaceAll(RegExp(r'(.)\1+'), r'$1');
  return result;
}

/// Похожесть двух наименований после приведения к транслит-ключу.
double translitSimilarity(String a, String b) {
  final keyA = translitKey(a);
  final keyB = translitKey(b);
  if (keyA.isEmpty || keyB.isEmpty) return 0;
  final direct = similarity(keyA, keyB);
  final noSpacesA = keyA.replaceAll(' ', '');
  final noSpacesB = keyB.replaceAll(' ', '');
  final packed = similarity(noSpacesA, noSpacesB);
  final containment = noSpacesA.length >= 4 && noSpacesB.length >= 4 &&
          (noSpacesA.contains(noSpacesB) || noSpacesB.contains(noSpacesA))
      ? 0.9
      : 0.0;
  return [direct, packed, containment]
      .reduce((value, element) => value > element ? value : element);
}

/// Маркеры русского транслита в латинской строке (используются, когда
/// кириллического «оригинала» в наименовании нет).
final _russianTranslitMarkers = <RegExp>[
  RegExp(r'\b\w*(rossi|rossiy|rusi)\w*\b'),
  RegExp(r'\w*(aya|ogo|ovo|skiy|sky|skaya|nnaya|nost)\b'),
  RegExp(r'(zh|shch|tch|kh)'),
  RegExp(r'\b(otkrytaya|svobodnaya|russkiy|narodnaya|nash|nasha|gazeta|fond)\b'),
];

/// Похожа ли латинская строка на транслит русских слов.
bool looksLikeRussianTranslit(String value) {
  final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ');
  var hits = 0;
  for (final marker in _russianTranslitMarkers) {
    if (marker.hasMatch(normalized)) hits++;
  }
  return hits >= 2;
}
