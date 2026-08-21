/// Общие фикстуры для тестов ядра.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:perechen_core/perechen_core.dart';

/// Путь к каталогу эталонных файлов (`/reference`).
final referenceDir = Directory('../../reference');

/// Справочник стран из `assets/countries_ru.txt`.
CountryRegistry loadCountries({bool normalize = false}) => CountryRegistry.parse(
      File('assets/countries_ru.txt').readAsStringSync(),
      normalize: normalize,
    );

/// Эталонный первоисточник.
Uint8List loadReferenceXlsx() =>
    File('${referenceDir.path}/export.xlsx').readAsBytesSync();

/// Эталонный целевой CSV (в байтах, cp1251).
Uint8List loadReferenceCsv() => File(
      '${referenceDir.path}/perechen_organizatsij_272_FZ_2025_03_03.csv',
    ).readAsBytesSync();

/// Парсер наименований с эталонным справочником стран.
NameParser buildNameParser({CoreConfig config = const CoreConfig()}) =>
    NameParser(countries: loadCountries(), config: config);

/// Конвейер с эталонным справочником стран.
PerechenPipeline buildPipeline({CoreConfig config = const CoreConfig()}) =>
    PerechenPipeline(countries: loadCountries(), config: config);

/// Строка первоисточника для тестов.
SourceRow sourceRow({
  int rowNum = 4,
  String ordinal = '1',
  String inclusionDate = '29.07.2015',
  String inclusionNumber = '1076-р',
  String gpDecisionDate = '28.07.2015',
  String rawName = 'Test organization (Тестовая организация) (США)',
  String publicationDate = '',
  String exclusionDate = '',
  String exclusionNumber = '',
  String gpCancelDate = '',
  String status = 'Включена',
}) =>
    SourceRow(rowNum: rowNum, cells: [
      ordinal,
      inclusionDate,
      inclusionNumber,
      gpDecisionDate,
      rawName,
      publicationDate,
      exclusionDate,
      exclusionNumber,
      gpCancelDate,
      status,
    ]);
