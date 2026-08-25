/// Настройки, которые ответственный правит в UI без перезапуска службы.
///
/// Источник значения: правка из UI (таблица `meta`) перекрывает конфигурацию
/// (переменные окружения -> `config.yaml` -> значения по умолчанию). Правку
/// можно снять — тогда снова действует значение из конфигурации.
///
/// Значения читаются из БД при каждом обращении: их берут редко (раз в
/// скачивание и раз в публикацию), зато изменение действует сразу, без
/// пересборки загрузчика и публикатора.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../scheduler/cron.dart';
import '../util/logging.dart';
import '../util/moscow_time.dart';
import 'app_config.dart';

/// Ошибка проверки значения: сообщение показывается ответственному в UI.
class SettingsException implements Exception {
  SettingsException(this.message, {this.field = ''});

  final String message;

  /// Поле, к которому относится ошибка (`minjustExportUrl` и т. п.).
  final String field;

  @override
  String toString() => 'SettingsException: $message';
}

/// Одно настраиваемое значение: что действует сейчас и что записано в
/// конфигурации.
class SettingValue {
  const SettingValue({
    required this.value,
    required this.fromConfig,
    required this.overridden,
  });

  /// Действующее значение.
  final String value;

  /// Значение из конфигурации (env/`config.yaml`/умолчание).
  final String fromConfig;

  /// Значение изменено через UI и перекрывает конфигурацию.
  final bool overridden;

  Map<String, Object?> toJson() => {
        'value': value,
        'fromConfig': fromConfig,
        'overridden': overridden,
      };
}

class RuntimeSettings {
  RuntimeSettings({
    required this.config,
    required this.db,
    AppLogger? logger,
  }) : _logger = logger ?? AppLogger();

  final AppConfig config;
  final AppDatabase db;
  final AppLogger _logger;

  static const exportUrlKey = 'settings.minjust_export_url';
  static const pageUrlKey = 'settings.minjust_page_url';
  static const cdiDropDirKey = 'settings.cdi_drop_dir';
  static const downloadCronKey = 'settings.download_cron';
  static const autoPublishCronKey = 'settings.auto_publish_cron';
  static const updatedAtKey = 'settings.updated_at';
  static const updatedByKey = 'settings.updated_by';

  /// Прямая ссылка на xlsx. Пустая — адрес ищется на странице перечня.
  String get minjustExportUrl =>
      db.meta(exportUrlKey) ?? config.minjustExportUrl;

  /// Страница перечня на сайте Минюста.
  String get minjustPageUrl => db.meta(pageUrlKey) ?? config.minjustPageUrl;

  /// Папка, из которой существующий скрипт забирает целевой CSV.
  String get cdiDropDir => db.meta(cdiDropDirKey) ?? config.cdiDropDir;

  /// Расписание ежедневной проверки сайта (МСК).
  String get downloadCron => db.meta(downloadCronKey) ?? config.downloadCron;

  /// Расписание авто-публикации неподтверждённой версии (МСК).
  String get autoPublishCron =>
      db.meta(autoPublishCronKey) ?? config.autoPublishCron;

  /// Вызывается после успешной правки: планировщик перечитывает расписания.
  void Function(RuntimeSettings settings)? onChanged;

  SettingValue get _exportUrlValue => SettingValue(
        value: minjustExportUrl,
        fromConfig: config.minjustExportUrl,
        overridden: db.meta(exportUrlKey) != null,
      );

  SettingValue get _pageUrlValue => SettingValue(
        value: minjustPageUrl,
        fromConfig: config.minjustPageUrl,
        overridden: db.meta(pageUrlKey) != null,
      );

  SettingValue get _cdiDropDirValue => SettingValue(
        value: cdiDropDir,
        fromConfig: config.cdiDropDir,
        overridden: db.meta(cdiDropDirKey) != null,
      );

  SettingValue get _downloadCronValue => SettingValue(
        value: downloadCron,
        fromConfig: config.downloadCron,
        overridden: db.meta(downloadCronKey) != null,
      );

  SettingValue get _autoPublishCronValue => SettingValue(
        value: autoPublishCron,
        fromConfig: config.autoPublishCron,
        overridden: db.meta(autoPublishCronKey) != null,
      );

  Map<String, Object?> toJson() => {
        'minjustExportUrl': _exportUrlValue.toJson(),
        'minjustPageUrl': _pageUrlValue.toJson(),
        'cdiDropDir': _cdiDropDirValue.toJson(),
        'downloadCron': _downloadCronValue.toJson(),
        'autoPublishCron': _autoPublishCronValue.toJson(),
        'timeZone': config.timeZone,
        'updatedAt': db.meta(updatedAtKey),
        'updatedBy': db.meta(updatedByKey),
      };

  /// Применяет правки.
  ///
  /// Ключ отсутствует в [changes] — значение не трогаем; ключ со значением
  /// `null` — снимаем правку и возвращаемся к конфигурации; строка —
  /// сохраняем как правку.
  ///
  /// Бросает [SettingsException], если значение не проходит проверку;
  /// в этом случае не меняется ничего.
  Map<String, Object?> update(
    Map<String, Object?> changes, {
    required String author,
  }) {
    const fields = {
      'minjustExportUrl': exportUrlKey,
      'minjustPageUrl': pageUrlKey,
      'cdiDropDir': cdiDropDirKey,
      'downloadCron': downloadCronKey,
      'autoPublishCron': autoPublishCronKey,
    };

    final unknown = changes.keys.where((key) => !fields.containsKey(key));
    if (unknown.isNotEmpty) {
      throw SettingsException('неизвестные настройки: ${unknown.join(", ")}');
    }

    // Сначала считаем итоговые значения и проверяем их все вместе: настройки
    // связаны (ссылка на файл может быть пустой, только если задана страница).
    String resolve(String field) {
      if (!changes.containsKey(field)) {
        return switch (field) {
          'minjustExportUrl' => minjustExportUrl,
          'minjustPageUrl' => minjustPageUrl,
          'downloadCron' => downloadCron,
          'autoPublishCron' => autoPublishCron,
          _ => cdiDropDir,
        };
      }
      final value = changes[field];
      if (value == null) {
        return switch (field) {
          'minjustExportUrl' => config.minjustExportUrl,
          'minjustPageUrl' => config.minjustPageUrl,
          'downloadCron' => config.downloadCron,
          'autoPublishCron' => config.autoPublishCron,
          _ => config.cdiDropDir,
        };
      }
      return '$value'.trim();
    }

    final exportUrl = resolve('minjustExportUrl');
    final pageUrl = resolve('minjustPageUrl');
    final cdiDir = resolve('cdiDropDir');
    final downloadSchedule = resolve('downloadCron');
    final autoPublishSchedule = resolve('autoPublishCron');

    _validateUrl(exportUrl, field: 'minjustExportUrl', allowEmpty: true);
    _validateUrl(pageUrl, field: 'minjustPageUrl', allowEmpty: true);
    if (exportUrl.isEmpty && pageUrl.isEmpty) {
      throw SettingsException(
        'нужен хотя бы один адрес: прямая ссылка на файл или страница перечня',
        field: 'minjustExportUrl',
      );
    }
    _validateCdiDir(cdiDir);
    _validateCron(downloadSchedule, field: 'downloadCron');
    _validateCron(autoPublishSchedule, field: 'autoPublishCron');

    // Проверки пройдены — записываем.
    final applied = <String, Object?>{};
    for (final entry in fields.entries) {
      if (!changes.containsKey(entry.key)) continue;
      final incoming = changes[entry.key];
      final resolved = switch (entry.key) {
        'minjustExportUrl' => exportUrl,
        'minjustPageUrl' => pageUrl,
        'downloadCron' => downloadSchedule,
        'autoPublishCron' => autoPublishSchedule,
        _ => cdiDir,
      };
      if (incoming == null) {
        db.deleteMeta(entry.value);
        applied[entry.key] = null;
      } else {
        db.setMeta(entry.value, resolved);
        applied[entry.key] = resolved;
      }
    }

    if (applied.isEmpty) return toJson();

    db
      ..setMeta(updatedAtKey, MoscowTime.format(MoscowTime.now()))
      ..setMeta(updatedByKey, author)
      ..addEvent(
        EventType.settingsChanged,
        payload: {
          'author': author,
          'changed': applied.keys.toList(),
          'minjustExportUrl': exportUrl,
          'minjustPageUrl': pageUrl,
          'cdiDropDir': cdiDir,
          'downloadCron': downloadSchedule,
          'autoPublishCron': autoPublishSchedule,
        },
      );
    _logger.info('настройки изменены', {
      'author': author,
      'changed': applied.keys.join(', '),
    });
    onChanged?.call(this);
    return toJson();
  }

  /// Проверяет cron-выражение тем же разбором, что и планировщик.
  void _validateCron(String value, {required String field}) {
    if (value.trim().isEmpty) {
      throw SettingsException('укажите расписание', field: field);
    }
    try {
      CronSchedule.parse(value);
    } on FormatException catch (error) {
      throw SettingsException(error.message, field: field);
    } catch (error) {
      throw SettingsException('расписание не разобрано: $error', field: field);
    }
  }

  void _validateUrl(
    String value, {
    required String field,
    bool allowEmpty = false,
  }) {
    if (value.isEmpty) {
      if (allowEmpty) return;
      throw SettingsException('адрес не может быть пустым', field: field);
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.isAbsolute ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw SettingsException(
        'адрес должен начинаться с http:// или https:// и содержать имя узла',
        field: field,
      );
    }
  }

  /// Проверяет папку CDI боем: создаёт при необходимости и пробует записать
  /// файл — иначе о недоступности сетевой папки узнали бы только в момент
  /// публикации.
  void _validateCdiDir(String value) {
    const field = 'cdiDropDir';
    if (value.isEmpty) {
      throw SettingsException('укажите папку для выгрузки', field: field);
    }
    if (!p.isAbsolute(value)) {
      throw SettingsException(
        'нужен полный путь к папке, например '
        '${Platform.isWindows ? r"D:\cdi\inbox" : "/mnt/cdi/inbox"}',
        field: field,
      );
    }
    final directory = Directory(value);
    if (!directory.existsSync()) {
      try {
        directory.createSync(recursive: true);
      } catch (error) {
        throw SettingsException(
          'папку не удалось создать: $error',
          field: field,
        );
      }
    }
    final probe = File(p.join(
      value,
      '.perechen-write-test-${MoscowTime.now().microsecondsSinceEpoch}',
    ));
    try {
      probe.writeAsStringSync('', flush: true);
    } catch (error) {
      throw SettingsException('в папку нельзя записывать: $error',
          field: field);
    } finally {
      if (probe.existsSync()) {
        try {
          probe.deleteSync();
        } catch (_) {
          // файл-пробник не удалился — на работу сервиса не влияет
        }
      }
    }
  }
}
