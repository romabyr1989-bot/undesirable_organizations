/// Мелкие элементы интерфейса: бейджи записей и статусов, плитки счётчиков.
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../util/formatting.dart';

/// Ширина служебных колонок таблицы (№ п/п, стрелка разворота).
///
/// Растёт вместе с масштабом текста: при фиксированной ширине увеличенный
/// шрифт наезжает на соседнюю колонку.
double tableGutter(BuildContext context, double base) =>
    MediaQuery.textScalerOf(context).scale(base);

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
    this.selected = false,
    this.gap = 0,
  });

  final String label;
  final int value;
  final Color? color;
  final VoidCallback? onTap;

  /// Плашка — активный фильтр перечня. Показывается рамкой и заливкой:
  /// галочка внутри плашки только зашумляла ряд.
  final bool selected;

  /// Отступ справа: задаётся плашкой, а не `Wrap.spacing`, чтобы ширина
  /// ряда правильно считалась внутри [IntrinsicWidth].
  final double gap;

  /// Плашка с нулём никуда не ведёт: перечень по ней всё равно пуст.
  bool get enabled => value > 0 && onTap != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective =
        enabled ? color ?? scheme.primary : scheme.onSurfaceVariant;

    final chip = InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: effective.withAlpha(selected ? 51 : 20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? effective : Colors.transparent,
            width: 1.5,
          ),
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
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: enabled ? null : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(right: gap),
      // Заблокированная плашка съедает нажатие пустым обработчиком: без него
      // клик достаётся карточке версии под ней и всё-таки открывает перечень.
      child: enabled
          ? chip
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: chip,
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
    this.selectedFilter,
  });

  final VersionCounters counters;
  final void Function(String filter)? onFilterSelected;

  /// Активный фильтр перечня: плашки заменяют собой отдельный ряд фильтров.
  final String? selectedFilter;

  /// Отступ между плашками задан их собственным полем, а не `Wrap.spacing`:
  /// `spacing` не входит в intrinsic width, и обёртка [IntrinsicWidth]
  /// занижала бы ширину ряда.
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) => Wrap(
        runSpacing: _gap,
        children: [
          CounterChip(
            label: 'всего',
            value: counters.total,
            onTap: () => onFilterSelected?.call('all'),
            gap: _gap,
            selected: selectedFilter == 'all',
          ),
          CounterChip(
            label: 'новых',
            value: counters.added,
            color: const Color(0xFF1B7F3B),
            onTap: () => onFilterSelected?.call('new'),
            gap: _gap,
            selected: selectedFilter == 'new',
          ),
          CounterChip(
            label: 'изменённых',
            value: counters.changed,
            color: const Color(0xFF9A6A00),
            onTap: () => onFilterSelected?.call('changed'),
            gap: _gap,
            selected: selectedFilter == 'changed',
          ),
          CounterChip(
            label: 'исключённых',
            value: counters.excluded,
            color: const Color(0xFF7A7A7A),
            onTap: () => onFilterSelected?.call('excluded'),
            gap: _gap,
            selected: selectedFilter == 'excluded',
          ),
          CounterChip(
            label: 'требуют проверки',
            value: counters.review,
            color: const Color(0xFFB3261E),
            onTap: () => onFilterSelected?.call('review'),
            gap: _gap,
            selected: selectedFilter == 'review',
          ),
          CounterChip(
            label: 'с правками',
            value: counters.edited,
            color: const Color(0xFF1857B6),
            onTap: () => onFilterSelected?.call('edited'),
            selected: selectedFilter == 'edited',
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
