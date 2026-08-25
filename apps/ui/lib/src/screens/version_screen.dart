/// Экран 2. Версия — основной рабочий экран ответственного (п. 10 ТЗ).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../util/formatting.dart';
import '../util/link_opener.dart';
import '../widgets/badges.dart';
import '../widgets/record_editor.dart';

class VersionScreen extends StatefulWidget {
  const VersionScreen({
    super.key,
    required this.api,
    required this.versionId,
    this.initialFilter = 'all',
  });

  final PerechenApi api;
  final int versionId;
  final String initialFilter;

  @override
  State<VersionScreen> createState() => _VersionScreenState();
}

class _VersionScreenState extends State<VersionScreen> {
  VersionSummary? _version;
  List<RecordItem> _records = const [];
  late String _filter = widget.initialFilter;
  String _search = '';
  String? _expandedOrgKey;
  bool _loading = true;
  bool _publishing = false;
  String? _error;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final version = await widget.api.version(widget.versionId);
      final records = await widget.api.records(
        widget.versionId,
        filter: _filter,
        search: _search,
      );
      if (!mounted) return;
      setState(() {
        _version = version;
        _records = records;
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

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _search = value;
      _load();
    });
  }

  Future<void> _saveCorrection(
    RecordItem record,
    Map<String, String> values,
  ) async {
    try {
      final updated = await widget.api
          .saveCorrection(widget.versionId, record.orgKey, values);
      if (!mounted) return;
      _replaceRecord(updated);
      _refreshVersion();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Правка сохранена')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить правку: ${error.message}')),
      );
    }
  }

  Future<void> _revertCorrection(RecordItem record) async {
    try {
      final updated = await widget.api.revertCorrection(
        widget.versionId,
        record.orgKey,
        RecordField.values.map((f) => f.id).toList(),
      );
      if (!mounted) return;
      _replaceRecord(updated);
      _refreshVersion();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Возвращён автоматический разбор')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отменить правку: ${error.message}')),
      );
    }
  }

  void _replaceRecord(RecordItem updated) {
    setState(() {
      _records = [
        for (final record in _records)
          record.orgKey == updated.orgKey ? updated : record,
      ];
    });
  }

  Future<void> _refreshVersion() async {
    try {
      final version = await widget.api.version(widget.versionId);
      if (mounted) setState(() => _version = version);
    } on ApiException {
      // счётчики обновятся при следующей загрузке
    }
  }

  Future<void> _confirm() async {
    final version = _version;
    if (version == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтвердить и передать в CDI?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Файл: ${version.targetFileName}'),
            const SizedBox(height: 4),
            Text('Записей: ${version.counters.total}'),
            if (version.counters.review > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Внимание: ${plural(version.counters.review, 'запись требует',
                    'записи требуют', 'записей требуют')} проверки.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _publishing = true);
    try {
      final result = await widget.api.confirm(widget.versionId);
      if (!mounted) return;
      setState(() => _version = result.version);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Опубликовано: ${result.fileName} '
            '(${plural(result.rows, 'запись', 'записи', 'записей')})'
            '${result.warnings.isEmpty ? '' : '. Предупреждений: '
                '${result.warnings.length}'}',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Публикация не выполнена: ${error.message}')),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = _version;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          version == null
              ? 'Версия'
              : 'Версия от ${formatMoscowDateTime(version.actualityDate)}',
        ),
        actions: [
          if (version != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: VersionStatusBadge(version: version),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Скачать целевой CSV',
              onPressed: () =>
                  openLink(widget.api.exportUri(widget.versionId).toString()),
              icon: const Icon(Icons.download),
            ),
          ],
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    _toolbar(context),
                    const Divider(height: 1),
                    _tableHeader(context),
                    const Divider(height: 1),
                    Expanded(child: _recordsList()),
                  ],
                ),
      bottomNavigationBar: version == null ? null : _bottomBar(context, version),
    );
  }

  /// Панель над таблицей: плашки счётчиков (они же переключатель фильтра)
  /// слева, поиск — у правого края. Отдельного ряда фильтров нет: он
  /// дублировал плашки.
  Widget _toolbar(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            // Flexible, чтобы на узком окне плашки переносились, а не
            // выдавливали поиск за край.
            Flexible(
              child: _version == null
                  ? const SizedBox.shrink()
                  : CountersRow(
                      counters: _version!.counters,
                      selectedFilter: _filter,
                      onFilterSelected: (filter) {
                        setState(() => _filter = filter);
                        _load();
                      },
                    ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              // При увеличенном шрифте подсказка в 320 px не помещается.
              width: 380,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Поиск по наименованию и реквизитам',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ],
        ),
      );

  Widget _tableHeader(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(fontWeight: FontWeight.w700);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: tableGutter(context, 56),
            child: Text('№ п/п', style: style),
          ),
          Expanded(flex: 3, child: Text('Наименование (рус)', style: style)),
          Expanded(flex: 3, child: Text('Наименование (доп.)', style: style)),
          Expanded(flex: 2, child: Text('Страна', style: style)),
          Expanded(flex: 2, child: Text('Реквизиты', style: style)),
          SizedBox(width: tableGutter(context, 40)),
        ],
      ),
    );
  }

  Widget _recordsList() {
    if (_records.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Записей по выбранному фильтру нет'),
        ),
      );
    }
    return ListView.builder(
      // Виртуализация: строится только видимая часть списка (400-1000 строк).
      itemCount: _records.length,
      itemBuilder: (context, index) {
        final record = _records[index];
        final expanded = _expandedOrgKey == record.orgKey;
        return RecordRow(
          record: record,
          expanded: expanded,
          onToggle: () => setState(
            () => _expandedOrgKey = expanded ? null : record.orgKey,
          ),
          onSave: (values) => _saveCorrection(record, values),
          onRevert: () => _revertCorrection(record),
        );
      },
    );
  }

  Widget _bottomBar(BuildContext context, VersionSummary version) => SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  version.isPublished
                      ? 'Опубликовано '
                          '${formatMoscowDateTime(version.publishedAt)}: '
                          '${version.publishedFileName} '
                          '(${version.confirmedBy ?? '—'})'
                      : 'Файл будет выложен как '
                          '${version.targetFileName}. '
                          'Записей: ${version.counters.total}, '
                          'требуют проверки: ${version.counters.review}.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _publishing || !version.canConfirm ? null : _confirm,
                icon: _publishing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish),
                label: Text(
                  version.isPublished
                      ? 'Опубликовать повторно'
                      : 'Подтвердить и передать в CDI',
                ),
              ),
            ],
          ),
        ),
      );
}
