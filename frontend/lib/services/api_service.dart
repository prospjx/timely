import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/core/constants.dart';
import 'package:kairos/models/brief.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/models/task.dart';

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
              'X-Timezone': AppConstants.defaultTimezone,
            },
          ),
        );

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

  Future<ScheduleBlock> submitTaskDraft(TaskDraft draft) {
    return submitRawTask(draft.toRawText());
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
    try {
      final response = await _dio.get<Map<String, dynamic>>('/diagnostics/analysis/today');
      return response.data ?? <String, dynamic>{};
    } on DioException {
      return <String, dynamic>{};
    }
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
    try {
      final response = await _dio.get<Map<String, dynamic>>('/diagnostics/reflections/today');
      return response.data ?? <String, dynamic>{};
    } on DioException {
      return <String, dynamic>{};
    }
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
}
