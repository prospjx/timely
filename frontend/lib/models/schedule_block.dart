class ScheduleBlock {
  const ScheduleBlock({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.type,
    this.priority,
  });

  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String type;
  final String? priority;

  factory ScheduleBlock.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] as String?) ?? 'Task';

    return ScheduleBlock(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      title: (json['title'] as String?) ?? type,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      type: type,
      priority: json['priority'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'type': type,
      'priority': priority,
    };
  }
}
