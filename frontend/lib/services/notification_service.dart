import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/core/constants.dart';
import 'package:kairos/services/api_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.read(apiServiceProvider));
});

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final payload = _decodePayload(response.payload);
  if (payload['kind'] != 'activity_probe') {
    return;
  }

  final actionId = response.actionId ?? 'task_due';
  final actionLabel = _resolveActionLabel(actionId, payload);

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      headers: {
        'X-Firebase-Uid': AppConstants.defaultFirebaseUid,
        'X-Timezone': AppConstants.defaultTimezone,
      },
    ),
  );

  dio.post<void>('/diagnostics/interaction/log', data: {
    'action_id': actionId,
    'action_label': actionLabel,
    'prompt_text': payload['prompt_text'] ?? 'What are you doing',
    'source': 'notification_background',
    'scheduled_task_label': payload['scheduled_task_label'],
    'metadata': {
      'payload_kind': payload['kind'],
      'notification_id': payload['notification_id'],
    },
  });
}

Map<String, dynamic> _decodePayload(String? rawPayload) {
  if (rawPayload == null || rawPayload.isEmpty) {
    return const <String, dynamic>{};
  }
  try {
    final decoded = jsonDecode(rawPayload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {
    return const <String, dynamic>{};
  }
  return const <String, dynamic>{};
}

String _resolveActionLabel(String actionId, Map<String, dynamic> payload) {
  switch (actionId) {
    case 'task_due':
      return payload['task_action_label'] as String? ?? 'Studying for an exam';
    case 'scrolling':
      return 'Scrolling';
    case 'urgent_task':
      return 'Impromptu task to do immediately';
    case 'snooze':
      return 'Snooze';
    default:
      return 'Unknown action';
  }
}

class NotificationService {
  NotificationService(this._apiService);

  final ApiService _apiService;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const AndroidNotificationChannel _highImportanceChannel =
      AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        importance: Importance.high,
      );

  static const int _fullDiagnosticPromptId = 2002;
  static const int _partTimeDiagnosticPromptId = 2003;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_highImportanceChannel);

    final diagnosticChannel = AndroidNotificationChannel(
      'timely_diagnostic_channel',
      'Timely Diagnostics',
      importance: Importance.high,
    );
    await androidPlugin?.createNotificationChannel(diagnosticChannel);

    final briefChannel = AndroidNotificationChannel(
      'timely_brief_channel',
      'Timely Brief',
      importance: Importance.high,
    );
    await androidPlugin?.createNotificationChannel(briefChannel);

    await androidPlugin?.requestNotificationsPermission();

    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      await FirebaseMessaging.instance.subscribeToTopic('timely_diagnostic_test');

      FirebaseMessaging.onMessage.listen((message) async {
        await _showForegroundRemoteNotification(message);
        await _handleForegroundMessage(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) async {
        final type = message.data['type'];
        if (type == 'brief_ready') {
          await showBriefReadyNotification();
        }
      });
    } catch (_) {
      // Firebase is optional in local/dev runs; keep local notifications active.
    }

    _initialized = true;
  }

  Future<void> _showForegroundRemoteNotification(RemoteMessage message) async {
    final notification = message.notification;
    final android = notification?.android;
    if (notification == null || android == null) {
      return;
    }

    await _plugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> showBriefReadyNotification() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'timely_brief_channel',
        'Timely Brief',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      1001,
      'Your Timely Brief is Ready',
      'Tap to open your daily brief.',
      details,
      payload: 'brief_ready',
    );
  }

  Future<void> showDiagnosticNotification() async {
    await showActivityProbeNotification();
  }

  Future<void> showActivityProbeNotification({
    String promptText = 'What are you doing',
    String scheduledTaskLabel = 'Studying for an exam',
  }) async {
    final payload = _activityProbePayload(
      promptText: promptText,
      scheduledTaskLabel: scheduledTaskLabel,
    );

    final details = _activityProbeDetails(scheduledTaskLabel: scheduledTaskLabel);

    await _plugin.show(
      1002,
      promptText,
      'Tick, snooze, or mark distraction now.',
      details,
      payload: payload,
    );
  }

  Future<void> startFullDiagnosticAutoPrompts({
    String scheduledTaskLabel = 'Studying for an exam',
  }) async {
    await initialize();
    await _plugin.cancel(_fullDiagnosticPromptId);

    final details = _activityProbeDetails(scheduledTaskLabel: scheduledTaskLabel);
    final payload = _activityProbePayload(
      promptText: 'What are you doing',
      scheduledTaskLabel: scheduledTaskLabel,
    );

    try {
      await _plugin.periodicallyShow(
        _fullDiagnosticPromptId,
        'What are you doing',
        'Tick, snooze, or mark distraction now.',
        RepeatInterval.hourly,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (_) {
      // Many Android devices block exact alarms unless app-level permission is granted.
      // Fall back to inexact scheduling so full diagnostic reminders still run.
      await _plugin.periodicallyShow(
        _fullDiagnosticPromptId,
        'What are you doing',
        'Tick, snooze, or mark distraction now.',
        RepeatInterval.hourly,
        details,
        androidScheduleMode: AndroidScheduleMode.inexact,
        payload: payload,
      );
    }

    // Trigger one immediate prompt so user sees it right after starting.
    await showActivityProbeNotification(
      promptText: 'What are you doing',
      scheduledTaskLabel: scheduledTaskLabel,
    );
  }

  Future<void> startPartTimeDiagnosticAutoPrompts({
    String scheduledTaskLabel = 'Studying for an exam',
  }) async {
    await initialize();
    await _plugin.cancel(_partTimeDiagnosticPromptId);

    final details = _activityProbeDetails(scheduledTaskLabel: scheduledTaskLabel);
    await _plugin.periodicallyShow(
      _partTimeDiagnosticPromptId,
      'What are you doing',
      'Quick part-time check-in.',
      RepeatInterval.hourly,
      details,
      androidScheduleMode: AndroidScheduleMode.inexact,
      payload: _activityProbePayload(
        promptText: 'What are you doing',
        scheduledTaskLabel: scheduledTaskLabel,
      ),
    );

    await showActivityProbeNotification(
      promptText: 'What are you doing',
      scheduledTaskLabel: scheduledTaskLabel,
    );
  }

  Future<void> stopDiagnosticAutoPrompts() async {
    await _plugin.cancel(_fullDiagnosticPromptId);
    await _plugin.cancel(_partTimeDiagnosticPromptId);
  }

  NotificationDetails _activityProbeDetails({required String scheduledTaskLabel}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'timely_diagnostic_channel',
        'Timely Diagnostics',
        importance: Importance.high,
        priority: Priority.high,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('task_due', scheduledTaskLabel),
          const AndroidNotificationAction('scrolling', 'Scrolling'),
          const AndroidNotificationAction('urgent_task', 'Impromptu Task'),
          const AndroidNotificationAction('snooze', 'Snooze'),
        ],
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  String _activityProbePayload({
    required String promptText,
    required String scheduledTaskLabel,
  }) {
    return jsonEncode({
      'kind': 'activity_probe',
      'prompt_text': promptText,
      'scheduled_task_label': scheduledTaskLabel,
      'task_action_label': scheduledTaskLabel,
      'notification_id': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final type = message.data['type'];
    if (type == 'brief_ready') {
      await showBriefReadyNotification();
      return;
    }

    if (type == 'micro_checkin') {
      await showActivityProbeNotification(
        promptText: message.data['prompt_text'] ?? message.data['prompt'] ?? 'What are you doing',
        scheduledTaskLabel: message.data['scheduled_task_label'] ?? 'Studying for an exam',
      );
      return;
    }

    if (type == 'activity_probe') {
      await showActivityProbeNotification(
        promptText: message.data['prompt_text'] ?? 'What are you doing',
        scheduledTaskLabel: message.data['scheduled_task_label'] ?? 'Studying for an exam',
      );
    }
  }

  Future<void> _onNotificationTap(NotificationResponse response) async {
    if (response.payload == 'brief_ready') {
      return;
    }

    final payload = _decodePayload(response.payload);
    if (payload['kind'] == 'activity_probe') {
      final actionId = response.actionId ?? 'task_due';
      final actionLabel = _resolveActionLabel(actionId, payload);

      await _apiService.logNotificationInteraction(
        actionId: actionId,
        actionLabel: actionLabel,
        promptText: payload['prompt_text'] as String? ?? 'What are you doing',
        scheduledTaskLabel: payload['scheduled_task_label'] as String?,
        source: 'notification_foreground',
        metadata: <String, dynamic>{
          'payload_kind': payload['kind'],
          'notification_id': payload['notification_id'],
        },
      );
    }
  }
}
