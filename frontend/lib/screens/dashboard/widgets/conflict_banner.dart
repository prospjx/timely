import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';
import 'package:kairos/utils/schedule_conflicts.dart';

class ConflictBanner extends StatelessWidget {
  const ConflictBanner({
    super.key,
    required this.groups,
    required this.onResolve,
  });

  final List<ConflictGroup> groups;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    final timely = context.timelyColors;
    final theme = Theme.of(context);
    final totalEvents = groups.fold<int>(0, (sum, group) => sum + group.blocks.length);
    final allFixed = groups.every((group) => group.isFullyFixed);
    final subtitle = allFixed
        ? 'These Google Calendar events overlap. Edit one in Google Calendar.'
        : "Let's make room — drag to prioritize, then auto-fix or reschedule.";

    return Material(
      color: timely.warningSurface,
      borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
      child: InkWell(
        onTap: onResolve,
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
            border: Border.all(color: timely.conflictBorder.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              Icon(Icons.event_available_outlined, color: timely.conflictIcon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${groups.length} time overlap${groups.length == 1 ? '' : 's'} ($totalEvents events)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: timely.conflictBorder,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: timely.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: timely.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

String formatConflictWindow(ConflictGroup group) {
  final start = group.blocks.map((block) => block.startTime).reduce(
        (a, b) => a.isBefore(b) ? a : b,
      );
  final end = group.blocks.map((block) => block.endTime).reduce(
        (a, b) => a.isAfter(b) ? a : b,
      );
  return '${DateFormat.jm().format(start)} – ${DateFormat.jm().format(end)}';
}
