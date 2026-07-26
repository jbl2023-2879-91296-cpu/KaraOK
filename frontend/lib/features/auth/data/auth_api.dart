import 'package:karaok_app/core/network/api_service.dart';

export 'package:karaok_app/core/network/api_exception.dart';

/// Authentication-specific API surface used by the auth and account features.
class AuthApi {
  AuthApi({ApiService? client}) : _client = client ?? ApiService();

  final ApiService _client;

  Future<Map<String, dynamic>> startRegistration({
    required String name,
    required String email,
    required String password,
    required String userType,
  }) => _client.startRegistration(
    name: name,
    email: email,
    password: password,
    userType: userType,
  );

  Future<Map<String, dynamic>> verifyRegistration({
    required String email,
    required String code,
  }) => _client.verifyRegistration(email: email, code: code);

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) => _client.login(identifier: identifier, password: password);

  Future<void> logout() => _client.logout();

  Future<Map<String, dynamic>> requestPasswordReset(String email) =>
      _client.requestPasswordReset(email);

  Future<void> changePassword({
    String? currentPassword,
    required String newPassword,
  }) => _client.changePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  Future<void> clearTokens() => _client.clearTokens();
}
