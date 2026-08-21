/// Разбор реквизита «Наименование организации» (п. 6 ТЗ).
///
/// Сырая строка первоисточника раскладывается на три целевых поля:
/// `(рус)`, `(доп.)` и `Страна регистрации`. Реализованы все 11 правил
/// постановки задачи; неоднозначные ветки помечают запись `review`.
library;

import '../config/core_config.dart';
import '../models/parsed.dart';
import '../util/text.dart';
import 'countries.dart';
import 'script.dart';
import 'translit.dart';

/// Фрагмент строки, полученный на этапе токенизации.
class _Fragment {
  _Fragment({
    required this.raw,
    required this.depth,
    required this.order,
    this.renamed = false,
  });

  final String raw;
  final int depth;
  final int order;
  final bool renamed;
}

class NameParser {
  NameParser({
    required this.countries,
    this.config = const CoreConfig(),
  });

  final CountryRegistry countries;
  final CoreConfig config;

  /// Организационно-правовые формы: приклеиваются к предыдущему фрагменту,
  /// чтобы «Project Harmony, Inc.» не распадалось на два наименования.
  static const _legalForms = <String>{
    'inc', 'inc.', 'ltd', 'ltd.', 'llc', 'gmbh', 'ggmbh', 'ug', 'ag', 'kg',
    'e.v', 'e.v.', 'ev', 'z.s', 'z.s.', 'zs', 's.r.o', 's.r.o.', 'sro',
    'b.v', 'b.v.', 'bv', 'n.v', 'n.v.', 'nv', 's.a', 's.a.', 'sa', 'sarl',
    's.a.r.l.', 'as', 'ab', 'oy', 'oyj', 'ry', 'mtu', 'o.p.s', 'o.p.s.',
    'corp', 'corp.', 'co', 'co.', 'plc', 'aps', 'iks', 'spa', 's.p.a.',
    'ооо', 'оао', 'зао', 'ао',
  };

  /// Примечание о переименовании (Р-8): `с 08.11.2017 - NEW NAME`.
  static final _renamedPattern = RegExp(
    r'^\s*(?:с|from)\s+\d{1,2}[.\-/]\d{1,2}[.\-/]\d{2,4}\s*[-‐-―]\s*(.+)$',
    caseSensitive: false,
  );

  /// Служебные префиксы: «другое используемое наименование: X».
  static final _servicePrefixes = <RegExp>[
    RegExp(r'^\s*(?:другое|иное)\s+используемое\s+наименование\s*:?\s*',
        caseSensitive: false),
    RegExp(r'^\s*сокраще[нн]ое\s+наименование\s*:?\s*', caseSensitive: false),
    RegExp(r'^\s*полное\s+наименование\s*:?\s*', caseSensitive: false),
    RegExp(r'^\s*использу[а-яё]*\s+(?:также\s+)?наименование\s*:?\s*',
        caseSensitive: false),
    RegExp(r'^\s*(?:ранее|прежнее\s+наименование)\s*:?\s*',
        caseSensitive: false),
  ];

  /// Разбирает сырое наименование.
  ParsedName parse(String rawName) {
    final source = rawName;
    final notes = <String>{};
    final fragments = _tokenize(normalizeSpaces(rawName, collapse: false));
    final candidates = _classify(fragments, notes);

    final country = _selectCountry(candidates, notes);
    final nameRus = _selectName(
      candidates,
      CandidateKind.cyrillic,
      CandidateKind.latin,
      notes,
    );
    final nameAdd = _selectName(
      candidates,
      CandidateKind.latin,
      CandidateKind.cyrillic,
      notes,
    );

    if (nameRus.isEmpty && nameAdd.isEmpty) {
      notes.add(ParseNote.emptyName);
    } else {
      if (nameRus.isEmpty) notes.add(ParseNote.noCyrillicName);
      if (nameAdd.isEmpty) notes.add(ParseNote.noLatinName);
    }
    if (country.isEmpty) notes.add(ParseNote.countryMissing);

    return ParsedName(
      source: source,
      nameRus: nameRus,
      nameAdd: nameAdd,
      country: country,
      confidence: _confidenceOf(notes),
      notes: notes.toList()..sort(),
      candidates: candidates,
    );
  }

  Confidence _confidenceOf(Set<String> notes) {
    const reviewNotes = <String>{
      ParseNote.translitDropped,
      ParseNote.transcriptionDropped,
      ParseNote.ambiguousLength,
      ParseNote.otherScriptOnly,
      ParseNote.otherScriptDropped,
      ParseNote.renamed,
      ParseNote.countryNotFound,
      ParseNote.emptyName,
    };
    return notes.any(reviewNotes.contains) ? Confidence.review : Confidence.ok;
  }

  // --------------------------------------------------------------------
  // 1. Токенизация (п. 6.1, шаг 1)
  // --------------------------------------------------------------------

  List<_Fragment> _tokenize(String input) {
    final fragments = <_Fragment>[];
    var order = 0;

    void addPieces(String text, int depth) {
      for (final piece in _splitTopLevelCommas(text)) {
        final trimmed = piece.trim();
        if (trimmed.isEmpty) continue;
        // Организационно-правовая форма приклеивается к предыдущему куску.
        final key = comparisonKey(trimmed).replaceAll(' ', '');
        final isLegalForm =
            _legalForms.contains(trimmed.toLowerCase().trim()) ||
                (key.length <= 4 && _legalForms.contains(key));
        if (isLegalForm && fragments.isNotEmpty) {
          final previous = fragments.removeLast();
          fragments.add(_Fragment(
            raw: '${previous.raw}, $trimmed',
            depth: previous.depth,
            order: previous.order,
            renamed: previous.renamed,
          ));
          continue;
        }
        fragments.add(_Fragment(raw: trimmed, depth: depth, order: order++));
      }
    }

    void walk(String text, int depth) {
      final buffer = StringBuffer();
      var index = 0;
      while (index < text.length) {
        final char = text[index];
        if (char == '(' || char == '[') {
          final closing = char == '(' ? ')' : ']';
          var nesting = 0;
          var end = index;
          for (; end < text.length; end++) {
            if (text[end] == char) {
              nesting++;
            } else if (text[end] == closing) {
              nesting--;
              if (nesting == 0) break;
            }
          }
          final inner = end < text.length
              ? text.substring(index + 1, end)
              : text.substring(index + 1);
          addPieces(buffer.toString(), depth);
          buffer.clear();
          walk(inner, depth + 1);
          index = end < text.length ? end + 1 : text.length;
          continue;
        }
        if (char == ')' || char == ']') {
          index++;
          continue;
        }
        buffer.write(char);
        index++;
      }
      addPieces(buffer.toString(), depth);
    }

    walk(input, 0);
    return fragments;
  }

  /// Делит текст по запятым верхнего уровня, не трогая запятые внутри кавычек.
  static List<String> _splitTopLevelCommas(String text) {
    final result = <String>[];
    final buffer = StringBuffer();
    var insideQuotes = false;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      // Кавычки в перечне часто не сбалансированы («А «Б»), поэтому кавычка
      // не считается уровнем вложенности: «открывает» и «закрывает» режим.
      if (char == '«') insideQuotes = true;
      if (char == '»') insideQuotes = false;
      // Точка с запятой в наименованиях не встречается, поэтому режет всегда;
      // запятая — только вне кавычек («Прожект Хармони, Инк.» не делим).
      if (char == ';' || (char == ',' && !insideQuotes)) {
        result.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    result.add(buffer.toString());
    return result;
  }

  // --------------------------------------------------------------------
  // 2. Классификация (п. 6.1, шаг 2)
  // --------------------------------------------------------------------

  List<NameCandidate> _classify(List<_Fragment> fragments, Set<String> notes) {
    final candidates = <NameCandidate>[];
    for (final fragment in fragments) {
      candidates.add(_classifyOne(fragment, notes));
    }
    _markLocations(candidates);
    return candidates;
  }

  NameCandidate _classifyOne(_Fragment fragment, Set<String> notes) {
    var raw = fragment.raw;
    var renamed = fragment.renamed;

    final renamedMatch = _renamedPattern.firstMatch(raw);
    if (renamedMatch != null) {
      raw = renamedMatch.group(1)!;
      renamed = true;
      notes.add(ParseNote.renamed);
    }
    for (final prefix in _servicePrefixes) {
      if (prefix.hasMatch(raw)) {
        raw = raw.replaceFirst(prefix, '');
      }
    }

    final value = cleanupName(raw, collapseSpaces: config.collapseInnerSpaces);
    final stats = scriptStats(value);
    final script = stats.script;

    CandidateKind kind;
    if (value.isEmpty || stats.totalLetters == 0) {
      kind = CandidateKind.garbage;
    } else if (countries.isCountry(value)) {
      kind = CandidateKind.country;
    } else if (_isAbbreviation(value, stats)) {
      kind = CandidateKind.abbreviation;
      notes.add(ParseNote.abbreviationDropped);
    } else if (script == NameScript.other) {
      kind = CandidateKind.otherScript;
      notes.add(ParseNote.otherScriptDropped);
    } else if (script == NameScript.cyrillic) {
      kind = CandidateKind.cyrillic;
    } else {
      kind = CandidateKind.latin;
    }

    if (kind != CandidateKind.country &&
        kind != CandidateKind.garbage &&
        countries.looksLikeCountry(value) &&
        _looksLikeStandaloneCountry(value, stats)) {
      // Похоже на страну, но в справочнике такого написания нет (п. 6.1.6).
      notes.add(ParseNote.countryNotFound);
    }

    return NameCandidate(
      raw: fragment.raw,
      value: value,
      kind: kind,
      script: script,
      depth: fragment.depth,
      order: fragment.order,
      renamed: renamed,
    );
  }

  /// Короткий кириллический фрагмент без «организационных» слов —
  /// кандидат на неизвестную страну, а не на наименование.
  static bool _looksLikeStandaloneCountry(String value, ScriptStats stats) {
    final words = value.split(' ').where((w) => w.isNotEmpty).length;
    if (words > 3) return false;
    final lower = value.toLowerCase();
    const organizationMarkers = <String>[
      'фонд', 'центр', 'институт', 'ассоциац', 'организац', 'движение',
      'общество', 'союз', 'комитет', 'сеть', 'группа', 'платформа', 'совет',
      'университет', 'школа', 'церковь', 'партия', 'альянс', 'коалиц',
      'федерац', 'конгресс', 'лига', 'палата', 'служба', 'академия',
      'корпорация', 'сообщество', 'объединение', 'инициатива', 'проект',
      'движени', 'агентство', 'бюро', 'колледж', 'радио', 'редакц',
    ];
    return !organizationMarkers.any(lower.contains);
  }

  /// Правило 9: аббревиатуры не переносим.
  bool _isAbbreviation(String value, ScriptStats stats) {
    final words = value.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length > 2) return false;
    final lettersAndDigits =
        value.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    if (lettersAndDigits.isEmpty) return false;
    if (stats.totalLetters == 0) return false;
    if (stats.totalLetters > config.abbreviationMaxLetters) return false;
    if (lettersAndDigits != lettersAndDigits.toUpperCase()) return false;
    // Инициалы вида «Л.Р.Х.» тоже считаем аббревиатурой.
    return true;
  }

  /// Помечает географическую привязку рядом со страной: «Великобритания, Лондон».
  void _markLocations(List<NameCandidate> candidates) {
    for (var index = 1; index < candidates.length; index++) {
      final previous = candidates[index - 1];
      final current = candidates[index];
      if (previous.kind != CandidateKind.country) continue;
      if (current.kind != CandidateKind.cyrillic) continue;
      if (current.depth != previous.depth) continue;
      final words = current.value.split(' ').where((w) => w.isNotEmpty).length;
      if (words > 2) continue;
      if (index != candidates.length - 1) continue;
      current.kind = CandidateKind.location;
      current.excludedReason = 'географическая привязка рядом со страной';
    }
  }

  // --------------------------------------------------------------------
  // 3. Страна (п. 6.1, шаг 3; правила 7-8)
  // --------------------------------------------------------------------

  String _selectCountry(List<NameCandidate> candidates, Set<String> notes) {
    final countryCandidates =
        candidates.where((c) => c.kind == CandidateKind.country).toList();
    if (countryCandidates.isEmpty) return '';
    countryCandidates.sort((a, b) {
      final byLength = b.length.compareTo(a.length);
      return byLength != 0 ? byLength : a.order.compareTo(b.order);
    });
    final selected = countryCandidates.first;
    for (final other in countryCandidates.skip(1)) {
      other.excludedReason = 'страна уже определена';
    }
    return countries.countryValue(selected.value) ?? selected.value;
  }

  // --------------------------------------------------------------------
  // 4. Выбор итоговых наименований (правила 4, 5, 6, 10, 11)
  // --------------------------------------------------------------------

  String _selectName(
    List<NameCandidate> candidates,
    CandidateKind kind,
    CandidateKind oppositeKind,
    Set<String> notes,
  ) {
    var pool = candidates.where((c) => c.kind == kind).toList();
    if (pool.isEmpty) {
      return _fallbackToAbbreviation(candidates, kind, notes);
    }

    final opposite = candidates.where((c) => c.kind == oppositeKind).toList();

    // Правило 4 + 11: дедупликация подстрок и почти-дублей.
    pool = _dedupe(pool, notes);

    // Р-8: если есть новое наименование после переименования — оно целевое.
    final renamedCandidates = pool.where((c) => c.renamed).toList();
    if (renamedCandidates.isNotEmpty) {
      for (final candidate in pool) {
        if (!candidate.renamed) {
          candidate.excludedReason = 'наименование до переименования';
        }
      }
      pool = renamedCandidates;
      notes.add(ParseNote.renamed);
    }

    // Правила 5 и 6: транслит/транскрипция при наличии «родного» варианта.
    if (pool.length > 1 || opposite.isNotEmpty) {
      final translitMatches = <NameCandidate>[];
      final normal = <NameCandidate>[];
      for (final candidate in pool) {
        if (_isTranscriptionOfAny(candidate, opposite)) {
          translitMatches.add(candidate);
        } else {
          normal.add(candidate);
        }
      }
      if (translitMatches.isNotEmpty && normal.isNotEmpty) {
        for (final candidate in translitMatches) {
          candidate.excludedReason = kind == CandidateKind.latin
              ? 'транслитерация русского наименования (правило 5)'
              : 'транскрипция иностранного наименования (правило 6)';
        }
        notes.add(kind == CandidateKind.latin
            ? ParseNote.translitDropped
            : ParseNote.transcriptionDropped);
        pool = normal;
      } else if (translitMatches.isNotEmpty && normal.isEmpty) {
        notes.add(kind == CandidateKind.latin
            ? ParseNote.translitKept
            : ParseNote.transcriptionKept);
      }
    }

    if (pool.isEmpty) return _fallbackToAbbreviation(candidates, kind, notes);

    // Правило 11: самое длинное наименование.
    pool.sort((a, b) {
      final byLength = b.length.compareTo(a.length);
      return byLength != 0 ? byLength : a.order.compareTo(b.order);
    });
    final best = pool.first;
    final rivals = pool
        .skip(1)
        .where((c) => c.length == best.length && comparisonKey(c.value) != comparisonKey(best.value))
        .toList();
    if (rivals.isNotEmpty) notes.add(ParseNote.ambiguousLength);
    for (final candidate in pool.skip(1)) {
      candidate.excludedReason ??= 'выбрано более длинное наименование';
    }
    return best.value;
  }

  /// Если после исключений в классе не осталось ничего, кроме аббревиатуры,
  /// переносим её (иначе поле осталось бы пустым) и помечаем `review`.
  String _fallbackToAbbreviation(
    List<NameCandidate> candidates,
    CandidateKind kind,
    Set<String> notes,
  ) {
    final wantedScript =
        kind == CandidateKind.cyrillic ? NameScript.cyrillic : NameScript.latin;
    final abbreviations = candidates
        .where((c) =>
            c.kind == CandidateKind.abbreviation && c.script == wantedScript)
        .toList();
    if (abbreviations.isEmpty) return '';
    final hasOtherName = candidates.any((c) =>
        (c.kind == CandidateKind.cyrillic || c.kind == CandidateKind.latin) &&
        c.script == wantedScript);
    if (hasOtherName) return '';
    abbreviations.sort((a, b) => b.length.compareTo(a.length));
    notes.add(ParseNote.ambiguousLength);
    return abbreviations.first.value;
  }

  /// Правило 4 + 11: убираем кандидатов, являющихся подстрокой более длинного
  /// кандидата того же класса, и почти полные дубли.
  List<NameCandidate> _dedupe(
    List<NameCandidate> pool,
    Set<String> notes,
  ) {
    final sorted = [...pool]..sort((a, b) => b.length.compareTo(a.length));
    final kept = <NameCandidate>[];
    for (final candidate in sorted) {
      var duplicate = false;
      for (final other in kept) {
        if (isSubstringOf(candidate.value, other.value) ||
            similarity(comparisonKey(candidate.value),
                    comparisonKey(other.value)) >=
                config.duplicateSimilarityThreshold) {
          duplicate = true;
          candidate.excludedReason =
              'дубль более длинного наименования: "${other.value}"';
          notes.add(ParseNote.duplicateDropped);
          break;
        }
      }
      if (!duplicate) kept.add(candidate);
    }
    kept.sort((a, b) => a.order.compareTo(b.order));
    return kept;
  }

  /// Является ли кандидат транслитом/транскрипцией одного из кандидатов
  /// противоположного алфавита.
  bool _isTranscriptionOfAny(
    NameCandidate candidate,
    List<NameCandidate> opposite,
  ) {
    for (final other in opposite) {
      if (translitSimilarity(candidate.value, other.value) >=
          config.translitSimilarityThreshold) {
        return true;
      }
    }
    if (candidate.script == NameScript.latin &&
        opposite.isNotEmpty &&
        looksLikeRussianTranslit(candidate.value)) {
      return true;
    }
    return false;
  }
}
