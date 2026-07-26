import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local allowance for one successful guest assessment.
///
/// This is intentionally not a server identity or security boundary. Clearing
/// application/browser storage or reinstalling the app can reset the allowance.
class GuestAssessmentService {
  GuestAssessmentService._();

  static final GuestAssessmentService instance = GuestAssessmentService._();
  static const _usedKey = 'karaok_guest_assessment_used_v1';
  static const _storage = FlutterSecureStorage();
  bool _usedThisSession = false;

  Future<bool> hasUsedAssessment() async =>
      _usedThisSession || await _storage.read(key: _usedKey) == 'true';

  Future<bool> canAssess() async => !await hasUsedAssessment();

  Future<void> markAssessmentUsed() async {
    _usedThisSession = true;
    await _storage.write(key: _usedKey, value: 'true');
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    _usedThisSession = false;
    await _storage.delete(key: _usedKey);
  }
}
