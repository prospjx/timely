import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/models/schedule_block.dart';

void main() {
  test('ScheduleBlock fromJson maps backend payload', () {
    final block = ScheduleBlock.fromJson({
      '_id': 'abc123',
      'title': 'Math Homework',
      'start_time': '2026-04-11T09:00:00.000Z',
      'end_time': '2026-04-11T10:00:00.000Z',
      'type': 'Task',
    });

    expect(block.id, 'abc123');
    expect(block.title, 'Math Homework');
    expect(block.type, 'Task');
  });
}
