import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/forgot_password_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/otp_verification_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/reset_password_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/detailed_report_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';
import 'package:karaok_app/shared/widgets/adaptive_layout.dart';
import 'package:karaok_app/shared/widgets/app_sidebar.dart';
import 'package:karaok_app/shared/widgets/otp_countdown.dart';

import 'support/audio_platform_stub.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'auth and analysis screens fit at ${size.width} × ${size.height}',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AudioPlatformStub().install();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );

        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final challenge = OtpChallenge(
          email: 'user@gmail.com',
          challengeId: 'fixture',
          expiresAt: now + 600,
          resendAvailableAt: now + 300,
          skewSeconds: 0,
        );
        for (final page in [
          const LoginScreen(),
          const SignUpScreen(),
          const ForgotPasswordScreen(),
          OtpVerificationScreen(challenge: challenge),
          ResetPasswordScreen(challenge: challenge),
          const AppShell(),
          const AudioTestScreen(),
          const ResultsScreen(score: 87),
          const DetailedReportScreen(score: 87),
        ]) {
          await tester.pumpWidget(MaterialApp(home: page));
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '${page.runtimeType} at $size',
          );
          if (page is AppShell) {
            expect(
              find.byType(AppSidebar),
              size.width >= 600 ? findsOneWidget : findsNothing,
            );
            expect(
              find.byType(NavigationBar),
              size.width < 600 ? findsOneWidget : findsNothing,
            );
          }
          if (page is ResultsScreen || page is DetailedReportScreen) {
            expect(
              find.byType(AdaptiveColumns),
              page is ResultsScreen || size.width >= 840
                  ? findsOneWidget
                  : findsNothing,
            );
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        }
      },
    );
  }
}
