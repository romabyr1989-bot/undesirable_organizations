/// Расположение программы, данных и конфигурации на «чистой» ОС.
///
/// Сервис ставится системной службой (systemd / launchd / планировщик задач
/// Windows), поэтому пути зависят от платформы. Всё перечисленное ниже — лишь
/// значения по умолчанию: любое переопределяется переменной окружения или
/// `config.yaml` (п. 11 ТЗ).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Имя каталога сервиса в системных папках Windows и macOS.
const _productDirName = 'Perechen272FZ';

class AppPaths {
  const AppPaths._();

  static String? _bundleRootCache;

  /// Корень комплекта поставки: каталог, внутри которого лежат `bin/`,
  /// `web/`, `assets/`, `lib/`.
  ///
  /// Для собранного бинарника это каталог установки (родитель `bin/`), при
  /// запуске через `dart run bin/server.dart` — каталог пакета `apps/server`.
  static String get bundleRoot => _bundleRootCache ??= _resolveBundleRoot();

  static String _resolveBundleRoot() {
    final executable = Platform.resolvedExecutable;
    final executableName = p.basenameWithoutExtension(executable).toLowerCase();
    // Под `dart run` и `dart test` resolvedExecutable указывает на сам SDK —
    // тогда ориентируемся на расположение скрипта.
    final launchedBySdk =
        executableName == 'dart' || executableName == 'dartaotruntime';
    final script = Platform.script;
    final directory = !launchedBySdk
        ? p.dirname(executable)
        : script.scheme == 'file'
            ? p.dirname(script.toFilePath())
            : Directory.current.path;

    // `<корень>/bin/perechen` или `<пакет>/bin/server.dart`.
    return p.basename(directory).toLowerCase() == 'bin'
        ? p.dirname(directory)
        : directory;
  }

  /// `%ProgramData%` (обычно `C:\ProgramData`).
  static String get _windowsProgramData =>
      Platform.environment['ProgramData'] ??
      Platform.environment['PROGRAMDATA'] ??
      r'C:\ProgramData';

  /// Рабочая папка сервиса: `downloads/`, `published/`, БД.
  static String get defaultDataDir {
    if (Platform.isWindows) {
      return p.join(_windowsProgramData, _productDirName);
    }
    if (Platform.isMacOS) return '/usr/local/var/perechen';
    return '/var/lib/perechen';
  }

  /// Папка, из которой скрипт CDI забирает целевой CSV.
  ///
  /// На Linux сохранена точка монтирования из ТЗ, на Windows и macOS такой
  /// договорённости нет — по умолчанию подпапка рабочего каталога.
  static String get defaultCdiDropDir {
    if (Platform.isWindows || Platform.isMacOS) {
      return p.join(defaultDataDir, 'cdi-inbox');
    }
    return '/mnt/cdi/inbox';
  }

  /// Системный каталог конфигурации службы.
  static String get configDir {
    if (Platform.isWindows) {
      return p.join(_windowsProgramData, _productDirName);
    }
    if (Platform.isMacOS) return '/usr/local/etc/perechen';
    return '/etc/perechen';
  }

  /// Где ищется `config.yaml`, если он не задан явно (`--config`,
  /// `CONFIG_FILE`). Первый существующий файл выигрывает.
  static List<String> get configCandidates => <String>[
        p.join(configDir, 'config.yaml'),
        p.join(bundleRoot, 'config.yaml'),
      ];

  /// Справочник стран из комплекта поставки.
  static String get defaultCountriesFile =>
      p.join(bundleRoot, 'assets', 'countries_ru.txt');

  /// Каталог собранного Flutter Web.
  static String get defaultUiDir => p.join(bundleRoot, 'web');

  /// Каталог для нативных библиотек комплекта (sqlite3).
  static String get nativeLibDir => p.join(bundleRoot, 'lib');

  /// Файл журнала службы для рабочего каталога [dataDir].
  ///
  /// В systemd и launchd вывод перехватывается системой, а планировщик задач
  /// Windows не сохраняет ничего — поэтому там журнал в файл обязателен.
  static String logFileFor(String dataDir) =>
      Platform.isWindows ? p.join(dataDir, 'logs', 'perechen.log') : '';
}
