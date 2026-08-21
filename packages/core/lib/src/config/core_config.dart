/// Точки изменения поведения ядра (раздел 14 ТЗ: решения по умолчанию).
///
/// Каждое решение из таблицы Р-1..Р-8 вынесено сюда либо в отдельную
/// стратегию, чтобы смена поведения стоила одного изменения в одном месте
/// и покрывалась параметризованным тестом.
library;

/// Формат реквизитов решения Генпрокуратуры (Р-2).
enum GpDecisionFormat {
  /// `от 28.07.2015` — по умолчанию: номера решения в первоисточнике нет.
  dateOnly('date_only'),

  /// `№ {номер} от {дата}` — если номер когда-нибудь появится в источнике.
  withNumber('with_number');

  const GpDecisionFormat(this.id);

  final String id;

  static GpDecisionFormat byId(String? id) =>
      id == withNumber.id ? withNumber : dateOnly;
}

/// Режим экранирования значений CSV (Р-6).
enum CsvQuoteMode {
  /// Экранировать только при наличии `;`, `"` или перевода строки (+warning).
  minimal('minimal'),

  /// Экранировать все значения (на случай смены требований загрузчика CDI).
  always('always');

  const CsvQuoteMode(this.id);

  final String id;

  static CsvQuoteMode byId(String? id) => id == always.id ? always : minimal;
}

/// Конфигурация ядра: разбор наименований, мэппинг, генерация CSV.
class CoreConfig {
  const CoreConfig({
    this.gpDecisionFormat = GpDecisionFormat.dateOnly,
    this.countryNormalize = false,
    this.csvQuoteMode = CsvQuoteMode.minimal,
    this.trimValues = true,
    this.collapseInnerSpaces = true,
    this.abbreviationMaxLetters = 6,
    this.translitSimilarityThreshold = 0.62,
    this.duplicateSimilarityThreshold = 0.92,
  });

  /// Р-2: формат реквизитов решения Генпрокуратуры.
  final GpDecisionFormat gpDecisionFormat;

  /// Р-3: приводить ли страну к каноническому написанию справочника.
  /// По умолчанию false — страна переносится «как есть» (правило 8).
  final bool countryNormalize;

  /// Р-6: режим экранирования CSV.
  final CsvQuoteMode csvQuoteMode;

  /// Р-6: обрезать висящие пробелы значений (артефакт эталона).
  final bool trimValues;

  /// Р-6: схлопывать двойные пробелы внутри значений — в первоисточнике они
  /// появляются из-за переносов строк исходного документа.
  final bool collapseInnerSpaces;

  /// Правило 9: максимальная длина «слова из заглавных букв», которое
  /// считается аббревиатурой и не переносится.
  final int abbreviationMaxLetters;

  /// Правила 5-6: порог похожести транслитерации/транскрипции.
  final double translitSimilarityThreshold;

  /// Правило 4/11: порог, при котором два кандидата считаются дублями.
  final double duplicateSimilarityThreshold;

  CoreConfig copyWith({
    GpDecisionFormat? gpDecisionFormat,
    bool? countryNormalize,
    CsvQuoteMode? csvQuoteMode,
    bool? trimValues,
    bool? collapseInnerSpaces,
    int? abbreviationMaxLetters,
    double? translitSimilarityThreshold,
    double? duplicateSimilarityThreshold,
  }) =>
      CoreConfig(
        gpDecisionFormat: gpDecisionFormat ?? this.gpDecisionFormat,
        countryNormalize: countryNormalize ?? this.countryNormalize,
        csvQuoteMode: csvQuoteMode ?? this.csvQuoteMode,
        trimValues: trimValues ?? this.trimValues,
        collapseInnerSpaces: collapseInnerSpaces ?? this.collapseInnerSpaces,
        abbreviationMaxLetters:
            abbreviationMaxLetters ?? this.abbreviationMaxLetters,
        translitSimilarityThreshold:
            translitSimilarityThreshold ?? this.translitSimilarityThreshold,
        duplicateSimilarityThreshold:
            duplicateSimilarityThreshold ?? this.duplicateSimilarityThreshold,
      );
}
