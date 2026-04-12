import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/models/task.dart';
import 'package:kairos/services/api_service.dart';

final scheduleProvider =
    AsyncNotifierProvider<ScheduleNotifier, List<ScheduleBlock>>(
  ScheduleNotifier.new,
);

class ScheduleNotifier extends AsyncNotifier<List<ScheduleBlock>> {
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Future<List<ScheduleBlock>> build() {
    return _loadSchedule();
  }

  Future<List<ScheduleBlock>> _loadSchedule() {
    return _loadScheduleEnsuringDemoData();
  }

  Future<List<ScheduleBlock>> _loadScheduleEnsuringDemoData() async {
    final api = ref.read(apiServiceProvider);
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;

    try {
      final live = await api.getMonthSchedule(year: year, month: month);
      if (live.isNotEmpty) {
        return live;
      }

      try {
        await api.seedDemoSchedule(year: year, month: month);
        final seeded = await api.getMonthSchedule(year: year, month: month);
        if (seeded.isNotEmpty) {
          return seeded;
        }
      } catch (_) {
        // Fall through to local demo blocks.
      }
    } catch (_) {
      // Fall through to local demo blocks.
    }

    return _localDemoBlocksForMonth(_visibleMonth);
  }

  Future<void> refreshSchedule() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      _loadSchedule,
    );
  }

  Future<void> loadMonth(DateTime monthDate) async {
    _visibleMonth = DateTime(monthDate.year, monthDate.month);
    await refreshSchedule();
  }

  Future<void> submitTask(TaskDraft draft) async {
    final api = ref.read(apiServiceProvider);
    try {
      final createdBlock = await api.submitTaskDraft(draft);
      final currentBlocks = state.valueOrNull ?? <ScheduleBlock>[];
      state = AsyncData(<ScheduleBlock>[createdBlock, ...currentBlocks]);
      await refreshSchedule();
    } catch (_) {
      final localBlock = _localBlockFromDraft(draft);
      final currentBlocks = state.valueOrNull ?? <ScheduleBlock>[];
      final updated = <ScheduleBlock>[localBlock, ...currentBlocks]..sort(
        (a, b) => a.startTime.compareTo(b.startTime),
      );
      state = AsyncData(updated);
    }
  }

  List<ScheduleBlock> blocksForDay(DateTime day) {
    final data = state.valueOrNull ?? <ScheduleBlock>[];
    return data.where((block) {
      final start = block.startTime;
      return start.year == day.year && start.month == day.month && start.day == day.day;
    }).toList();
  }

  List<ScheduleBlock> _localDemoBlocksForMonth(DateTime monthDate) {
    final daysInMonth = DateUtils.getDaysInMonth(monthDate.year, monthDate.month);
    final daySet = <int>{1, 3, 5, 11, 18, 24, 28}
        .where((day) => day <= daysInMonth)
        .toList();

    final blocks = <ScheduleBlock>[];
    for (final day in daySet) {
      final date = DateTime(monthDate.year, monthDate.month, day);
      blocks.addAll(_demoBlocksForDay(date));
    }

    blocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    return blocks;
  }

  List<ScheduleBlock> _demoBlocksForDay(DateTime date) {
    return [
      ScheduleBlock(
        id: '${date.year}${date.month}${date.day}_focus',
        title: 'Morning Focus Session',
        startTime: DateTime(date.year, date.month, date.day, 9, 0),
        endTime: DateTime(date.year, date.month, date.day, 10, 30),
        type: 'Task',
        priority: 'high',
      ),
      ScheduleBlock(
        id: '${date.year}${date.month}${date.day}_planning',
        title: 'Afternoon Planning',
        startTime: DateTime(date.year, date.month, date.day, 15, 0),
        endTime: DateTime(date.year, date.month, date.day, 16, 0),
        type: 'Task',
        priority: 'medium',
      ),
      ScheduleBlock(
        id: '${date.year}${date.month}${date.day}_read',
        title: 'Read',
        startTime: DateTime(date.year, date.month, date.day, 18, 30),
        endTime: DateTime(date.year, date.month, date.day, 19, 15),
        type: 'Break',
        priority: 'low',
      ),
    ];
  }

  ScheduleBlock _localBlockFromDraft(TaskDraft draft) {
    final duration = draft.timingType == TaskTimingType.event
        ? const Duration(hours: 1)
        : const Duration(minutes: 90);

    final start = draft.deadline;
    final end = start.add(duration);

    return ScheduleBlock(
      id: 'local_${start.microsecondsSinceEpoch}',
      title: draft.title,
      startTime: start,
      endTime: end,
      type: draft.timingType == TaskTimingType.event ? 'Meeting' : 'Task',
      priority: draft.priority.backendWord.toLowerCase(),
    );
  }
}
