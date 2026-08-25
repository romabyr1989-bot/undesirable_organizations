/// Точка входа сервиса.
///
/// Запуск:
///   dart run bin/server.dart                 — сервер + планировщик
///   dart run bin/server.dart check-now       — разовая проверка сайта
///   dart run bin/server.dart publish <id>    — публикация версии вручную
///   dart run bin/server.dart reparse <id>    — перерасбор скачанного файла
///   dart run bin/server.dart paths           — какие пути и файлы использует
library;

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:perechen_server/src/app.dart';
import 'package:perechen_server/src/config/app_config.dart';
import 'package:perechen_server/src/config/runtime_settings.dart';
import 'package:perechen_server/src/db/database.dart';
import 'package:perechen_server/src/db/sqlite_library.dart';
import 'package:perechen_server/src/util/app_paths.dart';
import 'package:perechen_server/src/util/logging.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('config', help: 'путь к config.yaml')
    ..addOption('log-level', help: 'перекрывает LOG_LEVEL из конфигурации')
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);

  if (args['help'] == true) {
    stdout
      ..writeln('Сервис обработки перечня «нежелательных организаций» '
          '(272-ФЗ)')
      ..writeln(parser.usage)
      ..writeln('\nКоманды: check-now, publish <id>, reparse <id>, paths');
    return;
  }

  final config = _loadConfig(args['config'] as String?);
  final command = args.rest.isEmpty ? 'serve' : args.rest.first;

  if (command == 'paths') {
    _printPaths(config);
    return;
  }

  final levelName = (args['log-level'] as String?) ?? config.logLevel;
  final logger = AppLogger(
    minLevel: LogLevel.values.firstWhere(
      (level) => level.name == levelName,
      orElse: () => LogLevel.info,
    ),
    file: config.logFile.isEmpty ? null : LogFile(config.logFile),
  );

  final app = PerechenApp.create(config, logger: logger);

  switch (command) {
    case 'check-now':
      final outcome = await app.service.checkNow(trigger: 'cli');
      logger.info('проверка завершена', outcome.toJson());
      await app.stop();
      exit(outcome.status.name == 'error' ? 1 : 0);

    case 'publish':
      final id = int.tryParse(args.rest.length > 1 ? args.rest[1] : '');
      if (id == null) {
        stderr.writeln('укажите идентификатор версии: publish <id>');
        await app.stop();
        exit(2);
      }
      final result = await app.service.confirm(id, 'cli');
      logger.info('версия опубликована', {
        'fileName': result.fileName,
        'rows': result.rowCount,
        'cdiPath': result.cdiPath,
      });
      await app.stop();
      exit(0);

    case 'reparse':
      final id = int.tryParse(args.rest.length > 1 ? args.rest[1] : '');
      if (id == null) {
        stderr.writeln('укажите идентификатор версии: reparse <id>');
        await app.stop();
        exit(2);
      }
      final outcome = await app.service.reparse(id);
      logger.info('перерасбор завершён', outcome.toJson());
      await app.stop();
      exit(0);

    case 'serve':
      await app.start();
      final completer = Completer<void>();
      ProcessSignal.sigint.watch().listen((_) async {
        logger.info('останавливаем сервис');
        await app.stop();
        if (!completer.isCompleted) completer.complete();
      });
      if (!Platform.isWindows) {
        ProcessSignal.sigterm.watch().listen((_) async {
          logger.info('останавливаем сервис (SIGTERM)');
          await app.stop();
          if (!completer.isCompleted) completer.complete();
        });
      }
      await completer.future;

    default:
      stderr.writeln('неизвестная команда: $command');
      await app.stop();
      exit(2);
  }
}

/// Читает конфигурацию, сообщая об ошибке человеку, а не стеком вызовов:
/// на «чистой» ОС первая проблема установки — неверный путь к config.yaml.
AppConfig _loadConfig(String? configPath) {
  try {
    return AppConfig.load(configPath: configPath);
  } on StateError catch (error) {
    stderr.writeln('конфигурация не прочитана: ${error.message}');
    exit(2);
  }
}

/// Печатает разложенные по платформе пути — первое, что нужно при разборе
/// проблем установки на «чистой» ОС.
void _printPaths(AppConfig config) {
  String mark(String path) =>
      FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound
          ? 'нет'
          : 'есть';

  // Правки из UI живут в БД и перекрывают конфигурацию — показываем то, что
  // действительно используется. БД не создаём: до первого запуска её нет.
  final effective = _EffectivePaths.read(config);

  final configFile = config.configFile.isEmpty
      ? 'не найден (только окружение)'
      : config.configFile;
  final logTarget = config.logFile.isEmpty
      ? 'stdout (перехватывает служба)'
      : config.logFile;

  stdout
    ..writeln('платформа:            ${Platform.operatingSystem} '
        '(${Platform.operatingSystemVersion})')
    ..writeln('каталог установки:    ${AppPaths.bundleRoot}')
    ..writeln('config.yaml:          $configFile')
    ..writeln('рабочая папка:        ${config.dataDir} '
        '(${mark(config.dataDir)})')
    ..writeln('  файл БД:            ${config.databaseFile}')
    ..writeln('  скачанные файлы:    ${config.downloadsDir}')
    ..writeln('  опубликованные:     ${config.publishedDir}')
    ..writeln('папка CDI:            ${effective.cdiDropDir} '
        '(${mark(effective.cdiDropDir)})${effective.cdiNote}')
    ..writeln('справочник стран:     ${config.countriesFile} '
        '(${mark(config.countriesFile)})')
    ..writeln('веб-интерфейс:        ${config.uiDir} (${mark(config.uiDir)})')
    ..writeln('журнал:               $logTarget')
    ..writeln('адрес:                http://${config.host}:${config.port}')
    ..writeln('библиотека SQLite, порядок поиска:');
  for (final candidate in SqliteLibrary.candidates()) {
    // У системных библиотек наличие файла ничего не значит: их ищет
    // загрузчик ОС по своим путям.
    final state =
        SqliteLibrary.isBundled(candidate) ? ' (${mark(candidate)})' : '';
    stdout.writeln('  - $candidate$state');
  }
}


/// Значения, перекрытые правками из UI (таблица `meta` в БД).
class _EffectivePaths {
  _EffectivePaths({required this.cdiDropDir, required this.overridden});

  final String cdiDropDir;
  final bool overridden;

  String get cdiNote => overridden ? ', изменена в UI' : '';

  static _EffectivePaths read(AppConfig config) {
    if (!File(config.databaseFile).existsSync()) {
      return _EffectivePaths(cdiDropDir: config.cdiDropDir, overridden: false);
    }
    try {
      SqliteLibrary.ensureConfigured();
      final db = AppDatabase.open(config.databaseFile);
      try {
        final value = db.meta(RuntimeSettings.cdiDropDirKey);
        return _EffectivePaths(
          cdiDropDir: value ?? config.cdiDropDir,
          overridden: value != null,
        );
      } finally {
        db.close();
      }
    } catch (_) {
      // БД занята или несовместима — показываем значение из конфигурации
      return _EffectivePaths(cdiDropDir: config.cdiDropDir, overridden: false);
    }
  }
}
