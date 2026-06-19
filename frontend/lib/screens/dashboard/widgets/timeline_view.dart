import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kairos/models/schedule_block.dart';

class TimelineView extends StatelessWidget {
  const TimelineView({
    super.key,
    required this.blocks,
    this.conflictingIds = const {},
    this.onBlockTap,
    this.onBlockDelete,
  });

  final List<ScheduleBlock> blocks;
  final Set<String> conflictingIds;
  final ValueChanged<ScheduleBlock>? onBlockTap;
  final ValueChanged<ScheduleBlock>? onBlockDelete;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) {
      return const Center(
        child: Text('No schedule blocks yet. Tap + to add your first task.'),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: blocks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final block = blocks[index];
        final card = _BlockCard(
          block: block,
          hasConflict: conflictingIds.contains(block.id),
          onTap: onBlockTap == null ? null : () => onBlockTap!(block),
        );

        if (!block.canDelete || onBlockDelete == null) {
          return card;
        }

        return Dismissible(
          key: ValueKey(block.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF5A1A1A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_outline, color: Color(0xFFFF8A80)),
          ),
          confirmDismiss: (_) async {
            onBlockDelete!(block);
            return false;
          },
          child: card,
        );
      },
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.block,
    required this.hasConflict,
    this.onTap,
  });

  final ScheduleBlock block;
  final bool hasConflict;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(block.type);
    final borderColor = hasConflict ? const Color(0xFFFF6B6B) : color.withValues(alpha: 0.45);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: hasConflict
                ? const Color(0xFF3A1A1A).withValues(alpha: 0.85)
                : color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: hasConflict ? 1.6 : 1),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: hasConflict ? const Color(0xFFFF6B6B) : color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatTitle(block.title),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (hasConflict)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: Color(0xFFFF8A80),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      block.allDay
                          ? 'All day'
                          : '${DateFormat.Hm().format(block.startTime)} - ${DateFormat.Hm().format(block.endTime)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                    if (onTap != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Tap to manage',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white38),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Chip(
                    label: Text(block.type),
                    backgroundColor: color.withValues(alpha: 0.2),
                  ),
                  if (onTap != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
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
