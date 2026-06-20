import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';
import 'package:kairos/screens/brief/daily_brief_modal.dart';
import 'package:kairos/services/haptic_service.dart';

String timeOfDaySalutation(DateTime time) {
  final hour = time.hour;
  if (hour < 12) {
    return 'Good morning';
  }
  if (hour < 17) {
    return 'Good afternoon';
  }
  return 'Good evening';
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class DashboardGreetingHeader extends StatelessWidget {
  const DashboardGreetingHeader({
    super.key,
    required this.selectedDate,
    this.onPlayBrief,
  });

  final DateTime selectedDate;
  final VoidCallback? onPlayBrief;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timely = context.timelyColors;
    final now = DateTime.now();
    final salutation = timeOfDaySalutation(now);
    final scheduleDay = DateFormat('EEEE, MMMM d').format(selectedDate);
    final viewingOtherDay = !isSameDay(selectedDate, now);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$salutation.',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Here is your schedule for $scheduleDay.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: timely.onSurfaceMuted,
                  height: 1.4,
                ),
              ),
              if (viewingOtherDay) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "You're viewing another day.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: timely.onSurfaceMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton.tonalIcon(
          onPressed: () async {
            await HapticService.lightImpact();
            if (onPlayBrief != null) {
              onPlayBrief!();
              return;
            }
            if (!context.mounted) {
              return;
            }
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const DailyBriefModal(),
            );
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: const Text('Brief'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
