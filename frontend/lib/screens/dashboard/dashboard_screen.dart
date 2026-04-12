import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/providers/schedule_provider.dart';
import 'package:kairos/screens/brief/daily_brief_modal.dart';
import 'package:kairos/screens/dashboard/widgets/month_calendar_view.dart';
import 'package:kairos/screens/dashboard/widgets/timeline_view.dart';
import 'package:kairos/screens/input/quick_add_sheet.dart';
import 'package:kairos/services/notification_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final scheduleState = ref.watch(scheduleProvider);
    final selectedDayBlocks = ref.read(scheduleProvider.notifier).blocksForDay(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Timely'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: CustomScrollView(
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
                    blocks: scheduleState.valueOrNull ?? const [],
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
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 320,
                child: scheduleState.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(child: Text('Failed to load schedule: $error')),
                  data: (_) => TimelineView(blocks: selectedDayBlocks),
                ),
              ),
            ),
          ],
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
                        await ref.read(scheduleProvider.notifier).submitTask(draft);
                        setState(() {
                          _selectedDate = draft.deadline;
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
