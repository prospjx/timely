import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/models/task.dart';

void main() {
  group('TaskDraft', () {
    final scheduledAt = DateTime.utc(2026, 6, 19, 18, 30);

    test('toDeadlineJson sends UTC ISO deadline', () {
      final draft = TaskDraft(
        title: 'Lab report',
        priority: PriorityCode.a,
        scheduledAt: scheduledAt.toLocal(),
        timingType: TaskTimingType.deadline,
        durationMinutes: 90,
      );

      final json = draft.toDeadlineJson();
      expect(json['title'], 'Lab report');
      expect(json['priority'], 'High');
      expect(json['estimated_minutes'], 90);
      expect(json['deadline'], scheduledAt.toIso8601String());
    });

    test('toEventJson sends UTC start and end times', () {
      final draft = TaskDraft(
        title: 'Standup',
        priority: PriorityCode.b,
        scheduledAt: scheduledAt.toLocal(),
        timingType: TaskTimingType.event,
        durationMinutes: 30,
      );

      final json = draft.toEventJson();
      expect(json['start_time'], scheduledAt.toIso8601String());
      expect(json['end_time'], scheduledAt.add(const Duration(minutes: 30)).toIso8601String());
    });

    test('toRawText includes schedule mode for events and deadlines', () {
      final eventDraft = TaskDraft(
        title: 'Standup',
        priority: PriorityCode.b,
        scheduledAt: DateTime(2026, 6, 19, 9, 0),
        timingType: TaskTimingType.event,
      );
      final deadlineDraft = TaskDraft(
        title: 'Essay',
        priority: PriorityCode.c,
        scheduledAt: DateTime(2026, 6, 20, 17, 0),
        timingType: TaskTimingType.deadline,
      );

      expect(eventDraft.toRawText(), contains('Schedule mode Event'));
      expect(deadlineDraft.toRawText(), contains('Schedule mode Deadline'));
    });
  });
}
