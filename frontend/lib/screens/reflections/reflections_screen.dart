import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/services/api_service.dart';

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

  ({double completionRate, double restRate}) _fakeRates(DateTime now) {
    final daySeed = now.year * 10000 + now.month * 100 + now.day;
    final random = Random(daySeed ^ 0x5A17);
    final completionRate = 0.58 + random.nextDouble() * 0.34;
    final restRate = 0.22 + random.nextDouble() * 0.56;
    return (
      completionRate: double.parse(completionRate.clamp(0.0, 1.0).toStringAsFixed(2)),
      restRate: double.parse(restRate.clamp(0.0, 1.0).toStringAsFixed(2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                padding: const EdgeInsets.all(20),
                child: Text('Failed to load reflections: ${snapshot.error}'),
              ),
            );
          }

          final data = snapshot.data ?? <String, dynamic>{};
          final fakeRates = _fakeRates(DateTime.now());
          final completed = (data['tasks_completed_before_deadline'] as num?)?.toInt() ?? 0;
          final due = (data['tasks_due_count'] as num?)?.toInt() ?? 0;
          final free = (data['free_minutes'] as num?)?.toInt() ?? 0;
          final available = (data['available_minutes'] as num?)?.toInt() ?? 0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Today\'s Reflection Tips', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF111722),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _dailyTip,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Today\'s Reflection Metrics', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              _MetricCard(
                title: 'Completion Rate (Before Deadline)',
                value: '${(fakeRates.completionRate * 100).toStringAsFixed(0)}%',
                subtitle: '$completed of $due due tasks completed before deadline.',
                color: const Color(0xFF123D2E),
              ),
              const SizedBox(height: 12),
              _MetricCard(
                title: 'Rest Rate (Free Time in Day)',
                value: '${(fakeRates.restRate * 100).toStringAsFixed(0)}%',
                subtitle: '$free free minutes out of $available awake minutes.',
                color: const Color(0xFF1D2E4B),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF111722),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  (data['summary'] as String?) ??
                      'Once you complete a full day of tracking, reflections will get richer.',
                ),
              ),
              const SizedBox(height: 12),
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
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
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
          Text(subtitle),
        ],
      ),
    );
  }
}
