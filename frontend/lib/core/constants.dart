class AppConstants {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );
  static const String defaultFirebaseUid = 'demo-user';
  static const String defaultTimezone = 'UTC';
}
