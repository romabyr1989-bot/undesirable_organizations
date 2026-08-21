import 'dart:io';

import 'package:perechen_core/perechen_core.dart';

void main(List<String> args) {
  final countries = CountryRegistry.parse(
      File('assets/countries_ru.txt').readAsStringSync());
  final pipeline = PerechenPipeline(countries: countries);
  final result = pipeline.run(
      xlsxBytes: File('../../reference/export.xlsx').readAsBytesSync());

  final counters = result.counters;
  stdout.writeln('total=${counters.total} review=${counters.review}');
  var noCountry = 0;
  var noRus = 0;
  var noAdd = 0;
  final noteCounts = <String, int>{};
  for (final r in result.records) {
    if (r.value(RecordField.country).isEmpty) noCountry++;
    if (r.value(RecordField.nameRus).isEmpty) noRus++;
    if (r.value(RecordField.nameAdd).isEmpty) noAdd++;
    for (final note in r.notes) {
      noteCounts[note] = (noteCounts[note] ?? 0) + 1;
    }
  }
  stdout.writeln('noCountry=$noCountry noRus=$noRus noAdd=$noAdd');
  final sortedNotes = noteCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sortedNotes) {
    stdout.writeln('  ${e.key}: ${e.value}');
  }

  final mode = args.isEmpty ? 'review' : args.first;
  for (final r in result.records) {
    final show = switch (mode) {
      'all' => true,
      'review' => r.confidence == Confidence.review,
      'nocountry' => r.value(RecordField.country).isEmpty,
      'norus' => r.value(RecordField.nameRus).isEmpty,
      _ => false,
    };
    if (!show) continue;
    stdout.writeln('--- #${r.value(RecordField.targetNo)} ${r.notes}');
    stdout.writeln('  RAW: ${r.sourceRow.rawName}');
    stdout.writeln('  RUS: ${r.value(RecordField.nameRus)}');
    stdout.writeln('  ADD: ${r.value(RecordField.nameAdd)}');
    stdout.writeln('  CNT: ${r.value(RecordField.country)}');
  }
}
