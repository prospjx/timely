import 'package:kairos/models/schedule_block.dart';

class ConflictResolveResult {
  const ConflictResolveResult({
    required this.movedCount,
    required this.unresolved,
    this.blocks,
  });

  final int movedCount;
  final List<String> unresolved;
  final List<ScheduleBlock>? blocks;
}

class ConflictGroup {
  const ConflictGroup({required this.blocks});

  final List<ScheduleBlock> blocks;

  bool get hasResolvableBlock => blocks.any((block) => block.isReschedulable);

  bool get isFullyFixed => blocks.every((block) => block.isFromGoogleCalendar);
}

bool blocksOverlap(ScheduleBlock a, ScheduleBlock b) {
  if (a.allDay || b.allDay) {
    return false;
  }
  return a.startTime.isBefore(b.endTime) && a.endTime.isAfter(b.startTime);
}

List<ConflictGroup> findConflictGroups(List<ScheduleBlock> blocks) {
  final timed = blocks.where((block) => !block.allDay).toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final parent = <String, String>{};
  String find(String id) {
    return parent[id] = parent[id] == id ? id : find(parent[id]!);
  }

  void union(String a, String b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) {
      parent[rootB] = rootA;
    }
  }

  for (final block in timed) {
    parent[block.id] = block.id;
  }

  for (var i = 0; i < timed.length; i++) {
    for (var j = i + 1; j < timed.length; j++) {
      if (blocksOverlap(timed[i], timed[j])) {
        union(timed[i].id, timed[j].id);
      }
    }
  }

  final grouped = <String, List<ScheduleBlock>>{};
  for (final block in timed) {
    final root = find(block.id);
    grouped.putIfAbsent(root, () => <ScheduleBlock>[]).add(block);
  }

  return grouped.values
      .where((group) => group.length > 1)
      .map((group) {
        final sorted = List<ScheduleBlock>.from(group)
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        return ConflictGroup(blocks: sorted);
      })
      .toList()
    ..sort((a, b) => a.blocks.first.startTime.compareTo(b.blocks.first.startTime));
}

Set<String> conflictingBlockIds(List<ScheduleBlock> blocks) {
  final ids = <String>{};
  for (final group in findConflictGroups(blocks)) {
    for (final block in group.blocks) {
      ids.add(block.id);
    }
  }
  return ids;
}

bool dayHasConflicts(List<ScheduleBlock> blocks) {
  return findConflictGroups(blocks).isNotEmpty;
}

Set<DateTime> conflictDatesInMonth(List<ScheduleBlock> blocks) {
  final dates = <DateTime>{};
  final byDay = <String, List<ScheduleBlock>>{};

  for (final block in blocks) {
    if (block.allDay) {
      continue;
    }
    final key = '${block.startTime.year}-${block.startTime.month}-${block.startTime.day}';
    byDay.putIfAbsent(key, () => <ScheduleBlock>[]).add(block);
  }

  for (final dayBlocks in byDay.values) {
    if (findConflictGroups(dayBlocks).isNotEmpty) {
      final first = dayBlocks.first.startTime;
      dates.add(DateTime(first.year, first.month, first.day));
    }
  }

  return dates;
}
