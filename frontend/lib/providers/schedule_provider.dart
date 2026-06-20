import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/models/task.dart';
import 'package:kairos/services/api_service.dart';
import 'package:kairos/utils/calendar_math.dart';
import 'package:kairos/utils/schedule_conflicts.dart';

final scheduleProvider =
    AsyncNotifierProvider<ScheduleNotifier, List<ScheduleBlock>>(
  ScheduleNotifier.new,
);

class ScheduleNotifier extends AsyncNotifier<List<ScheduleBlock>> {
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final Set<int> _loadedMonthKeys = <int>{};

  @override
  Future<List<ScheduleBlock>> build() async {
    final month = CalendarMath.monthStart(_visibleMonth);
    final blocks = await _fetchMonth(month);
    _loadedMonthKeys.add(CalendarMath.monthKey(month));
    return blocks;
  }

  Future<List<ScheduleBlock>> _fetchMonth(DateTime month) async {
    final api = ref.read(apiServiceProvider);
    return api.getMonthSchedule(year: month.year, month: month.month);
  }

  bool _hasMonth(DateTime month) => _loadedMonthKeys.contains(CalendarMath.monthKey(month));

  bool _serverBlockInMonth(ScheduleBlock block, DateTime month) {
    if (block.isLocalOnly) {
      return false;
    }
    final monthStart = CalendarMath.monthStart(month);
    final monthEnd = DateTime(month.year, month.month + 1);
    if (block.allDay) {
      final blockStart = DateTime(block.startTime.year, block.startTime.month, block.startTime.day);
      final blockEnd = DateTime(block.endTime.year, block.endTime.month, block.endTime.day);
      return blockStart.isBefore(monthEnd) && !blockEnd.isBefore(monthStart);
    }
    return block.startTime.year == month.year && block.startTime.month == month.month;
  }

  Future<void> refreshSchedule() async {
    final localOnly = (state.valueOrNull ?? <ScheduleBlock>[])
        .where((block) => block.isLocalOnly)
        .toList();
    final months = _loadedMonthKeys.isEmpty
        ? <DateTime>[CalendarMath.monthStart(_visibleMonth)]
        : _loadedMonthKeys
            .map((key) => DateTime(key ~/ 100, key % 100))
            .toList()
          ..sort((a, b) => a.compareTo(b));

    if (state.valueOrNull == null) {
      state = const AsyncLoading();
    }

    _loadedMonthKeys.clear();
    var merged = localOnly;
    for (final month in months) {
      final loaded = await AsyncValue.guard(() => _fetchMonth(month));
      if (loaded case AsyncData<List<ScheduleBlock>>(value: final serverBlocks)) {
        _loadedMonthKeys.add(CalendarMath.monthKey(month));
        merged = _mergeLocalBlocks(merged, serverBlocks);
        continue;
      }
      state = loaded;
      return;
    }
    state = AsyncData(merged);
  }

  List<ScheduleBlock> _mergeLocalBlocks(
    List<ScheduleBlock> localBlocks,
    List<ScheduleBlock> serverBlocks,
  ) {
    if (localBlocks.isEmpty) {
      return serverBlocks;
    }
    final merged = <ScheduleBlock>[...localBlocks, ...serverBlocks]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return merged;
  }

  Future<bool> submitTask(TaskDraft draft) async {
    try {
      await _persistDraftToServer(draft);
      return true;
    } catch (_) {
      final currentBlocks = state.valueOrNull ?? <ScheduleBlock>[];
      final localBlock = _localBlockFromDraft(draft, currentBlocks);
      final updated = <ScheduleBlock>[localBlock, ...currentBlocks]..sort(
        (a, b) => a.startTime.compareTo(b.startTime),
      );
      state = AsyncData(updated);
      return false;
    }
  }

  Future<void> _persistDraftToServer(TaskDraft draft) async {
    final api = ref.read(apiServiceProvider);
    await api.submitTaskDraft(draft);
    await refreshSchedule();
  }

  /// Saves a device-only event to the server. Returns a user message, or null on success.
  Future<String?> syncLocalBlock(ScheduleBlock block) async {
    if (!block.isLocalOnly) {
      return null;
    }

    final previousBlocks = state.valueOrNull ?? <ScheduleBlock>[];
    state = AsyncData(
      previousBlocks.where((item) => item.id != block.id).toList(),
    );

    var draft = block.toTaskDraft();
    var adjusted = false;
    final dayBlocks = previousBlocks
        .where(
          (item) =>
              !item.isLocalOnly &&
              item.id != block.id &&
              item.occursOnDate(block.startTime) &&
              !item.allDay,
        )
        .toList();

    if (dayBlocks.any((item) => blocksOverlap(block, item))) {
      final anchorEnd = dayBlocks
          .where((item) => blocksOverlap(block, item))
          .map((item) => item.endTime)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final slot = _findLocalSlot(
        blocks: dayBlocks,
        duration: block.duration,
        notBefore: anchorEnd,
        excludeId: block.id,
      );
      if (slot == null) {
        state = AsyncData(previousBlocks);
        return 'No open slot today for ${block.title}. Pick a new time, then try again.';
      }

      draft = TaskDraft(
        title: draft.title,
        priority: draft.priority,
        scheduledAt: slot.$1,
        timingType: draft.timingType,
        durationMinutes: draft.durationMinutes,
      );
      adjusted = true;
    }

    try {
      await _persistDraftToServer(draft);
      if (adjusted) {
        final timeLabel = DateFormat.jm().format(draft.scheduledAt);
        return '${block.title} saved at $timeLabel to avoid the conflict.';
      }
      return null;
    } on DioException catch (error) {
      state = AsyncData(previousBlocks);
      final detail = error.response?.data;
      if (detail is Map && detail['detail'] is String) {
        return detail['detail'] as String;
      }
      return 'Could not save ${block.title}. Check that the backend is running.';
    } catch (_) {
      state = AsyncData(previousBlocks);
      return 'Could not save ${block.title}. Check that the backend is running.';
    }
  }

  List<ScheduleBlock> blocksForDay(DateTime day) {
    final data = state.valueOrNull ?? <ScheduleBlock>[];
    return data.where((block) => block.occursOnDate(day)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<void> loadMonth(DateTime monthDate) async {
    final month = CalendarMath.monthStart(monthDate);
    _visibleMonth = month;
    if (_hasMonth(month)) {
      return;
    }
    await _mergeMonth(month);
  }

  Future<void> loadMonthsForWeek(DateTime weekStart) async {
    for (final month in CalendarMath.monthsToCoverWeek(weekStart)) {
      await loadMonth(month);
    }
  }

  Future<void> loadMonthIfNeeded(DateTime date) => loadMonth(date);

  Future<void> _mergeMonth(DateTime month) async {
    final kept = (state.valueOrNull ?? <ScheduleBlock>[])
        .where((block) => block.isLocalOnly || !_serverBlockInMonth(block, month))
        .toList();

    if (state.valueOrNull == null) {
      state = const AsyncLoading();
    }

    final loaded = await AsyncValue.guard(() => _fetchMonth(month));
    if (loaded case AsyncData<List<ScheduleBlock>>(value: final serverBlocks)) {
      _loadedMonthKeys.add(CalendarMath.monthKey(month));
      final merged = [...kept, ...serverBlocks]
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      state = AsyncData(merged);
      return;
    }
    state = loaded;
  }

  Future<ConflictResolveResult> resolveDayConflicts({
    required DateTime date,
    required List<String> priorityBlockIds,
  }) async {
    final current = List<ScheduleBlock>.from(state.valueOrNull ?? <ScheduleBlock>[]);
    final dayBlocks = current.where((block) => block.occursOnDate(date) && !block.allDay).toList();
    final localResult = _autoResolveLocalBlocks(
      date: date,
      allBlocks: current,
      priorityBlockIds: priorityBlockIds,
    );

    var movedCount = localResult.movedCount;
    var unresolved = List<String>.from(localResult.unresolved);
    if (localResult.movedCount > 0 && localResult.blocks != null) {
      state = AsyncData(localResult.blocks!);
    }

    final hasServerResolvable = dayBlocks.any(
      (block) => block.isReschedulable && !block.isLocalOnly,
    );
    if (hasServerResolvable) {
      final api = ref.read(apiServiceProvider);
      final serverResult = await api.resolveDayConflicts(
        date: date,
        priorityBlockIds: priorityBlockIds,
      );
      movedCount += serverResult.movedCount;
      unresolved = [...unresolved, ...serverResult.unresolved];
      await refreshSchedule();
    }

    return ConflictResolveResult(movedCount: movedCount, unresolved: unresolved);
  }

  ConflictResolveResult _autoResolveLocalBlocks({
    required DateTime date,
    required List<ScheduleBlock> allBlocks,
    required List<String> priorityBlockIds,
  }) {
    final updated = List<ScheduleBlock>.from(allBlocks);
    var movedCount = 0;
    final unresolved = <String>[];

    bool changed = true;
    while (changed) {
      changed = false;
      final timed = updated.where((block) => block.occursOnDate(date) && !block.allDay).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      for (var i = 0; i < timed.length; i++) {
        for (var j = i + 1; j < timed.length; j++) {
          final blockA = timed[i];
          final blockB = timed[j];
          if (!blocksOverlap(blockA, blockB)) {
            continue;
          }

          final toMove = _pickLocalBlockToMove(
            blockA,
            blockB,
            priorityBlockIds,
          );
          if (toMove == null) {
            continue;
          }

          final duration = toMove.duration;
          final anchorEnd = blockA.endTime.isAfter(blockB.endTime) ? blockA.endTime : blockB.endTime;
          final slot = _findLocalSlot(
            blocks: timed,
            duration: duration,
            notBefore: anchorEnd,
            excludeId: toMove.id,
          );
          if (slot == null) {
            unresolved.add('No open slot today for ${toMove.title}');
            continue;
          }

          final index = updated.indexWhere((block) => block.id == toMove.id);
          if (index == -1) {
            continue;
          }
          updated[index] = toMove.copyWith(startTime: slot.$1, endTime: slot.$2);
          movedCount += 1;
          changed = true;
          break;
        }
        if (changed) {
          break;
        }
      }
    }

    return ConflictResolveResult(
      movedCount: movedCount,
      unresolved: unresolved,
      blocks: updated,
    );
  }

  ScheduleBlock? _pickLocalBlockToMove(
    ScheduleBlock blockA,
    ScheduleBlock blockB,
    List<String> priorityBlockIds,
  ) {
    if (priorityBlockIds.contains(blockA.id) && !priorityBlockIds.contains(blockB.id)) {
      return blockB.isReschedulable ? blockB : null;
    }
    if (priorityBlockIds.contains(blockB.id) && !priorityBlockIds.contains(blockA.id)) {
      return blockA.isReschedulable ? blockA : null;
    }

    if (blockA.isReschedulable && !blockB.isReschedulable) {
      return blockA;
    }
    if (blockB.isReschedulable && !blockA.isReschedulable) {
      return blockB;
    }
    if (blockA.isReschedulable && blockB.isReschedulable) {
      return blockB.startTime.isAfter(blockA.startTime) ? blockB : blockA;
    }
    return null;
  }

  (DateTime, DateTime)? _findLocalSlot({
    required List<ScheduleBlock> blocks,
    required Duration duration,
    required DateTime notBefore,
    required String excludeId,
  }) {
    final dayEnd = DateTime(notBefore.year, notBefore.month, notBefore.day, 23, 59);
    var cursor = notBefore;
    const step = Duration(minutes: 15);

    while (cursor.add(duration).isBefore(dayEnd) || cursor.add(duration).isAtSameMomentAs(dayEnd)) {
      final candidateEnd = cursor.add(duration);
      final overlap = blocks.any((block) {
        if (block.id == excludeId || block.allDay) {
          return false;
        }
        return block.startTime.isBefore(candidateEnd) && block.endTime.isAfter(cursor);
      });
      if (!overlap) {
        return (cursor, candidateEnd);
      }
      cursor = cursor.add(step);
    }
    return null;
  }

  Future<void> rescheduleBlock({
    required ScheduleBlock block,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    if (block.isLocalOnly) {
      final current = state.valueOrNull ?? <ScheduleBlock>[];
      state = AsyncData(
        current
            .map(
              (item) => item.id == block.id
                  ? item.copyWith(startTime: startTime, endTime: endTime)
                  : item,
            )
            .toList(),
      );
      return;
    }

    final api = ref.read(apiServiceProvider);
    await api.rescheduleBlock(
      blockId: block.id,
      startTime: startTime,
      endTime: endTime,
    );
    await refreshSchedule();
  }

  Future<void> updateBlock({
    required ScheduleBlock block,
    String? title,
    String? priority,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    if (block.isLocalOnly) {
      final current = state.valueOrNull ?? <ScheduleBlock>[];
      state = AsyncData(
        current
            .map(
              (item) => item.id == block.id
                  ? item.copyWith(
                      title: title ?? item.title,
                      priority: priority ?? item.priority,
                      startTime: startTime ?? item.startTime,
                      endTime: endTime ?? item.endTime,
                    )
                  : item,
            )
            .toList(),
      );
      return;
    }

    final api = ref.read(apiServiceProvider);
    await api.updateScheduleBlock(
      blockId: block.id,
      title: title,
      priority: priority,
      startTime: startTime,
      endTime: endTime,
    );
    await refreshSchedule();
  }

  Future<void> deleteBlock(ScheduleBlock block) async {
    if (block.isLocalOnly) {
      final current = state.valueOrNull ?? <ScheduleBlock>[];
      state = AsyncData(current.where((item) => item.id != block.id).toList());
      return;
    }

    final api = ref.read(apiServiceProvider);
    await api.deleteScheduleBlock(block.id);
    await refreshSchedule();
  }

  Future<void> completeBlock(ScheduleBlock block) async {
    if (block.isLocalOnly) {
      await deleteBlock(block);
      return;
    }

    final taskId = block.taskId;
    if (taskId == null) {
      return;
    }

    final api = ref.read(apiServiceProvider);
    await api.completeTask(taskId);
    await refreshSchedule();
  }

  ScheduleBlock _localBlockFromDraft(TaskDraft draft, List<ScheduleBlock> existingBlocks) {
    final duration = Duration(minutes: draft.durationMinutes);

    late DateTime start;
    late DateTime end;
    DateTime? deadlineTime;

    if (draft.timingType == TaskTimingType.deadline) {
      deadlineTime = draft.scheduledAt;
      final slot = _findLocalDeadlineSlot(
        draft: draft,
        blocks: existingBlocks,
      );
      if (slot != null) {
        start = slot.$1;
        end = slot.$2;
      } else {
        start = draft.scheduledAt.subtract(duration);
        end = draft.scheduledAt;
      }
    } else {
      start = draft.scheduledAt;
      end = start.add(duration);
    }

    return ScheduleBlock(
      id: 'local_${start.microsecondsSinceEpoch}',
      title: draft.title,
      startTime: start,
      endTime: end,
      type: draft.timingType == TaskTimingType.event ? 'Meeting' : 'Task',
      priority: draft.priority.backendWord.toLowerCase(),
      deadlineTime: deadlineTime,
    );
  }

  bool _slotOverlaps(
    List<ScheduleBlock> blocks,
    DateTime start,
    DateTime end, {
    String? excludeId,
  }) {
    return blocks.any((block) {
      if (block.id == excludeId || block.allDay) {
        return false;
      }
      return block.startTime.isBefore(end) && block.endTime.isAfter(start);
    });
  }

  DateTime _roundUpToStep(DateTime value, Duration step) {
    final epoch = value.millisecondsSinceEpoch;
    final stepMs = step.inMilliseconds;
    final rounded = ((epoch + stepMs - 1) ~/ stepMs) * stepMs;
    return DateTime.fromMillisecondsSinceEpoch(rounded);
  }

  (DateTime, DateTime)? _findLocalDeadlineSlot({
    required TaskDraft draft,
    required List<ScheduleBlock> blocks,
  }) {
    final deadline = draft.scheduledAt;
    final duration = Duration(minutes: draft.durationMinutes);
    final now = DateTime.now();
    if (!deadline.isAfter(now)) {
      return null;
    }

    const step = Duration(minutes: 15);

    final finishAtDeadline = deadline.subtract(duration);
    if (!finishAtDeadline.isBefore(now) &&
        !_slotOverlaps(blocks, finishAtDeadline, deadline)) {
      return (finishAtDeadline, deadline);
    }

    var cursor = _roundUpToStep(now, step);
    while (!cursor.add(duration).isAfter(deadline)) {
      final candidateEnd = cursor.add(duration);
      if (!_slotOverlaps(blocks, cursor, candidateEnd)) {
        return (cursor, candidateEnd);
      }
      cursor = cursor.add(step);
    }

    return null;
  }
}
