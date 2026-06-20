import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/models/task.dart';
import 'package:kairos/providers/schedule_provider.dart';
import 'package:kairos/screens/account/account_screen.dart';
import 'package:kairos/screens/brief/daily_brief_modal.dart';
import 'package:kairos/screens/dashboard/widgets/conflict_banner.dart';
import 'package:kairos/screens/dashboard/widgets/conflict_resolver_sheet.dart';
import 'package:kairos/screens/dashboard/widgets/dashboard_greeting_header.dart';
import 'package:kairos/screens/dashboard/widgets/event_detail_sheet.dart';
import 'package:kairos/screens/dashboard/widgets/schedule_calendar_section.dart';
import 'package:kairos/screens/dashboard/widgets/timeline_view.dart';
import 'package:kairos/screens/input/quick_add_sheet.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/utils/schedule_conflicts.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationServiceProvider).initialize();
      ref.read(scheduleProvider.notifier).loadMonth(_selectedDate);
    });
  }

  Future<void> _openEventDetail(ScheduleBlock block) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EventDetailSheet(block: block),
    );

    if (updated == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _confirmDelete(ScheduleBlock block) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text('Remove "${block.title}" from your schedule?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await ref.read(scheduleProvider.notifier).deleteBlock(block);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${block.title} deleted')),
      );
    }
  }

  Future<void> _openConflictResolver(List<ConflictGroup> groups) async {
    final resolved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ConflictResolverSheet(
        date: _selectedDate,
        groups: groups,
        onAutoResolve: (priorityBlockIds) {
          return ref.read(scheduleProvider.notifier).resolveDayConflicts(
                date: _selectedDate,
                priorityBlockIds: priorityBlockIds,
              );
        },
        onReschedule: (block, start, end) {
          return ref.read(scheduleProvider.notifier).rescheduleBlock(
                block: block,
                startTime: start,
                endTime: end,
              );
        },
        onSync: (block) {
          return ref.read(scheduleProvider.notifier).syncLocalBlock(block);
        },
      ),
    );

    if (resolved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schedule updated')),
      );
    }
  }

  void _openDailyBrief() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const DailyBriefModal(),
    );
  }

  void _openQuickAdd() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => QuickAddSheet(
        initialDeadline: _selectedDate,
        onSubmit: (draft) async {
          final saved = await ref.read(scheduleProvider.notifier).submitTask(draft);
          if (!sheetContext.mounted) {
            return;
          }
          if (!saved) {
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                content: Text(
                  draft.timingType == TaskTimingType.deadline
                      ? 'Saved on this device only. AI scheduling needs the backend — tap the event and use Save to account when connected.'
                      : 'Saved on this device only — reconnect to sync it to your account.',
                ),
              ),
            );
          }
          if (mounted) {
            setState(() {
              _selectedDate = draft.scheduledAt;
            });
          }
        },
      ),
    );
  }

  void _onWeekChanged(DateTime weekStart) {
    ref.read(scheduleProvider.notifier).loadMonthsForWeek(weekStart);
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    ref.read(scheduleProvider.notifier).loadMonthIfNeeded(date);
  }

  void _onMonthChanged(DateTime monthDate) {
    ref.read(scheduleProvider.notifier).loadMonth(monthDate);
  }

  @override
  Widget build(BuildContext context) {
    final scheduleState = ref.watch(scheduleProvider);
    final monthBlocks = scheduleState.valueOrNull ?? const [];
    final selectedDayBlocks = monthBlocks.where((block) => block.occursOnDate(_selectedDate)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final conflictGroups = findConflictGroups(selectedDayBlocks);
    final conflictIds = conflictingBlockIds(selectedDayBlocks);
    final conflictDates = conflictDatesInMonth(monthBlocks);
    final fabClearance = MediaQuery.paddingOf(context).bottom + 80;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Timely'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen()));
            },
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Account',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(scheduleProvider.notifier).refreshSchedule(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: DashboardGreetingHeader(
                  selectedDate: _selectedDate,
                  onPlayBrief: _openDailyBrief,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              SliverToBoxAdapter(
                child: ScheduleCalendarSection(
                  selectedDate: _selectedDate,
                  blocks: monthBlocks,
                  conflictDates: conflictDates,
                  onDateSelected: _onDateSelected,
                  onWeekChanged: _onWeekChanged,
                  onMonthChanged: _onMonthChanged,
                ),
              ),
              if (conflictGroups.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
                SliverToBoxAdapter(
                  child: ConflictBanner(
                    groups: conflictGroups,
                    onResolve: () => _openConflictResolver(conflictGroups),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm + 4)),
              SliverFillRemaining(
                hasScrollBody: true,
                child: scheduleState.when(
                  loading: () => monthBlocks.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : TimelineView(
                          blocks: selectedDayBlocks,
                          conflictingIds: conflictIds,
                          onBlockTap: _openEventDetail,
                          onBlockDelete: _confirmDelete,
                          bottomPadding: fabClearance,
                        ),
                  error: (error, _) => Center(child: Text('Failed to load schedule: $error')),
                  data: (_) => TimelineView(
                    blocks: selectedDayBlocks,
                    conflictingIds: conflictIds,
                    onBlockTap: _openEventDetail,
                    onBlockDelete: _confirmDelete,
                    bottomPadding: fabClearance,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: _openQuickAdd,
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
    );
  }
}
