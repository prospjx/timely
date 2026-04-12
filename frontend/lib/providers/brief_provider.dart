import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/models/brief.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/providers/schedule_provider.dart';
import 'package:kairos/services/api_service.dart';

final briefControllerProvider = AsyncNotifierProvider<BriefController, Brief?>(
  BriefController.new,
);

class BriefController extends AsyncNotifier<Brief?> {
  @override
  Future<Brief?> build() async {
    return _loadBriefWithFallback();
  }

  Future<void> refreshBrief() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_loadBriefWithFallback);
  }

  Future<Brief> _loadBriefWithFallback() async {
    try {
      return await ref.read(apiServiceProvider).triggerBrief();
    } catch (_) {
      return _buildOfflineBrief();
    }
  }

  Brief _buildOfflineBrief() {
    final now = DateTime.now();
    final schedule = ref.read(scheduleProvider).valueOrNull ?? const <ScheduleBlock>[];

    final today = schedule
        .where(
          (item) =>
              item.startTime.year == now.year &&
              item.startTime.month == now.month &&
              item.startTime.day == now.day,
        )
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final count = today.length;
    final lead =
      'Here is your daily brief. You have $count ${count == 1 ? 'task' : 'tasks'} scheduled today.';

    if (today.isEmpty) {
      return Brief(
        success: true,
        text: '$lead Enjoy your day and add a task when you are ready.',
        audioUrl: null,
      );
    }

    final preview = today.take(3).map((item) {
      final time = DateFormat.jm().format(item.startTime);
      return 'At $time: ${item.title}';
    }).join(' ');

    return Brief(
      success: true,
      text: '$lead $preview',
      audioUrl: null,
    );
  }
}
