import 'package:flutter/material.dart';
import 'package:kairos/core/timely_theme_extension.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/utils/block_colors.dart';

class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    super.key,
    required this.date,
    required this.selectedDate,
    required this.blocks,
    required this.conflictDates,
    required this.onTap,
    this.borderRadius = 8,
    this.compact = false,
  });

  final DateTime date;
  final DateTime selectedDate;
  final List<ScheduleBlock> blocks;
  final Set<DateTime> conflictDates;
  final VoidCallback onTap;
  final double borderRadius;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final timely = context.timelyColors;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final isSelected = date.year == selectedDate.year &&
        date.month == selectedDate.month &&
        date.day == selectedDate.day;
    final dayBlocks = blocks.where((block) => block.occursOnDate(date)).toList();
    final hasConflict = conflictDates.any(
      (conflictDate) =>
          conflictDate.year == date.year &&
          conflictDate.month == date.month &&
          conflictDate.day == date.day,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? timely.primary.withValues(alpha: 0.12) : timely.calendarCell,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: isSelected || isToday ? timely.primary : timely.calendarBorder,
            width: isSelected || isToday ? 1.4 : 0.9,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${date.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isSelected || isToday
                    ? timely.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.85),
                fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w400,
                fontSize: compact ? 13 : null,
              ),
            ),
            if (dayBlocks.isNotEmpty || hasConflict)
              Padding(
                padding: EdgeInsets.only(top: compact ? 1 : 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasConflict)
                      Container(
                        margin: const EdgeInsets.only(right: 2),
                        width: compact ? 3 : 4,
                        height: compact ? 3 : 4,
                        decoration: BoxDecoration(
                          color: timely.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ...dayBlocks.take(compact ? 2 : 3).map(
                          (block) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            width: compact ? 3 : 4,
                            height: compact ? 3 : 4,
                            decoration: BoxDecoration(
                              color: blockColorFor(block, timely),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CalendarWeekdayLabels extends StatelessWidget {
  const CalendarWeekdayLabels({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _WeekdayLabel('Mon'),
        _WeekdayLabel('Tue'),
        _WeekdayLabel('Wed'),
        _WeekdayLabel('Thu'),
        _WeekdayLabel('Fri'),
        _WeekdayLabel('Sat'),
        _WeekdayLabel('Sun'),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.timelyColors.onSurfaceMuted,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
