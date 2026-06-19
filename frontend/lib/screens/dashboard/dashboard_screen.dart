import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/providers/schedule_provider.dart';
import 'package:kairos/screens/account/account_screen.dart';
import 'package:kairos/screens/brief/daily_brief_modal.dart';
import 'package:kairos/screens/dashboard/widgets/conflict_banner.dart';
import 'package:kairos/screens/dashboard/widgets/conflict_resolver_sheet.dart';
import 'package:kairos/screens/dashboard/widgets/event_detail_sheet.dart';
import 'package:kairos/screens/dashboard/widgets/month_calendar_view.dart';
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

  @override
  Widget build(BuildContext context) {
    final scheduleState = ref.watch(scheduleProvider);
    final selectedDayBlocks = ref.read(scheduleProvider.notifier).blocksForDay(_selectedDate);
    final conflictGroups = findConflictGroups(selectedDayBlocks);
    final conflictIds = conflictingBlockIds(selectedDayBlocks);
    final monthBlocks = scheduleState.valueOrNull ?? const [];
    final conflictDates = conflictDatesInMonth(monthBlocks);

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
          padding: const EdgeInsets.all(16),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat.yMMMMEEEEd().format(DateTime.now()),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    MonthCalendarView(
                      selectedDate: _selectedDate,
                      blocks: monthBlocks,
                      conflictDates: conflictDates,
                      onDateSelected: (date) {
                        setState(() {
                          _selectedDate = date;
                        });
                      },
                      onMonthChanged: (monthDate) {
                        ref.read(scheduleProvider.notifier).loadMonth(monthDate);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Schedule for ${DateFormat.yMMMd().format(_selectedDate)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (conflictGroups.isNotEmpty) ...[
                      ConflictBanner(
                        groups: conflictGroups,
                        onResolve: () => _openConflictResolver(conflictGroups),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: conflictGroups.isEmpty ? 320 : 360,
                  child: scheduleState.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(child: Text('Failed to load schedule: $error')),
                    data: (_) => TimelineView(
                      blocks: selectedDayBlocks,
                      conflictingIds: conflictIds,
                      onBlockTap: _openEventDetail,
                      onBlockDelete: _confirmDelete,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FloatingActionButton(
                heroTag: 'brief_fab',
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const DailyBriefModal(),
                  );
                },
                backgroundColor: const Color(0xFF4EA1FF),
                foregroundColor: Colors.black,
                child: const Icon(Icons.play_arrow_rounded),
              ),
              FloatingActionButton(
                heroTag: 'add_task_fab',
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => QuickAddSheet(
                      initialDeadline: _selectedDate,
                      onSubmit: (draft) async {
                        final saved = await ref.read(scheduleProvider.notifier).submitTask(draft);
                        if (!context.mounted) {
                          return;
                        }
                        if (!saved) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Saved on this device only — reconnect to sync it to your account.',
                              ),
                            ),
                          );
                        }
                        setState(() {
                          _selectedDate = draft.scheduledAt;
                        });
                      },
                    ),
                  );
                },
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
