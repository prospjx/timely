import 'package:flutter/material.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/screens/dashboard/widgets/calendar_day_cell.dart';
import 'package:kairos/utils/calendar_math.dart';

export 'package:kairos/utils/calendar_math.dart' show CalendarMath, WeekStripMath;

class WeekStripView extends StatelessWidget {
  const WeekStripView({
    super.key,
    required this.selectedDate,
    required this.blocks,
    this.conflictDates = const {},
    required this.pageController,
    required this.onDateSelected,
    required this.onWeekChanged,
  });

  final DateTime selectedDate;
  final List<ScheduleBlock> blocks;
  final Set<DateTime> conflictDates;
  final PageController pageController;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<int> onWeekChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CalendarWeekdayLabels(),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 64,
          child: PageView.builder(
            controller: pageController,
            onPageChanged: onWeekChanged,
            itemBuilder: (context, page) {
              final pageWeekStart = CalendarMath.weekStartForPage(page);
              final days = CalendarMath.daysInWeek(pageWeekStart);
              return Row(
                children: days.map((date) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: CalendarDayCell(
                        date: date,
                        selectedDate: selectedDate,
                        blocks: blocks,
                        conflictDates: conflictDates,
                        onTap: () => onDateSelected(date),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}
