import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The only component allowed to persist API credentials on the device.
class SecureTokenStore {
  SecureTokenStore._();

  static final SecureTokenStore instance = SecureTokenStore._();

  static const _accessTokenKey = 'karaok_access_token';
  static const _refreshTokenKey = 'karaok_refresh_token';
  static const _storage = FlutterSecureStorage();

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
