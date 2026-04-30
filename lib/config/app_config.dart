
class AppConfig {
  AppConfig._();

  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://horribly-fun-guinea.ngrok-free.app/api',
  );
}
