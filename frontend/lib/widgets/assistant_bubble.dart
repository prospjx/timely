import 'package:flutter/material.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';

class AssistantBubble extends StatelessWidget {
  const AssistantBubble({
    super.key,
    required this.message,
    this.label = 'Timely',
    this.icon = Icons.auto_awesome_outlined,
  });

  final String message;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final timely = context.timelyColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: timely.primary.withValues(alpha: 0.15),
              child: Icon(icon, size: 18, color: timely.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: timely.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: timely.briefBubbleBackground,
            borderRadius: BorderRadius.circular(AppSpacing.bubbleRadius),
            border: Border.all(color: timely.briefBubbleBorder),
          ),
          child: Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }
}
