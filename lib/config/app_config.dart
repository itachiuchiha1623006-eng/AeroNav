
class AppConfig {
  AppConfig._();

  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://b8ea-103-153-166-110.ngrok-free.app/api',
  );
}
