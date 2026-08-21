/// Строка таблицы записей с разворотом и редактированием (п. 10, экран 2).
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../util/formatting.dart';
import 'badges.dart';

class RecordRow extends StatelessWidget {
  const RecordRow({
    super.key,
    required this.record,
    required this.expanded,
    required this.onToggle,
    required this.onSave,
    required this.onRevert,
  });

  final RecordItem record;
  final bool expanded;
  final VoidCallback onToggle;
  final Future<void> Function(Map<String, String> values) onSave;
  final Future<void> Function() onRevert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = record.needsReview
        ? const Color(0xFFB3261E).withAlpha(12)
        : record.isNew
            ? const Color(0xFF1B7F3B).withAlpha(12)
            : null;

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(record.value(RecordField.targetNo)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(record.value(RecordField.nameRus)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(record.value(RecordField.nameAdd)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(record.value(RecordField.country)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          record.value(RecordField.inclOrder),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                      ),
                    ],
                  ),
                  if (record.isNew ||
                      record.isChanged ||
                      record.needsReview ||
                      record.hasEdits ||
                      record.hasStale ||
                      record.isExcluded) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: RecordBadges(record: record),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (expanded)
            _RecordDetails(
              record: record,
              onSave: onSave,
              onRevert: onRevert,
            ),
        ],
      ),
    );
  }
}

class _RecordDetails extends StatefulWidget {
  const _RecordDetails({
    required this.record,
    required this.onSave,
    required this.onRevert,
  });

  final RecordItem record;
  final Future<void> Function(Map<String, String> values) onSave;
  final Future<void> Function() onRevert;

  @override
  State<_RecordDetails> createState() => _RecordDetailsState();
}

class _RecordDetailsState extends State<_RecordDetails> {
  late final Map<RecordField, TextEditingController> _controllers = {
    for (final field in RecordField.values)
      if (field.editable)
        field: TextEditingController(text: widget.record.value(field)),
  };
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _changedValues {
    final values = <String, String>{};
    _controllers.forEach((field, controller) {
      if (controller.text != widget.record.value(field)) {
        values[field.id] = controller.text;
      }
    });
    return values;
  }

  Future<void> _save() async {
    final values = _changedValues;
    if (values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Изменений нет')),
      );
      return;
    }
    setState(() => _saving = true);
    await widget.onSave(values);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = widget.record;
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
      padding: const EdgeInsets.fromLTRB(72, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'Сырая строка первоисточника'),
          SelectableText(record.rawName),
          if (record.previousRawName != null) ...[
            const SizedBox(height: 6),
            _sectionTitle(context, 'Было в предыдущей версии'),
            SelectableText(
              record.previousRawName!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 10),
          _sectionTitle(context, 'Как разобрал автомат'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final candidate in record.candidates)
                Tooltip(
                  message: candidate.excludedReason ?? 'перенесено',
                  child: Chip(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${candidate.kindTitle}: ${candidate.value}',
                      style: TextStyle(
                        fontSize: 11,
                        decoration: candidate.excludedReason == null
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (record.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            NotesLine(notes: record.notes),
          ],
          if (record.hasStale) ...[
            const SizedBox(height: 10),
            _sectionTitle(context, 'Правка, отвязавшаяся от наименования'),
            for (final stale in record.staleCorrections)
              Text(
                '${RecordField.byId(stale.field)?.title ?? stale.field}: '
                '«${stale.value}» — ${stale.author}, '
                '${formatMoscowDateTime(stale.createdAt)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8B2FB0),
                ),
              ),
          ],
          const SizedBox(height: 14),
          _sectionTitle(context, 'Целевые поля'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final entry in _controllers.entries)
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: entry.value,
                    decoration: InputDecoration(
                      labelText: entry.key.title,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      helperText: record.editedFields.contains(entry.key.id)
                          ? 'правка вручную; автоматически: '
                              '«${record.autoValue(entry.key)}»'
                          : null,
                      helperMaxLines: 2,
                      suffixIcon: record.editedFields.contains(entry.key.id)
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Сохранить правку'),
              ),
              OutlinedButton.icon(
                onPressed: _saving || !record.hasEdits
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        await widget.onRevert();
                        if (mounted) setState(() => _saving = false);
                      },
                icon: const Icon(Icons.undo),
                label: const Text('Вернуть авторазбор'),
              ),
              Text(
                'org_key: ${record.orgKey}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}
