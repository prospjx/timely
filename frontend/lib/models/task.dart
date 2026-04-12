import 'package:intl/intl.dart';

class TaskRequest {
  const TaskRequest({required this.rawText});

  final String rawText;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'raw_text': rawText,
    };
  }
}

enum PriorityCode { a, b, c }

enum TaskTimingType { deadline, event }

extension PriorityCodeX on PriorityCode {
  String get label {
    switch (this) {
      case PriorityCode.a:
        return 'A';
      case PriorityCode.b:
        return 'B';
      case PriorityCode.c:
        return 'C';
    }
  }

  String get backendWord {
    switch (this) {
      case PriorityCode.a:
        return 'High';
      case PriorityCode.b:
        return 'Medium';
      case PriorityCode.c:
        return 'Low';
    }
  }
}

class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.priority,
    required this.deadline,
    required this.timingType,
  });

  final String title;
  final PriorityCode priority;
  final DateTime deadline;
  final TaskTimingType timingType;

  String toRawText() {
    final formatted = DateFormat('yyyy-MM-dd HH:mm').format(deadline);
    if (timingType == TaskTimingType.event) {
      return '$title. Priority ${priority.backendWord} (${priority.label}). '
          'Schedule mode Event. Event date $formatted. Keep this on that day only.';
    }

    return '$title. Priority ${priority.backendWord} (${priority.label}). '
        'Schedule mode Deadline. Deadline $formatted.';
  }
}
