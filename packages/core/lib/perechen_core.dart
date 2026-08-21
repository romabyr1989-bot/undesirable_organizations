/// Ядро сервиса обработки перечня «нежелательных организаций» (272-ФЗ).
///
/// Пакет не зависит от Flutter и не выполняет сетевых вызовов: он читает
/// xlsx-байты, разбирает наименования по правилам п. 6 ТЗ, формирует целевые
/// записи и байты целевого CSV, а также считает diff версий.
library;

export 'src/config/core_config.dart';
export 'src/csv/cp1251.dart';
export 'src/csv/csv_writer.dart';
export 'src/diff/version_differ.dart';
export 'src/mapping/exclusion_policy.dart';
export 'src/mapping/record_mapper.dart';
export 'src/models/correction.dart';
export 'src/models/parsed.dart';
export 'src/models/record.dart';
export 'src/models/source.dart';
export 'src/models/version.dart';
export 'src/names/countries.dart';
export 'src/names/name_parser.dart';
export 'src/names/script.dart';
export 'src/names/translit.dart';
export 'src/pipeline.dart';
export 'src/util/org_key.dart';
export 'src/util/ru_date.dart';
export 'src/util/text.dart';
export 'src/xlsx/source_parser.dart';
export 'src/xlsx/xlsx_reader.dart';
