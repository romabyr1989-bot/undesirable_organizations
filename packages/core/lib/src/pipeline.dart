/// Конвейер обработки версии перечня: xlsx -> записи -> diff -> CSV (п. 7 ТЗ).
library;

import 'dart:typed_data';

import 'config/core_config.dart';
import 'csv/csv_writer.dart';
import 'diff/version_differ.dart';
import 'mapping/exclusion_policy.dart';
import 'mapping/record_mapper.dart';
import 'models/record.dart';
import 'models/source.dart';
import 'models/version.dart';
import 'names/countries.dart';
import 'names/name_parser.dart';
import 'xlsx/source_parser.dart';

/// Результат прогона конвейера по одному файлу-первоисточнику.
class PipelineResult {
  PipelineResult({
    required this.document,
    required this.records,
    required this.excluded,
    required this.counters,
    required this.warnings,
  });

  final SourceDocument document;

  /// Записи текущей версии (в порядке первоисточника).
  final List<ParsedRecord> records;

  /// Записи, исчезнувшие из первоисточника.
  final List<ParsedRecord> excluded;

  final VersionCounters counters;

  /// Некритичные замечания разбора.
  final List<String> warnings;

  DateTime get actualityDate => document.actualityDate;
}

/// Конвейер ядра. Не выполняет ввод-вывод: файлы читает и пишет сервер.
class PerechenPipeline {
  PerechenPipeline({
    required CountryRegistry countries,
    this.config = const CoreConfig(),
    this.exclusionPolicy = const ExclusionPolicy(),
  })  : _mapper = RecordMapper(
          nameParser: NameParser(countries: countries, config: config),
          config: config,
          exclusionPolicy: exclusionPolicy,
        ),
        _sourceParser = const SourceParser();

  final CoreConfig config;
  final ExclusionPolicy exclusionPolicy;
  final RecordMapper _mapper;
  final SourceParser _sourceParser;

  RecordMapper get mapper => _mapper;

  /// Разбирает файл и собирает записи версии.
  ///
  /// [previousRows] — строки предыдущей версии (для diff),
  /// [corrections] — сохранённые ручные правки по `org_key` (FR-4).
  PipelineResult run({
    required Uint8List xlsxBytes,
    List<SourceRow> previousRows = const [],
    Map<String, List<CorrectionInput>> corrections = const {},
  }) {
    final parsed = _sourceParser.parseBytes(xlsxBytes);
    return runOnDocument(
      parsed.document,
      previousRows: previousRows,
      corrections: corrections,
      warnings: parsed.warnings,
    );
  }

  /// То же самое для уже разобранного документа (перерасбор из БД).
  PipelineResult runOnDocument(
    SourceDocument document, {
    List<SourceRow> previousRows = const [],
    Map<String, List<CorrectionInput>> corrections = const {},
    List<String> warnings = const [],
  }) {
    const applier = CorrectionApplier();
    final records = <ParsedRecord>[];
    for (final row in document.rows) {
      final mapped = _mapper.map(row);
      final rowCorrections = corrections[mapped.orgKey] ?? const [];
      records.add(applier.apply(mapped, rowCorrections));
    }

    final diff = VersionDiffer(mapper: _mapper).diff(
      currentRecords: records,
      previousRows: previousRows,
    );

    return PipelineResult(
      document: document,
      records: diff.records,
      excluded: diff.excluded,
      counters: diff.counters,
      warnings: warnings,
    );
  }

  /// Собирает целевой CSV по результату прогона.
  CsvBuildResult buildCsv(PipelineResult result) => CsvWriter(config: config)
      .build(actualityDate: result.actualityDate, records: result.records);
}
