import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karaok_app/core/network/api_service.dart';
import 'package:karaok_app/core/security/submit_guard.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/forgot_password_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/otp_verification_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/reset_password_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';
import 'package:karaok_app/shared/widgets/app_widgets.dart';
import 'package:karaok_app/shared/widgets/form_feedback.dart';
import 'package:karaok_app/shared/widgets/otp_countdown.dart';
import 'package:karaok_app/shared/widgets/stage_progress.dart';

class _ResetApi extends AuthApi {
  (String, String, String, String)? submission;

  @override
  Future<void> resetPassword({
    required String email,
    required String challengeId,
    required String code,
    required String newPassword,
  }) async {
    submission = (email, challengeId, code, newPassword);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final flow in ['signup', 'OTP resend', 'forgot password']) {
    testWidgets('$flow shows countdown after hourly device cap 429', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      const message = 'Too many attempts. Try again in 30 minutes.';
      var requests = 0;
      final api = AuthApi(
        client: ApiService.withClient(
          MockClient((request) async {
            requests++;
            final endpoint = switch (flow) {
              'signup' => '/auth/register',
              'OTP resend' => '/auth/register/resend',
              _ => '/auth/forgot-password',
            };
            expect(request.url.path, endsWith(endpoint));
            return http.Response(
              '{"error":"$message","retry_after":1800}',
              429,
            );
          }),
        ),
      );
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final page = switch (flow) {
        'signup' => SignUpScreen(authApi: api),
        'OTP resend' => OtpVerificationScreen(
          authApi: api,
          challenge: OtpChallenge(
            email: 'a@gmail.com',
            challengeId: 'fixture',
            expiresAt: now + 300,
            resendAvailableAt: now,
            skewSeconds: 0,
          ),
        ),
        _ => ForgotPasswordScreen(authApi: api),
      };
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      if (flow != 'OTP resend') {
        await tester.enterText(fields.first, 'a@gmail.com');
      }
      if (flow == 'signup') {
        await tester.enterText(fields.at(1), 'New#Pass1');
        await tester.ensureVisible(fields.at(2));
        await tester.enterText(fields.at(2), 'New#Pass1');
      }
      final submit = find.text(switch (flow) {
        'signup' => 'Send Verification Code',
        'OTP resend' => 'Resend code',
        _ => 'Send reset code',
      });
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(requests, 1);
      expect(find.text(message), findsOneWidget);
      if (flow == 'OTP resend') {
        final button = find.widgetWithText(TextButton, 'Resend code in 30:00');
        expect(tester.widget<TextButton>(button).onPressed, isNull);
      } else {
        final button = find.widgetWithText(
          AppPrimaryButton,
          'Try again in 30:00',
        );
        expect(tester.widget<AppPrimaryButton>(button).onPressed, isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  test(
    'a restored lock preserves the deadline and escalates the next burst',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      var now = DateTime.utc(2026);
      final guard = SubmitGuard('login', now: () => now);
      for (var i = 0; i < 5; i++) {
        expect(await guard.recordAttempt(), isNull);
      }
      expect(await guard.recordAttempt(), const Duration(seconds: 30));
      final restored = SubmitGuard('login', now: () => now);
      await restored.restore();
      expect(restored.remaining, const Duration(seconds: 30));
      now = now.add(const Duration(seconds: 30));
      for (var i = 0; i < 5; i++) {
        expect(await restored.recordAttempt(), isNull);
      }
      expect(await restored.recordAttempt(), const Duration(seconds: 60));
      guard.dispose();
      restored.dispose();
    },
  );

  test('OTP countdown uses the server clock at issuance', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1600 * 1000);
    final challenge = OtpChallenge.fromResponse('a@gmail.com', {
      'challenge_id': 'challenge',
      'expires_at': 1600,
      'resend_available_at': 1300,
      'server_time': 1000,
    }, now: () => now);
    expect(challenge.untilExpiry(now), const Duration(minutes: 10));
    expect(challenge.untilResend(now), const Duration(minutes: 5));
  });

  testWidgets(
    'resend waits for the server deadline and restarts both countdowns',
    (tester) async {
      var now = DateTime.fromMillisecondsSinceEpoch(1000 * 1000);
      var resends = 0;
      final initial = OtpChallenge.fromResponse('a@gmail.com', {
        'challenge_id': 'fixture',
        'expires_at': 1600,
        'resend_available_at': 1300,
        'server_time': 1000,
      }, now: () => now);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpCountdown(
              challenge: initial,
              now: () => now,
              onResend: () async {
                resends++;
                return OtpChallenge.fromResponse('a@gmail.com', {
                  'challenge_id': 'fixture',
                  'expires_at': 1900,
                  'resend_available_at': 1600,
                  'server_time': 1300,
                }, now: () => now);
              },
            ),
          ),
        ),
      );
      expect(find.text('Code expires in 10:00'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      expect(resends, 1);
      expect(find.text('Code expires in 10:00'), findsOneWidget);
      expect(find.text('Resend code in 5:00'), findsOneWidget);
      now = now.add(const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Code expired. Request a new code.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('stored challenge resumes only for the same cleaned email', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final challenge = OtpChallenge.fromResponse('A@GMAIL.COM', {
      'challenge_id': 'fixture',
      'expires_at': now + 600,
      'resend_available_at': now + 300,
      'server_time': now,
    });
    await challenge.save('registration');
    expect(
      (await OtpChallenge.restore(
        'registration',
        ' a@gmail.com ',
      ))?.challengeId,
      'fixture',
    );
    expect(await OtpChallenge.restore('registration', 'b@gmail.com'), isNull);
    expect(await OtpChallenge.restore('password_reset', 'a@gmail.com'), isNull);
    await OtpChallenge.clear('registration');
    expect(await OtpChallenge.restore('registration', 'a@gmail.com'), isNull);
  });

  testWidgets(
    'password reset sends code and password for the active challenge',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = _ResetApi();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final challenge = OtpChallenge.fromResponse('a@gmail.com', {
        'challenge_id': 'fixture',
        'expires_at': now + 600,
        'resend_available_at': now + 300,
        'server_time': now,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ResetPasswordScreen(challenge: challenge, authApi: api),
        ),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '123456');
      await tester.enterText(fields.at(1), 'New#Pass1');
      await tester.ensureVisible(fields.at(2));
      await tester.enterText(fields.at(2), 'New#Pass1');
      final submit = find.text('Update password');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.submission, ('a@gmail.com', 'fixture', '123456', 'New#Pass1'));
      expect(
        find.text('Password updated. Sign in with your new password.'),
        findsOneWidget,
      );
    },
  );

  test('analysis progress stays below 95 percent while awaiting results', () {
    expect(
      analysisProgress(
        stage: AnalysisStage.uploading,
        uploadFraction: 1,
        audioLength: const Duration(minutes: 1),
      ),
      closeTo(.40, .00001),
    );
    final progress = analysisProgress(
      stage: AnalysisStage.analyzing,
      elapsedAnalyzing: const Duration(hours: 1),
      audioLength: const Duration(minutes: 1),
    );
    expect(progress, lessThan(.95));
    expect(
      analysisProgress(
        stage: AnalysisStage.finishing,
        audioLength: Duration.zero,
      ),
      1,
    );
  });

  testWidgets('password rules use read-only check and close icons', (
    tester,
  ) async {
    final password = TextEditingController(text: 'Example');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PasswordChecklist(controller: password)),
      ),
    );
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(3));
    expect(find.byType(Checkbox), findsNothing);
    await tester.pumpWidget(const SizedBox());
    password.dispose();
  });
}
