/// Тесты развёртывания без контейнера: платформенные пути, поиск конфигурации,
/// поиск библиотеки SQLite, журнал в файл.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:perechen_server/src/config/app_config.dart';
import 'package:perechen_server/src/db/sqlite_library.dart';
import 'package:perechen_server/src/util/app_paths.dart';
import 'package:perechen_server/src/util/logging.dart';
import 'package:test/test.dart';

void main() {
  group('AppPaths', () {
    test('корень комплекта — существующий каталог', () {
      expect(Directory(AppPaths.bundleRoot).existsSync(), isTrue);
      expect(p.isAbsolute(AppPaths.bundleRoot), isTrue);
    });

    test('корень комплекта не указывает на bin/', () {
      // Бинарник лежит в `<корень>/bin/`, ресурсы — в `<корень>/web` и
      // `<корень>/assets`: корнем должен быть родитель bin.
      expect(p.basename(AppPaths.bundleRoot), isNot('bin'));
    });

    test('пути данных абсолютны и соответствуют платформе', () {
      expect(p.isAbsolute(AppPaths.defaultDataDir), isTrue);
      expect(p.isAbsolute(AppPaths.defaultCdiDropDir), isTrue);
      if (Platform.isWindows) {
        expect(AppPaths.defaultDataDir, contains('Perechen272FZ'));
        expect(AppPaths.configDir, contains('Perechen272FZ'));
      } else if (Platform.isMacOS) {
        expect(AppPaths.defaultDataDir, '/usr/local/var/perechen');
        expect(AppPaths.configDir, '/usr/local/etc/perechen');
      } else {
        expect(AppPaths.defaultDataDir, '/var/lib/perechen');
        expect(AppPaths.configDir, '/etc/perechen');
      }
    });

    test('журнал в файл обязателен только на Windows', () {
      final logFile = AppPaths.logFileFor(p.join('D:', 'perechen'));
      expect(logFile.isEmpty, !Platform.isWindows);
      if (Platform.isWindows) {
        // Считается от выбранного при установке каталога, а не от стандартного.
        expect(logFile, startsWith(p.join('D:', 'perechen')));
      }
    });

    test('ресурсы ищутся в комплекте поставки', () {
      expect(
        AppPaths.defaultCountriesFile,
        p.join(AppPaths.bundleRoot, 'assets', 'countries_ru.txt'),
      );
      expect(AppPaths.defaultUiDir, p.join(AppPaths.bundleRoot, 'web'));
    });
  });

  group('AppConfig', () {
    test('значения по умолчанию берутся из платформенных путей', () {
      final config = AppConfig.load(environment: const {});
      expect(config.dataDir, AppPaths.defaultDataDir);
      expect(config.cdiDropDir, AppPaths.defaultCdiDropDir);
      expect(config.countriesFile, AppPaths.defaultCountriesFile);
      expect(config.uiDir, AppPaths.defaultUiDir);
    });

    test('производные пути собираются разделителем текущей ОС', () {
      final base = Directory.systemTemp.path;
      final config = AppConfig.load(environment: {'DATA_DIR': base});
      expect(config.downloadsDir, p.join(base, 'downloads'));
      expect(config.publishedDir, p.join(base, 'published'));
      expect(config.databaseFile, p.join(base, 'perechen.db'));
    });

    test('явное окружение отключает поиск системного config.yaml', () {
      // Иначе тесты зависели бы от файлов конкретной машины.
      final config = AppConfig.load(environment: const {});
      expect(config.configFile, isEmpty);
    });

    test('указанный, но отсутствующий config.yaml — ошибка', () {
      expect(
        () => AppConfig.load(
          environment: const {},
          configPath: p.join(Directory.systemTemp.path, 'нет-такого.yaml'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('config.yaml читается, окружение важнее файла', () {
      final directory = Directory.systemTemp.createTempSync('perechen-config');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File(p.join(directory.path, 'config.yaml'))
        ..writeAsStringSync('PORT: 9090\nBASIC_AUTH_USER: from-yaml\n');

      final config = AppConfig.load(
        environment: {'BASIC_AUTH_USER': 'from-env'},
        configPath: file.path,
      );
      expect(config.port, 9090);
      expect(config.basicAuthUser, 'from-env');
      expect(config.configFile, file.path);
    });
  });

  group('SqliteLibrary', () {
    test('сначала комплект поставки, затем системная библиотека', () {
      final candidates = SqliteLibrary.candidates();
      expect(candidates, isNotEmpty);
      final bundled = candidates
          .indexWhere((c) => c.startsWith(AppPaths.nativeLibDir));
      final system = candidates.indexWhere((c) => !p.isAbsolute(c));
      expect(bundled, isNonNegative, reason: 'нет пути внутри комплекта');
      expect(system, isNonNegative, reason: 'нет системной библиотеки');
      expect(bundled, lessThan(system));
    });

    test('SQLITE_LIBRARY проверяется первой', () {
      final explicit = Platform.environment['SQLITE_LIBRARY'];
      if (explicit == null || explicit.isEmpty) return;
      expect(SqliteLibrary.candidates().first, explicit);
    });

    test('имена библиотеки соответствуют платформе', () {
      final candidates = SqliteLibrary.candidates();
      if (Platform.isWindows) {
        expect(candidates, contains('sqlite3.dll'));
        // Запасной вариант для машин без своей библиотеки.
        expect(candidates, contains('winsqlite3.dll'));
      } else if (Platform.isMacOS) {
        expect(candidates, contains('libsqlite3.dylib'));
      } else {
        // Пакеты дистрибутивов кладут только версионный файл.
        expect(candidates, contains('libsqlite3.so.0'));
      }
    });
  });

  group('LogFile', () {
    test('пишет строки и разворачивает ротацию по размеру', () {
      final directory = Directory.systemTemp.createTempSync('perechen-log');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = p.join(directory.path, 'nested', 'perechen.log');

      final log = LogFile(path, maxBytes: 200, keep: 2);
      for (var i = 0; i < 20; i++) {
        log.writeLine('{"n":$i,"filler":"..........................."}');
      }

      expect(File(path).existsSync(), isTrue, reason: 'каталог создаётся сам');
      expect(File('$path.1').existsSync(), isTrue, reason: 'ротация была');
      expect(File('$path.3').existsSync(), isFalse, reason: 'keep = 2');
      expect(File(path).lengthSync(), lessThanOrEqualTo(400));
    });

    test('AppLogger пишет и в stdout, и в файл', () async {
      final directory = Directory.systemTemp.createTempSync('perechen-log');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = p.join(directory.path, 'perechen.log');
      final stdoutFile = File(p.join(directory.path, 'stdout.jsonl'));
      final sink = stdoutFile.openWrite();

      AppLogger(sink: sink, file: LogFile(path))
          .info('проверка', {'ключ': 'значение'});
      await sink.close();

      final written = File(path).readAsStringSync();
      expect(written, contains('"message":"проверка"'));
      expect(written, contains('"ключ":"значение"'));
      expect(written.endsWith('\n'), isTrue);
      // Строка та же самая: служба и в журнал, и в вывод пишет одно и то же.
      expect(stdoutFile.readAsStringSync(), written);
    });
  });
}
