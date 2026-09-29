import '../support/settle_with_storage.dart';
import 'dart:convert';
import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/core/storage/guest_assessment_store.dart';
import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/features/home/presentation/pages/user_home_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/reports/presentation/pages/previous_results_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.instance.setGuest('user');
    await GuestAssessmentService.instance.resetForTesting();
    await GuestAssessmentStore.instance.clearAll();
  });
  tearDown(UserSession.instance.clear);
  for (final guest in [true, false]) {
    testWidgets(
      'empty ${guest ? 'guest' : 'account'} history shows three sample assessments',
      (tester) async {
        if (!guest) {
          UserSession.instance.setUser(
            id: 1,
            name: 'New',
            email: 'new@example.com',
            userType: 'user',
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            home: PreviousResultsScreen(resultsLoader: () async => []),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sample: Balanced audio'), findsOneWidget);
        expect(find.text('Sample: Audio needs improvement'), findsOneWidget);
        expect(find.text('Sample: Problematic audio'), findsOneWidget);
        await tester.tap(find.text('Sample: Balanced audio'));
        await tester.pumpAndSettle();
        expect(find.byType(ResultsScreen), findsOneWidget);
        expect(find.text('Sample assessment'), findsOneWidget);
        expect(
          find.text('Illustrative feature values; no recording was analyzed.'),
          findsOneWidget,
        );
        expect(find.text('Empirical five-feature grading'), findsOneWidget);
        expect(find.text('Guest assessment complete'), findsNothing);
        expect(find.text('View Visual Report'), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(PreviousResultsScreen), findsOneWidget);
        expect(await GuestAssessmentService.instance.remainingAttempts(), 3);
        expect(
          await tester.runAsync(GuestAssessmentStore.instance.guestHistory),
          isEmpty,
        );
      },
    );
  }
  testWidgets('refresh replaces all samples with first real record', (
    tester,
  ) async {
    var records = <dynamic>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PreviousResultsScreen(resultsLoader: () async => records),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sample: Balanced audio'), findsOneWidget);
    records = [
      {
        'test_name': 'My first recording.wav',
        'score': 86,
        'status': 'Acceptable',
      },
    ];
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();
    expect(find.text('My first recording.wav'), findsOneWidget);
    expect(find.textContaining('Sample:'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('historySearchField')),
      'absent',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Sample:'), findsNothing);
    expect(find.text('No reports match your filters'), findsOneWidget);
  });
  testWidgets('Home shows samples and replaces them after first assessment', (
    tester,
  ) async {
    var records = <dynamic>[];
    await tester.pumpWidget(
      MaterialApp(home: UserHomeScreen(resultsLoader: () async => records)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sample: Balanced audio'), findsOneWidget);
    expect(find.text('Sample: Audio needs improvement'), findsOneWidget);
    expect(find.text('Sample: Problematic audio'), findsOneWidget);
    records = [
      {
        'test_name': 'Real home recording.wav',
        'score': 89,
        'status': 'Acceptable',
      },
    ];
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();
    expect(find.text('Real home recording.wav'), findsOneWidget);
    expect(find.textContaining('Sample:'), findsNothing);
  });
  testWidgets('guest Home has sign in beside create account at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: UserHomeScreen(resultsLoader: () async => [])),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
  testWidgets(
    'guest saved assessment replaces samples on Home and Records without restarting',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AppShell()));
      await settleWithStorage(tester);
      expect(find.text('Sample: Balanced audio'), findsOneWidget);
      await tester.runAsync(
        () => GuestAssessmentStore.instance.saveCompleted({
          'test_name': 'Recorded for real.wav',
          'score': 87,
          'status': 'Acceptable',
          'visualizations': {
            'waveform': base64Encode([1, 2, 3]),
            'spectrogram': base64Encode([4, 5, 6]),
          },
        }),
      );
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
      await settleWithStorage(tester);
      expect(find.text('Recorded for real.wav'), findsOneWidget);
      expect(find.textContaining('Sample:'), findsNothing);
      await tester.tap(find.text('Records'));
      await settleWithStorage(tester);
      expect(find.text('Recorded for real.wav'), findsOneWidget);
      expect(find.textContaining('Sample:'), findsNothing);
      expect(
        (await tester.runAsync(
          GuestAssessmentStore.instance.guestHistory,
        ))!.length,
        1,
      );
    },
  );

  testWidgets(
    'Home account with no history gets samples and failed refresh hides them',
    (tester) async {
      UserSession.instance.setUser(
        id: 12,
        name: 'New account',
        email: 'new@example.com',
        userType: 'user',
      );
      var fail = false;
      await tester.pumpWidget(
        MaterialApp(
          home: UserHomeScreen(
            resultsLoader: () async {
              if (fail) throw Exception('offline');
              return [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sample: Balanced audio'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
      fail = true;
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
      await tester.pumpAndSettle();
      expect(find.textContaining('Sample:'), findsNothing);
      expect(
        find.text('Could not load your analysis records.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'previous guest evaluation does not regain samples if its report is unavailable',
    (tester) async {
      await GuestAssessmentService.instance.markAssessmentUsed();
      await tester.pumpWidget(const MaterialApp(home: AppShell()));
      await settleWithStorage(tester);
      expect(find.textContaining('Sample:'), findsNothing);
      await tester.tap(find.text('Records'));
      await settleWithStorage(tester);
      expect(find.textContaining('Sample:'), findsNothing);
    },
  );
  testWidgets('failed history load does not show samples', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PreviousResultsScreen(
          resultsLoader: () async => throw Exception('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Sample:'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });
}
