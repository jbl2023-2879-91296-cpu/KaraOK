import 'dart:developer' as developer;

import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/core/storage/analysis_cache.dart';
import 'package:karaok_app/core/storage/guest_assessment_store.dart';
import 'package:karaok_app/features/assessments/data/assessment_api.dart';

class GuestAssessmentMigration {
  GuestAssessmentMigration({GuestAssessmentStore? store, AssessmentApi? api})
    : _store = store ?? GuestAssessmentStore.instance,
      _api = api ?? AssessmentApi();

  final GuestAssessmentStore _store;
  final AssessmentApi _api;

  Future<void> claimForNewAccount() async {
    final userId = UserSession.instance.id;
    if (userId == null) return;
    await _store.claimUnownedForUser(userId);
  }

  Future<int> syncPending() async {
    final userId = UserSession.instance.id;
    if (userId == null) return 0;
    late final List<Map<String, dynamic>> pending;
    try {
      pending = await _store.pendingForUser(userId);
    } catch (error, stackTrace) {
      developer.log(
        'Guest report migration could not read local reports',
        error: error,
        stackTrace: stackTrace,
      );
      return 0;
    }
    var imported = 0;
    for (final record in pending) {
      try {
        final images = Map<String, String>.from(
          record['visualizations'] as Map,
        );
        final response = await _api.importGuestAudioTest(
          receipt: record['guest_import_receipt'] as String,
          visualizations: images,
        );
        final assessmentId = (response['assessment_id'] as num).toInt();
        for (final kind in const ['waveform', 'spectrogram']) {
          final bytes = await _store.visualizationBytes(
            record['local_guest_id'].toString(),
            kind,
          );
          if (bytes != null) {
            await AnalysisCache.instance.saveVisualization(
              assessmentId: assessmentId,
              kind: kind,
              bytes: bytes,
            );
          }
        }
        await _store.markSynced(
          localId: record['local_guest_id'].toString(),
          assessmentId: assessmentId,
        );
        imported++;
      } catch (error, stackTrace) {
        developer.log(
          'Guest report migration will retry later',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (imported > 0) {
      try {
        await _api.getAudioTests();
      } catch (_) {
        // Imported server records remain safe if history refresh is interrupted.
      }
    }
    return imported;
  }
}
