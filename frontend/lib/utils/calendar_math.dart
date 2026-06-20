import 'package:flutter/material.dart';

/// Monday-based calendar helpers shared by week strip and month grid.
///
/// All date math uses UTC date-only values so week paging stays stable across
/// daylight-saving transitions.
class CalendarMath {
  CalendarMath._();

  static final epochMonday = DateTime.utc(2020, 1, 6);
  static const centerPage = 10000;

  static DateTime normalize(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  static DateTime startOfWeek(DateTime date) {
    final normalized = normalize(date);
    final offset = (normalized.weekday + 6) % 7;
    return normalized.subtract(Duration(days: offset));
  }

  static int pageForDate(DateTime date) {
    final weekStart = startOfWeek(date);
    final weeks = weekStart.difference(epochMonday).inDays ~/ 7;
    return centerPage + weeks;
  }

  static DateTime weekStartForPage(int page) {
    return epochMonday.add(Duration(days: (page - centerPage) * 7));
  }

  static List<DateTime> daysInWeek(DateTime weekStart) {
    return List.generate(7, (index) => weekStart.add(Duration(days: index)));
  }

  static bool weekSpansTwoMonths(DateTime weekStart) {
    final end = weekStart.add(const Duration(days: 6));
    return weekStart.month != end.month || weekStart.year != end.year;
  }

  static bool weekContainsDate(DateTime weekStart, DateTime date) {
    final normalized = normalize(date);
    final end = weekStart.add(const Duration(days: 6));
    return !normalized.isBefore(weekStart) && !normalized.isAfter(end);
  }

  static DateTime monthStart(DateTime date) {
    return DateTime.utc(date.year, date.month);
  }

  static int monthKey(DateTime date) => date.year * 100 + date.month;

  static int monthGridCellCount(DateTime month) {
    final firstDayOfMonth = DateTime.utc(month.year, month.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final leadingEmptyCells = (firstDayOfMonth.weekday + 6) % 7;
    final totalCells = leadingEmptyCells + daysInMonth;
    final trailingEmptyCells = (7 - (totalCells % 7)) % 7;
    return totalCells + trailingEmptyCells;
  }

  static int monthGridWeekRows(DateTime month) => monthGridCellCount(month) ~/ 7;

  static Iterable<DateTime> monthsToCoverWeek(DateTime weekStart) sync* {
    yield monthStart(weekStart);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final endMonth = monthStart(weekEnd);
    if (monthKey(endMonth) != monthKey(weekStart)) {
      yield endMonth;
    }
  }
}

// Backwards-compatible alias used by dashboard widgets.
typedef WeekStripMath = CalendarMath;
