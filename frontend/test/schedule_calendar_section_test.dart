import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/core/theme.dart';
import 'package:kairos/screens/dashboard/widgets/schedule_calendar_section.dart';
import 'package:kairos/utils/calendar_math.dart';

void main() {
  Future<void> pumpCalendar(
    WidgetTester tester, {
    required DateTime selectedDate,
    required ValueChanged<DateTime> onDateSelected,
    void Function(DateTime weekStart)? onWeekChanged,
    void Function(DateTime month)? onMonthChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: ScheduleCalendarSection(
            selectedDate: selectedDate,
            blocks: const [],
            onDateSelected: onDateSelected,
            onWeekChanged: onWeekChanged ?? (_) {},
            onMonthChanged: onMonthChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  group('ScheduleCalendarSection', () {
    testWidgets('starts in week view showing the selected date week', (tester) async {
      final selected = DateTime(2026, 6, 18);
      await pumpCalendar(tester, selectedDate: selected, onDateSelected: (_) {});
      await tester.pumpAndSettle();

      expect(find.text('Week view'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('8'), findsNothing);
    });

    testWidgets('switching to month view shows month grid for selected date', (tester) async {
      final selected = DateTime(2026, 6, 18);
      await pumpCalendar(
        tester,
        selectedDate: selected,
        onDateSelected: (_) {},
        onMonthChanged: (_) {},
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Week view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Month view').last);
      await tester.pumpAndSettle();

      expect(find.text('Month view'), findsOneWidget);
      expect(find.text('June 2026'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
    });

    testWidgets('switching back to week view does not crash and keeps selected week', (tester) async {
      final selected = DateTime(2026, 6, 18);
      await pumpCalendar(
        tester,
        selectedDate: selected,
        onDateSelected: (_) {},
        onMonthChanged: (_) {},
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Week view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Month view').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Month view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week view').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('8'), findsNothing);
    });

    testWidgets('selecting a day in month view updates selection callback', (tester) async {
      final selected = DateTime(2026, 6, 18);
      DateTime? picked;

      await pumpCalendar(
        tester,
        selectedDate: selected,
        onDateSelected: (date) => picked = date,
        onMonthChanged: (_) {},
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Week view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Month view').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('25').last);
      await tester.pumpAndSettle();

      expect(picked, DateTime(2026, 6, 25));
    });

    testWidgets('week chevrons move to adjacent weeks', (tester) async {
      final selected = DateTime(2026, 6, 15);
      final requestedWeeks = <DateTime>[];

      await pumpCalendar(
        tester,
        selectedDate: selected,
        onDateSelected: (_) {},
        onWeekChanged: requestedWeeks.add,
      );
      await tester.pumpAndSettle();

      expect(find.text('15'), findsOneWidget);
      expect(find.text('22'), findsNothing);

      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();

      expect(requestedWeeks.isNotEmpty, isTrue);
      expect(find.text('22'), findsOneWidget);
      expect(find.text('15'), findsNothing);

      await tester.tap(find.byTooltip('Previous week'));
      await tester.pumpAndSettle();

      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('month chevrons request adjacent months', (tester) async {
      final selected = DateTime(2026, 6, 18);
      final requestedMonths = <DateTime>[];

      await pumpCalendar(
        tester,
        selectedDate: selected,
        onDateSelected: (_) {},
        onMonthChanged: requestedMonths.add,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Week view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Month view').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();

      expect(requestedMonths.last, DateTime(2026, 7));
      expect(find.text('July 2026'), findsOneWidget);
    });
  });

  test('selected date week math matches widget expectations for June 18 2026', () {
    final weekStart = CalendarMath.startOfWeek(DateTime(2026, 6, 18));
    expect(weekStart, DateTime.utc(2026, 6, 15));
    expect(CalendarMath.weekContainsDate(weekStart, DateTime(2026, 6, 18)), isTrue);
    expect(CalendarMath.weekContainsDate(weekStart, DateTime(2026, 6, 8)), isFalse);
  });
}
