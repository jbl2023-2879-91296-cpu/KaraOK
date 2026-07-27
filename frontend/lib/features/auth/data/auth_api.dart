import 'package:karaok_app/core/network/api_service.dart';

export 'package:karaok_app/core/network/api_exception.dart';

/// Authentication-specific API surface used by the auth and account features.
class AuthApi {
  AuthApi({ApiService? client}) : _client = client ?? ApiService();

  final ApiService _client;

  Future<Map<String, dynamic>> startRegistration({
    required String username,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String address,
    required String city,
    required String stateProvince,
    required String areaCode,
    required String country,
    required String countryCode,
    required String phoneNumber,
    required String birthday,
    String? profileImageBase64,
    String? profileImageMime,
  }) => _client.startRegistration(
    username: username,
    firstName: firstName,
    lastName: lastName,
    email: email,
    password: password,
    address: address,
    city: city,
    stateProvince: stateProvince,
    areaCode: areaCode,
    country: country,
    countryCode: countryCode,
    phoneNumber: phoneNumber,
    birthday: birthday,
    profileImageBase64: profileImageBase64,
    profileImageMime: profileImageMime,
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
