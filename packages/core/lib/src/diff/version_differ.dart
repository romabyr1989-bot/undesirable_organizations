/// Сравнение версий перечня (FR-3).
library;

import '../mapping/record_mapper.dart';
import '../models/parsed.dart';
import '../models/record.dart';
import '../models/source.dart';
import '../models/version.dart';
import '../util/org_key.dart';

/// Результат сравнения новой версии с предыдущей.
class DiffResult {
  DiffResult({
    required this.records,
    required this.excluded,
    required this.counters,
  });

  /// Записи текущей версии с проставленными флагами `isNew` / `isChanged`.
  final List<ParsedRecord> records;

  /// Записи, исчезнувшие из первоисточника (в CSV не попадают, Р-1).
  final List<ParsedRecord> excluded;

  final VersionCounters counters;
}

class VersionDiffer {
  const VersionDiffer({required this.mapper});

  final RecordMapper mapper;

  /// Сравнивает записи текущей версии со строками предыдущей по `org_key`.
  DiffResult diff({
    required List<ParsedRecord> currentRecords,
    required List<SourceRow> previousRows,
  }) {
    final previousByKey = <String, SourceRow>{};
    for (final row in previousRows) {
      previousByKey[orgKeyOf(row)] = row;
    }

    final records = <ParsedRecord>[];
    final seenKeys = <String>{};
    var added = 0;
    var changed = 0;
    var review = 0;
    var edited = 0;

    for (final record in currentRecords) {
      seenKeys.add(record.orgKey);
      final previous = previousByKey[record.orgKey];
      final isNew = previousRows.isNotEmpty && previous == null;
      final isChanged = previous != null &&
          previous.contentHash != record.sourceRow.contentHash;
      final updated = record.copyWith(
        isNew: isNew,
        isChanged: isChanged,
        previousRawName:
            isChanged && previous.rawName != record.sourceRow.rawName
                ? previous.rawName
                : null,
      );
      if (isNew) added++;
      if (isChanged) changed++;
      if (updated.confidence == Confidence.review) review++;
      if (updated.editedFields.isNotEmpty) edited++;
      records.add(updated);
    }

    final excluded = <ParsedRecord>[];
    for (final entry in previousByKey.entries) {
      if (seenKeys.contains(entry.key)) continue;
      excluded.add(mapper.map(entry.value).copyWith(isExcluded: true));
    }

    return DiffResult(
      records: records,
      excluded: excluded,
      counters: VersionCounters(
        total: records.length,
        added: added,
        excluded: excluded.length,
        changed: changed,
        review: review,
        edited: edited,
      ),
    );
  }
}
