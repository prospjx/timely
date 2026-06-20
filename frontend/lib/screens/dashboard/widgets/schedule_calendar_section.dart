import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/screens/dashboard/widgets/month_calendar_view.dart';
import 'package:kairos/screens/dashboard/widgets/week_strip_view.dart';

enum CalendarViewMode { week, month }

class ScheduleCalendarSection extends StatefulWidget {
  const ScheduleCalendarSection({
    super.key,
    required this.selectedDate,
    required this.blocks,
    this.conflictDates = const {},
    required this.onDateSelected,
    required this.onWeekChanged,
    required this.onMonthChanged,
  });

  final DateTime selectedDate;
  final List<ScheduleBlock> blocks;
  final Set<DateTime> conflictDates;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onWeekChanged;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  State<ScheduleCalendarSection> createState() => _ScheduleCalendarSectionState();
}

class _ScheduleCalendarSectionState extends State<ScheduleCalendarSection> {
  CalendarViewMode _viewMode = CalendarViewMode.week;
  late PageController _weekPageController;
  late int _weekPage;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _weekPage = CalendarMath.pageForDate(widget.selectedDate);
    _weekPageController = PageController(initialPage: _weekPage);
    _visibleMonth = CalendarMath.monthStart(widget.selectedDate);
  }

  @override
  void dispose() {
    _weekPageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ScheduleCalendarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedWeek = CalendarMath.startOfWeek(widget.selectedDate);
    final visibleWeek = CalendarMath.weekStartForPage(_weekPage);

    if (_viewMode == CalendarViewMode.week &&
        !CalendarMath.weekContainsDate(visibleWeek, widget.selectedDate)) {
      _syncWeekPage(CalendarMath.pageForDate(widget.selectedDate));
    } else if (_viewMode == CalendarViewMode.week &&
        !CalendarMath.startOfWeek(oldWidget.selectedDate).isAtSameMomentAs(selectedWeek)) {
      _syncWeekPage(CalendarMath.pageForDate(widget.selectedDate));
    }

    final selectedMonth = CalendarMath.monthStart(widget.selectedDate);
    if (_viewMode == CalendarViewMode.month &&
        oldWidget.selectedDate.month != widget.selectedDate.month &&
        CalendarMath.monthKey(oldWidget.selectedDate) != CalendarMath.monthKey(widget.selectedDate)) {
      _visibleMonth = selectedMonth;
    }
  }

  void _syncWeekPage(int page) {
    _weekPage = page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_weekPageController.hasClients) {
        return;
      }
      final current = _weekPageController.page?.round();
      if (current == page) {
        return;
      }
      _weekPageController.jumpToPage(page);
    });
  }

  DateTime get _visibleWeekStart => CalendarMath.weekStartForPage(_weekPage);

  String get _headerLabel {
    if (_viewMode == CalendarViewMode.month) {
      return DateFormat.yMMMM().format(_visibleMonth);
    }

    if (CalendarMath.weekSpansTwoMonths(_visibleWeekStart)) {
      final weekEnd = _visibleWeekStart.add(const Duration(days: 6));
      return '${DateFormat.MMMd().format(_visibleWeekStart)} – ${DateFormat.MMMd().format(weekEnd)}';
    }
    return DateFormat.yMMMM().format(_visibleWeekStart);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
    widget.onMonthChanged(_visibleMonth);
  }

  void _shiftWeek(int delta) {
    final nextPage = _weekPage + delta;
    setState(() => _weekPage = nextPage);
    widget.onWeekChanged(CalendarMath.weekStartForPage(nextPage));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_weekPageController.hasClients) {
        return;
      }
      final current = _weekPageController.page?.round();
      if (current == nextPage) {
        return;
      }
      _weekPageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleWeekPageChanged(int page) {
    setState(() => _weekPage = page);
    widget.onWeekChanged(CalendarMath.weekStartForPage(page));
  }

  void _handleViewModeChanged(CalendarViewMode? mode) {
    if (mode == null || mode == _viewMode) {
      return;
    }

    if (mode == CalendarViewMode.month) {
      setState(() {
        _viewMode = mode;
        _visibleMonth = CalendarMath.monthStart(widget.selectedDate);
      });
      widget.onMonthChanged(_visibleMonth);
      return;
    }

    final targetPage = CalendarMath.pageForDate(widget.selectedDate);
    setState(() => _viewMode = CalendarViewMode.week);
    _syncWeekPage(targetPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onWeekChanged(_visibleWeekStart);
    });
  }

  @override
  Widget build(BuildContext context) {
    final timely = context.timelyColors;
    final isMonthView = _viewMode == CalendarViewMode.month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: isMonthView ? () => _shiftMonth(-1) : () => _shiftWeek(-1),
              icon: const Icon(Icons.chevron_left),
              visualDensity: VisualDensity.compact,
              tooltip: isMonthView ? 'Previous month' : 'Previous week',
            ),
            Expanded(
              child: Text(
                _headerLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: timely.onSurfaceMuted,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            IconButton(
              onPressed: isMonthView ? () => _shiftMonth(1) : () => _shiftWeek(1),
              icon: const Icon(Icons.chevron_right),
              visualDensity: VisualDensity.compact,
              tooltip: isMonthView ? 'Next month' : 'Next week',
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<CalendarViewMode>(
                value: _viewMode,
                isDense: true,
                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                icon: Icon(Icons.expand_more, color: timely.onSurfaceMuted, size: 20),
                style: Theme.of(context).textTheme.labelLarge,
                onChanged: _handleViewModeChanged,
                items: const [
                  DropdownMenuItem(
                    value: CalendarViewMode.week,
                    child: Text('Week view'),
                  ),
                  DropdownMenuItem(
                    value: CalendarViewMode.month,
                    child: Text('Month view'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _viewMode == CalendarViewMode.week
              ? WeekStripView(
                  key: const ValueKey('week-strip'),
                  selectedDate: widget.selectedDate,
                  blocks: widget.blocks,
                  conflictDates: widget.conflictDates,
                  pageController: _weekPageController,
                  onDateSelected: widget.onDateSelected,
                  onWeekChanged: _handleWeekPageChanged,
                )
              : MonthCalendarView(
                  key: ValueKey('month-${_visibleMonth.year}-${_visibleMonth.month}'),
                  visibleMonth: _visibleMonth,
                  selectedDate: widget.selectedDate,
                  blocks: widget.blocks,
                  conflictDates: widget.conflictDates,
                  onDateSelected: widget.onDateSelected,
                ),
        ),
      ],
    );
  }
}
