/// Экран 4. Настройки: адреса первоисточника и папка выгрузки.
///
/// Значение по умолчанию берётся из конфигурации службы (`config.yaml` или
/// переменная окружения). Правка, сделанная здесь, перекрывает конфигурацию и
/// действует сразу — перезапускать службу не нужно. Кнопка «Вернуть из
/// конфигурации» снимает правку.
library;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../util/formatting.dart';

/// Идентификаторы настроек: совпадают с полями REST API.
const _pageUrlKey = 'minjustPageUrl';
const _cdiDropDirKey = 'cdiDropDir';
const _downloadCronKey = 'downloadCron';
const _autoPublishCronKey = 'autoPublishCron';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});

  final PerechenApi api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _pageUrl = TextEditingController();
  final _cdiDropDir = TextEditingController();
  final _downloadCron = TextEditingController();
  final _autoPublishCron = TextEditingController();

  /// Настройки, какими их отдал сервер: с ними сравниваем поля при сохранении.
  AppSettings _settings = const AppSettings();

  /// Настройки, для которых нажали «Вернуть из конфигурации».
  final Set<String> _resetFields = {};

  /// Ошибки проверки, пришедшие с сервера, по идентификатору настройки.
  final Map<String, String> _fieldErrors = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageUrl.dispose();
    _cdiDropDir.dispose();
    _downloadCron.dispose();
    _autoPublishCron.dispose();
    super.dispose();
  }

  TextEditingController _controller(String key) => switch (key) {
        _pageUrlKey => _pageUrl,
        _downloadCronKey => _downloadCron,
        _autoPublishCronKey => _autoPublishCron,
        _ => _cdiDropDir,
      };

  SettingValue _valueOf(String key) => switch (key) {
        _pageUrlKey => _settings.minjustPageUrl,
        _downloadCronKey => _settings.downloadCron,
        _autoPublishCronKey => _settings.autoPublishCron,
        _ => _settings.cdiDropDir,
      };

  static const _allKeys = [
    _pageUrlKey,
    _cdiDropDirKey,
    _downloadCronKey,
    _autoPublishCronKey,
  ];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await widget.api.settings();
      if (!mounted) return;
      setState(() {
        _apply(settings);
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить настройки: ${error.message}';
        _loading = false;
      });
    }
  }

  void _apply(AppSettings settings) {
    _settings = settings;
    _pageUrl.text = settings.minjustPageUrl.value;
    _cdiDropDir.text = settings.cdiDropDir.value;
    _downloadCron.text = settings.downloadCron.value;
    _autoPublishCron.text = settings.autoPublishCron.value;
    _resetFields.clear();
    _fieldErrors.clear();
  }

  /// Что именно отправляем: `null` — вернуть значение из конфигурации,
  /// строка — сохранить правку, отсутствие ключа — не трогать.
  Map<String, String?> _changes() {
    final changes = <String, String?>{};
    for (final key in _allKeys) {
      if (_resetFields.contains(key)) {
        if (_valueOf(key).overridden) changes[key] = null;
        continue;
      }
      final text = _controller(key).text.trim();
      if (text != _valueOf(key).value) changes[key] = text;
    }
    return changes;
  }

  Future<void> _save() async {
    final changes = _changes();
    if (changes.isEmpty) {
      _notify('Изменений нет');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors.clear();
    });
    try {
      final settings = await widget.api.saveSettings(changes);
      if (!mounted) return;
      setState(() {
        _apply(settings);
        _saving = false;
      });
      _notify('Настройки сохранены');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (error.field.isNotEmpty) {
          _fieldErrors[error.field] = error.message;
        } else {
          _error = error.message;
        }
      });
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _resetToConfig(String key) {
    setState(() {
      _controller(key).text = _valueOf(key).fromConfig;
      _resetFields.add(key);
      _fieldErrors.remove(key);
    });
  }

  void _onChanged(String key) {
    _resetFields.remove(key);
    _fieldErrors.remove(key);
    // Перерисовываем на каждый символ: под полем расписания показывается,
    // как выражение прочитано.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Настройки'),
          actions: [
            IconButton(
              onPressed: _loading || _saving ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Обновить',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _settings.cdiDropDir.value.isEmpty
                ? Center(child: Text(_error!))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // На широком окне три раздела стоят в ряд одинаковой
                      // ширины, IntrinsicHeight равняет их и по высоте.
                      // На узком — тем же порядком в столбик, тоже во всю
                      // ширину.
                      final inRow = constraints.maxWidth >= 1100;
                      final sections = [
                        _sourceSection(),
                        _scheduleSection(),
                        _cdiSection(),
                      ];
                      return ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          if (_error != null) ...[
                            _ErrorBanner(message: _error!),
                            const SizedBox(height: 20),
                          ],
                          if (inRow)
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final section in sections) ...[
                                    Expanded(child: section),
                                    if (section != sections.last)
                                      const SizedBox(width: 20),
                                  ],
                                ],
                              ),
                            )
                          else
                            for (final section in sections) ...[
                              section,
                              if (section != sections.last)
                                const SizedBox(height: 20),
                            ],
                        ],
                      );
                    },
                  ),
        bottomNavigationBar: _loading ? null : _actionsBar(context),
      );

  Widget _sourceSection() => _Section(
        icon: Icons.cloud_download_outlined,
        title: 'Первоисточник',
        children: [
          _SettingField(
            label: 'Страница перечня на сайте Минюста',
            controller: _pageUrl,
            setting: _settings.minjustPageUrl,
            errorText: _fieldErrors[_pageUrlKey],
            willReset: _resetFields.contains(_pageUrlKey),
            onChanged: () => _onChanged(_pageUrlKey),
            onReset: () => _resetToConfig(_pageUrlKey),
            enabled: !_saving,
          ),
        ],
      );

  Widget _scheduleSection() => _Section(
        icon: Icons.alarm,
        title: 'Расписание',
        children: [
          _SettingField(
            label: 'Проверка сайта',
            controller: _downloadCron,
            setting: _settings.downloadCron,
            errorText: _fieldErrors[_downloadCronKey],
            willReset: _resetFields.contains(_downloadCronKey),
            onChanged: () => _onChanged(_downloadCronKey),
            onReset: () => _resetToConfig(_downloadCronKey),
            enabled: !_saving,
          ),
          const SizedBox(height: 20),
          _SettingField(
            label: 'Авто-публикация',
            controller: _autoPublishCron,
            setting: _settings.autoPublishCron,
            errorText: _fieldErrors[_autoPublishCronKey],
            willReset: _resetFields.contains(_autoPublishCronKey),
            onChanged: () => _onChanged(_autoPublishCronKey),
            onReset: () => _resetToConfig(_autoPublishCronKey),
            enabled: !_saving,
          ),
        ],
      );

  Widget _cdiSection() => _Section(
        icon: Icons.folder_open,
        title: 'Выгрузка в CDI',
        children: [
          _SettingField(
            label: 'Папка для целевого CSV',
            controller: _cdiDropDir,
            setting: _settings.cdiDropDir,
            errorText: _fieldErrors[_cdiDropDirKey],
            willReset: _resetFields.contains(_cdiDropDirKey),
            onChanged: () => _onChanged(_cdiDropDirKey),
            onReset: () => _resetToConfig(_cdiDropDirKey),
            enabled: !_saving,
          ),
        ],
      );

  /// Кнопки внизу экрана: форма может быть длинной, а «Сохранить» должно быть
  /// на виду всегда.
  Widget _actionsBar(BuildContext context) {
    final theme = Theme.of(context);
    final updatedAt = _settings.updatedAt;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                updatedAt == null
                    ? 'Значения берутся из конфигурации службы, пока их не '
                        'изменили здесь.'
                    : 'Последнее изменение: '
                        '${formatMoscowDateTime(updatedAt)}'
                        '${_settings.updatedBy == null ? '' : ' · '
                            '${_settings.updatedBy}'}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed:
                  _saving ? null : () => setState(() => _apply(_settings)),
              child: const Text('Отменить изменения'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingField extends StatelessWidget {
  const _SettingField({
    required this.label,
    required this.controller,
    required this.setting,
    required this.onChanged,
    required this.onReset,
    required this.willReset,
    required this.enabled,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final SettingValue setting;
  final VoidCallback onChanged;
  final VoidCallback onReset;
  final bool willReset;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showConfigValue = setting.overridden && !willReset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          enabled: enabled,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            border: const OutlineInputBorder(),
            suffixIcon: setting.overridden
                ? Tooltip(
                    message: 'Значение изменено в интерфейсе',
                    child: Icon(
                      Icons.edit_note,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : null,
          ),
        ),
        if (showConfigValue)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            // Wrap, а не Row: в узкой колонке кнопка не помещается рядом со
            // значением и переносится под него.
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'В конфигурации службы: '
                  '${setting.fromConfig.isEmpty ? "не задано" : setting.fromConfig}',
                  style: theme.textTheme.bodySmall,
                ),
                TextButton(
                  onPressed: enabled ? onReset : null,
                  child: const Text('Вернуть из конфигурации'),
                ),
              ],
            ),
          ),
        if (willReset)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'После сохранения снова будет действовать значение из '
              'конфигурации службы.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
