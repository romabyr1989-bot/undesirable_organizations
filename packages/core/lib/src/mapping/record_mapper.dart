/// Мэппинг «первоисточник → целевой файл» (п. 5 ТЗ).
library;

import '../config/core_config.dart';
import '../csv/cp1251.dart';
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
    // В первоисточнике попадаются слова, где буква набрана не тем алфавитом
    // («Управлiння» с латинской «i»). Приводим к одному алфавиту до разбора:
    // иначе и разбор делит слово на фрагменты по алфавитам, и в целевом файле
    // такое слово не находится поиском.
    final rawName = fixHomoglyphs(row.rawName);
    final homoglyphsFixed = rawName != row.rawName;
    final parsedName = nameParser.parse(rawName);

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

    // Символ, которого нет в cp1251 и которому не нашлось аналога, ушёл бы в
    // целевой файл вопросительным знаком. Такое встречается в самом
    // первоисточнике (следы кривой конвертации на стороне Минюста), поэтому
    // запись отправляется человеку на проверку до выгрузки.
    final lossy = values.values.any(_hasUnrepresentableChars);
    final extraNotes = <String>{
      if (lossy) ParseNote.charNotInCp1251,
      if (homoglyphsFixed) ParseNote.homoglyphFixed,
    };
    final notes = extraNotes.isEmpty
        ? parsedName.notes
        : (<String>{...parsedName.notes, ...extraNotes}.toList()..sort());

    return ParsedRecord(
      orgKey: orgKeyOf(row),
      rowNum: row.rowNum,
      values: values,
      confidence: lossy ? Confidence.review : parsedName.confidence,
      notes: notes,
      sourceRow: row,
      parsedName: parsedName,
    );
  }

  bool _hasUnrepresentableChars(String value) =>
      hasUnrepresentableChars(value);

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

const _cp1251Encoder = Cp1251Encoder();

/// Есть ли в значении символ, которому не нашлось аналога в cp1251: в целевом
/// файле он превратится в «?».
bool hasUnrepresentableChars(String value) => _cp1251Encoder
    .encode(value)
    .replacements
    .any((replacement) => replacement.isLossy);

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

    // Пометку про непереносимый символ считаем по итоговым значениям: если
    // ответственный поправил наименование, причина исчезла — незачем держать
    // запись на проверке.
    final lossy = values.values.any(hasUnrepresentableChars);
    notes.remove(ParseNote.charNotInCp1251);
    if (lossy) notes.add(ParseNote.charNotInCp1251);
    notes.sort();

    return record.copyWith(
      values: values,
      editedFields: edited,
      staleCorrections: stale,
      notes: notes,
      confidence: stale.isNotEmpty || lossy
          ? Confidence.review
          // Базовая уверенность — от разбора: пометка про символ могла быть
          // единственной причиной проверки. Разбора под рукой нет только у
          // записей, поднятых из БД, — там оставляем как было.
          : record.parsedName?.confidence ?? record.confidence,
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
