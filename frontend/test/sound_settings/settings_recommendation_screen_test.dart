import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';
import 'package:karaok_app/features/sound_settings/presentation/pages/settings_recommendation_screen.dart';

void main() {
  _screenTest('renders all five current to recommended settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(SettingsRecommendationScreen(recommendation: _sample())),
    );

    for (final label in const [
      'Volume',
      'Bass',
      'Treble',
      'Sharpness',
      'Flatness',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('4.0 → 5.5'), findsOneWidget);
    expect(find.text('+1.5'), findsOneWidget);
    expect(find.byKey(const Key('direction-bass-increase')), findsOneWidget);
  });

  _screenTest('verification remains optional and disabled before apply', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(SettingsRecommendationScreen(recommendation: _sample())),
    );

    expect(find.text("I've Applied These Settings"), findsOneWidget);
    expect(find.text('Record Again to Verify'), findsOneWidget);
    expect(find.text('Finish Without Verification'), findsOneWidget);
    final verify = tester.widget<OutlinedButton>(
      find.byKey(const Key('verify-settings')),
    );
    expect(verify.onPressed, isNull);
  });

  _screenTest('unavailable result keeps the score and explains the blocker', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          recommendation: _sample(
            status: 'unavailable',
            reasonCode: 'genre_profile_unavailable',
            message:
                'Genre calibration data is unavailable. Please try again later.',
          ),
        ),
      ),
    );

    expect(find.text('Quality score: 72.0'), findsOneWidget);
    expect(
      find.text(
        'Genre calibration data is unavailable. Please try again later.',
      ),
      findsOneWidget,
    );
    expect(find.text('Record Again'), findsOneWidget);
    expect(find.text("I've Applied These Settings"), findsNothing);
  });

  _screenTest('shows analyzer safety warning before adjustment cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          recommendation: _sample(
            volumeReasonCode: 'volume_increase_blocked_by_clipping',
          ),
        ),
      ),
    );

    final warning = find.text(
      'Clipping was detected, so KaraOK will not increase volume.',
    );
    expect(warning, findsOneWidget);
    expect(
      tester.getTopLeft(warning).dy,
      lessThan(tester.getTopLeft(find.text('Volume')).dy),
    );
  });

  _screenTest('shows noise and distortion safety signals above cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          recommendation: _sample(),
          safetySignals: const {
            'excessive_noise': true,
            'excessive_distortion': true,
          },
        ),
      ),
    );

    final noise = find.text(
      'Background noise is high and may reduce recommendation confidence.',
    );
    expect(noise, findsOneWidget);
    expect(
      find.text('Distortion is high and may reduce recommendation confidence.'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(noise).dy,
      lessThan(tester.getTopLeft(find.text('Volume')).dy),
    );
  });

  _screenTest('worse verification recommends rollback', (tester) async {
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          recommendation: _sample(
            parentRecommendationId: 41,
            verificationScore: 68,
            rollbackRecommended: true,
          ),
        ),
      ),
    );

    expect(find.text('Return to your previous settings'), findsOneWidget);
    expect(find.text('Before: 72.0'), findsOneWidget);
    expect(find.text('After: 68.0'), findsOneWidget);
    expect(find.text('Score change: -4.0'), findsOneWidget);
  });
}

Widget _testApp(Widget home) => MaterialApp(home: home);

void _screenTest(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await callback(tester);
  });
}

SettingsRecommendation _sample({
  String status = 'generated',
  String reasonCode = 'within_genre_range',
  String? volumeReasonCode,
  int? parentRecommendationId,
  double? verificationScore,
  bool rollbackRecommended = false,
  String? message,
}) {
  const current = {
    'volume': 5.0,
    'bass': 4.0,
    'treble': 6.0,
    'sharpness': 5.0,
    'flatness': 5.0,
  };
  final recommended = status == 'unavailable'
      ? <String, double?>{for (final name in current.keys) name: null}
      : <String, double?>{
          'volume': 5.0,
          'bass': 5.5,
          'treble': 5.5,
          'sharpness': 5.0,
          'flatness': 4.5,
        };
  return SettingsRecommendation.fromJson({
    'id': 41,
    'persisted': true,
    'assessment_id': 11,
    'amplifier_profile_id': 12,
    'parent_recommendation_id': parentRecommendationId,
    'status': status,
    'genre': 'rock',
    'profile_version': message == null ? '2026.09.1' : null,
    'profile_checksum': message == null
        ? '8b87b9f1106bab8dab4978e4590e84c9bb294400a0d60ce5263e196f44701b61'
        : null,
    'message': ?message,
    'algorithm_version': '1.0.0',
    'overall_confidence': status == 'unavailable' ? 'unavailable' : 'medium',
    'scale': {'minimum': 0.0, 'maximum': 10.0, 'step': 0.5},
    'current': current,
    'recommended': recommended,
    'adjustments': {
      for (final entry in current.entries)
        entry.key: {
          'current': entry.value,
          'recommended': recommended[entry.key],
          'delta': recommended[entry.key] == null
              ? null
              : recommended[entry.key]! - entry.value,
          'delta_normalized': recommended[entry.key] == null ? null : 0.0,
          'reason_code': entry.key == 'volume'
              ? volumeReasonCode ?? reasonCode
              : reasonCode,
          'confidence': status == 'unavailable' ? 'unavailable' : 'medium',
        },
    },
    'original_score': 72.0,
    'verification_score': verificationScore,
    'before_score': 72.0,
    'after_score': verificationScore,
    'score_change': verificationScore == null ? null : verificationScore - 72.0,
    'verification_status': verificationScore == null
        ? 'not_verified'
        : verificationScore < 72
        ? 'worsened'
        : 'improved',
    'rollback_recommended': rollbackRecommended,
    'verification_token': null,
    'created_at': '2026-09-02T00:00:00Z',
    'applied_at': null,
  });
}
