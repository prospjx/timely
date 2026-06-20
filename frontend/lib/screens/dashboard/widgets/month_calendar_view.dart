import 'package:flutter/material.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/screens/dashboard/widgets/calendar_day_cell.dart';
import 'package:kairos/utils/calendar_math.dart';

class MonthCalendarView extends StatelessWidget {
  const MonthCalendarView({
    super.key,
    required this.visibleMonth,
    required this.selectedDate,
    required this.blocks,
    this.conflictDates = const {},
    required this.onDateSelected,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final List<ScheduleBlock> blocks;
  final Set<DateTime> conflictDates;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final month = CalendarMath.monthStart(visibleMonth);
    final firstDayOfMonth = month;
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final leadingEmptyCells = (firstDayOfMonth.weekday + 6) % 7;
    final totalGridItems = CalendarMath.monthGridCellCount(month);
    final weekRows = CalendarMath.monthGridWeekRows(month);

    return LayoutBuilder(
      builder: (context, constraints) {
        const crossSpacing = AppSpacing.sm;
        const mainSpacing = AppSpacing.sm;
        final cellWidth = (constraints.maxWidth - crossSpacing * 6) / 7;
        final cellHeight = (cellWidth * 0.82).clamp(32.0, 44.0);
        final gridHeight = weekRows * cellHeight + (weekRows - 1) * mainSpacing;

        return Column(
          children: [
            const CalendarWeekdayLabels(),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: gridHeight,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: mainSpacing,
                  crossAxisSpacing: crossSpacing,
                  mainAxisExtent: cellHeight,
                ),
                itemCount: totalGridItems,
                itemBuilder: (context, index) {
                  if (index < leadingEmptyCells || index >= leadingEmptyCells + daysInMonth) {
                    return const SizedBox.shrink();
                  }

                  final day = index - leadingEmptyCells + 1;
                  final date = DateTime(month.year, month.month, day);

                  return CalendarDayCell(
                    date: date,
                    selectedDate: selectedDate,
                    blocks: blocks,
                    conflictDates: conflictDates,
                    onTap: () => onDateSelected(date),
                    borderRadius: 4,
                    compact: true,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
