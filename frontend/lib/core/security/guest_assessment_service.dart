import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local allowance for successful guest assessments.
///
/// This is intentionally not a server identity or security boundary. Clearing
/// application/browser storage or reinstalling the app can reset the allowance.
class GuestAssessmentService {
  GuestAssessmentService._();

  static final GuestAssessmentService instance = GuestAssessmentService._();
  static const maxAttempts = 3;
  static const _countKey = 'karaok_guest_assessment_count_v2';
  static const _legacyUsedKey = 'karaok_guest_assessment_used_v1';
  static const _storage = FlutterSecureStorage();
  int? _sessionCount;

  Future<int> usedAttempts() async {
    if (_sessionCount != null) return _sessionCount!;
    final stored = int.tryParse(await _storage.read(key: _countKey) ?? '');
    if (stored != null) {
      _sessionCount = stored.clamp(0, maxAttempts);
      return _sessionCount!;
    }

    // Preserve a previous guest's single completed assessment when upgrading.
    final usedLegacy = await _storage.read(key: _legacyUsedKey) == 'true';
    _sessionCount = usedLegacy ? 1 : 0;
    return _sessionCount!;
  }

  Future<int> remainingAttempts() async => maxAttempts - await usedAttempts();

  Future<bool> hasUsedAssessment() async => await usedAttempts() > 0;

  Future<bool> canAssess() async => await remainingAttempts() > 0;

  Future<void> markAssessmentUsed() async {
    final next = ((await usedAttempts()) + 1).clamp(0, maxAttempts);
    _sessionCount = next;
    await _storage.write(key: _countKey, value: '$next');
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    _sessionCount = null;
    await _storage.delete(key: _countKey);
    await _storage.delete(key: _legacyUsedKey);
  }
}
