/// Структурированные логи (п. 12 ТЗ): одна строка — один json-объект.
///
/// Без контейнера `docker logs` больше нет: systemd и launchd перехватывают
/// stdout сами, а планировщик задач Windows вывод не сохраняет, поэтому
/// параллельно поддерживается запись в файл с ротацией по размеру.
library;

import 'dart:convert';
import 'dart:io';

import 'moscow_time.dart';

enum LogLevel { debug, info, warning, error }

/// Файл журнала с ротацией: `perechen.log`, `perechen.log.1`, ...
class LogFile {
  LogFile(
    this.path, {
    this.maxBytes = 8 * 1024 * 1024,
    this.keep = 5,
  });

  /// Путь к текущему файлу журнала.
  final String path;

  /// Размер, после которого файл откладывается в `.1`.
  final int maxBytes;

  /// Сколько предыдущих файлов хранить.
  final int keep;

  bool _directoryReady = false;

  void writeLine(String line) {
    try {
      _ensureDirectory();
      _rotateIfNeeded();
      File(path).writeAsStringSync(
        '$line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (error) {
      // Журнал не должен ронять службу: сообщаем в stderr и работаем дальше.
      stderr.writeln('не удалось записать журнал ($path): $error');
    }
  }

  void _ensureDirectory() {
    if (_directoryReady) return;
    final directory = File(path).parent;
    if (!directory.existsSync()) directory.createSync(recursive: true);
    _directoryReady = true;
  }

  void _rotateIfNeeded() {
    final current = File(path);
    if (!current.existsSync() || current.lengthSync() < maxBytes) return;
    final oldest = File('$path.$keep');
    if (oldest.existsSync()) oldest.deleteSync();
    for (var index = keep - 1; index >= 1; index--) {
      final file = File('$path.$index');
      if (file.existsSync()) file.renameSync('$path.${index + 1}');
    }
    current.renameSync('$path.1');
  }
}

class AppLogger {
  AppLogger({this.minLevel = LogLevel.info, IOSink? sink, LogFile? file})
      : _sink = sink ?? stdout,
        _file = file;

  final LogLevel minLevel;
  final IOSink _sink;
  final LogFile? _file;

  void debug(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.debug, message, fields);

  void info(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.info, message, fields);

  void warning(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.warning, message, fields);

  void error(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.error, message, fields);

  void log(LogLevel level, String message, Map<String, Object?> fields) {
    if (level.index < minLevel.index) return;
    final record = <String, Object?>{
      'ts': MoscowTime.format(MoscowTime.now()),
      'level': level.name,
      'message': message,
      ...fields,
    };
    final line = jsonEncode(record);
    _sink.writeln(line);
    _file?.writeLine(line);
  }
}
