import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/main.dart';
import 'package:karaok_app/core/network/api_service.dart';
import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_settings_suggestion_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';
import 'package:karaok_app/features/home/presentation/pages/user_home_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/user_previous_results_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await GuestAssessmentService.instance.resetForTesting();
  });
  tearDown(UserSession.instance.clear);

  testWidgets('KaraOK opens directly in guest mode', (tester) async {
    await tester.pumpWidget(const KaraOKApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(UserSession.instance.isGuest, isTrue);
    expect(find.text('karaOK', findRichText: true), findsOneWidget);
    expect(find.text('Owner'), findsNothing);
    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    expect(find.byType(Drawer), findsNothing);
  });

  test('guest allowance survives authentication token cleanup', () async {
    expect(await GuestAssessmentService.instance.canAssess(), isTrue);

    await GuestAssessmentService.instance.markAssessmentUsed();
    await ApiService().clearTokens();

    expect(await GuestAssessmentService.instance.remainingAttempts(), 2);
    expect(await GuestAssessmentService.instance.canAssess(), isTrue);

    await GuestAssessmentService.instance.markAssessmentUsed();
    await GuestAssessmentService.instance.markAssessmentUsed();

    expect(await GuestAssessmentService.instance.canAssess(), isFalse);
  });

  testWidgets('three used guest evaluations block either assessment feature', (
    tester,
  ) async {
    UserSession.instance.setGuest('user');
    for (var i = 0; i < GuestAssessmentService.maxAttempts; i++) {
      await GuestAssessmentService.instance.markAssessmentUsed();
    }

    await tester.pumpWidget(
      const MaterialApp(home: AudioSettingsSuggestionScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guest evaluation limit reached'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('user home presents the two separate audio features', (
    tester,
  ) async {
    UserSession.instance.setGuest('user');

    await tester.pumpWidget(const MaterialApp(home: UserHomeScreen()));
    await tester.pump();

    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
    expect(find.text('Generate Audio Settings Suggestion'), findsOneWidget);
    expect(find.text('Start Audio Test'), findsNothing);
    expect(find.text('Upload Audio File'), findsNothing);
    expect(find.text('Recent Analysis'), findsNothing);
    expect(find.text('View all'), findsNothing);
  });

  testWidgets('each user action opens its own record or upload page', (
    tester,
  ) async {
    UserSession.instance.setGuest('user');
    await tester.pumpWidget(const MaterialApp(home: UserHomeScreen()));
    await tester.pump();

    await tester.tap(find.text('Evaluate Audio Quality'));
    await tester.pumpAndSettle();
    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
    expect(find.text('Record Audio'), findsOneWidget);
    expect(find.text('Select Audio File'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate Audio Settings Suggestion'));
    await tester.pumpAndSettle();
    expect(find.text('Generate Settings Suggestion'), findsOneWidget);
    expect(find.text('Record Audio'), findsOneWidget);
    expect(find.text('Select Audio File'), findsOneWidget);
  });

  testWidgets('guest navigation uses bottom buttons on one app shell', (
    tester,
  ) async {
    await tester.pumpWidget(const KaraOKApp());
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byType(Drawer), findsNothing);

    await tester.tap(find.text('Records'));
    await tester.pump();
    expect(find.text('Save your evaluation records'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('You are using KaraOK as a guest'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('authenticated shell settings contain account and logout', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 1,
      name: 'Test User',
      email: 'user@example.com',
      userType: 'user',
    );
    await tester.pumpWidget(const KaraOKApp());
    await tester.pump();
    await tester.tap(find.text('Settings'));
    await tester.pump();

    expect(find.text('Test User'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pump();
    expect(find.text('Log Out'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('settings displays the authenticated user details', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Test User',
      username: 'test-user',
      email: 'user@example.com',
      userType: 'user',
      firstName: 'Test',
      lastName: 'User',
      address: '123 Sample Street',
      city: 'Manila',
      stateProvince: 'Metro Manila',
      areaCode: '1000',
      country: 'Philippines',
      countryCode: 'PH',
      phoneNumber: '+639123456789',
      birthday: '2000-01-02',
    );

    await tester.pumpWidget(const MaterialApp(home: ChangePasswordScreen()));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Account Details'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Test User'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('test-user'), findsOneWidget);
    expect(find.text('Email (cannot be changed)'), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('+639123456789'), findsOneWidget);
    expect(find.text('Birthday'), findsOneWidget);
    expect(find.text('2000-01-02'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.textContaining('123 Sample Street'), findsOneWidget);
    expect(find.text('Account type'), findsNothing);

    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Street address'), findsOneWidget);
    expect(find.byTooltip('Choose profile image'), findsOneWidget);
    final editableEmails = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .where((field) => field.controller?.text == 'user@example.com');
    expect(editableEmails, isEmpty);
  });

  testWidgets('user View all destination is the analysis history', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 1,
      name: 'User',
      email: 'user@example.com',
      userType: 'user',
    );

    await tester.pumpWidget(
      const MaterialApp(home: UserPreviousResultsScreen()),
    );
    await tester.pump();

    expect(find.text('Analysis History'), findsOneWidget);
    expect(find.text('Recommendation Records'), findsNothing);
    expect(find.text('Genre'), findsNothing);
    expect(find.text('Acceptable'), findsOneWidget);
    expect(find.text('Problematic'), findsOneWidget);
  });

  testWidgets('account creation collects the user profile without a type', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));

    expect(find.text('Account type'), findsNothing);
    expect(find.text('First name'), findsWidgets);
    expect(find.text('Last name'), findsWidgets);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Street address'), findsOneWidget);
    expect(find.text('City / Municipality'), findsOneWidget);
    expect(find.text('Province / State'), findsOneWidget);
    expect(find.text('Postal code'), findsOneWidget);
    expect(find.text('Country'), findsOneWidget);
    expect(find.text('Country code'), findsNothing);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Birthday'), findsOneWidget);
    expect(find.textContaining('Profile image'), findsOneWidget);
  });

  testWidgets('empirical result shows a real score and five feature grades', (
    tester,
  ) async {
    final features = <String, dynamic>{
      for (final name in [
        'loudness',
        'bass',
        'treble',
        'sharpness',
        'flatness',
      ])
        name: {
          'value': name == 'loudness' ? -11.2 : 0.5,
          'score': 88.5,
          'status': 'good',
        },
    };

    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen.fromRecord({
          'test_name': 'Browser recording.wav',
          'score': null,
          'empirical_quality': {
            'overall_score': 88.5,
            'overall_status': 'good',
            'features': features,
          },
        }),
      ),
    );

    expect(find.textContaining('88.5', findRichText: true), findsWidgets);
    expect(find.text('Empirical five-feature grading'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.text('Loudness'), findsOneWidget);
    expect(find.text('Bass'), findsOneWidget);
    expect(find.text('Treble'), findsOneWidget);
    expect(find.text('Sharpness'), findsOneWidget);
    expect(find.text('Flatness'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('View Visual Report'), findsOneWidget);
  });

  testWidgets('visual report remains available when generated images exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen.fromRecord({
          'file_name': 'Analyzed recording.wav',
          'score': 85,
          'visualizations': {
            'waveform': 'generated-waveform-bytes',
            'spectrogram': 'generated-spectrogram-bytes',
          },
        }, isGuest: true),
      ),
    );

    expect(find.text('View Visual Report'), findsOneWidget);
  });

  testWidgets('results app-bar back replaces recording flow with Home', (
    tester,
  ) async {
    UserSession.instance.setGuest('user');
    await tester.pumpWidget(const MaterialApp(home: _ResultFlowLauncher()));

    await tester.tap(find.text('Open result'));
    await tester.pumpAndSettle();
    expect(find.text('Results'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to Home'));
    await tester.pumpAndSettle();

    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
    expect(find.text('Recording screen'), findsNothing);
    expect(find.text('Results'), findsNothing);
  });

  testWidgets('system back from results replaces recording flow with Home', (
    tester,
  ) async {
    UserSession.instance.setGuest('user');
    await tester.pumpWidget(const MaterialApp(home: _ResultFlowLauncher()));

    await tester.tap(find.text('Open result'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
    expect(find.text('Recording screen'), findsNothing);
    expect(find.text('Results'), findsNothing);
  });

  testWidgets('guest result allows another evaluation while attempts remain', (
    tester,
  ) async {
    UserSession.instance.setGuest('user');
    await GuestAssessmentService.instance.markAssessmentUsed();
    await tester.pumpWidget(
      const MaterialApp(
        home: ResultsScreen(
          testName: 'Guest recording.wav',
          score: 85,
          empiricalStatus: 'good',
          isGuest: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Guest assessment complete'), findsOneWidget);
    expect(find.text('Evaluate another audio'), findsOneWidget);
    expect(
      find.textContaining('2 of 3 guest audio evaluations remain'),
      findsOneWidget,
    );
  });

  testWidgets('guest result asks for an account after the third evaluation', (
    tester,
  ) async {
    UserSession.instance.setGuest('user');
    for (var i = 0; i < GuestAssessmentService.maxAttempts; i++) {
      await GuestAssessmentService.instance.markAssessmentUsed();
    }
    await tester.pumpWidget(
      const MaterialApp(
        home: ResultsScreen(
          testName: 'Guest recording.wav',
          score: 85,
          empiricalStatus: 'good',
          isGuest: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Create Account or Log In'), findsOneWidget);
    expect(
      find.textContaining('All three guest audio evaluations are used'),
      findsOneWidget,
    );
  });
}

class _ResultFlowLauncher extends StatelessWidget {
  const _ResultFlowLauncher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Recording screen'),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ResultsScreen(
                  testName: 'Finished audio.wav',
                  score: 85,
                  empiricalStatus: 'good',
                  isGuest: true,
                ),
              ),
            ),
            child: const Text('Open result'),
          ),
        ],
      ),
    );
  }
}
