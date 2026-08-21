/// Кодирование строк в Windows-1251 с транслитерацией непредставимых
/// символов (п. 4 ТЗ, решение Р-6).
library;

import 'dart:typed_data';

import 'cp1251_tables.dart';

/// Замена одного символа при кодировании.
class Cp1251Replacement {
  const Cp1251Replacement({
    required this.original,
    required this.replacement,
    required this.context,
  });

  /// Исходный символ.
  final String original;

  /// Чем заменён.
  final String replacement;

  /// Значение, в котором произошла замена (для лога/письма).
  final String context;

  bool get isLossy => replacement == Cp1251Encoder.unknownReplacement;

  @override
  String toString() => 'заменён символ "$original" -> "$replacement" '
      'в значении "$context"';
}

/// Результат кодирования.
class Cp1251EncodeResult {
  Cp1251EncodeResult({required this.bytes, required this.replacements});

  final Uint8List bytes;
  final List<Cp1251Replacement> replacements;
}

/// Кодировщик cp1251.
class Cp1251Encoder {
  const Cp1251Encoder();

  /// Символ, которым заменяется всё, для чего не нашлось аналога.
  static const unknownReplacement = '?';

  /// Кодирует строку, при необходимости транслитерируя символы.
  Cp1251EncodeResult encode(String text, {String context = ''}) {
    final bytes = BytesBuilder();
    final replacements = <Cp1251Replacement>[];
    for (final rune in text.runes) {
      final direct = cp1251Table[rune];
      if (direct != null) {
        bytes.addByte(direct);
        continue;
      }
      final char = String.fromCharCode(rune);
      final analogue = translitTable[char];
      if (analogue != null) {
        var wrote = false;
        for (final analogueRune in analogue.runes) {
          final code = cp1251Table[analogueRune];
          if (code != null) {
            bytes.addByte(code);
            wrote = true;
          }
        }
        replacements.add(Cp1251Replacement(
          original: char,
          replacement: wrote ? analogue : unknownReplacement,
          context: context,
        ));
        if (!wrote) bytes.addByte(cp1251Table[unknownReplacement.codeUnitAt(0)]!);
        continue;
      }
      bytes.addByte(cp1251Table[unknownReplacement.codeUnitAt(0)]!);
      replacements.add(Cp1251Replacement(
        original: char,
        replacement: unknownReplacement,
        context: context,
      ));
    }
    return Cp1251EncodeResult(
      bytes: bytes.toBytes(),
      replacements: replacements,
    );
  }

  /// Можно ли закодировать строку без замен.
  bool isRepresentable(String text) =>
      text.runes.every(cp1251Table.containsKey);

  /// Декодирование cp1251 -> строка (нужно тестам и предпросмотру).
  String decode(List<int> bytes) {
    final reverse = <int, int>{
      for (final entry in cp1251Table.entries) entry.value: entry.key,
    };
    final buffer = StringBuffer();
    for (final byte in bytes) {
      final code = reverse[byte];
      if (code != null) buffer.writeCharCode(code);
    }
    return buffer.toString();
  }
}
