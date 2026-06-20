import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';
import 'package:kairos/services/api_service.dart';
import 'package:kairos/widgets/zen_card.dart';

class ReflectionsScreen extends ConsumerStatefulWidget {
  const ReflectionsScreen({super.key});

  @override
  ConsumerState<ReflectionsScreen> createState() => _ReflectionsScreenState();
}

class _ReflectionsScreenState extends ConsumerState<ReflectionsScreen> {
  Future<Map<String, dynamic>>? _metricsFuture;
  late String _dailyTip;

  static const List<String> _reflectionTips = [
    'When making big life decisions, choose the option that offers more temporal freedom, like a shorter commute, even if it comes with a lower salary.',
    'Use small amounts of discretionary income to "buy back" your time by hiring help for chores you dislike, which acts as a buffer against daily stress.',
    'Disable non-urgent notifications and set "No Scroll Zones" during meals or morning routines to prevent your free time from being shredded into "time confetti."',
    'Track your activities for one week and prune "time sucks" or commitments that do not align with your core values and "North Star."',
    'Deliberately schedule 15- to 30-minute "slack" blocks between tasks to recalibrate and avoid the mental exhaustion of back-to-back meetings.',
    'When declining a task, state that you lack the "energy or resources" rather than just the "time" to make your professional boundary more effective.',
    'Spend time on others through volunteering to boost your self-efficacy, which paradoxically "stretches" your mental perception of available time.',
    'Aim for a "sweet spot" of 2 to 5 hours of discretionary time daily, prioritizing active leisure like hobbies or socializing over passive scrolling.',
    'Slow down to savor daily experiences, like a meal or a walk, to move from a reactive mindset to an intentional one.',
  ];

  @override
  void initState() {
    super.initState();
    _dailyTip = _pickDailyTip(DateTime.now());
    _refresh();
  }

  void _refresh() {
    setState(() {
      _dailyTip = _pickDailyTip(DateTime.now());
      _metricsFuture = ref.read(apiServiceProvider).getTodayReflections();
    });
  }

  String _pickDailyTip(DateTime now) {
    final daySeed = now.year * 10000 + now.month * 100 + now.day;
    final shuffled = List<String>.from(_reflectionTips)..shuffle(Random(daySeed));
    return shuffled.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timely = context.timelyColors;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Reflections'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _metricsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg - 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load reflections. Check that the backend is running, then try again.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm + 4),
                    TextButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data ?? <String, dynamic>{};
          final completionRate =
              (data['completion_rate_before_deadline'] as num?)?.toDouble() ?? 0.0;
          final restRate = (data['rest_rate'] as num?)?.toDouble() ?? 0.0;
          final completed = (data['tasks_completed_before_deadline'] as num?)?.toInt() ?? 0;
          final due = (data['tasks_due_count'] as num?)?.toInt() ?? 0;
          final free = (data['free_minutes'] as num?)?.toInt() ?? 0;
          final available = (data['available_minutes'] as num?)?.toInt() ?? 0;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text('Today\'s Reflection Tips', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm + 4),
              ZenCard(
                tint: timely.briefBubbleBackground,
                child: Text(
                  _dailyTip,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg - 4),
              Text('Today\'s Reflection Metrics', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm + 4),
              _MetricCard(
                title: 'Completion Rate (Before Deadline)',
                value: '${(completionRate * 100).toStringAsFixed(0)}%',
                subtitle: '$completed of $due due tasks completed before deadline.',
                tint: timely.secondary.withValues(alpha: 0.3),
              ),
              const SizedBox(height: AppSpacing.sm + 4),
              _MetricCard(
                title: 'Rest Rate (Free Time in Day)',
                value: '${(restRate * 100).toStringAsFixed(0)}%',
                subtitle: '$free free minutes out of $available awake minutes.',
                tint: timely.tertiary.withValues(alpha: 0.25),
              ),
              const SizedBox(height: AppSpacing.sm + 4),
              ZenCard(
                tint: timely.surfaceElevated,
                child: Text(
                  (data['summary'] as String?) ??
                      'Once you complete a full day of tracking, reflections will get richer.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: timely.onSurfaceMuted),
                ),
              ),
              const SizedBox(height: AppSpacing.sm + 4),
              TextButton(
                onPressed: _refresh,
                child: const Text('Refresh Metrics'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.tint,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final timely = context.timelyColors;

    return ZenCard(
      tint: tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: timely.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}
