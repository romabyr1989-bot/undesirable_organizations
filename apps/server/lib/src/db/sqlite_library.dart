/// Подключение нативной библиотеки SQLite при установке на «чистую» ОС.
///
/// Раньше библиотеку доставлял пакетный менеджер внутри образа (`libsqlite3-dev`
/// ради симлинка `libsqlite3.so`). На чистой ОС такой гарантии нет: в Windows
/// системной libsqlite3 не существует вовсе, в Linux обычно есть только
/// версионный `libsqlite3.so.0`. Поэтому библиотека ищется сначала в комплекте
/// поставки, затем среди системных.
///
/// Явно указать файл можно переменной `SQLITE_LIBRARY`.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';

import '../util/app_paths.dart';

class SqliteLibraryException implements Exception {
  SqliteLibraryException(this.tried, this.lastError);

  /// Проверенные пути и имена.
  final List<String> tried;
  final Object? lastError;

  @override
  String toString() => 'не удалось загрузить библиотеку SQLite. '
      'Проверены: ${tried.join(', ')}. '
      'Укажите файл переменной SQLITE_LIBRARY. Последняя ошибка: $lastError';
}

class SqliteLibrary {
  const SqliteLibrary._();

  static bool _configured = false;

  /// Путь (или имя), по которому библиотека загрузилась. Заполняется при
  /// первом обращении к SQLite, до этого `null`.
  static String? loadedFrom;

  /// Регистрирует поиск библиотеки в пакете `sqlite3`.
  ///
  /// Вызывается перед первым открытием БД; повторные вызовы бесплатны.
  static void ensureConfigured() {
    if (_configured) return;
    _configured = true;
    for (final os in const [
      OperatingSystem.windows,
      OperatingSystem.linux,
      OperatingSystem.macOS,
    ]) {
      open.overrideFor(os, _open);
    }
  }

  /// Имена файла библиотеки для текущей платформы.
  static List<String> get _libraryNames {
    if (Platform.isWindows) return const ['sqlite3.dll'];
    if (Platform.isMacOS) return const ['libsqlite3.dylib'];
    return const ['libsqlite3.so.0', 'libsqlite3.so'];
  }

  /// Лежит ли кандидат внутри комплекта поставки.
  ///
  /// Только абсолютный путь: системные кандидаты — голые имена вроде
  /// `libsqlite3.so.0`, которые ищет загрузчик. Без проверки на абсолютность
  /// такое имя разрешалось относительно текущего каталога, и когда он лежал
  /// внутри каталога установки (а юнит systemd задаёт ровно
  /// `WorkingDirectory=/opt/perechen`), имя признавалось файлом комплекта,
  /// не находилось на диске и молча пропускалось. Откат на системную
  /// библиотеку переставал работать вообще.
  static bool isBundled(String candidate) =>
      p.isAbsolute(candidate) && p.isWithin(AppPaths.bundleRoot, candidate);

  /// Порядок поиска: явная переменная -> комплект поставки -> система.
  static List<String> candidates() {
    final explicit = Platform.environment['SQLITE_LIBRARY'];
    return <String>[
      if (explicit != null && explicit.isNotEmpty) explicit,
      // Рядом с бинарником и в `lib/` комплекта.
      for (final name in _libraryNames) ...[
        p.join(AppPaths.nativeLibDir, name),
        p.join(AppPaths.bundleRoot, 'bin', name),
      ],
      // Системные библиотеки (загрузчик ищет по стандартным путям).
      ..._libraryNames,
      if (Platform.isMacOS) '/usr/lib/libsqlite3.dylib',
      // Windows 10+ несёт собственную сборку SQLite.
      if (Platform.isWindows) 'winsqlite3.dll',
    ];
  }

  static DynamicLibrary _open() {
    final tried = candidates();
    Object? lastError;
    for (final candidate in tried) {
      // На существование проверяем только файлы комплекта: системные пути
      // могут быть внутри dyld-кэша macOS, где файла на диске нет, но
      // dlopen их находит.
      if (isBundled(candidate) && !File(candidate).existsSync()) continue;
      try {
        final library = DynamicLibrary.open(candidate);
        loadedFrom = candidate;
        return library;
      } catch (error) {
        lastError = error;
      }
    }
    throw SqliteLibraryException(tried, lastError);
  }
}
