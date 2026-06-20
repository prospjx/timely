import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/utils/block_colors.dart';

class TimelineView extends StatelessWidget {
  const TimelineView({
    super.key,
    required this.blocks,
    this.conflictingIds = const {},
    this.onBlockTap,
    this.onBlockDelete,
    this.bottomPadding = 0,
  });

  final List<ScheduleBlock> blocks;
  final Set<String> conflictingIds;
  final ValueChanged<ScheduleBlock>? onBlockTap;
  final ValueChanged<ScheduleBlock>? onBlockDelete;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) {
      return Center(
        child: Text(
          'No schedule blocks yet. Tap + to add your first task.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.timelyColors.onSurfaceMuted,
              ),
        ),
      );
    }

    final now = DateTime.now();
    final upcoming = blocks
        .where((block) => !block.allDay && block.endTime.isAfter(now))
        .toList();
    final upNextId = upcoming.isEmpty ? null : upcoming.first.id;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemCount: blocks.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm + 2),
      itemBuilder: (context, index) {
        final block = blocks[index];
        final isUpNext = block.id == upNextId;

        final card = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUpNext)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.xs),
                child: Text(
                  'Up Next',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: context.timelyColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            _BlockCard(
              block: block,
              hasConflict: conflictingIds.contains(block.id),
              onTap: onBlockTap == null ? null : () => onBlockTap!(block),
            ),
          ],
        );

        if (!block.canDelete || onBlockDelete == null) {
          return card;
        }

        final timely = context.timelyColors;
        return Dismissible(
          key: ValueKey(block.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: timely.warningSurface,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: Icon(Icons.delete_outline, color: timely.deleteAction),
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
    final timely = context.timelyColors;
    final theme = Theme.of(context);
    final color = timely.blockColorForBlock(block);
    final borderColor = hasConflict ? timely.conflictBorder : color.withValues(alpha: 0.45);
    final muted = timely.onSurfaceMuted;
    final isGoogle = blockIsGoogleCalendar(block);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Container(
            decoration: BoxDecoration(
              color: hasConflict
                  ? timely.conflictSurface.withValues(alpha: 0.85)
                  : color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(
                color: borderColor,
                width: hasConflict ? 1.6 : 1,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
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
                    color: hasConflict ? timely.conflictIcon : color,
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
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (hasConflict)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: timely.conflictIcon,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        block.allDay
                            ? 'All day'
                            : '${DateFormat.Hm().format(block.startTime)} - ${DateFormat.Hm().format(block.endTime)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                      if (isGoogle)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Google Calendar',
                            style: theme.textTheme.labelSmall?.copyWith(color: muted),
                          ),
                        ),
                      if (onTap != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Tap to manage',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: muted.withValues(alpha: 0.7),
                            ),
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
                      side: isGoogle
                          ? BorderSide(color: color.withValues(alpha: 0.5), style: BorderStyle.solid)
                          : BorderSide.none,
                    ),
                    if (onTap != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(Icons.chevron_right, color: muted.withValues(alpha: 0.7), size: 20),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
