/// Модели результата автоматического разбора (п. 6 ТЗ).
library;

import '../names/script.dart';

/// Уверенность автоматического разбора записи (п. 6.1, шаг 6 ТЗ).
enum Confidence {
  /// Разбор однозначный.
  ok,

  /// Сработали неоднозначные ветки — запись подсвечивается в UI.
  review;

  static Confidence fromName(String value) =>
      value == 'review' ? Confidence.review : Confidence.ok;
}

/// Классы кандидатов-наименований (п. 6.1, шаг 2 ТЗ).
enum CandidateKind {
  /// Наименование на кириллице.
  cyrillic,

  /// Наименование на латинице.
  latin,

  /// Страна регистрации.
  country,

  /// Аббревиатура (правило 9: исключаем).
  abbreviation,

  /// Служебный фрагмент: примечание о переименовании, «сокращенное
  /// наименование», «другое используемое наименование» и т. п.
  service,

  /// Буквы вне кириллицы и латиницы (правило 10).
  otherScript,

  /// Географическая привязка рядом со страной («Великобритания, Лондон»).
  location,

  /// Мусор: пустые фрагменты, отдельные знаки, номера.
  garbage,
}

/// Кандидат-наименование, полученный на этапе токенизации.
class NameCandidate {
  NameCandidate({
    required this.raw,
    required this.value,
    required this.kind,
    required this.script,
    this.depth = 0,
    this.order = 0,
    this.renamed = false,
    this.excludedReason,
  });

  /// Исходный фрагмент до очистки.
  final String raw;

  /// Очищенное значение (без кавычек, скобок, висящих знаков).
  final String value;

  /// Класс кандидата.
  CandidateKind kind;

  /// Алфавит фрагмента.
  final NameScript script;

  /// Глубина вложенности скобок (0 — вне скобок).
  final int depth;

  /// Порядок появления в исходной строке.
  final int order;

  /// Кандидат получен из примечания о переименовании (Р-8).
  final bool renamed;

  /// Причина, по которой кандидат не попал в целевое поле.
  String? excludedReason;

  int get length => value.length;

  NameCandidate copyWith({CandidateKind? kind, String? excludedReason}) =>
      NameCandidate(
        raw: raw,
        value: value,
        kind: kind ?? this.kind,
        script: script,
        depth: depth,
        order: order,
        renamed: renamed,
        excludedReason: excludedReason ?? this.excludedReason,
      );

  Map<String, Object?> toJson() => {
        'raw': raw,
        'value': value,
        'kind': kind.name,
        'script': script.name,
        'depth': depth,
        'order': order,
        'renamed': renamed,
        'excludedReason': excludedReason,
      };

  @override
  String toString() => '${kind.name}:"$value"';
}

/// Коды пометок разбора (машиночитаемые, попадают в БД и UI).
class ParseNote {
  static const translitDropped = 'translit_dropped';
  static const translitKept = 'translit_kept';
  static const transcriptionDropped = 'transcription_dropped';
  static const transcriptionKept = 'transcription_kept';
  static const abbreviationDropped = 'abbreviation_dropped';
  static const otherScriptDropped = 'other_script_dropped';
  static const otherScriptOnly = 'other_script_only';
  static const ambiguousLength = 'ambiguous_length';
  static const countryNotFound = 'country_not_found';
  static const countryMissing = 'country_missing';
  static const renamed = 'renamed';
  static const emptyName = 'empty_name';
  static const duplicateDropped = 'duplicate_dropped';
  static const noLatinName = 'no_latin_name';
  static const noCyrillicName = 'no_cyrillic_name';

  /// В слове буква была набрана не тем алфавитом (латинская `i` в
  /// кириллическом слове и наоборот) — приведено к одному алфавиту.
  static const homoglyphFixed = 'homoglyph_fixed';

  /// В значении есть символ, которого нет в cp1251 и для которого нет
  /// аналога: в целевом файле он станет «?».
  static const charNotInCp1251 = 'char_not_in_cp1251';
}

/// Результат разбора реквизита «Наименование организации».
class ParsedName {
  ParsedName({
    required this.source,
    required this.nameRus,
    required this.nameAdd,
    required this.country,
    required this.confidence,
    required this.notes,
    required this.candidates,
  });

  /// Исходная сырая строка.
  final String source;

  /// Целевая колонка 4: наименование на кириллице.
  final String nameRus;

  /// Целевая колонка 5: наименование на латинице (доп.).
  final String nameAdd;

  /// Целевая колонка 6: страна регистрации.
  final String country;

  final Confidence confidence;

  /// Коды сработавших неоднозначных веток (см. [ParseNote]).
  final List<String> notes;

  /// Все кандидаты с классификацией — показываются в UI при разворачивании.
  final List<NameCandidate> candidates;

  Map<String, Object?> toJson() => {
        'source': source,
        'nameRus': nameRus,
        'nameAdd': nameAdd,
        'country': country,
        'confidence': confidence.name,
        'notes': notes,
        'candidates': candidates.map((c) => c.toJson()).toList(),
      };
}
