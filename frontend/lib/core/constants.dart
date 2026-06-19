class AppConstants {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );
  static const String defaultFirebaseUid = 'demo-user';
  static const String defaultTimezone = 'UTC';
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '920522963940-ni6do3lc2oqtscrlo6f1tqaidgatsn74.apps.googleusercontent.com',
  );
}
