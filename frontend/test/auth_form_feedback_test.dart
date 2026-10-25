import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/otp_verification_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/forgot_password_screen.dart';
import 'package:karaok_app/shared/widgets/form_feedback.dart';

// All values are synthetic fixtures; no real account or network is used.
class _Auth extends AuthApi {
  Object failure = const ApiException(503, 'Service temporarily unavailable.');
  int calls = 0;
  String? email;
  String? submittedCode;
  String? submittedPassword;
  Future<Map<String, dynamic>> fail() async {
    calls++;
    throw failure;
  }

  @override
  Future<Map<String, dynamic>> startRegistration({
    String? username,
    required String email,
    required String password,
  }) {
    this.email = email;
    submittedPassword = password;
    return fail();
  }

  @override
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) {
    email = identifier;
    submittedPassword = password;
    return fail();
  }

  @override
  Future<Map<String, dynamic>> verifyRegistration({
    required String email,
    required String code,
  }) {
    this.email = email;
    submittedCode = code;
    return fail();
  }

  @override
  Future<Map<String, dynamic>> requestPasswordReset(String email) {
    this.email = email;
    return fail();
  }
}

Finder field(int index) => find.byType(TextFormField).at(index);
TextField fieldWidget(WidgetTester tester, int index) =>
    tester.widget<TextField>(
      find.descendant(of: field(index), matching: find.byType(TextField)),
    );
Future<void> show(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

Future<void> submit(WidgetTester tester, String label) async {
  final button = find.widgetWithText(ElevatedButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> signupValues(WidgetTester tester) async {
  await tester.enterText(field(0), '  singer@example.com  ');
  await tester.enterText(field(1), 'Example123!');
  await tester.enterText(field(2), 'Example123!');
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final signup in [true, false]) {
    testWidgets(
      '${signup ? 'signup' : 'login'} validates only the edited field before submit',
      (tester) async {
        final api = _Auth();
        await show(
          tester,
          signup ? SignUpScreen(authApi: api) : LoginScreen(authApi: api),
        );
        for (var index = 0; index < (signup ? 3 : 2); index++) {
          expect(fieldWidget(tester, index).decoration?.errorText, isNull);
        }
        await tester.enterText(field(0), 'invalid');
        await tester.pumpAndSettle();
        expect(
          fieldWidget(tester, 0).decoration?.errorText,
          'Enter a valid email address.',
        );
        expect(fieldWidget(tester, 1).decoration?.errorText, isNull);
        if (signup) {
          expect(fieldWidget(tester, 2).decoration?.errorText, isNull);
        }
        await tester.enterText(field(0), 'singer@example.com');
        await tester.enterText(field(1), signup ? 'weak' : 'fixture');
        await tester.pumpAndSettle();
        expect(fieldWidget(tester, 0).decoration?.errorText, isNull);
        if (signup) {
          expect(
            fieldWidget(tester, 1).decoration?.errorText,
            'Password must be between 8 and 128 characters.',
          );
          expect(fieldWidget(tester, 2).decoration?.errorText, isNull);
        }
        expect(api.calls, 0);
      },
    );
  }

  testWidgets('signup required fields focus first error and never call API', (
    tester,
  ) async {
    final api = _Auth();
    await show(tester, SignUpScreen(authApi: api));
    await submit(tester, 'Send Verification Code');
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(
      find.text('Password must be between 8 and 128 characters.'),
      findsOneWidget,
    );
    expect(find.text('Confirm your password.'), findsOneWidget);
    expect(fieldWidget(tester, 0).focusNode!.hasFocus, isTrue);
    expect(api.calls, 0);
  });

  testWidgets(
    'signup rejects bad email, weak password and mismatched confirmation',
    (tester) async {
      final api = _Auth();
      await show(tester, SignUpScreen(authApi: api));
      await tester.enterText(field(0), 'not-an-email');
      await tester.enterText(field(1), 'lowercaseonly');
      await tester.enterText(field(2), 'different');
      await submit(tester, 'Send Verification Code');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(
        find.text('Include uppercase, lowercase, number, and symbol.'),
        findsOneWidget,
      );
      expect(find.text('Passwords must match.'), findsOneWidget);
      expect(api.calls, 0);
      await signupValues(tester);
      await submit(tester, 'Send Verification Code');
      expect(api.calls, 1);
      expect(api.email, 'singer@example.com');
      expect(api.submittedPassword, 'Example123!');
    },
  );

  testWidgets('signup password checklist updates each rule while typing', (
    tester,
  ) async {
    await show(tester, SignUpScreen(authApi: _Auth()));
    final checklist = find.byType(PasswordChecklist);
    Finder checks(IconData icon) =>
        find.descendant(of: checklist, matching: find.byIcon(icon));
    expect(checks(Icons.circle_outlined), findsNWidgets(5));
    await tester.enterText(field(1), 'lowercase');
    await tester.pump();
    expect(checks(Icons.check_circle), findsNWidgets(2));
    expect(checks(Icons.circle_outlined), findsNWidgets(3));
    await tester.enterText(field(1), 'Example123!');
    await tester.pump();
    expect(checks(Icons.check_circle), findsNWidgets(5));
    expect(checks(Icons.circle_outlined), findsNothing);
  });

  testWidgets(
    'signup server fields attach to inputs and clear independently on edit',
    (tester) async {
      final api = _Auth()
        ..failure = const ApiException(
          422,
          'Invalid registration',
          fieldErrors: {
            'email': 'Email cannot be used.',
            'password': 'Choose a different password.',
          },
        );
      await show(tester, SignUpScreen(authApi: api));
      await signupValues(tester);
      await submit(tester, 'Send Verification Code');
      expect(
        fieldWidget(tester, 0).decoration?.errorText,
        'Email cannot be used.',
      );
      expect(
        fieldWidget(tester, 1).decoration?.errorText,
        'Choose a different password.',
      );
      expect(fieldWidget(tester, 0).focusNode!.hasFocus, isTrue);
      expect(find.byType(FormErrorBanner), findsNothing);
      await tester.enterText(field(0), 'other@example.com');
      await tester.pumpAndSettle();
      expect(fieldWidget(tester, 0).decoration?.errorText, isNull);
      expect(
        fieldWidget(tester, 1).decoration?.errorText,
        'Choose a different password.',
      );
    },
  );

  for (final structured in [false, true]) {
    testWidgets(
      'signup 409 offers account recovery (field errors: $structured)',
      (tester) async {
        final api = _Auth()
          ..failure = ApiException(
            409,
            'Account already exists.',
            fieldErrors: structured ? {'email': 'Account already exists.'} : {},
          );
        await show(tester, SignUpScreen(authApi: api));
        await signupValues(tester);
        await submit(tester, 'Send Verification Code');
        expect(
          fieldWidget(tester, 0).decoration?.errorText,
          'Account already exists.',
        );
        expect(find.text('Sign in'), findsOneWidget);
        expect(find.text('Reset password'), findsOneWidget);
        expect(find.byType(FormErrorBanner), findsNothing);
        expect(api.calls, 1);
      },
    );
  }

  testWidgets('login client validation blocks missing and invalid email', (
    tester,
  ) async {
    final api = _Auth();
    await show(tester, LoginScreen(authApi: api));
    await submit(tester, 'Log In');
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    await tester.enterText(field(0), 'invalid');
    await tester.enterText(field(1), 'fixture');
    await submit(tester, 'Log In');
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(api.calls, 0);
  });

  testWidgets(
    'login aliases identifier errors to email and retains password errors',
    (tester) async {
      final api = _Auth()
        ..failure = const ApiException(
          401,
          'Sign in failed.',
          fieldErrors: {
            'identifier': 'Email is not verified.',
            'password': 'Password is incorrect.',
          },
        );
      await show(tester, LoginScreen(authApi: api));
      await tester.enterText(field(0), '  singer@example.com  ');
      await tester.enterText(field(1), 'fixture');
      await submit(tester, 'Log In');
      expect(api.email, 'singer@example.com');
      expect(
        fieldWidget(tester, 0).decoration?.errorText,
        'Email is not verified.',
      );
      expect(
        fieldWidget(tester, 1).decoration?.errorText,
        'Password is incorrect.',
      );
      expect(fieldWidget(tester, 0).focusNode!.hasFocus, isTrue);
      await tester.enterText(field(1), 'updated');
      await tester.pumpAndSettle();
      expect(fieldWidget(tester, 1).decoration?.errorText, isNull);
      expect(
        fieldWidget(tester, 0).decoration?.errorText,
        'Email is not verified.',
      );
    },
  );

  for (final failure in <Object>[
    const ApiException(401, 'Email or password is incorrect.'),
    const ApiException(403, 'Verify your email before signing in.'),
    const ApiException(429, 'Too many attempts. Try again later.'),
    StateError('offline'),
  ]) {
    testWidgets('login preserves specific failure: $failure', (tester) async {
      final api = _Auth()..failure = failure;
      await show(tester, LoginScreen(authApi: api));
      await tester.enterText(field(0), 'singer@example.com');
      await tester.enterText(field(1), 'fixture');
      await submit(tester, 'Log In');
      final message = failure is ApiException
          ? failure.message
          : 'Could not connect to server.';
      expect(find.text(message), findsOneWidget);
      expect(find.byType(FormErrorBanner), findsOneWidget);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(api.calls, 2);
      expect(find.text(message), findsOneWidget);
    });
  }

  testWidgets(
    'OTP validates locally then maps injected expired-code error and clears on edit',
    (tester) async {
      final api = _Auth()
        ..failure = const ApiException(
          400,
          'Verification failed.',
          fieldErrors: {'otp': 'This code has expired.'},
        );
      await show(
        tester,
        OtpVerificationScreen(email: 'singer@example.com', authApi: api),
      );
      await tester.enterText(field(0), '123');
      await submit(tester, 'Verify Email');
      expect(
        find.text('Enter the 6-digit code from your email'),
        findsOneWidget,
      );
      expect(api.calls, 0);
      await tester.enterText(field(0), '123456');
      await submit(tester, 'Verify Email');
      expect(api.email, 'singer@example.com');
      expect(api.submittedCode, '123456');
      expect(
        fieldWidget(tester, 0).decoration?.errorText,
        'This code has expired.',
      );
      expect(find.byType(FormErrorBanner), findsNothing);
      await tester.enterText(field(0), '654321');
      await tester.pumpAndSettle();
      expect(fieldWidget(tester, 0).decoration?.errorText, isNull);
    },
  );

  testWidgets(
    'forgot password validates email then maps injected server field error',
    (tester) async {
      final api = _Auth()
        ..failure = const ApiException(
          422,
          'Reset failed.',
          fieldErrors: {'email': 'Use a verified email address.'},
        );
      await show(tester, ForgotPasswordScreen(authApi: api));
      await submit(tester, 'Send temporary password');
      expect(find.text('Enter your email address.'), findsOneWidget);
      await tester.enterText(field(0), 'invalid');
      await submit(tester, 'Send temporary password');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(api.calls, 0);
      await tester.enterText(field(0), '  singer@example.com  ');
      await submit(tester, 'Send temporary password');
      expect(api.email, 'singer@example.com');
      expect(api.calls, 1);
      expect(
        fieldWidget(tester, 0).decoration?.errorText,
        'Use a verified email address.',
      );
      expect(fieldWidget(tester, 0).focusNode!.hasFocus, isTrue);
      await tester.enterText(field(0), 'other@example.com');
      await tester.pumpAndSettle();
      expect(fieldWidget(tester, 0).decoration?.errorText, isNull);
    },
  );

  for (final otp in [true, false]) {
    testWidgets(
      'injected ${otp ? 'OTP' : 'forgot'} transport failure enables retry',
      (tester) async {
        final api = _Auth()..failure = StateError('offline');
        await show(
          tester,
          otp
              ? OtpVerificationScreen(email: 'singer@example.com', authApi: api)
              : ForgotPasswordScreen(authApi: api),
        );
        await tester.enterText(field(0), otp ? '123456' : 'singer@example.com');
        await submit(tester, otp ? 'Verify Email' : 'Send temporary password');
        expect(
          find.text(
            otp
                ? 'Could not connect to server.'
                : 'Could not connect to the server.',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(api.calls, 2);
        expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNotNull,
        );
      },
    );
  }
}
