/// Ключ записи, стабильный между версиями файла (FR-3).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/source.dart';
import 'ru_date.dart';
import 'text.dart';

/// `{номер распоряжения о включении}__{дата включения в ISO}`,
/// например `1076-р__2015-07-29`.
///
/// При пустом номере — fallback на SHA-1 нормализованной сырой строки
/// наименования (префикс `name-`).
String orgKeyOf(SourceRow row) {
  final number = normalizeSpaces(row.inclusionNumber);
  final date = parseRuDate(row.inclusionDate);
  if (number.isNotEmpty && date != null) {
    return '${number}__${formatIsoDate(date)}';
  }
  if (number.isNotEmpty) {
    final rawDate = normalizeSpaces(row.inclusionDate);
    return rawDate.isEmpty ? number : '${number}__$rawDate';
  }
  final digest = sha1.convert(utf8.encode(comparisonKey(row.rawName)));
  return 'name-$digest';
}
