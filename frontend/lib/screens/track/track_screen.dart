import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';
import 'package:kairos/services/api_service.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/widgets/zen_card.dart';

enum DiagnosticMode { fullDay, partTime }

class TrackScreen extends ConsumerStatefulWidget {
  const TrackScreen({super.key});

  @override
  ConsumerState<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends ConsumerState<TrackScreen> {
  DiagnosticMode _mode = DiagnosticMode.fullDay;
  Future<Map<String, dynamic>>? _analysisFuture;

  @override
  void initState() {
    super.initState();
    _refreshAnalysis();
  }

  void _refreshAnalysis() {
    setState(() {
      _analysisFuture = ref.read(apiServiceProvider).getTodayTimeAnalysis();
    });
  }

  @override
  Widget build(BuildContext context) {
    final timely = context.timelyColors;
    final isFullDay = _mode == DiagnosticMode.fullDay;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Track'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Time Diagnostic',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Pick how you want Timely to evaluate your time management habits.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: timely.onSurfaceMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<DiagnosticMode>(
            segments: const [
              ButtonSegment<DiagnosticMode>(
                value: DiagnosticMode.fullDay,
                label: Text('Full Diagnostic'),
                icon: Icon(Icons.schedule),
              ),
              ButtonSegment<DiagnosticMode>(
                value: DiagnosticMode.partTime,
                label: Text('Part Time'),
                icon: Icon(Icons.bolt),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) {
              setState(() {
                _mode = selection.first;
              });
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _ModeExplanationCard(isFullDay: isFullDay),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () async {
              final notifications = ref.read(notificationServiceProvider);
              if (isFullDay) {
                await notifications.startFullDiagnosticAutoPrompts();
              } else {
                await notifications.startPartTimeDiagnosticAutoPrompts();
              }

              if (!context.mounted) {
                return;
              }

              final modeLabel = isFullDay ? 'Full Diagnostic' : 'Part Time';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$modeLabel started. Auto "What are you doing" prompts are now active.')),
              );
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(isFullDay ? 'Start Full Diagnostic' : 'Start Part-Time Diagnostic'),
          ),
          const SizedBox(height: AppSpacing.lg - 4),
          FutureBuilder<Map<String, dynamic>>(
            future: _analysisFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Column(
                  children: [
                    ZenCard(
                      tint: timely.warningSurface,
                      child: Text(
                        'Could not load today\'s analysis. Check that the backend is running, then try again.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm + 4),
                    TextButton(
                      onPressed: _refreshAnalysis,
                      child: const Text('Retry'),
                    ),
                  ],
                );
              }

              final data = snapshot.data;
              return Column(
                children: [
                  _ScoreCard(
                    score: (data?['focus_score'] as num?)?.toInt() ?? 0,
                    hasData: data != null && data.isNotEmpty,
                  ),
                  const SizedBox(height: AppSpacing.sm + 4),
                  _ReportCard(data: data),
                  const SizedBox(height: AppSpacing.sm + 4),
                  TextButton(
                    onPressed: _refreshAnalysis,
                    child: const Text('Refresh Analysis'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ModeExplanationCard extends StatelessWidget {
  const _ModeExplanationCard({required this.isFullDay});

  final bool isFullDay;

  @override
  Widget build(BuildContext context) {
    return ZenCard(
      tint: context.timelyColors.wellbeing.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isFullDay ? 'Full Diagnostic (all day)' : 'Part-Time Diagnostic (random check-ins)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isFullDay
                ? 'Runs across the full day and asks short hourly prompts to track focus, interruptions, and progress.'
                : 'Runs at random points during your day with quick prompts to fine-tune how you use time.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isFullDay
                ? 'End of day: full score + summary report.'
                : 'End of run: quick score + compact report.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.timelyColors.onSurfaceMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score, required this.hasData});

  final int score;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final timely = context.timelyColors;

    return ZenCard(
      tint: timely.secondary.withValues(alpha: 0.25),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: timely.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$score',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasData ? 'Today\'s Time Management Score' : 'No analysis yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  hasData
                      ? '$score/100 - ${score >= 75 ? 'Good momentum' : 'Needs recovery focus'}, with room to reduce context switching.'
                      : 'Respond to activity prompts to build your first score.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: timely.onSurfaceMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.data});

  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    return ZenCard(
      tint: context.timelyColors.surfaceElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s End-of-Day Trend',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Text('Total interactions: ${data?['total_interactions'] ?? 0}'),
          Text('Completions: ${data?['completion_count'] ?? 0}'),
          Text('Snoozes: ${data?['snooze_count'] ?? 0}'),
          Text('Distractions: ${data?['distraction_count'] ?? 0}'),
          const SizedBox(height: AppSpacing.sm + 2),
          Text(
            data?['summary'] as String? ??
                'No interaction data yet. Start a diagnostic to begin tracking.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.timelyColors.onSurfaceMuted,
                ),
          ),
        ],
      ),
    );
  }
}
