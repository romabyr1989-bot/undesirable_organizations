/// Сборка приложения: БД, загрузчик, сервисы, планировщик, HTTP-сервер.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:perechen_core/perechen_core.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'api/api_router.dart';
import 'config/app_config.dart';
import 'db/database.dart';
import 'db/sqlite_library.dart';
import 'download/downloader.dart';
import 'mail/mail_sender.dart';
import 'mail/notifier.dart';
import 'scheduler/cron.dart';
import 'service/publisher.dart';
import 'service/version_service.dart';
import 'util/app_paths.dart';
import 'util/logging.dart';
import 'util/moscow_time.dart';

class PerechenApp {
  PerechenApp({
    required this.config,
    required this.db,
    required this.service,
    required this.publisher,
    required this.api,
    required this.scheduler,
    required this.logger,
  });

  final AppConfig config;
  final AppDatabase db;
  final VersionService service;
  final Publisher publisher;
  final ApiServer api;
  final CronScheduler scheduler;
  final AppLogger logger;

  HttpServer? _server;

  /// Собирает приложение по конфигурации.
  ///
  /// [mailSender] и [httpClient] подменяются в тестах.
  static PerechenApp create(
    AppConfig config, {
    MailSender? mailSender,
    http.Client? httpClient,
    AppLogger? logger,
    AppDatabase? database,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
  }) {
    final appLogger = logger ?? AppLogger();
    final db = database ?? AppDatabase.open(config.databaseFile);
    final countries = loadCountries(config, appLogger);

    final downloader = Downloader(
      config: config,
      client: httpClient,
      logger: appLogger,
      sleep: sleep,
    );
    final notifier = Notifier(
      config: config,
      sender: mailSender ?? SmtpMailSender(config),
      db: db,
      logger: appLogger,
    );
    final publisher = Publisher(config: config, db: db, logger: appLogger);
    final service = VersionService(
      config: config,
      db: db,
      downloader: downloader,
      notifier: notifier,
      publisher: publisher,
      countries: countries,
      logger: appLogger,
      clock: clock,
    );

    final scheduler = CronScheduler(
      clock: clock ?? MoscowTime.now,
      onError: (job, error, stackTrace) => appLogger.error(
        'задача планировщика упала',
        {'job': job.name, 'error': '$error'},
      ),
    )
      ..addJob(CronJob(
        name: 'download',
        schedule: CronSchedule.parse(config.downloadCron),
        action: () => service.checkNow(trigger: 'cron'),
      ))
      ..addJob(CronJob(
        name: 'auto-publish',
        schedule: CronSchedule.parse(config.autoPublishCron),
        action: service.autoPublishPending,
      ));

    final api = ApiServer(
      config: config,
      db: db,
      service: service,
      publisher: publisher,
      logger: appLogger,
      scheduler: scheduler,
    );

    return PerechenApp(
      config: config,
      db: db,
      service: service,
      publisher: publisher,
      api: api,
      scheduler: scheduler,
      logger: appLogger,
    );
  }

  /// Читает справочник стран, пробуя запасные пути (удобно в разработке).
  static CountryRegistry loadCountries(AppConfig config, AppLogger logger) {
    final candidates = <String>[
      config.countriesFile,
      // Комплект поставки: `<каталог установки>/assets/countries_ru.txt`.
      AppPaths.defaultCountriesFile,
      // Запасные пути для запуска из исходников.
      p.join('assets', 'countries_ru.txt'),
      p.join('..', '..', 'packages', 'core', 'assets', 'countries_ru.txt'),
      p.join('packages', 'core', 'assets', 'countries_ru.txt'),
    ];
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        final registry = CountryRegistry.parse(
          file.readAsStringSync(),
          normalize: config.core.countryNormalize,
        );
        logger.info('справочник стран загружен', {
          'path': path,
          'entries': registry.length,
        });
        return registry;
      }
    }
    logger.error('справочник стран не найден', {'tried': candidates});
    throw StateError(
      'не найден файл справочника стран (COUNTRIES_FILE=${config.countriesFile})',
    );
  }

  /// Поднимает HTTP-сервер и планировщик.
  Future<void> start() async {
    for (final path in [config.dataDir, config.downloadsDir, config.publishedDir]) {
      final directory = Directory(path);
      if (!directory.existsSync()) directory.createSync(recursive: true);
    }

    _server = await shelf_io.serve(api.handler, config.host, config.port);
    logger.info('сервис запущен', {
      'host': config.host,
      'port': config.port,
      'timeZone': MoscowTime.zoneName,
      'downloadCron': config.downloadCron,
      'autoPublishCron': config.autoPublishCron,
      'cdiDropDir': config.cdiDropDir,
      'ui': config.uiBaseUrl,
      // Что именно подхватилось на этой машине (установка без контейнера).
      'platform': Platform.operatingSystem,
      'installDir': AppPaths.bundleRoot,
      'dataDir': config.dataDir,
      'configFile': config.configFile,
      'sqlite': SqliteLibrary.loadedFrom,
    });

    if (config.schedulerEnabled) {
      scheduler.start();
      logger.info('планировщик запущен', {
        'jobs': scheduler.jobs.map((j) => '${j.name}: ${j.schedule}').toList(),
        'nextRunAt': scheduler.nextRunAt == null
            ? null
            : MoscowTime.format(scheduler.nextRunAt!),
      });
    }
  }

  /// Адрес запущенного сервера (нужен тестам).
  Uri? get address => _server == null
      ? null
      : Uri.parse('http://${_server!.address.host}:${_server!.port}');

  Future<void> stop() async {
    scheduler.stop();
    await _server?.close(force: true);
    _server = null;
    db.close();
  }
}
