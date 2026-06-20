import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/models/task.dart';
import 'package:kairos/providers/schedule_provider.dart';
import 'package:kairos/screens/input/quick_add_sheet.dart';
import 'package:kairos/services/haptic_service.dart';
import 'package:kairos/widgets/assistant_bubble.dart';
import 'package:url_launcher/url_launcher.dart';

class EventDetailSheet extends ConsumerStatefulWidget {
  const EventDetailSheet({
    super.key,
    required this.block,
  });

  final ScheduleBlock block;

  @override
  ConsumerState<EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends ConsumerState<EventDetailSheet> {
  bool _working = false;
  String? _message;

  ScheduleBlock get block => widget.block;

  String _friendlyError(Object error) {
    if (error is DioException) {
      final detail = error.response?.data;
      if (detail is Map && detail['detail'] is String) {
        return detail['detail'] as String;
      }
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _run(Future<void> Function() action, {String? successMessage}) async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await action();
      if (!mounted) {
        return;
      }
      if (successMessage != null) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = _friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text('Remove "${block.title}" from your schedule?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await _run(
      () => ref.read(scheduleProvider.notifier).deleteBlock(block),
      successMessage: '${block.title} deleted',
    );
  }

  Future<void> _complete() async {
    await HapticService.lightImpact();
    await _run(
      () => ref.read(scheduleProvider.notifier).completeBlock(block),
      successMessage: '${block.title} marked complete',
    );
  }

  Future<void> _syncLocal() async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final message = await ref.read(scheduleProvider.notifier).syncLocalBlock(block);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message ?? '${block.title} saved to your account')),
      );
    } catch (error) {
      setState(() => _message = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _openEdit() async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuickAddSheet(
        initialBlock: block,
        onSubmit: (draft) async {
          final priority = draft.priority.backendWord;
          if (block.isLocalOnly) {
            await ref.read(scheduleProvider.notifier).updateBlock(
                  block: block,
                  title: draft.title,
                  priority: priority,
                  startTime: draft.scheduledAt,
                  endTime: draft.eventEndTime,
                );
            return;
          }

          await ref.read(scheduleProvider.notifier).updateBlock(
                block: block,
                title: draft.title,
                priority: priority,
                startTime: draft.scheduledAt,
                endTime: draft.eventEndTime,
              );
        },
      ),
    );

    if (updated == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openGoogleCalendar() async {
    final link = block.googleHtmlLink;
    if (link == null || link.isEmpty) {
      setState(() => _message = 'No Google Calendar link available for this event.');
      return;
    }
    final uri = Uri.parse(link);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      setState(() => _message = 'Could not open Google Calendar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final timely = context.timelyColors;
    final theme = Theme.of(context);
    final timeLabel = block.allDay
        ? 'All day'
        : '${DateFormat.jm().format(block.startTime)} – ${DateFormat.jm().format(block.endTime)}';

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg - 4,
        right: AppSpacing.lg - 4,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  block.title,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: _working ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            DateFormat.yMMMEd().format(block.startTime),
            style: theme.textTheme.bodyMedium?.copyWith(color: timely.onSurfaceMuted),
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          _DetailRow(label: 'Time', value: timeLabel),
          _DetailRow(label: 'Type', value: block.type),
          if (block.priority != null) _DetailRow(label: 'Priority', value: block.priority!),
          if (block.deadlineTime != null)
            _DetailRow(
              label: 'Deadline',
              value: DateFormat('EEE, MMM d • h:mm a').format(block.deadlineTime!),
            ),
          _DetailRow(label: 'Source', value: block.sourceLabel),
          if (block.schedulingNote != null && block.schedulingNote!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            AssistantBubble(
              message: block.schedulingNote!,
              label: 'Why this time',
              icon: Icons.schedule_outlined,
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _message!,
              style: theme.textTheme.bodySmall?.copyWith(color: timely.warning),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (block.isLocalOnly) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _working ? null : _openEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _working ? null : _syncLocal,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Save to account'),
              ),
            ),
          ],
          if (block.canEdit && !block.isLocalOnly) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _working ? null : _openEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (block.isFromGoogleCalendar && block.googleHtmlLink != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _working ? null : _openGoogleCalendar,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in Google Calendar'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (block.canComplete) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _working ? null : _complete,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Mark complete'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (block.canDelete)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _working ? null : _confirmDelete,
                icon: Icon(Icons.delete_outline, color: timely.deleteAction),
                label: Text('Delete', style: TextStyle(color: timely.deleteAction)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final timely = context.timelyColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: timely.onSurfaceMuted),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
