class ApiException implements Exception {
  const ApiException(
    this.statusCode,
    this.message, {
    this.fieldErrors = const {},
    this.retryAfterSeconds,
  });

  final int statusCode;
  final String message;
  final Map<String, String> fieldErrors;
  final int? retryAfterSeconds;

  @override
  String toString() => 'ApiException $statusCode: $message';
}
