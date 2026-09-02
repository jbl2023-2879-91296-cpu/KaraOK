/// Compile-time environment configuration supplied through `--dart-define`.
abstract final class Environment {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:5000/api',
  );
}
