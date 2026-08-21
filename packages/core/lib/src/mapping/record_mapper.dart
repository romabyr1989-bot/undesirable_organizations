/// Мэппинг «первоисточник → целевой файл» (п. 5 ТЗ).
library;

import '../config/core_config.dart';
import '../models/parsed.dart';
import '../models/record.dart';
import '../models/source.dart';
import '../names/name_parser.dart';
import '../util/org_key.dart';
import '../util/text.dart';
import 'exclusion_policy.dart';

class RecordMapper {
  const RecordMapper({
    required this.nameParser,
    this.config = const CoreConfig(),
    this.exclusionPolicy = const ExclusionPolicy(),
  });

  final NameParser nameParser;
  final CoreConfig config;
  final ExclusionPolicy exclusionPolicy;

  /// Собирает целевую запись из строки первоисточника.
  ParsedRecord map(SourceRow row) {
    final parsedName = nameParser.parse(row.rawName);

    final values = <RecordField, String>{
      RecordField.targetNo: _clean(row.ordinal),
      RecordField.inclOrder:
          orderRequisites(row.inclusionNumber, row.inclusionDate),
      RecordField.gpDecision: gpRequisites(row.gpDecisionDate),
      RecordField.nameRus: _clean(parsedName.nameRus),
      RecordField.nameAdd: _clean(parsedName.nameAdd),
      RecordField.country: _clean(parsedName.country),
      RecordField.exclOrder: exclusionPolicy.shouldFillExclusionColumns(row)
          ? orderRequisites(row.exclusionNumber, row.exclusionDate)
          : '',
      RecordField.gpCancel: exclusionPolicy.shouldFillExclusionColumns(row)
          ? gpRequisites(row.gpCancelDate)
          : '',
    };

    return ParsedRecord(
      orgKey: orgKeyOf(row),
      rowNum: row.rowNum,
      values: values,
      confidence: parsedName.confidence,
      notes: parsedName.notes,
      sourceRow: row,
      parsedName: parsedName,
    );
  }

  /// `№ {номер} от {дата}` (колонки 2 и 7 целевого файла).
  String orderRequisites(String number, String date) {
    final cleanNumber = normalizeSpaces(number);
    final cleanDate = normalizeSpaces(date);
    if (cleanNumber.isEmpty && cleanDate.isEmpty) return '';
    if (cleanNumber.isEmpty) return 'от $cleanDate';
    if (cleanDate.isEmpty) return '№ $cleanNumber';
    return '№ $cleanNumber от $cleanDate';
  }

  /// Реквизиты решения Генпрокуратуры (колонки 3 и 8 целевого файла).
  ///
  /// По умолчанию (Р-2) — только дата: номера решения в первоисточнике нет.
  String gpRequisites(String date, {String number = ''}) {
    final cleanDate = normalizeSpaces(date);
    final cleanNumber = normalizeSpaces(number);
    if (cleanDate.isEmpty && cleanNumber.isEmpty) return '';
    switch (config.gpDecisionFormat) {
      case GpDecisionFormat.withNumber:
        if (cleanNumber.isEmpty) return 'от $cleanDate';
        if (cleanDate.isEmpty) return '№ $cleanNumber';
        return '№ $cleanNumber от $cleanDate';
      case GpDecisionFormat.dateOnly:
        return cleanDate.isEmpty ? '' : 'от $cleanDate';
    }
  }

  String _clean(String value) {
    var result = value;
    if (config.collapseInnerSpaces) {
      result = normalizeSpaces(result);
    } else if (config.trimValues) {
      result = normalizeSpaces(result, collapse: false);
    }
    return result;
  }
}

/// Применяет ручные правки к записям (FR-4: приоритет человека).
class CorrectionApplier {
  const CorrectionApplier();

  /// Возвращает копию записи с применёнными правками.
  ///
  /// Правка применяется, если её `source_name_hash` совпадает с хэшем текущего
  /// сырого наименования. Иначе правка считается протухшей: применяется
  /// автоматический разбор, запись получает `confidence = review`.
  ParsedRecord apply(ParsedRecord record, List<CorrectionInput> corrections) {
    if (corrections.isEmpty) return record;

    final currentHash = record.sourceRow.sourceNameHash;
    final values = Map<RecordField, String>.from(record.values);
    final edited = <RecordField>{};
    final stale = <StaleCorrection>[];
    final notes = [...record.notes];

    for (final correction in corrections) {
      if (correction.sourceNameHash == currentHash) {
        values[correction.field] = correction.value;
        edited.add(correction.field);
      } else {
        stale.add(StaleCorrection(
          field: correction.field,
          value: correction.value,
          author: correction.author,
          createdAt: correction.createdAt,
        ));
      }
    }

    if (stale.isNotEmpty && !notes.contains('stale_correction')) {
      notes.add('stale_correction');
    }

    return record.copyWith(
      values: values,
      editedFields: edited,
      staleCorrections: stale,
      notes: notes,
      confidence:
          stale.isNotEmpty ? Confidence.review : record.confidence,
    );
  }
}

/// Минимальное представление правки, нужное ядру.
class CorrectionInput {
  const CorrectionInput({
    required this.field,
    required this.value,
    required this.sourceNameHash,
    required this.author,
    required this.createdAt,
  });

  final RecordField field;
  final String value;
  final String sourceNameHash;
  final String author;
  final DateTime createdAt;
}
