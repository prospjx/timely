import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kairos/models/schedule_block.dart';

class TimelineView extends StatelessWidget {
  const TimelineView({super.key, required this.blocks});

  final List<ScheduleBlock> blocks;

  static const Map<String, String> _wordOverrides = {
    'api': 'API',
    'ui': 'UI',
    'ux': 'UX',
    'aws': 'AWS',
    'sql': 'SQL',
    'ai': 'AI',
    'ml': 'ML',
    'comptia': 'CompTIA',
  };

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) {
      return const Center(child: Text('No schedule blocks yet. Add your first task.'));
    }

    return ListView.separated(
      itemCount: blocks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final block = blocks[index];
        final color = _typeColor(block.type);

        return Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatTitle(block.title),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${DateFormat.Hm().format(block.startTime)} - ${DateFormat.Hm().format(block.endTime)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(block.type),
                backgroundColor: color.withValues(alpha: 0.2),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _typeColor(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('meeting')) {
      return Colors.blueAccent;
    }
    if (normalized.contains('break')) {
      return Colors.greenAccent;
    }
    return const Color(0xFF9A6DFF);
  }

  String _formatTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return title;
    }

    final words = trimmed.split(RegExp(r'\s+'));
    final transformed = words.map((word) {
      final lower = word.toLowerCase();
      if (_wordOverrides.containsKey(lower)) {
        return _wordOverrides[lower]!;
      }

      // Keep tokens that already contain mixed/upper case such as "CompTIA".
      final hasInternalUpper = word.length > 1 && word.substring(1).contains(RegExp(r'[A-Z]'));
      if (hasInternalUpper) {
        return word;
      }

      final parts = word.split('-');
      final casedParts = parts.map((part) {
        if (part.isEmpty || part == '+') {
          return part;
        }
        final partLower = part.toLowerCase();
        return partLower[0].toUpperCase() + partLower.substring(1);
      }).toList();
      return casedParts.join('-');
    }).toList();

    return transformed.join(' ');
  }
}
