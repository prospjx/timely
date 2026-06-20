import 'package:flutter/material.dart';
import 'package:kairos/core/timely_theme_extension.dart';
import 'package:kairos/models/schedule_block.dart';

/// Resolves semantic block colors from schedule block metadata.
Color blockColorFor(ScheduleBlock block, TimelyColors colors) {
  final type = block.type.toLowerCase();
  final source = block.source ?? '';

  if (type.contains('break')) {
    return colors.secondary;
  }

  if (type.contains('meeting')) {
    return colors.primary;
  }

  if (source == 'ai_deadline' || source == 'ai_scheduled') {
    return colors.tertiary;
  }

  if (source == 'calendar_sync') {
    return colors.primary;
  }

  if (type.contains('task')) {
    return colors.accentTeal;
  }

  return colors.tertiary;
}

bool blockIsGoogleCalendar(ScheduleBlock block) => block.isFromGoogleCalendar;

bool blockIsAiScheduled(ScheduleBlock block) {
  final source = block.source ?? '';
  return source == 'ai_deadline' || source == 'ai_scheduled';
}
