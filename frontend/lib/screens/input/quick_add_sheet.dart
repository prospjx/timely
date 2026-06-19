import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kairos/models/task.dart';

class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({
    super.key,
    required this.onSubmit,
    this.initialDeadline,
  });

  final Future<void> Function(TaskDraft) onSubmit;
  final DateTime? initialDeadline;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final TextEditingController _titleController = TextEditingController();
  late DateTime _scheduledAt;
  final TextEditingController _durationController = TextEditingController(text: '60');
  PriorityCode _priority = PriorityCode.b;
  TaskTimingType _timingType = TaskTimingType.deadline;
  bool _isSubmitting = false;
  String? _errorMessage;

  DateTime _defaultDeadlineFor(DateTime? initialDeadline) {
    final now = DateTime.now();
    final candidate = initialDeadline ?? now.add(const Duration(hours: 4));

    if (initialDeadline == null) {
      return candidate;
    }

    final hasTimeComponent = candidate.hour != 0 || candidate.minute != 0 || candidate.second != 0;
    if (hasTimeComponent) {
      return candidate;
    }

    final normalized = DateTime(candidate.year, candidate.month, candidate.day, now.hour, now.minute);
    final minimumUsefulTime = now.add(const Duration(minutes: 30));
    return normalized.isBefore(minimumUsefulTime) ? minimumUsefulTime : normalized;
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 409) {
        final data = error.response?.data;
        if (data is Map && data['detail'] != null) {
          return data['detail'].toString();
        }
        return 'This time slot conflicts with another activity. Please choose another time.';
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Connection timed out. Please check if the backend server is running.';
      }

      return 'Could not save your task right now. Please try again.';
    }

    return 'Could not save your task right now. Please try again.';
  }

  @override
  void initState() {
    super.initState();
    _scheduledAt = _defaultDeadlineFor(widget.initialDeadline);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final durationMinutes = int.tryParse(_durationController.text.trim()) ?? 60;
    if (title.isEmpty || _isSubmitting) {
      return;
    }

    if (durationMinutes < 15) {
      setState(() {
        _errorMessage = 'Duration must be at least 15 minutes.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await widget.onSubmit(
        TaskDraft(
          title: title,
          priority: _priority,
          scheduledAt: _scheduledAt,
          timingType: _timingType,
          durationMinutes: durationMinutes,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyError(error);
      setState(() {
        _errorMessage = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );

    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _scheduledAt.hour,
        time?.minute ?? _scheduledAt.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Event or Deadline', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            minLines: 1,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Task title (e.g. Read chapter 4 for biology)',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PriorityCode>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: const [
              DropdownMenuItem(value: PriorityCode.a, child: Text('A - Top priority')),
              DropdownMenuItem(value: PriorityCode.b, child: Text('B - Medium priority')),
              DropdownMenuItem(value: PriorityCode.c, child: Text('C - Low priority')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _priority = value;
                _errorMessage = null;
              });
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<TaskTimingType>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: TaskTimingType.deadline,
                label: Text('Deadline'),
                icon: Icon(Icons.flag_outlined),
              ),
              ButtonSegment(
                value: TaskTimingType.event,
                label: Text('Event'),
                icon: Icon(Icons.event),
              ),
            ],
            selected: <TaskTimingType>{_timingType},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) {
                return;
              }
              setState(() {
                _timingType = selection.first;
                _errorMessage = null;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _durationController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _timingType == TaskTimingType.event
                  ? 'Event Duration (minutes)'
                  : 'Estimated Duration (minutes)',
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDeadline,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: _timingType == TaskTimingType.event ? 'Event Start Time' : 'Deadline Time',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(DateFormat('EEE, MMM d • HH:mm').format(_scheduledAt)),
            ),
          ),
          const SizedBox(height: 12),
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add to Schedule'),
            ),
          ),
        ],
      ),
    );
  }
}
