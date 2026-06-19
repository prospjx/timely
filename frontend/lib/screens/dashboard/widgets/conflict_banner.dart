import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

    final totalEvents = groups.fold<int>(0, (sum, group) => sum + group.blocks.length);
    final allFixed = groups.every((group) => group.isFullyFixed);
    final subtitle = allFixed
        ? 'These Google Calendar events overlap. Edit one in Google Calendar.'
        : 'Drag to prioritize, then auto-fix or reschedule Timely events.';

    return Material(
      color: const Color(0xFF3A1A1A),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onResolve,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF8A80)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${groups.length} time conflict${groups.length == 1 ? '' : 's'} ($totalEvents events)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: const Color(0xFFFFCDD2),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
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
