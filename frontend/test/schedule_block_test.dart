import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/models/schedule_block.dart';

void main() {
  group('ScheduleBlock.fromJson', () {
    test('maps backend payload including optional fields', () {
      final block = ScheduleBlock.fromJson({
        '_id': 'abc123',
        'title': 'Math Homework',
        'start_time': '2026-04-11T09:00:00.000Z',
        'end_time': '2026-04-11T10:00:00.000Z',
        'type': 'Task',
        'priority': 'High',
        'task_id': 'task-1',
        'source': 'manual',
      });

      expect(block.id, 'abc123');
      expect(block.title, 'Math Homework');
      expect(block.type, 'Task');
      expect(block.priority, 'High');
      expect(block.taskId, 'task-1');
      expect(block.canComplete, isTrue);
    });

    test('occursOnDate matches local day for timed blocks', () {
      final block = ScheduleBlock.fromJson({
        '_id': '1',
        'title': 'Morning block',
        'start_time': '2026-04-11T09:00:00.000Z',
        'end_time': '2026-04-11T10:00:00.000Z',
        'type': 'Task',
      });

      expect(block.occursOnDate(block.startTime), isTrue);
      expect(
        block.occursOnDate(block.startTime.add(const Duration(days: 1))),
        isFalse,
      );
    });

    test('toTaskDraft maps meeting blocks to event drafts', () {
      final block = ScheduleBlock(
        id: '1',
        title: 'Sync',
        startTime: DateTime(2026, 6, 19, 9, 0),
        endTime: DateTime(2026, 6, 19, 10, 0),
        type: 'Meeting',
        priority: 'high',
      );

      final draft = block.toTaskDraft();
      expect(draft.title, 'Sync');
      expect(draft.timingType.name, 'event');
      expect(draft.durationMinutes, 60);
    });
  });
}
