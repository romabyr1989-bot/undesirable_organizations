/// Мелкие элементы интерфейса: бейджи записей и статусов, плитки счётчиков.
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../util/formatting.dart';

/// Цветной бейдж.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withAlpha(31),
          border: Border.all(color: color.withAlpha(128)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

/// Бейджи записи: новая / изменена / review / правка / stale.
class RecordBadges extends StatelessWidget {
  const RecordBadges({super.key, required this.record});

  final RecordItem record;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      if (record.isNew)
        const StatusBadge(
          text: 'новая',
          color: Color(0xFF1B7F3B),
          icon: Icons.fiber_new,
        ),
      if (record.isChanged)
        const StatusBadge(
          text: 'изменена',
          color: Color(0xFF9A6A00),
          icon: Icons.edit_note,
        ),
      if (record.isExcluded)
        const StatusBadge(
          text: 'исключена',
          color: Color(0xFF7A7A7A),
          icon: Icons.remove_circle_outline,
        ),
      if (record.needsReview)
        const StatusBadge(
          text: 'требует проверки',
          color: Color(0xFFB3261E),
          icon: Icons.help_outline,
        ),
      if (record.hasEdits)
        const StatusBadge(
          text: 'правка вручную',
          color: Color(0xFF1857B6),
          icon: Icons.person,
        ),
      if (record.hasStale)
        const StatusBadge(
          text: 'stale-правка',
          color: Color(0xFF8B2FB0),
          icon: Icons.link_off,
        ),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: badges);
  }
}

/// Бейдж статуса версии.
class VersionStatusBadge extends StatelessWidget {
  const VersionStatusBadge({super.key, required this.version});

  final VersionSummary version;

  @override
  Widget build(BuildContext context) {
    final color = switch (version.status) {
      'PUBLISHED' => const Color(0xFF1B7F3B),
      'ERROR' => const Color(0xFFB3261E),
      'PENDING_REVIEW' => const Color(0xFF9A6A00),
      _ => const Color(0xFF5A6472),
    };
    return StatusBadge(text: version.statusTitle, color: color);
  }
}

/// Плитка счётчика версии.
class CounterChip extends StatelessWidget {
  const CounterChip({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  final String label;
  final int value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effective = color ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: effective.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: effective,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Строка счётчиков версии.
class CountersRow extends StatelessWidget {
  const CountersRow({
    super.key,
    required this.counters,
    this.onFilterSelected,
  });

  final VersionCounters counters;
  final void Function(String filter)? onFilterSelected;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          CounterChip(
            label: 'всего',
            value: counters.total,
            onTap: () => onFilterSelected?.call('all'),
          ),
          CounterChip(
            label: 'новых',
            value: counters.added,
            color: const Color(0xFF1B7F3B),
            onTap: () => onFilterSelected?.call('new'),
          ),
          CounterChip(
            label: 'изменённых',
            value: counters.changed,
            color: const Color(0xFF9A6A00),
            onTap: () => onFilterSelected?.call('changed'),
          ),
          CounterChip(
            label: 'исключённых',
            value: counters.excluded,
            color: const Color(0xFF7A7A7A),
            onTap: () => onFilterSelected?.call('excluded'),
          ),
          CounterChip(
            label: 'требуют проверки',
            value: counters.review,
            color: const Color(0xFFB3261E),
            onTap: () => onFilterSelected?.call('review'),
          ),
          CounterChip(
            label: 'с правками',
            value: counters.edited,
            color: const Color(0xFF1857B6),
            onTap: () => onFilterSelected?.call('edited'),
          ),
        ],
      );
}

/// Список пометок автоматического разбора.
class NotesLine extends StatelessWidget {
  const NotesLine({super.key, required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return Text(
      notes.map(noteTitle).join('; '),
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
