/// Справочник стран (п. 6.1, шаг 3 ТЗ; решение Р-3).
///
/// Справочник используется ТОЛЬКО для распознавания страны в наименовании.
/// В целевое поле значение переносится из первоисточника без преобразований,
/// если [CountryRegistry.normalize] не включён явно (COUNTRY_NORMALIZE).
library;

import '../util/text.dart';

class CountryRegistry {
  CountryRegistry(Iterable<String> names, {this.normalize = false}) {
    for (final raw in names) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      _canonicalByKey[_key(line)] = line;
    }
  }

  /// Разбирает содержимое файла `countries_ru.txt`.
  factory CountryRegistry.parse(String fileContent, {bool normalize = false}) =>
      CountryRegistry(fileContent.split('\n'), normalize: normalize);

  /// Пустой справочник (страна не будет распознаваться).
  factory CountryRegistry.empty() => CountryRegistry(const <String>[]);

  /// Если true — в целевое поле пишется каноническое написание из справочника,
  /// иначе (по умолчанию, Р-3) — исходная строка первоисточника.
  final bool normalize;

  final Map<String, String> _canonicalByKey = <String, String>{};

  int get length => _canonicalByKey.length;

  static String _key(String value) =>
      comparisonKey(value).replaceAll('ё', 'е').toLowerCase();

  /// Является ли строка названием страны целиком.
  bool isCountry(String value) => _canonicalByKey.containsKey(_key(value));

  /// Значение для целевого поля «Страна регистрации».
  ///
  /// По умолчанию — исходная строка (правило 8: «без преобразований»).
  String? countryValue(String value) {
    final canonical = _canonicalByKey[_key(value)];
    if (canonical == null) return null;
    return normalize ? canonical : value;
  }

  /// Похоже ли значение на страну, хотя точного совпадения нет.
  ///
  /// Используется для пометки `review`: например «Республика Сомалиленд»
  /// или страна с опечаткой — распознать нельзя, но насторожиться стоит.
  bool looksLikeCountry(String value) {
    final key = _key(value);
    if (key.isEmpty || key.length > 60) return false;
    if (_canonicalByKey.containsKey(key)) return true;
    const markers = <String>[
      'республик', 'королевств', 'федерац', 'княжеств', 'герцогств',
      'конфедерац', 'штаты', 'эмираты', 'острова', 'соединенное королевство',
    ];
    for (final marker in markers) {
      if (key.contains(marker)) return true;
    }
    for (final canonicalKey in _canonicalByKey.keys) {
      if (canonicalKey.length < 5) continue;
      if (similarity(canonicalKey, key) >= 0.85) return true;
    }
    return false;
  }
}
