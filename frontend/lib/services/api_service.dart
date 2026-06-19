import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/core/constants.dart';
import 'package:kairos/models/brief.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/models/task.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/utils/schedule_conflicts.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

class ApiService {
  ApiService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: AppConstants.apiBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            headers: {
              'X-Firebase-Uid': AppConstants.defaultFirebaseUid,
            },
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['X-Timezone'] = TimezoneService.current;
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

  Future<List<ScheduleBlock>> getTodaySchedule() async {
    final response = await _dio.get<List<dynamic>>('/schedule/today');
    final data = response.data ?? <dynamic>[];
    return data
        .map((item) => ScheduleBlock.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ScheduleBlock>> getMonthSchedule({required int year, required int month}) async {
    final response = await _dio.get<List<dynamic>>(
      '/schedule/month',
      queryParameters: {
        'year': year,
        'month': month,
      },
    );
    final data = response.data ?? <dynamic>[];
    return data
        .map((item) => ScheduleBlock.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> seedDemoSchedule({required int year, required int month}) async {
    await _dio.post<void>(
      '/schedule/seed-demo',
      queryParameters: {
        'year': year,
        'month': month,
      },
    );
  }

  Future<ScheduleBlock> submitRawTask(String text) async {
    final payload = TaskRequest(rawText: text);
    final response = await _dio.post<Map<String, dynamic>>(
      '/tasks/process',
      data: payload.toJson(),
    );
    return ScheduleBlock.fromJson(response.data ?? <String, dynamic>{});
  }

  Future<ScheduleBlock> createEvent(TaskDraft draft) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/tasks/events',
      data: draft.toEventJson(),
    );
    return ScheduleBlock.fromJson(response.data ?? <String, dynamic>{});
  }

  Future<ScheduleBlock> createDeadline(TaskDraft draft) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/tasks/deadlines',
      data: draft.toDeadlineJson(),
    );
    return ScheduleBlock.fromJson(response.data ?? <String, dynamic>{});
  }

  Future<ScheduleBlock> submitTaskDraft(TaskDraft draft) {
    if (draft.timingType == TaskTimingType.event) {
      return createEvent(draft);
    }
    return createDeadline(draft);
  }

  Future<void> triggerReshuffle() async {
    await _dio.post<void>('/schedule/reshuffle');
  }

  Future<ConflictResolveResult> resolveDayConflicts({
    required DateTime date,
    required List<String> priorityBlockIds,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/schedule/resolve-conflicts',
      data: {
        'year': date.year,
        'month': date.month,
        'day': date.day,
        'priority_block_ids': priorityBlockIds,
      },
    );
    final data = response.data ?? <String, dynamic>{};
    return ConflictResolveResult(
      movedCount: (data['moved_count'] as num?)?.toInt() ?? 0,
      unresolved: (data['unresolved'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  Future<ScheduleBlock> updateScheduleBlock({
    required String blockId,
    String? title,
    String? priority,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final payload = <String, dynamic>{};
    if (title != null) {
      payload['title'] = title;
    }
    if (priority != null) {
      payload['priority'] = priority;
    }
    if (startTime != null) {
      payload['start_time'] = startTime.toUtc().toIso8601String();
    }
    if (endTime != null) {
      payload['end_time'] = endTime.toUtc().toIso8601String();
    }

    final response = await _dio.patch<Map<String, dynamic>>(
      '/schedule/blocks/$blockId',
      data: payload,
    );
    return ScheduleBlock.fromJson(response.data ?? <String, dynamic>{});
  }

  Future<ScheduleBlock> rescheduleBlock({
    required String blockId,
    required DateTime startTime,
    required DateTime endTime,
  }) {
    return updateScheduleBlock(
      blockId: blockId,
      startTime: startTime,
      endTime: endTime,
    );
  }

  Future<void> deleteScheduleBlock(String blockId) async {
    await _dio.delete<void>('/schedule/blocks/$blockId');
  }

  Future<void> completeTask(String taskId, {bool completed = true}) async {
    await _dio.post<void>(
      '/tasks/$taskId/complete',
      data: {'completed': completed},
    );
  }

  Future<void> submitDiagnosticResult(String type, int score) async {
    await _dio.post<void>(
      '/diagnostics/log',
      data: {
        'interaction_type': type,
        'energy_score': score,
      },
    );
  }

  Future<void> logNotificationInteraction({
    required String actionId,
    required String actionLabel,
    required String promptText,
    String? scheduledTaskLabel,
    String source = 'notification',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    await _dio.post<void>(
      '/diagnostics/interaction/log',
      data: {
        'action_id': actionId,
        'action_label': actionLabel,
        'prompt_text': promptText,
        'source': source,
        'scheduled_task_label': scheduledTaskLabel,
        'metadata': metadata,
      },
    );
  }

  Future<Map<String, dynamic>> getTodayTimeAnalysis() async {
    final response = await _dio.get<Map<String, dynamic>>('/diagnostics/analysis/today');
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> pushActivityPrompt() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/diagnostics/prompt/push');
      return response.data ?? <String, dynamic>{};
    } on DioException {
      return <String, dynamic>{'success': false};
    }
  }

  Future<Map<String, dynamic>> getTodayReflections() async {
    final response = await _dio.get<Map<String, dynamic>>('/diagnostics/reflections/today');
    return response.data ?? <String, dynamic>{};
  }

  Future<Brief> triggerBrief() async {
    final now = DateTime.now();
    final response = await _dio.post<Map<String, dynamic>>(
      '/brief/trigger',
      options: Options(
        headers: {
          'X-Client-Local-Time': now.toIso8601String(),
          'X-Client-Time-Display': DateFormat.jm().format(now),
        },
      ),
    );
    return Brief.fromJson(response.data ?? <String, dynamic>{});
  }

  // Google integration
  Future<Map<String, dynamic>> getGoogleAccount() async {
    final response = await _dio.get<Map<String, dynamic>>('/google/accounts');
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getGoogleAuthUrl() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/google/auth-url',
      queryParameters: {'user_id': AppConstants.defaultFirebaseUid},
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<void> connectGoogle({required String serverAuthCode}) async {
    await _dio.post<void>(
      '/google/connect',
      data: {
        'server_auth_code': serverAuthCode,
        'user_id': AppConstants.defaultFirebaseUid,
      },
    );
  }

  Future<int> syncGoogleCalendar() async {
    final response = await _dio.post<Map<String, dynamic>>('/google/sync');
    final data = response.data ?? <String, dynamic>{};
    return (data['imported'] as num?)?.toInt() ?? 0;
  }

  Future<void> completeGoogleOAuth({
    required String callbackUrl,
    required String userId,
  }) async {
    await _dio.post<void>(
      '/google/complete',
      data: {
        'callback_url': callbackUrl,
        'user_id': userId,
      },
    );
  }

  Future<bool> disconnectGoogle() async {
    final response = await _dio.delete<Map<String, dynamic>>('/google/disconnect');
    final data = response.data ?? <String, dynamic>{};
    return data['success'] == true;
  }
}
