/// Конфигурация сервиса (п. 11 ТЗ).
///
/// Источники значений по приоритету: переменные окружения -> `config.yaml`
/// -> значения по умолчанию.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:perechen_core/perechen_core.dart';
import 'package:yaml/yaml.dart';

import '../util/app_paths.dart';

class SmtpConfig {
  const SmtpConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.from,
    required this.useSsl,
    required this.allowInsecure,
  });

  final String host;
  final int port;
  final String user;
  final String password;
  final String from;
  final bool useSsl;
  final bool allowInsecure;

  bool get isConfigured => host.isNotEmpty;
}

class AppConfig {
  const AppConfig({
    required this.minjustPageUrl,
    required this.minjustExportUrl,
    required this.exportLinkSelector,
    required this.userAgent,
    required this.downloadCron,
    required this.autoPublishCron,
    required this.timeZone,
    required this.cdiDropDir,
    required this.dataDir,
    required this.countriesFile,
    required this.caBundleFile,
    required this.seedFile,
    required this.smtp,
    required this.notifyEmails,
    required this.notifyOnNoChanges,
    required this.uiBaseUrl,
    required this.basicAuthUser,
    required this.basicAuthPassword,
    required this.httpTimeout,
    required this.httpRetries,
    required this.retryDelays,
    required this.unavailableEscalateDays,
    required this.host,
    required this.port,
    required this.uiDir,
    required this.core,
    required this.schedulerEnabled,
    this.logFile = '',
    this.logLevel = 'info',
    this.configFile = '',
  });

  /// Страница перечня на сайте Минюста.
  final String minjustPageUrl;

  /// Прямая ссылка на xlsx (если пусто — ссылка ищется на странице).
  final String minjustExportUrl;

  /// CSS-селектор ссылки на файл экспорта (Р-5).
  final String exportLinkSelector;

  final String userAgent;

  /// Расписание ежедневной проверки (МСК).
  final String downloadCron;

  /// Расписание авто-публикации неподтверждённых версий (МСК).
  final String autoPublishCron;

  /// Часовой пояс расписаний и дат.
  final String timeZone;

  /// Папка, из которой скрипт CDI забирает файл.
  final String cdiDropDir;

  /// Рабочая папка сервиса: `downloads/`, `published/`, `db`.
  final String dataDir;

  /// Файл справочника стран.
  final String countriesFile;

  /// Файл с дополнительными доверенными сертификатами (PEM).
  ///
  /// Подставляется к системному хранилищу, а не заменяет его. Пусто или файла
  /// нет — работает только системное хранилище.
  final String caBundleFile;

  /// Стартовый файл перечня из комплекта (xlsx).
  ///
  /// Загружается один раз, при первом запуске с пустой базой. Пусто или файла
  /// нет — сервис стартует с пустым списком и наполнит его первой проверкой.
  final String seedFile;

  final SmtpConfig smtp;
  final List<String> notifyEmails;
  final bool notifyOnNoChanges;

  /// Базовый URL UI для ссылок в письмах.
  final String uiBaseUrl;

  final String basicAuthUser;
  final String basicAuthPassword;

  final Duration httpTimeout;
  final int httpRetries;

  /// Задержки между попытками скачивания (по умолчанию 1, 5, 15 минут).
  final List<Duration> retryDelays;

  /// Через сколько суток недоступности слать письмо-эскалацию (Р-5).
  final int unavailableEscalateDays;

  final String host;
  final int port;

  /// Каталог со собранным Flutter Web (раздаётся сервером).
  final String uiDir;

  /// Настройки ядра (решения Р-2, Р-3, Р-6).
  final CoreConfig core;

  /// Включён ли планировщик (в тестах выключается).
  final bool schedulerEnabled;

  /// Файл журнала. Пусто — писать только в stdout: systemd и launchd
  /// перехватывают вывод сами, планировщик задач Windows — нет.
  final String logFile;

  /// Порог журналирования: debug | info | warning | error.
  final String logLevel;

  /// Фактически прочитанный `config.yaml` (пусто — только окружение).
  final String configFile;

  String get downloadsDir => p.join(dataDir, 'downloads');

  String get publishedDir => p.join(dataDir, 'published');

  String get databaseFile => p.join(dataDir, 'perechen.db');

  /// Ищет `config.yaml`: сначала явно указанный путь (`--config`,
  /// `CONFIG_FILE`), затем системный каталог службы и каталог установки.
  ///
  /// Явно указанный, но отсутствующий файл — ошибка: опечатка в юните службы
  /// не должна молча превращаться в конфигурацию по умолчанию.
  static String? resolveConfigPath({
    String? explicitPath,
    bool searchDefaults = true,
  }) {
    if (explicitPath != null && explicitPath.isNotEmpty) {
      if (!File(explicitPath).existsSync()) {
        throw StateError('файл конфигурации не найден: $explicitPath');
      }
      return explicitPath;
    }
    if (!searchDefaults) return null;
    for (final candidate in AppPaths.configCandidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Читает `config.yaml`, превращая отказ файловой системы и синтаксическую
  /// ошибку в сообщение для человека.
  ///
  /// На площадке этот файл правят вручную, и оба случая там обычны: права
  /// `640 root:perechen` (служба читает, а запущенный от себя `paths` — уже
  /// нет) и съехавшие отступы после правки. Без этого служба падала стеком
  /// вызовов Dart, по которому причина не видна.
  static Map<String, Object?> _readYaml(String path) {
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException catch (error) {
      final reason = error.osError?.message ?? error.message;
      throw StateError('нет доступа к $path ($reason)');
    }
    final Object? parsed;
    try {
      parsed = loadYaml(text);
    } on YamlException catch (error) {
      throw StateError('$path разобрать не удалось: ${error.message}');
    }
    return parsed is YamlMap ? Map<String, Object?>.from(parsed) : const {};
  }

  /// Читает конфигурацию из окружения и (необязательного) yaml-файла.
  ///
  /// Явно переданный [environment] отключает поиск `config.yaml` по системным
  /// путям: тесты не должны зависеть от файлов конкретной машины.
  static AppConfig load({
    Map<String, String>? environment,
    String? configPath,
  }) {
    final env = environment ?? Platform.environment;
    Map<String, Object?> yamlValues = const {};
    final path = resolveConfigPath(
      explicitPath: configPath ?? env['CONFIG_FILE'],
      searchDefaults: environment == null,
    );
    if (path != null) {
      yamlValues = _readYaml(path);
    }

    String read(String key, String fallback) {
      final fromEnv = env[key];
      if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
      final fromYaml = yamlValues[key];
      if (fromYaml != null) return '$fromYaml';
      return fallback;
    }

    int readInt(String key, int fallback) =>
        int.tryParse(read(key, '$fallback')) ?? fallback;

    bool readBool(String key, bool fallback) {
      final value = read(key, '$fallback').toLowerCase();
      return value == 'true' || value == '1' || value == 'yes';
    }

    List<String> readList(String key) => read(key, '')
        .split(RegExp('[,;]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final dataDir = read('DATA_DIR', AppPaths.defaultDataDir);

    return AppConfig(
      minjustPageUrl: read(
        'MINJUST_PAGE_URL',
        'https://minjust.gov.ru/ru/pages/perechen-inostrannyh-i-mezhdunarodnyh-'
            'organizacij-deyatelnost-kotoryh-priznana-nezhelatelnoj-na-'
            'territorii-rossijskoj-federacii/',
      ),
      minjustExportUrl: read('MINJUST_EXPORT_URL', ''),
      exportLinkSelector: read('EXPORT_LINK_SELECTOR', 'a[href*=".xlsx"]'),
      userAgent: read(
        'HTTP_USER_AGENT',
        'PerechenBot/1.0 (+corporate data integration service)',
      ),
      downloadCron: read('DOWNLOAD_CRON', '0 6 * * *'),
      autoPublishCron: read('AUTO_PUBLISH_CRON', '0 20 * * *'),
      timeZone: read('TZ', 'Europe/Moscow'),
      cdiDropDir: read('CDI_DROP_DIR', AppPaths.defaultCdiDropDir),
      dataDir: dataDir,
      countriesFile: read('COUNTRIES_FILE', AppPaths.defaultCountriesFile),
      caBundleFile: read('CA_BUNDLE_FILE', AppPaths.defaultCaBundleFile),
      seedFile: read('SEED_FILE', AppPaths.defaultSeedFile),
      smtp: SmtpConfig(
        host: read('SMTP_HOST', ''),
        port: readInt('SMTP_PORT', 25),
        user: read('SMTP_USER', ''),
        password: read('SMTP_PASS', ''),
        from: read('SMTP_FROM', 'perechen@localhost'),
        useSsl: readBool('SMTP_SSL', false),
        allowInsecure: readBool('SMTP_ALLOW_INSECURE', true),
      ),
      notifyEmails: readList('NOTIFY_EMAILS'),
      notifyOnNoChanges: readBool('NOTIFY_ON_NO_CHANGES', false),
      uiBaseUrl: read('UI_BASE_URL', 'http://localhost:8080'),
      basicAuthUser: read('BASIC_AUTH_USER', 'admin'),
      basicAuthPassword: read('BASIC_AUTH_PASS', 'admin'),
      httpTimeout: Duration(seconds: readInt('HTTP_TIMEOUT_SEC', 60)),
      httpRetries: readInt('RETRIES', 3),
      retryDelays: read('RETRY_DELAYS_MIN', '1,5,15')
          .split(',')
          .map((e) => Duration(minutes: int.tryParse(e.trim()) ?? 1))
          .toList(),
      unavailableEscalateDays: readInt('UNAVAILABLE_ESCALATE_DAYS', 3),
      host: read('HOST', '0.0.0.0'),
      port: readInt('PORT', 8080),
      uiDir: read('UI_DIR', AppPaths.defaultUiDir),
      core: CoreConfig(
        gpDecisionFormat:
            GpDecisionFormat.byId(read('GP_DECISION_FORMAT', 'date_only')),
        countryNormalize: readBool('COUNTRY_NORMALIZE', false),
        csvQuoteMode: CsvQuoteMode.byId(read('CSV_QUOTE_MODE', 'minimal')),
        trimValues: readBool('TRIM_VALUES', true),
        collapseInnerSpaces: readBool('COLLAPSE_INNER_SPACES', true),
      ),
      schedulerEnabled: readBool('SCHEDULER_ENABLED', true),
      logFile: read('LOG_FILE', AppPaths.logFileFor(dataDir)),
      logLevel: read('LOG_LEVEL', 'info'),
      configFile: path ?? '',
    );
  }

  AppConfig copyWith({
    String? minjustExportUrl,
    String? cdiDropDir,
    String? dataDir,
    String? countriesFile,
    String? caBundleFile,
    String? seedFile,
    List<String>? notifyEmails,
    bool? notifyOnNoChanges,
    int? port,
    bool? schedulerEnabled,
    List<Duration>? retryDelays,
    SmtpConfig? smtp,
    String? uiDir,
    String? logFile,
  }) =>
      AppConfig(
        minjustPageUrl: minjustPageUrl,
        minjustExportUrl: minjustExportUrl ?? this.minjustExportUrl,
        exportLinkSelector: exportLinkSelector,
        userAgent: userAgent,
        downloadCron: downloadCron,
        autoPublishCron: autoPublishCron,
        timeZone: timeZone,
        cdiDropDir: cdiDropDir ?? this.cdiDropDir,
        dataDir: dataDir ?? this.dataDir,
        countriesFile: countriesFile ?? this.countriesFile,
        caBundleFile: caBundleFile ?? this.caBundleFile,
        seedFile: seedFile ?? this.seedFile,
        smtp: smtp ?? this.smtp,
        notifyEmails: notifyEmails ?? this.notifyEmails,
        notifyOnNoChanges: notifyOnNoChanges ?? this.notifyOnNoChanges,
        uiBaseUrl: uiBaseUrl,
        basicAuthUser: basicAuthUser,
        basicAuthPassword: basicAuthPassword,
        httpTimeout: httpTimeout,
        httpRetries: httpRetries,
        retryDelays: retryDelays ?? this.retryDelays,
        unavailableEscalateDays: unavailableEscalateDays,
        host: host,
        port: port ?? this.port,
        uiDir: uiDir ?? this.uiDir,
        core: core,
        schedulerEnabled: schedulerEnabled ?? this.schedulerEnabled,
        logFile: logFile ?? this.logFile,
        logLevel: logLevel,
        configFile: configFile,
      );
}
