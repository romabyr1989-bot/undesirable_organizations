/// Экран 3. Журнал событий (п. 10 ТЗ).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app.dart';
import '../models/models.dart';
import '../util/formatting.dart';
import '../widgets/badges.dart';
import '../widgets/record_editor.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key, required this.api});

  final PerechenApi api;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<EventItem> _events = const [];
  bool _loading = true;
  String? _error;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _load();
    _autoRefresh = Timer.periodic(
      autoRefreshInterval,
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  /// [silent] — фоновое обновление: без крутилки и без подмены показанного
  /// журнала сообщением, если запрос не прошёл.
  Future<void> _load({bool silent = false}) async {
    if (silent && _loading) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final events = await widget.api.events();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _error = 'Ошибка загрузки журнала: ${error.message}';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Журнал событий'),
          // Без кнопок справа Material центрирует заголовок — на остальных
          // экранах он слева, держим одинаково.
          centerTitle: false,
          // Шапка таблицы — часть панели приложения: так она гарантированно
          // остаётся на месте при прокрутке списка.
          bottom: _loading || _error != null || _events.isEmpty
              ? null
              : PreferredSize(
                  preferredSize: Size.fromHeight(
                    MediaQuery.textScalerOf(context).scale(34),
                  ),
                  child: _header(context),
                ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _events.isEmpty
                    ? const Center(child: Text('Событий пока нет'))
                    : ListView.separated(
                        itemCount: _events.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _row(context, _events[index]),
                      ),
      );

  Widget _header(BuildContext context) {
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
            width: tableGutter(context, 150),
            child: Text('Время', style: style),
          ),
          Expanded(flex: 3, child: Text('Событие', style: style)),
          SizedBox(
            width: tableGutter(context, 70),
            child: Text('Версия', style: style),
          ),
          Expanded(flex: 6, child: Text('Подробности', style: style)),
        ],
      ),
    );
  }

  /// Строка журнала. Переходов отсюда нет: журнал — это отчёт, а не навигация.
  Widget _row(BuildContext context, EventItem event) {
    final theme = Theme.of(context);
    final color = event.isError ? theme.colorScheme.error : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: tableGutter(context, 150),
            child: EllipsisCell(
              formatMoscowDateTime(event.timestamp),
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  event.isError
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  size: MediaQuery.textScalerOf(context).scale(16),
                  color: color ?? theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: EllipsisCell(
                    event.title,
                    style: TextStyle(color: color),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: tableGutter(context, 70),
            child: Text(
              // Событие может быть не привязано к версии — тогда ячейка
              // просто пустая, прочерк здесь ничего не сообщает.
              event.versionId?.toString() ?? '',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 6,
            child: EllipsisCell(
              eventDetails(event.type, event.payload),
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
