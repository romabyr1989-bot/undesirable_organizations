/// Экран 1. Версии (п. 10 ТЗ).
library;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../util/formatting.dart';
import '../util/link_opener.dart';
import '../widgets/badges.dart';

class VersionsScreen extends StatefulWidget {
  const VersionsScreen({super.key, required this.api});

  final PerechenApi api;

  @override
  State<VersionsScreen> createState() => _VersionsScreenState();
}

class _VersionsScreenState extends State<VersionsScreen> {
  List<VersionSummary> _versions = const [];
  HealthInfo? _health;
  bool _loading = true;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final versions = await widget.api.versions();
      final health = await widget.api.health();
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _health = health;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.isUnauthorized
            ? 'Нет доступа: проверьте логин и пароль.'
            : 'Ошибка загрузки: ${error.message}';
        _loading = false;
      });
    }
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    try {
      final result = await widget.api.checkNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.title}. ${result.message}')),
      );
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка проверки: ${error.message}')),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Перечень 272-ФЗ — версии'),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).pushNamed('/events'),
              icon: const Icon(Icons.receipt_long),
              tooltip: 'Журнал событий',
            ),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Обновить',
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _checking ? null : _checkNow,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download),
              label: const Text('Проверить сейчас'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _load)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_health != null) _HealthBar(health: _health!),
                      Expanded(child: _versionsTable(context)),
                    ],
                  ),
      );

  Widget _versionsTable(BuildContext context) {
    if (_versions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Версий пока нет. Нажмите «Проверить сейчас», чтобы скачать '
            'текущий файл перечня с сайта Минюста.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _versions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final version = _versions[index];
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () async {
              await Navigator.of(context).pushNamed('/versions/${version.id}');
              if (mounted) await _load();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Данные от ${formatMoscowDateTime(version.actualityDate)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 12),
                      VersionStatusBadge(version: version),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Скачать целевой CSV',
                        onPressed: () => openLink(
                          widget.api.exportUri(version.id).toString(),
                        ),
                        icon: const Icon(Icons.download),
                      ),
                      IconButton(
                        tooltip: 'Открыть версию',
                        onPressed: () async {
                          await Navigator.of(context)
                              .pushNamed('/versions/${version.id}');
                          if (mounted) await _load();
                        },
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Скачано: ${formatMoscowDateTime(version.downloadedAt)}'
                    '${version.publishedAt == null ? '' : ' · опубликовано: '
                        '${formatMoscowDateTime(version.publishedAt)}'
                        ' (${version.confirmedBy ?? '—'})'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Файл: ${version.targetFileName}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (version.errorText != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      version.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  CountersRow(counters: version.counters),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({required this.health});

  final HealthInfo health;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(
          spacing: 24,
          runSpacing: 6,
          children: [
            _healthItem(
              context,
              Icons.schedule,
              'Последняя проверка',
              '${formatMoscowDateTime(health.lastCheckAt)} '
                  '(${health.lastCheckTitle})',
            ),
            _healthItem(
              context,
              Icons.update,
              'Следующий запуск',
              formatMoscowDateTime(health.nextRunAt),
            ),
            _healthItem(
              context,
              Icons.alarm,
              'Расписание',
              'проверка ${health.downloadCron}, '
                  'авто-публикация ${health.autoPublishCron} '
                  '(${health.timeZone})',
            ),
            _healthItem(
              context,
              Icons.folder_open,
              'Папка CDI',
              health.cdiDropDir,
            ),
          ],
        ),
      );

  Widget _healthItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text('$label: ', style: const TextStyle(fontSize: 12)),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      );
}
