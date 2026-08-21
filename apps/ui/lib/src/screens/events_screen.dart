/// Экран 3. Журнал событий (п. 10 ТЗ).
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../util/formatting.dart';

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
      final events = await widget.api.events();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
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
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Обновить',
            ),
            const SizedBox(width: 8),
          ],
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
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          return ListTile(
                            leading: Icon(
                              event.isError
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              color: event.isError
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(event.title),
                            subtitle: Text(
                              '${formatMoscowDateTime(event.timestamp)}'
                              '${event.versionId == null ? '' : ' · версия '
                                  '${event.versionId}'}'
                              '${event.payload.isEmpty ? '' : '\n'
                                  '${jsonEncode(event.payload)}'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            isThreeLine: event.payload.isNotEmpty,
                            onTap: event.versionId == null
                                ? null
                                : () => Navigator.of(context)
                                    .pushNamed('/versions/${event.versionId}'),
                          );
                        },
                      ),
      );
}
