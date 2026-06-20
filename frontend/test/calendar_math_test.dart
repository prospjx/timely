import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/utils/calendar_math.dart';

void main() {
  group('CalendarMath.startOfWeek', () {
    test('uses Monday as week start', () {
      // Saturday June 20, 2026
      final start = CalendarMath.startOfWeek(DateTime(2026, 6, 20));
      expect(start, DateTime.utc(2026, 6, 15));
      expect(start.weekday, DateTime.monday);
    });

    test('Monday stays on same day', () {
      final monday = DateTime.utc(2026, 6, 15);
      expect(CalendarMath.startOfWeek(monday), monday);
    });

    test('Sunday maps to previous Monday', () {
      final start = CalendarMath.startOfWeek(DateTime(2026, 6, 21));
      expect(start, DateTime.utc(2026, 6, 15));
    });
  });

  group('CalendarMath page round-trip', () {
    test('pageForDate and weekStartForPage are inverses', () {
      for (final date in [
        DateTime(2026, 6, 20),
        DateTime(2026, 6, 18),
        DateTime(2026, 1, 1),
        DateTime(2024, 2, 29),
        DateTime(2020, 1, 6),
      ]) {
        final page = CalendarMath.pageForDate(date);
        final weekStart = CalendarMath.weekStartForPage(page);
        expect(
          weekStart,
          CalendarMath.startOfWeek(date),
          reason: 'Failed for $date',
        );
      }
    });

    test('June 18 2026 week is Mon 15 through Sun 21', () {
      final page = CalendarMath.pageForDate(DateTime(2026, 6, 18));
      final days = CalendarMath.daysInWeek(CalendarMath.weekStartForPage(page));
      expect(days.first, DateTime.utc(2026, 6, 15));
      expect(days.last, DateTime.utc(2026, 6, 21));
      expect(days.any((day) => day.day == 18), isTrue);
      expect(days.any((day) => day.day == 8), isFalse);
    });
  });

  group('CalendarMath.weekContainsDate', () {
    test('returns true for dates in the same week', () {
      final weekStart = DateTime.utc(2026, 6, 15);
      expect(CalendarMath.weekContainsDate(weekStart, DateTime(2026, 6, 18)), isTrue);
      expect(CalendarMath.weekContainsDate(weekStart, DateTime(2026, 6, 15)), isTrue);
      expect(CalendarMath.weekContainsDate(weekStart, DateTime(2026, 6, 21)), isTrue);
    });

    test('returns false for adjacent weeks', () {
      final weekStart = DateTime.utc(2026, 6, 15);
      expect(CalendarMath.weekContainsDate(weekStart, DateTime(2026, 6, 14)), isFalse);
      expect(CalendarMath.weekContainsDate(weekStart, DateTime(2026, 6, 22)), isFalse);
    });
  });

  group('CalendarMath.monthsToCoverWeek', () {
    test('returns one month for an in-month week', () {
      final months = CalendarMath.monthsToCoverWeek(DateTime.utc(2026, 6, 15)).toList();
      expect(months, [DateTime.utc(2026, 6)]);
    });

    test('returns two months for a boundary week', () {
      final months = CalendarMath.monthsToCoverWeek(DateTime.utc(2026, 6, 29)).toList();
      expect(months, [DateTime.utc(2026, 6), DateTime.utc(2026, 7)]);
    });
  });

  group('CalendarMath month grid', () {
    test('June 2026 uses 5 week rows', () {
      expect(CalendarMath.monthGridWeekRows(DateTime.utc(2026, 6)), 5);
    });

    test('month grid cell count is a multiple of 7', () {
      for (var month = 1; month <= 12; month++) {
        final cells = CalendarMath.monthGridCellCount(DateTime(2026, month));
        expect(cells % 7, 0, reason: 'Month $month should fill whole weeks');
      }
    });
  });
}
