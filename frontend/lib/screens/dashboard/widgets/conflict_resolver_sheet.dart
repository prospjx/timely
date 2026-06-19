import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/screens/dashboard/widgets/conflict_banner.dart';
import 'package:kairos/utils/schedule_conflicts.dart';

class ConflictResolverSheet extends StatefulWidget {
  const ConflictResolverSheet({
    super.key,
    required this.date,
    required this.groups,
    required this.onAutoResolve,
    required this.onReschedule,
    this.onSync,
  });

  final DateTime date;
  final List<ConflictGroup> groups;
  final Future<ConflictResolveResult> Function(List<String> priorityBlockIds) onAutoResolve;
  final Future<void> Function(ScheduleBlock block, DateTime start, DateTime end) onReschedule;
  final Future<String?> Function(ScheduleBlock block)? onSync;

  @override
  State<ConflictResolverSheet> createState() => _ConflictResolverSheetState();
}

class _ConflictResolverSheetState extends State<ConflictResolverSheet> {
  late List<String> _priorityOrder;
  bool _working = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _priorityOrder = _initialPriorityOrder();
  }

  List<String> _initialPriorityOrder() {
    final ids = <String>[];
    for (final group in widget.groups) {
      for (final block in group.blocks) {
        if (!ids.contains(block.id)) {
          ids.add(block.id);
        }
      }
    }
    return ids;
  }

  List<ScheduleBlock> get _orderedBlocks {
    final byId = <String, ScheduleBlock>{};
    for (final group in widget.groups) {
      for (final block in group.blocks) {
        byId[block.id] = block;
      }
    }
    return _priorityOrder.map(byId.remove).whereType<ScheduleBlock>().toList();
  }

  Future<void> _autoFix() async {
    setState(() {
      _working = true;
      _message = null;
    });

    try {
      final result = await widget.onAutoResolve(_priorityOrder);
      if (!mounted) {
        return;
      }

      if (result.movedCount > 0 && result.unresolved.isEmpty) {
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _message = result.movedCount > 0
            ? 'Moved ${result.movedCount} event${result.movedCount == 1 ? '' : 's'}. ${result.unresolved.join(' ')}'
            : result.unresolved.join(' ');
      });
    } catch (error) {
      setState(() {
        _message = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _pickNewTime(ScheduleBlock block) async {
    final date = widget.date;
    final initialStart = TimeOfDay.fromDateTime(block.startTime);
    final pickedStart = await showTimePicker(
      context: context,
      initialTime: initialStart,
      helpText: 'New start time for ${block.title}',
    );
    if (pickedStart == null || !mounted) {
      return;
    }

    final start = DateTime(
      date.year,
      date.month,
      date.day,
      pickedStart.hour,
      pickedStart.minute,
    );
    final end = start.add(block.duration);

    setState(() {
      _working = true;
      _message = null;
    });

    try {
      await widget.onReschedule(block, start, end);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      setState(() {
        _message = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _syncBlock(ScheduleBlock block) async {
    if (widget.onSync == null) {
      return;
    }

    setState(() {
      _working = true;
      _message = null;
    });

    try {
      final message = await widget.onSync!(block);
      if (!mounted) {
        return;
      }
      setState(() {
        _message = message ?? '${block.title} saved to your account.';
      });
    } catch (error) {
      setState(() {
        _message = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final detail = error.response?.data;
      if (detail is Map && detail['detail'] is String) {
        return detail['detail'] as String;
      }
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _orderedBlocks;
    final canAutoFix = widget.groups.any((group) => group.hasResolvableBlock);
    final hasLocalOnly = ordered.any((block) => block.isLocalOnly);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_busy, color: Color(0xFFFF8A80)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Resolve conflicts',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: _working ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            DateFormat.yMMMEd().format(widget.date),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            canAutoFix
                ? 'Top events stay put. Lower Timely events move to the next open slot.'
                : 'These overlaps are between Google Calendar events. Edit them in Google Calendar.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
          ),
          const SizedBox(height: 16),
          if (hasLocalOnly) ...[
            Text(
              'Events marked "Saved on device only" were created while offline. Tap the cloud icon to save them.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFFFCC80)),
            ),
            const SizedBox(height: 12),
          ],
          for (final group in widget.groups) ...[
            Text(
              formatConflictWindow(group),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: const Color(0xFFFFAB91)),
            ),
            const SizedBox(height: 8),
          ],
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              itemCount: ordered.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) {
                    newIndex -= 1;
                  }
                  final item = _priorityOrder.removeAt(oldIndex);
                  _priorityOrder.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final block = ordered[index];
                final inConflict = widget.groups.any(
                  (group) => group.blocks.any((item) => item.id == block.id),
                );

                return Card(
                  key: ValueKey(block.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  color: inConflict ? const Color(0xFF2A1414) : const Color(0xFF101818),
                  child: ListTile(
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle, color: Colors.white54),
                    ),
                    title: Text(block.title),
                    subtitle: Text(
                      '${DateFormat.jm().format(block.startTime)} · ${block.sourceLabel}',
                    ),
                    trailing: block.isLocalOnly
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Save to account',
                                onPressed: _working ? null : () => _syncBlock(block),
                                icon: const Icon(Icons.cloud_upload_outlined),
                              ),
                              IconButton(
                                tooltip: 'Pick new time',
                                onPressed: _working ? null : () => _pickNewTime(block),
                                icon: const Icon(Icons.schedule),
                              ),
                            ],
                          )
                        : block.isReschedulable
                            ? IconButton(
                                tooltip: 'Pick new time',
                                onPressed: _working ? null : () => _pickNewTime(block),
                                icon: const Icon(Icons.schedule),
                              )
                            : const Icon(Icons.lock_outline, color: Colors.white38, size: 18),
                  ),
                );
              },
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFFFAB91)),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _working || !canAutoFix ? null : _autoFix,
              icon: _working
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high),
              label: Text(canAutoFix ? 'Auto-fix schedule' : 'No movable events'),
            ),
          ),
        ],
      ),
    );
  }
}
