import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:kairos/core/constants.dart';

/// Resolves the device IANA timezone (e.g. America/New_York) for API requests.
class TimezoneService {
  TimezoneService._();

  static String _timezone = AppConstants.defaultTimezone;

  static String get current => _timezone;

  static Future<void> initialize() async {
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      if (timezone.isNotEmpty) {
        _timezone = timezone;
      }
    } catch (_) {
      _timezone = AppConstants.defaultTimezone;
    }
  }
}
