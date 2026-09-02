import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';

void main() {
  test('shared backend response fixture parses every recommendation field', () {
    final fixture = Map<String, dynamic>.from(
      jsonDecode(
            File(
              'test/fixtures/settings_recommendation_response.json',
            ).readAsStringSync(),
          )
          as Map,
    );
    final recommendation = SettingsRecommendation.fromJson(fixture);

    expect(fixture.keys.toSet(), {
      'id',
      'persisted',
      'assessment_id',
      'amplifier_profile_id',
      'parent_recommendation_id',
      'status',
      'genre',
      'profile_version',
      'algorithm_version',
      'overall_confidence',
      'scale',
      'current',
      'recommended',
      'adjustments',
      'original_score',
      'verification_score',
      'before_score',
      'after_score',
      'score_change',
      'verification_status',
      'rollback_recommended',
      'verification_token',
      'created_at',
      'applied_at',
    });
    expect(recommendation.id, 41);
    expect(recommendation.persisted, isTrue);
    expect(recommendation.assessmentId, 31);
    expect(recommendation.amplifierProfileId, 12);
    expect(recommendation.parentRecommendationId, isNull);
    expect(recommendation.status, 'reverted');
    expect(recommendation.genre, 'rock');
    expect(recommendation.profileVersion, '2026.09.1');
    expect(recommendation.algorithmVersion, '1.0.0');
    expect(recommendation.overallConfidence, 'medium');
    expect(recommendation.scale.minimum, 0);
    expect(recommendation.scale.maximum, 10);
    expect(recommendation.scale.step, 0.5);
    expect(recommendation.current.toJson(), fixture['current']);
    expect(recommendation.recommended, fixture['recommended']);
    expect(recommendation.adjustments.keys.toSet(), {
      'volume',
      'bass',
      'treble',
      'sharpness',
      'flatness',
    });
    for (final name in recommendation.adjustments.keys) {
      expect(
        recommendation.adjustments[name]!.toJson(),
        (fixture['adjustments'] as Map)[name],
        reason: '$name adjustment must match the backend contract',
      );
    }
    expect(recommendation.originalScore, 72.4);
    expect(recommendation.verificationScore, 68.4);
    expect(recommendation.beforeScore, 72.4);
    expect(recommendation.afterScore, 68.4);
    expect(recommendation.scoreChange, -4.0);
    expect(recommendation.verificationStatus, 'worsened');
    expect(recommendation.rollbackRecommended, isTrue);
    expect(recommendation.verificationToken, isNull);
    expect(recommendation.createdAt, '2026-09-02T00:00:00+00:00');
    expect(recommendation.appliedAt, '2026-09-02T01:00:00+00:00');
    expect(recommendation.toJson(), fixture);
  });
}
