import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/services/api_service.dart';
import 'package:kairos/services/notification_service.dart';

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
    final isFullDay = _mode == DiagnosticMode.fullDay;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Track'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Time Diagnostic',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Pick how you want Timely to evaluate your time management habits.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          _ModeExplanationCard(isFullDay: isFullDay),
          const SizedBox(height: 16),
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
          const SizedBox(height: 20),
          FutureBuilder<Map<String, dynamic>>(
            future: _analysisFuture,
            builder: (context, snapshot) {
              final data = snapshot.data;
              return Column(
                children: [
                  _ScoreCard(
                    score: (data?['focus_score'] as num?)?.toInt() ?? 78,
                    isMock: data == null,
                  ),
                  const SizedBox(height: 14),
                  _ReportCard(data: data),
                  const SizedBox(height: 12),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121A26),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isFullDay ? 'Full Diagnostic (all day)' : 'Part-Time Diagnostic (random check-ins)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            isFullDay
                ? 'Runs across the full day and asks short hourly prompts to track focus, interruptions, and progress.'
                : 'Runs at random points during your day with quick prompts to fine-tune how you use time.',
          ),
          const SizedBox(height: 8),
          Text(
            isFullDay
                ? 'End of day: full score + summary report.'
                : 'End of run: quick score + compact report.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score, required this.isMock});

  final int score;
  final bool isMock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF14304B), Color(0xFF1A3E61)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$score',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMock ? 'Mock Time Management Score' : 'Today\'s Time Management Score',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text('$score/100 - ${score >= 75 ? 'Good momentum' : 'Needs recovery focus'}, with room to reduce context switching.'),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101826),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data == null ? 'Mock End-of-Day Report' : 'Today\'s End-of-Day Trend',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text('Total interactions: ${data?['total_interactions'] ?? 8}'),
          Text('Completions: ${data?['completion_count'] ?? 4}'),
          Text('Snoozes: ${data?['snooze_count'] ?? 2}'),
          Text('Distractions: ${data?['distraction_count'] ?? 2}'),
          const SizedBox(height: 10),
          Text(
            data?['summary'] as String? ??
                'Recommendation: Batch similar tasks and protect one 90-minute deep-work block.',
          ),
        ],
      ),
    );
  }
}
