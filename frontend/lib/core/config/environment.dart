/// Compile-time environment configuration supplied through `--dart-define`.
abstract final class Environment {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000/api',
  );
}
