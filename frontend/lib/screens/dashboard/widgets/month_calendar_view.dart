import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kairos/models/schedule_block.dart';

class MonthCalendarView extends StatefulWidget {
  const MonthCalendarView({
    super.key,
    this.focusedDate,
    required this.selectedDate,
    required this.blocks,
    this.conflictDates = const {},
    required this.onDateSelected,
    required this.onMonthChanged,
  });

  final DateTime? focusedDate;
  final DateTime selectedDate;
  final List<ScheduleBlock> blocks;
  final Set<DateTime> conflictDates;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  State<MonthCalendarView> createState() => _MonthCalendarViewState();
}

class _MonthCalendarViewState extends State<MonthCalendarView> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = widget.focusedDate ?? DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final leadingEmptyCells = (firstDayOfMonth.weekday + 6) % 7;
    final totalCells = leadingEmptyCells + daysInMonth;
    final trailingEmptyCells = (7 - (totalCells % 7)) % 7;
    final totalGridItems = totalCells + trailingEmptyCells;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
                  widget.onMonthChanged(_visibleMonth);
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM().format(_visibleMonth),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
                  widget.onMonthChanged(_visibleMonth);
                }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(
            color: Colors.white.withValues(alpha: 0.08),
            height: 1,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _WeekdayLabel('Mon'),
              _WeekdayLabel('Tue'),
              _WeekdayLabel('Wed'),
              _WeekdayLabel('Thu'),
              _WeekdayLabel('Fri'),
              _WeekdayLabel('Sat'),
              _WeekdayLabel('Sun'),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: totalGridItems,
            itemBuilder: (context, index) {
              if (index < leadingEmptyCells || index >= leadingEmptyCells + daysInMonth) {
                return const SizedBox.shrink();
              }

              final day = index - leadingEmptyCells + 1;
              final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
              final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
              final isSelected = date.year == widget.selectedDate.year &&
                  date.month == widget.selectedDate.month &&
                  date.day == widget.selectedDate.day;
              final eventCount = widget.blocks.where((block) => block.occursOnDate(date)).length;
              final hasConflict = widget.conflictDates.any(
                (conflictDate) =>
                    conflictDate.year == date.year &&
                    conflictDate.month == date.month &&
                    conflictDate.day == date.day,
              );

              return InkWell(
                onTap: () => widget.onDateSelected(date),
                borderRadius: BorderRadius.zero,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF001515),
                    borderRadius: BorderRadius.zero,
                    border: Border.all(
                      color: isSelected || isToday
                          ? const Color(0xFF667373)
                          : const Color(0xFF3F4C4C),
                      width: isSelected || isToday ? 1.4 : 0.9,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: (isToday || isSelected) ? Colors.white : Colors.white70,
                              fontWeight: (isToday || isSelected) ? FontWeight.w700 : FontWeight.w400,
                            ),
                      ),
                      if (eventCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasConflict)
                                Container(
                                  margin: const EdgeInsets.only(right: 2),
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF6B6B),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ...List.generate(
                                eventCount > 3 ? 3 : eventCount,
                                (_) => Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: hasConflict ? Colors.white70 : Colors.white,
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
            },
          ),
        ],
      ),
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
                color: Colors.white54,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}