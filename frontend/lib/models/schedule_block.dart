import 'package:kairos/core/datetime_utils.dart';
import 'package:kairos/models/task.dart';

class ScheduleBlock {
  const ScheduleBlock({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.type,
    this.priority,
    this.allDay = false,
    this.source,
    this.deadlineTime,
    this.schedulingNote,
    this.taskId,
    this.googleEventId,
    this.googleHtmlLink,
  });

  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String type;
  final String? priority;
  final bool allDay;
  final String? source;
  final DateTime? deadlineTime;
  final String? schedulingNote;
  final String? taskId;
  final String? googleEventId;
  final String? googleHtmlLink;

  bool get isFromGoogleCalendar => source == 'calendar_sync';

  bool get isLocalOnly => id.startsWith('local_');

  bool get isReschedulable => !isFromGoogleCalendar;

  String get sourceLabel {
    if (isLocalOnly) {
      return 'Saved on device only';
    }
    if (isFromGoogleCalendar) {
      return 'Google Calendar';
    }
    if (source == 'ai_deadline') {
      return 'AI scheduled (deadline)';
    }
    if (source == 'ai_scheduled') {
      return 'AI scheduled';
    }
    return 'Timely';
  }

  TaskDraft toTaskDraft() {
    final normalizedPriority = (priority ?? 'medium').toLowerCase();
    final priorityCode = switch (normalizedPriority) {
      'high' => PriorityCode.a,
      'low' => PriorityCode.c,
      _ => PriorityCode.b,
    };
    final isEvent = type.toLowerCase().contains('meeting');
    final durationMinutes = duration.inMinutes.clamp(15, 600);

    return TaskDraft(
      title: title,
      priority: priorityCode,
      scheduledAt: deadlineTime ?? (isEvent ? startTime : endTime),
      timingType: isEvent ? TaskTimingType.event : TaskTimingType.deadline,
      durationMinutes: durationMinutes,
    );
  }

  Duration get duration => endTime.difference(startTime);

  factory ScheduleBlock.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] as String?) ?? 'Task';

    return ScheduleBlock(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      title: (json['title'] as String?) ?? type,
      startTime: parseApiDateTime(json['start_time'] as String),
      endTime: parseApiDateTime(json['end_time'] as String),
      type: type,
      priority: json['priority'] as String?,
      allDay: json['all_day'] == true,
      source: json['source'] as String?,
      deadlineTime: json['deadline_time'] == null
          ? null
          : parseApiDateTime(json['deadline_time'] as String),
      schedulingNote: json['scheduling_note'] as String?,
      taskId: json['task_id']?.toString(),
      googleEventId: json['google_event_id'] as String?,
      googleHtmlLink: json['google_html_link'] as String?,
    );
  }

  bool occursOnDate(DateTime date) {
    if (allDay) {
      final day = DateTime(date.year, date.month, date.day);
      final startDay = DateTime(startTime.year, startTime.month, startTime.day);
      final endDay = DateTime(endTime.year, endTime.month, endTime.day);
      return !day.isBefore(startDay) && day.isBefore(endDay);
    }

    return startTime.year == date.year &&
        startTime.month == date.month &&
        startTime.day == date.day;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'type': type,
      'priority': priority,
      'all_day': allDay,
      'source': source,
      'deadline_time': deadlineTime?.toUtc().toIso8601String(),
      'scheduling_note': schedulingNote,
      'task_id': taskId,
      'google_event_id': googleEventId,
      'google_html_link': googleHtmlLink,
    };
  }

  bool get canComplete => taskId != null && !isFromGoogleCalendar && !isLocalOnly;

  bool get canDelete => isReschedulable || isFromGoogleCalendar;

  bool get canEdit => isReschedulable || isLocalOnly || isFromGoogleCalendar;

  ScheduleBlock copyWith({
    String? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    String? type,
    String? priority,
    bool? allDay,
    String? source,
    DateTime? deadlineTime,
    String? schedulingNote,
    String? taskId,
    String? googleEventId,
    String? googleHtmlLink,
  }) {
    return ScheduleBlock(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      allDay: allDay ?? this.allDay,
      source: source ?? this.source,
      deadlineTime: deadlineTime ?? this.deadlineTime,
      schedulingNote: schedulingNote ?? this.schedulingNote,
      taskId: taskId ?? this.taskId,
      googleEventId: googleEventId ?? this.googleEventId,
      googleHtmlLink: googleHtmlLink ?? this.googleHtmlLink,
    );
  }
}
