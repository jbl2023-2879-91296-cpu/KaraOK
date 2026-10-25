import 'package:karaok_app/features/sound_settings/data/settings_api.dart';
import 'package:karaok_app/shared/widgets/app_widgets.dart';
import '../support/settle_with_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';
import 'package:karaok_app/features/sound_settings/presentation/pages/settings_recommendation_screen.dart';

void main() {
  for (final entry in const {
    'below_genre_range': 'more note-like',
    'above_genre_range': 'more noise-like',
  }.entries) {
    _screenTest('flatness explains ${entry.key} as ${entry.value}', (
      tester,
    ) async {
      await tester.pumpWidget(
        _testApp(
          SettingsRecommendationScreen(
            recommendation: _sample(reasonCode: entry.key),
          ),
        ),
      );
      expect(
        find.text(
          'Your recording was ${entry.value} than the songs we compared it with.',
        ),
        findsOneWidget,
      );
    });
  }

  _screenTest(
    'shows named profile, plain knob reasons and verification near the top',
    (tester) async {
      final data = _sample(reasonCode: 'above_genre_range').toJson();
      data['amplifier_profile_name'] = 'Living room';
      await tester.pumpWidget(
        _testApp(
          SettingsRecommendationScreen(
            recommendation: SettingsRecommendation.fromJson(data),
          ),
        ),
      );
      expect(
        find.textContaining(
          'These settings are a starting point for Living room.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Your recording was brighter than the songs we compared it with.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('verify-settings'))).dy,
        lessThan(tester.getTopLeft(find.text('Volume')).dy),
      );
    },
  );

  _screenTest('feedback saves each choice and stays selected after reopening', (
    tester,
  ) async {
    UserSession.instance.clear();
    final api = _FeedbackApi();
    for (final value in ['better', 'same', 'worse']) {
      await tester.pumpWidget(
        _testApp(
          SettingsRecommendationScreen(
            key: UniqueKey(),
            recommendation: api.saved,
            settingsApi: api,
          ),
        ),
      );
      expect(find.text('Did this sound better?'), findsOneWidget);
      await tester.ensureVisible(find.byKey(Key('feedback-$value')));
      await tester.tap(find.byKey(Key('feedback-$value')));
      await tester.pumpAndSettle();
      expect(api.saved.feedback, value);
      expect(
        tester.widget<ChoiceChip>(find.byKey(Key('feedback-$value'))).selected,
        isTrue,
      );
      expect(find.text('Your answer is saved.'), findsOneWidget);
    }
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          key: UniqueKey(),
          recommendation: api.saved,
          settingsApi: api,
        ),
      ),
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('feedback-worse')))
          .selected,
      isTrue,
    );
  });

  _screenTest('failed feedback preserves answer and lets the listener retry', (
    tester,
  ) async {
    UserSession.instance.clear();
    final api = _FeedbackApi()..fail = true;
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          recommendation: api.saved,
          settingsApi: api,
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('feedback-better')));
    await tester.tap(find.byKey(const Key('feedback-better')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save your answer.'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('feedback-better')))
          .selected,
      isFalse,
    );
    api.fail = false;
    await tester.tap(find.byKey(const Key('feedback-better')));
    await tester.pumpAndSettle();
    expect(find.text('Your answer is saved.'), findsOneWidget);
  });

  _screenTest('guest recommendations do not claim to save feedback', (
    tester,
  ) async {
    UserSession.instance.setGuest('user');
    addTearDown(UserSession.instance.clear);
    await tester.pumpWidget(
      _testApp(SettingsRecommendationScreen(recommendation: _sample())),
    );
    expect(find.text('Did this sound better?'), findsNothing);
  });

  _screenTest(
    'attenuation decrease is shown as louder and survives round trip',
    (tester) async {
      final data = _sample().toJson();
      data['current']['volume'] = 60.0;
      data['current']['volume_attenuation'] = true;
      data['recommended']['volume'] = 50.0;
      data['recommended']['volume_attenuation'] = true;
      data['adjustments']['volume'] = {
        'current': 60.0,
        'recommended': 50.0,
        'delta': -10.0,
        'delta_normalized': 10.0,
        'reason_code': 'below_genre_range',
        'confidence': 'low',
      };
      final recommendation = SettingsRecommendation.fromJson(data);
      expect(
        SettingsRecommendation.fromJson(
          recommendation.toJson(),
        ).current.volumeAttenuation,
        isTrue,
      );
      await tester.pumpWidget(
        _testApp(SettingsRecommendationScreen(recommendation: recommendation)),
      );
      expect(find.text('50 → 60'), findsOneWidget);
      expect(find.text('Louder'), findsOneWidget);
      expect(
        find.byKey(const Key('direction-volume-increase')),
        findsOneWidget,
      );
    },
  );
  _screenTest('Done returns to Home and removes every workflow route', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.instance.setGuest('user');
    addTearDown(UserSession.instance.clear);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Setup route')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Recording route')),
      ),
    );
    await settleWithStorage(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsRecommendationScreen(recommendation: _sample()),
      ),
    );
    await settleWithStorage(tester);
    await tester.ensureVisible(find.text('Done — Back to Main Page'));
    await tester.tap(find.text('Done — Back to Main Page'));
    await settleWithStorage(tester);
    expect(find.byType(AppShell), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(navigator.currentState!.canPop(), isFalse);
    expect(find.text('Setup route', skipOffstage: false), findsNothing);
    expect(find.text('Recording route', skipOffstage: false), findsNothing);
  });
  _screenTest('renders changes and hides unchanged optional controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(SettingsRecommendationScreen(recommendation: _sample())),
    );

    expect(find.byType(AppPageScaffold), findsOneWidget);
    expect(find.byType(AppSectionHeader), findsOneWidget);
    for (final label in const ['Volume', 'Bass', 'Treble', 'Flatness']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('4.0 → 5.5'), findsOneWidget);
    expect(find.text('+1.5'), findsOneWidget);
    expect(find.text('Sharpness'), findsNothing);
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
    expect(find.text('Done — Back to Main Page'), findsOneWidget);
    final verify = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(const Key('verify-settings')),
        matching: find.byType(OutlinedButton),
      ),
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

class _FeedbackApi extends SettingsApi {
  SettingsRecommendation saved = _sample();
  bool fail = false;

  @override
  Future<SettingsRecommendation> saveFeedback(
    int recommendationId,
    String feedback,
  ) async {
    if (fail) throw Exception('Offline');
    saved = SettingsRecommendation.fromJson({
      ...saved.toJson(),
      'feedback': feedback,
    });
    return saved;
  }
}
