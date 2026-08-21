/// Определение алфавита (скрипта) строки: кириллица / латиница / прочее.
library;

/// Алфавит, к которому отнесён фрагмент наименования.
enum NameScript {
  /// Преимущественно кириллица.
  cyrillic,

  /// Преимущественно латиница (включая диакритику: ä, č, ș, ğ, ł и т. п.).
  latin,

  /// Буквы вне кириллицы и латиницы (греческий, иврит, CJK и т. д.).
  other,

  /// Букв нет вовсе (только цифры/знаки).
  none,
}

/// Счётчик букв по алфавитам.
class ScriptStats {
  const ScriptStats({
    required this.cyrillic,
    required this.latin,
    required this.other,
  });

  final int cyrillic;
  final int latin;
  final int other;

  int get totalLetters => cyrillic + latin + other;

  /// Доля букв доминирующего алфавита (0..1).
  double get dominance {
    if (totalLetters == 0) return 0;
    final maxCount = [cyrillic, latin, other]
        .reduce((value, element) => value > element ? value : element);
    return maxCount / totalLetters;
  }

  /// Смешанный ли фрагмент: значимое присутствие двух алфавитов сразу
  /// (напр. «КрымSOS», «MIПЛ»).
  bool get isMixed {
    if (totalLetters == 0) return false;
    var significant = 0;
    for (final count in [cyrillic, latin, other]) {
      if (count / totalLetters >= 0.2) significant++;
    }
    return significant > 1;
  }

  NameScript get script {
    if (totalLetters == 0) return NameScript.none;
    if (other > cyrillic && other > latin) return NameScript.other;
    if (cyrillic == 0 && latin == 0) return NameScript.other;
    return cyrillic >= latin ? NameScript.cyrillic : NameScript.latin;
  }
}

bool _isCyrillicLetter(int code) =>
    (code >= 0x0400 && code <= 0x04FF) || (code >= 0x0500 && code <= 0x052F);

bool _isLatinLetter(int code) =>
    (code >= 0x0041 && code <= 0x005A) ||
    (code >= 0x0061 && code <= 0x007A) ||
    (code >= 0x00C0 && code <= 0x024F) ||
    (code >= 0x1E00 && code <= 0x1EFF);

final _letterPattern = RegExp(r'\p{L}', unicode: true);

/// Считает буквы по алфавитам.
ScriptStats scriptStats(String value) {
  var cyrillic = 0;
  var latin = 0;
  var other = 0;
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    if (!_letterPattern.hasMatch(ch)) continue;
    if (_isCyrillicLetter(rune)) {
      cyrillic++;
    } else if (_isLatinLetter(rune)) {
      latin++;
    } else {
      other++;
    }
  }
  return ScriptStats(cyrillic: cyrillic, latin: latin, other: other);
}

/// Алфавит строки по большинству букв.
NameScript detectScript(String value) => scriptStats(value).script;

/// Содержит ли строка хотя бы одну букву.
bool hasLetters(String value) => scriptStats(value).totalLetters > 0;
