/// Политика отражения исключения из перечня (решение Р-1).
///
/// По умолчанию: в целевой CSV попадают только строки текущего
/// первоисточника. Если у строки заполнены колонки исключения (7-9) или
/// статус отличается от «Включена» — заполняются целевые колонки 7-8.
/// Исчезнувшие строки в CSV не добавляются, факт фиксируется в БД и письме.
library;

import '../models/source.dart';
import '../util/text.dart';

class ExclusionPolicy {
  const ExclusionPolicy({
    this.includedStatus = 'Включена',
    this.keepDisappearedRowsInCsv = false,
  });

  /// Статус «строка действует».
  final String includedStatus;

  /// Добавлять ли в CSV записи, исчезнувшие из первоисточника (Р-1: нет).
  final bool keepDisappearedRowsInCsv;

  /// Есть ли в строке признаки исключения из перечня.
  bool isExcludedInSource(SourceRow row) {
    final hasExclusionColumns = row.exclusionDate.trim().isNotEmpty ||
        row.exclusionNumber.trim().isNotEmpty ||
        row.gpCancelDate.trim().isNotEmpty;
    if (hasExclusionColumns) return true;
    final status = normalizeSpaces(row.status);
    if (status.isEmpty) return false;
    return comparisonKey(status) != comparisonKey(includedStatus);
  }

  /// Нужно ли заполнять целевые колонки 7-8 (реквизиты исключения).
  bool shouldFillExclusionColumns(SourceRow row) => isExcludedInSource(row);
}
