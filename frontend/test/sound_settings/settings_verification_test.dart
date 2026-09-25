import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/previous_results_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';
import 'package:karaok_app/features/sound_settings/data/guest_amplifier_store.dart';
import 'package:karaok_app/features/sound_settings/data/settings_api.dart';
import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';
import 'package:karaok_app/features/sound_settings/presentation/pages/settings_recommendation_screen.dart';

void main() {
  late _FakeSettingsApi settingsApi;
  late _FakeGuestAmplifierStore guestStore;

  setUp(() {
    UserSession.instance.setGuest('user');
    settingsApi = _FakeSettingsApi();
    guestStore = _FakeGuestAmplifierStore();
  });

  tearDown(UserSession.instance.clear);

  _screenTest('guest apply saves targets and enables token verification', (
    tester,
  ) async {
    SettingsSuggestionInput? verification;
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          recommendation: _sample(guest: true, verificationToken: 'guest-jwt'),
          settingsApi: settingsApi,
          guestStore: guestStore,
          onVerify: (value) => verification = value,
        ),
      ),
    );

    var verifyButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('verify-settings')),
    );
    expect(verifyButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('apply-settings')));
    await tester.pumpAndSettle();

    expect(guestStore.saved?.lastPositions?.bass, 5.5);
    verifyButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('verify-settings')),
    );
    expect(verifyButton.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('verify-settings')));
    await tester.pumpAndSettle();

    expect(verification?.verificationToken, 'guest-jwt');
    expect(verification?.verificationOf, isNull);
    expect(verification?.amplifierScale?.maximum, 10);
    expect(verification?.current.bass, 5.5);
  });

  _screenTest('authenticated apply enables ID based verification', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    settingsApi.applied = _sample(status: 'applied');
    SettingsSuggestionInput? verification;
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          recommendation: _sample(),
          settingsApi: settingsApi,
          guestStore: guestStore,
          onVerify: (value) => verification = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('apply-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verify-settings')));
    await tester.pumpAndSettle();

    expect(settingsApi.appliedId, 41);
    expect(verification?.verificationOf, 41);
    expect(verification?.verificationToken, isNull);
    expect(verification?.amplifierProfileId, 12);
    expect(verification?.current.flatness, 4.5);
  });

  _screenTest('verification result never offers another verification pass', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          recommendation: _sample(parentRecommendationId: 41),
          settingsApi: settingsApi,
          guestStore: guestStore,
        ),
      ),
    );

    expect(find.text('Record Again to Verify'), findsNothing);
    expect(find.text('Done — Back to Main Page'), findsOneWidget);
  });

  _screenTest('terminal parent status never offers a second verification', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          recommendation: _sample(status: 'verified'),
          settingsApi: settingsApi,
          guestStore: guestStore,
        ),
      ),
    );

    expect(find.text('Record Again to Verify'), findsNothing);
    expect(find.text('Done — Back to Main Page'), findsOneWidget);
  });

  _screenTest('guest result without a token hides verification action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        SettingsRecommendationScreen(
          recommendation: _sample(guest: true),
          settingsApi: settingsApi,
          guestStore: guestStore,
        ),
      ),
    );

    expect(find.text('Record Again to Verify'), findsNothing);
  });

  test('settings upload result selects the recommendation screen', () {
    final destination = audioResultDestination(
      record: {
        'analysis_purpose': 'settings_suggestion',
        'safety_signals': {'excessive_noise': true},
        'settings_recommendation': _sample().toJson(),
      },
      purpose: AudioAnalysisPurpose.settingsSuggestion,
      isGuest: false,
    );

    expect(destination, isA<SettingsRecommendationScreen>());
    final screen = destination as SettingsRecommendationScreen;
    expect(screen.recommendation.id, 41);
    expect(screen.safetySignals['excessive_noise'], isTrue);
  });

  test('quality upload result retains the original results screen', () {
    final destination = audioResultDestination(
      record: const {
        'analysis_purpose': 'quality_evaluation',
        'test_name': 'quality.wav',
        'score': 81.0,
      },
      purpose: AudioAnalysisPurpose.qualityEvaluation,
      isGuest: false,
    );

    expect(destination, isA<ResultsScreen>());
  });

  _screenTest('records reopen a stored settings recommendation', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    final record = <String, dynamic>{
      'id': 11,
      'test_name': 'settings.wav',
      'score': 72.0,
      'status': 'Needs Improvement',
      'created_at': '2026-09-02T00:00:00Z',
      'analysis_purpose': 'settings_suggestion',
      'settings_recommendation': _sample().toJson(),
    };
    await tester.pumpWidget(
      _testApp(PreviousResultsScreen(resultsLoader: () async => [record])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('settings.wav'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsRecommendationScreen), findsOneWidget);
    expect(find.text('Generated Settings'), findsOneWidget);
    await tester.tap(find.text('View Audio Assessment'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultsScreen), findsOneWidget);
    expect(find.text('View Generated Settings'), findsOneWidget);
  });

  _screenTest(
    'recent analysis result retains saved settings beside assessment',
    (tester) async {
      final record = <String, dynamic>{
        'test_name': 'saved.wav',
        'score': 72.0,
        'analysis_purpose': 'settings_suggestion',
        'settings_recommendation': _sample().toJson(),
      };
      await tester.pumpWidget(_testApp(ResultsScreen.fromRecord(record)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View Generated Settings'));
      await tester.tap(find.text('View Generated Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsRecommendationScreen), findsOneWidget);
      expect(find.text('4.0 → 5.5'), findsOneWidget);
    },
  );
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
  bool guest = false,
  String status = 'generated',
  int? parentRecommendationId,
  String? verificationToken,
}) {
  const current = {
    'volume': 5.0,
    'bass': 4.0,
    'treble': 6.0,
    'sharpness': 5.0,
    'flatness': 5.0,
  };
  const recommended = {
    'volume': 5.0,
    'bass': 5.5,
    'treble': 5.5,
    'sharpness': 5.0,
    'flatness': 4.5,
  };
  return SettingsRecommendation.fromJson({
    'id': guest ? null : 41,
    'persisted': !guest,
    'assessment_id': guest ? null : 11,
    'amplifier_profile_id': guest ? null : 12,
    'parent_recommendation_id': parentRecommendationId,
    'status': status,
    'genre': 'rock',
    'profile_version': '2026.09.1',
    'profile_checksum':
        '8b87b9f1106bab8dab4978e4590e84c9bb294400a0d60ce5263e196f44701b61',
    'algorithm_version': '1.0.0',
    'overall_confidence': 'medium',
    'scale': {'minimum': 0.0, 'maximum': 10.0, 'step': 0.5},
    'current': current,
    'recommended': recommended,
    'adjustments': {
      for (final entry in current.entries)
        entry.key: {
          'current': entry.value,
          'recommended': recommended[entry.key],
          'delta': recommended[entry.key]! - entry.value,
          'delta_normalized': 0.0,
          'reason_code': 'within_genre_range',
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
    'verification_token': verificationToken,
    'created_at': '2026-09-02T00:00:00Z',
    'applied_at': status == 'applied' ? '2026-09-02T01:00:00Z' : null,
  });
}

class _FakeSettingsApi extends SettingsApi {
  SettingsRecommendation? applied;
  int? appliedId;

  @override
  Future<SettingsRecommendation> applyRecommendation(
    int recommendationId,
  ) async {
    appliedId = recommendationId;
    return applied!;
  }
}

class _FakeGuestAmplifierStore extends GuestAmplifierStore {
  _FakeGuestAmplifierStore()
    : super(directoryProvider: () async => Directory.systemTemp);

  AmplifierProfile? stored;
  AmplifierProfile? saved;

  @override
  Future<AmplifierProfile?> read() async => stored;

  @override
  Future<void> save(AmplifierProfile profile) async {
    saved = profile;
    stored = profile;
  }
}
