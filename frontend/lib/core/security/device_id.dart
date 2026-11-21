import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:karaok_app/core/security/secure_token_store.dart';

class DeviceId {
  static const _key = 'karaok_device_id';
  static Future<String>? _initialization;

  static Future<String> get() => _initialization ??= _initialize();

  /// Widget tests run each test in its own fake-async zone; a lookup started in
  /// an earlier test may never complete in a later one, so tests reset it.
  @visibleForTesting
  static void resetForTesting() => _initialization = null;

  static Future<String> _initialize() async {
    final store = SecureTokenStore.instance;
    final random = Random.secure();
    final generated = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    try {
      final saved = await store.readAuthState(_key);
      if (saved != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(saved)) {
        return saved;
      }
      await store.writeAuthState(_key, generated);
    } catch (_) {
      // Retain a stable ID for this process if secure storage is unavailable.
    }
    return generated;
  }
}
