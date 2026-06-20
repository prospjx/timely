import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/utils/schedule_conflicts.dart';

ScheduleBlock _block({
  required String id,
  required DateTime start,
  required Duration duration,
  String type = 'Task',
  String? source,
}) {
  return ScheduleBlock(
    id: id,
    title: id,
    startTime: start,
    endTime: start.add(duration),
    type: type,
    source: source,
  );
}

void main() {
  group('blocksOverlap', () {
    test('returns true when ranges intersect', () {
      final a = _block(
        id: 'a',
        start: DateTime(2026, 6, 19, 9, 0),
        duration: const Duration(hours: 1),
      );
      final b = _block(
        id: 'b',
        start: DateTime(2026, 6, 19, 9, 30),
        duration: const Duration(hours: 1),
      );

      expect(blocksOverlap(a, b), isTrue);
    });

    test('returns false for adjacent non-overlapping blocks', () {
      final a = _block(
        id: 'a',
        start: DateTime(2026, 6, 19, 9, 0),
        duration: const Duration(hours: 1),
      );
      final b = _block(
        id: 'b',
        start: DateTime(2026, 6, 19, 10, 0),
        duration: const Duration(hours: 1),
      );

      expect(blocksOverlap(a, b), isFalse);
    });

    test('ignores all-day blocks', () {
      final timed = _block(
        id: 'timed',
        start: DateTime(2026, 6, 19, 9, 0),
        duration: const Duration(hours: 1),
      );
      final allDay = ScheduleBlock(
        id: 'all-day',
        title: 'Holiday',
        startTime: DateTime(2026, 6, 19),
        endTime: DateTime(2026, 6, 20),
        type: 'Task',
        allDay: true,
      );

      expect(blocksOverlap(timed, allDay), isFalse);
    });
  });

  group('findConflictGroups', () {
    test('groups overlapping blocks together', () {
      final blocks = [
        _block(id: '1', start: DateTime(2026, 6, 19, 9, 0), duration: const Duration(hours: 1)),
        _block(id: '2', start: DateTime(2026, 6, 19, 9, 30), duration: const Duration(hours: 1)),
        _block(id: '3', start: DateTime(2026, 6, 19, 14, 0), duration: const Duration(hours: 1)),
      ];

      final groups = findConflictGroups(blocks);
      expect(groups, hasLength(1));
      expect(groups.first.blocks.map((block) => block.id), ['1', '2']);
    });

    test('conflictingBlockIds returns all ids in conflict groups', () {
      final blocks = [
        _block(id: '1', start: DateTime(2026, 6, 19, 9, 0), duration: const Duration(hours: 1)),
        _block(id: '2', start: DateTime(2026, 6, 19, 9, 15), duration: const Duration(hours: 1)),
      ];

      expect(conflictingBlockIds(blocks), {'1', '2'});
      expect(dayHasConflicts(blocks), isTrue);
    });
  });

  group('ScheduleBlock helpers', () {
    test('isLocalOnly and isFromGoogleCalendar flags', () {
      final local = _block(
        id: 'local_123',
        start: DateTime(2026, 6, 19, 9, 0),
        duration: const Duration(hours: 1),
      );
      final google = _block(
        id: 'g1',
        start: DateTime(2026, 6, 19, 10, 0),
        duration: const Duration(hours: 1),
        source: 'calendar_sync',
      );

      expect(local.isLocalOnly, isTrue);
      expect(local.isReschedulable, isTrue);
      expect(google.isFromGoogleCalendar, isTrue);
      expect(google.isReschedulable, isFalse);
    });
  });
}
