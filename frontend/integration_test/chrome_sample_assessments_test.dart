import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karaok_app/features/home/presentation/pages/user_home_screen.dart';
import 'package:karaok_app/features/reports/domain/sample_assessments.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/previous_results_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';

const sampleNames = [
  'Sample: Balanced audio',
  'Sample: Audio needs improvement',
  'Sample: Problematic audio',
];

Future<void> launch(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: UserHomeScreen(resultsLoader: () async => sampleAssessments),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1700));
  await tester.pumpAndSettle();
}

void expectSamples() {
  for (final name in sampleNames) {
    expect(find.text(name), findsOneWidget);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    UserSession.instance.setGuest('user');
  });
  tearDown(() async {
    UserSession.instance.clear();
  });

  testWidgets('guest samples use real results UI and preserve allowance', (
    tester,
  ) async {
    final allowanceBefore = await GuestAssessmentService.instance
        .remainingAttempts();
    await launch(tester);
    expectSamples();
    expect(
      Theme.of(tester.element(find.text('Sign in'))).brightness,
      Brightness.light,
    );
    for (final name in sampleNames) {
      await tester.ensureVisible(find.text(name));
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(ResultsScreen), findsOneWidget);
      expect(find.text('Sample assessment'), findsOneWidget);
      expect(find.text('Your sound measurements'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(
      await GuestAssessmentService.instance.remainingAttempts(),
      allowanceBefore,
    );
  });

  testWidgets('guest auth links open sign in and create account', (
    tester,
  ) async {
    await launch(tester);
    expect(find.text('Create Account'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.byType(SignUpScreen), findsOneWidget);
  });

  testWidgets('injected guest history replaces samples on Home and Records', (
    tester,
  ) async {
    var records = <dynamic>[...sampleAssessments];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: UserHomeScreen(resultsLoader: () async => records),
      ),
    );
    await tester.pumpAndSettle();
    expectSamples();
    records = [
      {
        'test_name': 'Chrome recording.wav',
        'score': 86,
        'status': 'Acceptable',
        'analysis_purpose': 'quality_evaluation',
      },
    ];
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Chrome recording.wav'), findsOneWidget);
    for (final name in sampleNames) {
      expect(find.text(name), findsNothing);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PreviousResultsScreen(resultsLoader: () async => records),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chrome recording.wav'), findsOneWidget);
    for (final name in sampleNames) {
      expect(find.text(name), findsNothing);
    }
  });

  testWidgets(
    'new account samples disappear when history returns a real assessment',
    (tester) async {
      UserSession.instance.setUser(
        id: 1,
        name: 'New',
        email: 'new@example.com',
        userType: 'user',
      );
      var records = <dynamic>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PreviousResultsScreen(resultsLoader: () async => records),
        ),
      );
      await tester.pumpAndSettle();
      expectSamples();
      records = [
        {
          'id': 1,
          'test_name': 'Account recording.wav',
          'score': 88,
          'status': 'Acceptable',
        },
      ];
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('Account recording.wav'), findsOneWidget);
      for (final name in sampleNames) {
        expect(find.text(name), findsNothing);
      }
    },
  );
}
