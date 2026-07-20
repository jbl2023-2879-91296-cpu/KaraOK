import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/main.dart';
import 'package:karaok_app/screens/audio_settings_suggestion_screen.dart';
import 'package:karaok_app/screens/change_password_screen.dart';
import 'package:karaok_app/screens/owner_home_screen.dart';
import 'package:karaok_app/screens/owner_previous_results_screen.dart';
import 'package:karaok_app/screens/results_screen.dart';
import 'package:karaok_app/screens/technician_home_screen.dart';
import 'package:karaok_app/services/api_service.dart';
import 'package:karaok_app/services/guest_assessment_service.dart';
import 'package:karaok_app/services/user_session.dart';
import 'package:karaok_app/widgets/app_navigation_drawer.dart';

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await GuestAssessmentService.instance.resetForTesting();
  });
  tearDown(UserSession.instance.clear);

  testWidgets('KaraOK starts on the get-started screen', (tester) async {
    await tester.pumpWidget(const KaraOKApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Log In / Register'), findsOneWidget);
    expect(find.text('Continue as Guest (1 assessment)'), findsOneWidget);
  });

  test('guest allowance survives authentication token cleanup', () async {
    expect(await GuestAssessmentService.instance.canAssess(), isTrue);

    await GuestAssessmentService.instance.markAssessmentUsed();
    await ApiService().clearTokens();

    expect(await GuestAssessmentService.instance.canAssess(), isFalse);
  });

  testWidgets('used guest allowance blocks either assessment feature', (
    tester,
  ) async {
    UserSession.instance.setGuest('owner');
    await GuestAssessmentService.instance.markAssessmentUsed();

    await tester.pumpWidget(
      const MaterialApp(home: AudioSettingsSuggestionScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guest assessment already used'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('owner home presents the two separate audio features', (
    tester,
  ) async {
    UserSession.instance.setGuest('owner');

    await tester.pumpWidget(const MaterialApp(home: OwnerHomeScreen()));
    await tester.pump();

    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
    expect(find.text('Generate Audio Settings Suggestion'), findsOneWidget);
    expect(find.text('Start Audio Test'), findsNothing);
    expect(find.text('Upload Audio File'), findsNothing);
    expect(find.text('Recent Analysis'), findsNothing);
    expect(find.text('View all'), findsNothing);
  });

  testWidgets('technician home presents the two separate audio features', (
    tester,
  ) async {
    UserSession.instance.setGuest('technician');

    await tester.pumpWidget(const MaterialApp(home: TechnicianHomeScreen()));
    await tester.pump();

    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
    expect(find.text('Generate Audio Settings Suggestion'), findsOneWidget);
    expect(find.text('Start Audio Test'), findsNothing);
    expect(find.text('Upload Audio File'), findsNothing);
    expect(find.text('Recent Analysis'), findsNothing);
    expect(find.text('View all'), findsNothing);
  });

  testWidgets('each owner action opens its own record or upload page', (
    tester,
  ) async {
    UserSession.instance.setGuest('owner');
    await tester.pumpWidget(const MaterialApp(home: OwnerHomeScreen()));
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

  testWidgets('guest navigation actions are consolidated in the drawer', (
    tester,
  ) async {
    UserSession.instance.setGuest('owner');
    await tester.pumpWidget(const MaterialApp(home: OwnerHomeScreen()));
    await tester.pump();

    expect(find.text('Home'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Record'), findsNothing);
    expect(find.text('Reports'), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final drawer = find.byType(Drawer);
    expect(find.descendant(of: drawer, matching: find.text('Home')), findsOne);
    expect(
      find.descendant(of: drawer, matching: find.text('Reports')),
      findsNothing,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Settings')),
      findsOne,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Sign In')),
      findsOne,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('Log Out')),
      findsNothing,
    );
  });

  testWidgets('authenticated drawer contains logout and settings', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 1,
      name: 'Test Owner',
      email: 'owner@example.com',
      userType: 'owner',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: const AppNavigationDrawer(),
          appBar: AppBar(leading: const AppDrawerButton()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();

    expect(find.text('Test Owner'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
    expect(find.text('Sign In'), findsNothing);
  });

  testWidgets('settings displays the authenticated user details', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Test Owner',
      email: 'owner@example.com',
      userType: 'owner',
    );

    await tester.pumpWidget(const MaterialApp(home: ChangePasswordScreen()));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Account Details'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Test Owner'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('Account type'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
  });

  testWidgets('owner View all destination is the analysis history', (
    tester,
  ) async {
    UserSession.instance.setGuest('owner');

    await tester.pumpWidget(
      const MaterialApp(home: OwnerPreviousResultsScreen()),
    );
    await tester.pump();

    expect(find.text('Analysis History'), findsOneWidget);
    expect(find.text('Recommendation Records'), findsNothing);
    expect(find.text('Genre'), findsNothing);
    expect(find.text('Acceptable'), findsOneWidget);
    expect(find.text('Problematic'), findsOneWidget);
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

    expect(
      find.textContaining('88.5', findRichText: true),
      findsWidgets,
    );
    expect(find.text('Empirical five-feature grading'), findsOneWidget);
    expect(find.text('Loudness'), findsOneWidget);
    expect(find.text('Bass'), findsOneWidget);
    expect(find.text('Treble'), findsOneWidget);
    expect(find.text('Sharpness'), findsOneWidget);
    expect(find.text('Flatness'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('guest result requires sign in before another assessment', (
    tester,
  ) async {
    UserSession.instance.setGuest('owner');
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
    expect(find.text('Sign in to assess another audio'), findsOneWidget);
    expect(find.text('Test another audio'), findsNothing);
  });
}
