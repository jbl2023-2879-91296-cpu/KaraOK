import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';

void main() {
  const scale = AmplifierScale(minimum: 0, maximum: 10, step: 0.5);
  const current = KnobSettings(
    volume: 5,
    bass: 4,
    treble: 6,
    sharpness: 5,
    flatness: 5,
  );

  test('0-10 settings normalize and round-trip at half steps', () {
    expect(scale.normalize(5.5), 55);
    expect(scale.denormalize(57), 5.5);
    expect(scale.denormalize(-20), 0);
    expect(scale.denormalize(120), 10);
  });

  test('custom decimal steps do not leak floating-point artifacts', () {
    const decimalScale = AmplifierScale(minimum: 0, maximum: 1, step: 0.1);

    expect(decimalScale.denormalize(30), 0.3);
  });

  test('scale and knob JSON reject non-finite and out-of-range values', () {
    expect(
      () => AmplifierScale.fromJson({
        'minimum': 0,
        'maximum': double.infinity,
        'step': 0.5,
      }),
      throwsFormatException,
    );
    expect(
      () => KnobSettings.fromJson({
        'volume': 11,
        'bass': 4,
        'treble': 6,
        'sharpness': 5,
        'flatness': 5,
      }, scale: scale),
      throwsFormatException,
    );
    expect(
      () => KnobSettings.fromJson({
        'volume': 5,
        'bass': 4,
        'treble': 6,
        'sharpness': 5,
        'flatness': 5,
        'echo': 3,
      }, scale: scale),
      throwsFormatException,
    );
  });

  test('amplifier profile parses backend JSON and round-trips', () {
    final profile = AmplifierProfile.fromJson({
      'id': 12,
      'name': 'Stage Amp',
      'scale_min': 0,
      'scale_max': 10,
      'scale_step': 0.5,
      'last_positions': current.toJson(),
      'created_at': '2026-09-02T01:02:03Z',
      'updated_at': null,
    });

    expect(profile.id, 12);
    expect(profile.name, 'Stage Amp');
    expect(profile.scale, scale);
    expect(profile.lastPositions, current);
    expect(AmplifierProfile.fromJson(profile.toJson()), profile);
  });

  test('suggestion input serializes the matching guest context', () {
    final fields = SettingsSuggestionInput(
      genre: '  HipHop  ',
      amplifierScale: scale,
      currentSettings: current,
      verificationToken: 'signed-token',
    ).toMultipartFields();

    expect(fields['genre'], 'hip-hop');
    expect(jsonDecode(fields['amplifier_scale']!), {
      'minimum': 0.0,
      'maximum': 10.0,
      'step': 0.5,
    });
    expect(jsonDecode(fields['current_settings']!), {
      'volume': 5.0,
      'bass': 4.0,
      'treble': 6.0,
      'sharpness': 5.0,
      'flatness': 5.0,
    });
    expect(fields['verification_token'], 'signed-token');
    expect(fields, isNot(contains('amplifier_profile_id')));
  });

  test('suggestion input serializes authenticated IDs without guest scale', () {
    final fields = SettingsSuggestionInput(
      genre: 'Rock',
      amplifierProfileId: 12,
      currentSettings: current,
      verificationOf: 41,
    ).toMultipartFields();

    expect(fields['genre'], 'rock');
    expect(fields['amplifier_profile_id'], '12');
    expect(fields['verification_of'], '41');
    expect(fields, isNot(contains('amplifier_scale')));
    expect(fields, isNot(contains('verification_token')));
  });

  test('suggestion input rejects mixed contexts and verification methods', () {
    expect(
      () => SettingsSuggestionInput(
        genre: 'rock',
        amplifierScale: scale,
        amplifierProfileId: 12,
        currentSettings: current,
      ),
      throwsArgumentError,
    );
    expect(
      () => SettingsSuggestionInput(
        genre: 'rock',
        amplifierScale: scale,
        currentSettings: current,
        verificationOf: 41,
        verificationToken: 'signed-token',
      ),
      throwsArgumentError,
    );
  });

  test('suggestion verification matches guest or authenticated context', () {
    expect(
      () => SettingsSuggestionInput(
        genre: 'rock',
        amplifierScale: scale,
        currentSettings: current,
        verificationOf: 41,
      ),
      throwsArgumentError,
    );
    expect(
      () => SettingsSuggestionInput(
        genre: 'rock',
        amplifierProfileId: 12,
        currentSettings: current,
        verificationToken: 'signed-token',
      ),
      throwsArgumentError,
    );
  });

  test('recommendation requires all five adjustments', () {
    final incomplete = _recommendationJson();
    (incomplete['adjustments'] as Map<String, dynamic>).remove('flatness');

    expect(
      () => SettingsRecommendation.fromJson(incomplete),
      throwsFormatException,
    );
  });

  test('recommendation parses guest verification and comparison fields', () {
    final recommendation = SettingsRecommendation.fromJson(
      _recommendationJson(),
    );

    expect(recommendation.id, isNull);
    expect(recommendation.persisted, isFalse);
    expect(recommendation.adjustments.keys, {
      'volume',
      'bass',
      'treble',
      'sharpness',
      'flatness',
    });
    expect(recommendation.adjustments['bass']!.recommended, 4.5);
    expect(recommendation.verificationToken, 'signed-token');
    expect(recommendation.beforeScore, 72);
    expect(recommendation.afterScore, isNull);
    expect(recommendation.rollbackRecommended, isFalse);
  });

  test('recommendation rejects disagreement between five-knob payloads', () {
    final malformed = _recommendationJson();
    final bass =
        (malformed['adjustments'] as Map<String, dynamic>)['bass']
            as Map<String, dynamic>;
    bass['current'] = 9.5;

    expect(
      () => SettingsRecommendation.fromJson(malformed),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _recommendationJson() {
  const current = {
    'volume': 5.0,
    'bass': 4.0,
    'treble': 6.0,
    'sharpness': 5.0,
    'flatness': 5.0,
  };
  const recommended = {
    'volume': 5.5,
    'bass': 4.5,
    'treble': 5.5,
    'sharpness': 5.0,
    'flatness': 4.5,
  };
  return {
    'id': null,
    'persisted': false,
    'amplifier_profile_id': null,
    'parent_recommendation_id': null,
    'status': 'generated',
    'genre': 'rock',
    'profile_version': '2026.09.1',
    'algorithm_version': '1.0.0',
    'overall_confidence': 'medium',
    'scale': {'minimum': 0.0, 'maximum': 10.0, 'step': 0.5},
    'current': current,
    'recommended': recommended,
    'adjustments': {
      for (final name in current.keys)
        name: {
          'current': current[name],
          'recommended': recommended[name],
          'delta': recommended[name]! - current[name]!,
          'delta_normalized': 5.0,
          'reason_code': 'toward_genre_target',
          'confidence': 'medium',
        },
    },
    'original_score': 72.0,
    'verification_score': null,
    'before_score': 72.0,
    'after_score': null,
    'score_change': null,
    'verification_status': 'not_verified',
    'rollback_recommended': false,
    'verification_token': 'signed-token',
  };
}
