import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/account/data/account_api.dart';
import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/shared/widgets/form_feedback.dart';

const completeUser = <String, dynamic>{
  'id': 31,
  'name': 'New User',
  'username': 'new-user',
  'email': 'user@example.com',
  'user_type': 'user',
  'first_name': 'New',
  'last_name': 'User',
  'address': '123 Sample Street',
  'city': 'Manila',
  'state_province': 'Metro Manila',
  'area_code': '1000',
  'country': 'Philippines',
  'country_code': 'PH',
  'phone_number': '+639123456789',
  'birthday': '2000-01-02',
};

class _Auth extends AuthApi {
  Object failure = const ApiException(
    401,
    'Password rejected.',
    fieldErrors: {'current_password': 'Current password is incorrect.'},
  );
  int calls = 0;
  int logoutCalls = 0;
  int clearTokenCalls = 0;
  Future<void>? pending;
  @override
  Future<void> logout() async {
    logoutCalls++;
  }

  @override
  Future<void> clearTokens() async {
    clearTokenCalls++;
  }

  String? current;
  String? password;
  @override
  Future<void> changePassword({
    String? currentPassword,
    required String newPassword,
  }) async {
    calls++;
    current = currentPassword;
    password = newPassword;
    if (pending != null) return pending!;
    throw failure;
  }
}

class _Account extends AccountApi {
  Future<Map<String, dynamic>>? pending;
  ApiException? failure;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> updateProfile({
    required String username,
    required String firstName,
    required String lastName,
    required String address,
    required String city,
    required String stateProvince,
    required String areaCode,
    required String country,
    required String countryCode,
    required String phoneNumber,
    required String birthday,
    String? profileImageBase64,
    String? profileImageMime,
    bool profileImageChanged = false,
  }) async {
    calls++;
    if (pending != null) return pending!;
    if (failure != null) throw failure!;
    return {
      ...completeUser,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'address': address,
      'city': city,
      'state_province': stateProvince,
      'area_code': areaCode,
      'country': country,
      'country_code': countryCode,
      'phone_number': phoneNumber,
      'birthday': birthday,
    };
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
TextField input(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label));

Future<void> show(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

Future<void> submit(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> passwordValues(WidgetTester tester) async {
  for (final entry in {
    'Current password': 'OldPassword1!',
    'New password': 'NewPassword2!',
    'Retype new password': 'NewPassword2!',
  }.entries) {
    await tester.ensureVisible(field(entry.key));
    await tester.enterText(field(entry.key), entry.value);
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.instance.setUserFromMap(completeUser);
  });
  tearDown(() => UserSession.instance.clear());

  testWidgets('password server error is inline, focused and cleared on edit', (
    tester,
  ) async {
    final api = _Auth();
    await show(tester, ChangePasswordScreen(authApi: api));
    await passwordValues(tester);
    await submit(tester, 'Confirm password change');
    expect(api.calls, 1);
    expect(api.current, 'OldPassword1!');
    expect(api.password, 'NewPassword2!');
    expect(
      input(tester, 'Current password').decoration?.errorText,
      'Current password is incorrect.',
    );
    expect(input(tester, 'Current password').focusNode!.hasFocus, isTrue);
    expect(find.byType(FormErrorBanner), findsNothing);
    await tester.enterText(field('Current password'), 'CorrectedPassword1!');
    await tester.pumpAndSettle();
    expect(input(tester, 'Current password').decoration?.errorText, isNull);
  });

  testWidgets('password alias targets new password during forced change', (
    tester,
  ) async {
    final api = _Auth()
      ..failure = const ApiException(
        400,
        'Rejected',
        fieldErrors: {'password': 'Choose a different password.'},
      );
    await show(tester, ChangePasswordScreen(forceChange: true, authApi: api));
    await tester.enterText(field('New password'), 'NewPassword2!');
    await tester.enterText(field('Retype new password'), 'NewPassword2!');
    await submit(tester, 'Confirm password change');
    expect(api.current, isNull);
    expect(
      input(tester, 'New password').decoration?.errorText,
      'Choose a different password.',
    );
    expect(input(tester, 'New password').focusNode!.hasFocus, isTrue);
  });

  testWidgets(
    'password interaction validates only touched field; submit validates all',
    (tester) async {
      final api = _Auth();
      await show(tester, ChangePasswordScreen(authApi: api));
      await tester.ensureVisible(field('New password'));
      await tester.enterText(field('New password'), 'weak');
      await tester.pumpAndSettle();
      expect(input(tester, 'New password').decoration?.errorText, isNotNull);
      expect(input(tester, 'Current password').decoration?.errorText, isNull);
      expect(
        input(tester, 'Retype new password').decoration?.errorText,
        isNull,
      );
      await submit(tester, 'Confirm password change');
      expect(
        input(tester, 'Current password').decoration?.errorText,
        'Enter your current password.',
      );
      expect(input(tester, 'Current password').focusNode!.hasFocus, isTrue);
      expect(api.calls, 0);
    },
  );

  testWidgets(
    'general password failure shows top retry banner without clearing values',
    (tester) async {
      final api = _Auth()..failure = Exception('offline');
      await show(tester, ChangePasswordScreen(forceChange: true, authApi: api));
      await tester.enterText(field('New password'), 'NewPassword2!');
      await tester.enterText(field('Retype new password'), 'NewPassword2!');
      await submit(tester, 'Confirm password change');
      expect(find.byType(FormErrorBanner), findsOneWidget);
      expect(find.text('Could not connect to the server.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(api.calls, 2);
      expect(input(tester, 'New password').controller!.text, 'NewPassword2!');
    },
  );

  for (final entry in {
    'username': 'Username',
    'phone_number': 'Phone number',
    'country_code': 'Country',
  }.entries) {
    testWidgets(
      'profile server field ${entry.key} maps inline and focuses input',
      (tester) async {
        final api = _Account()
          ..failure = ApiException(
            409,
            'Conflict',
            fieldErrors: {entry.key: 'Please change this value.'},
          );
        await show(
          tester,
          ChangePasswordScreen(editProfile: true, accountApi: api),
        );
        await submit(tester, 'Save Changes');
        expect(api.calls, 1);
        expect(
          input(tester, entry.value).decoration?.errorText,
          'Please change this value.',
        );
        expect(input(tester, entry.value).focusNode!.hasFocus, isTrue);
        expect(find.byType(FormErrorBanner), findsNothing);
      },
    );
  }

  for (final name in [
    'profile_image',
    'profile_image_base64',
    'profile_image_mime',
  ]) {
    testWidgets('profile image field $name maps to image feedback', (
      tester,
    ) async {
      final api = _Account()
        ..failure = ApiException(
          400,
          'Invalid image',
          fieldErrors: {name: 'Choose a valid profile image.'},
        );
      await show(
        tester,
        ChangePasswordScreen(editProfile: true, accountApi: api),
      );
      await submit(tester, 'Save Changes');
      expect(api.calls, 1);
      expect(find.text('Choose a valid profile image.'), findsOneWidget);
      expect(find.byType(FormErrorBanner), findsNothing);
    });
  }

  testWidgets('profile save updates session completion and exits editor', (
    tester,
  ) async {
    UserSession.instance.setUserFromMap({...completeUser, 'first_name': null});
    final api = _Account();
    await show(
      tester,
      ChangePasswordScreen(editProfile: true, accountApi: api),
    );
    expect(find.text('Finish your profile'), findsOneWidget);
    await tester.enterText(field('First name'), 'New');
    await submit(tester, 'Save Changes');
    expect(api.calls, 1);
    expect(UserSession.instance.needsProfileCompletion, isFalse);
    expect(find.text('Finish your profile'), findsNothing);
    expect(find.text('Save Changes'), findsNothing);
    expect(find.text('Account details updated.'), findsOneWidget);
  });

  testWidgets(
    'profile interaction leaves untouched fields quiet until submit',
    (tester) async {
      UserSession.instance.setUserFromMap({
        ...completeUser,
        'first_name': null,
        'last_name': null,
      });
      final api = _Account();
      await show(
        tester,
        ChangePasswordScreen(editProfile: true, accountApi: api),
      );
      await tester.enterText(field('Username'), '!');
      await tester.pumpAndSettle();
      expect(input(tester, 'Username').decoration?.errorText, isNotNull);
      expect(input(tester, 'First name').decoration?.errorText, isNull);
      expect(input(tester, 'Last name').decoration?.errorText, isNull);
      await submit(tester, 'Save Changes');
      expect(
        input(tester, 'First name').decoration?.errorText,
        'Enter your first name.',
      );
      expect(
        input(tester, 'Last name').decoration?.errorText,
        'Enter your last name.',
      );
      expect(input(tester, 'First name').focusNode!.hasFocus, isTrue);
      expect(api.calls, 0);
    },
  );

  testWidgets('editing one profile field retains other server errors', (
    tester,
  ) async {
    final api = _Account()
      ..failure = const ApiException(
        409,
        'Conflict',
        fieldErrors: {
          'username': 'Username is taken.',
          'phone_number': 'Phone number is taken.',
        },
      );
    await show(
      tester,
      ChangePasswordScreen(editProfile: true, accountApi: api),
    );
    await submit(tester, 'Save Changes');
    expect(
      input(tester, 'Username').decoration?.errorText,
      'Username is taken.',
    );
    expect(
      input(tester, 'Phone number').decoration?.errorText,
      'Phone number is taken.',
    );
    await tester.enterText(field('Username'), 'available-name');
    await tester.pumpAndSettle();
    expect(input(tester, 'Username').decoration?.errorText, isNull);
    expect(
      input(tester, 'Phone number').decoration?.errorText,
      'Phone number is taken.',
    );
  });

  testWidgets('profile image server error does not block password submission', (
    tester,
  ) async {
    final account = _Account()
      ..failure = const ApiException(
        400,
        'Invalid image',
        fieldErrors: {'profile_image': 'Choose a valid profile image.'},
      );
    final auth = _Auth();
    await show(
      tester,
      ChangePasswordScreen(
        editProfile: true,
        accountApi: account,
        authApi: auth,
      ),
    );
    await submit(tester, 'Save Changes');
    expect(find.text('Choose a valid profile image.'), findsOneWidget);
    await passwordValues(tester);
    await submit(tester, 'Confirm password change');
    expect(auth.calls, 1);
    expect(
      input(tester, 'Current password').decoration?.errorText,
      'Current password is incorrect.',
    );
  });

  testWidgets('pending profile save cannot restore account after logout', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    final account = _Account()..pending = response.future;
    final auth = _Auth();
    await show(
      tester,
      ChangePasswordScreen(
        editProfile: true,
        accountApi: account,
        authApi: auth,
      ),
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    expect(account.calls, 1);
    await tester.ensureVisible(find.text('Log Out'));
    // Logout awaits disk cache cleanup; let that I/O finish outside fake time.
    await tester.runAsync(() async {
      await tester.tap(find.text('Log Out'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(auth.logoutCalls, 1);
    expect(UserSession.instance.isGuest, isTrue);
    response.complete(completeUser);
    await tester.pumpAndSettle();
    expect(UserSession.instance.isGuest, isTrue);
    expect(UserSession.instance.id, isNull);
    expect(find.text('Account details updated.'), findsNothing);
  });

  testWidgets('late profile save ignores a new login by the same user', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>>();
    final account = _Account()..pending = response.future;
    await show(
      tester,
      ChangePasswordScreen(editProfile: true, accountApi: account),
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    UserSession.instance.clear();
    UserSession.instance.setUserFromMap({
      ...completeUser,
      'first_name': 'Fresh login',
    });
    response.complete(completeUser);
    await tester.pumpAndSettle();
    expect(UserSession.instance.firstName, 'Fresh login');
    expect(find.text('Account details updated.'), findsNothing);
  });

  for (final disposeScreen in [false, true]) {
    testWidgets(
      'late profile save ignores replaced session (disposed: $disposeScreen)',
      (tester) async {
        final response = Completer<Map<String, dynamic>>();
        final account = _Account()..pending = response.future;
        await show(
          tester,
          ChangePasswordScreen(editProfile: true, accountApi: account),
        );
        await tester.ensureVisible(find.text('Save Changes'));
        await tester.tap(find.text('Save Changes'));
        await tester.pump();
        expect(account.calls, 1);
        if (disposeScreen) await tester.pumpWidget(const SizedBox.shrink());
        UserSession.instance.setUserFromMap({
          ...completeUser,
          'id': 99,
          'email': 'other@example.com',
        });
        response.complete(completeUser);
        await tester.pumpAndSettle();
        expect(UserSession.instance.id, 99);
        expect(UserSession.instance.email, 'other@example.com');
        expect(find.text('Account details updated.'), findsNothing);
      },
    );
  }

  testWidgets(
    'late password change cannot clear replacement session or tokens',
    (tester) async {
      final response = Completer<void>();
      final auth = _Auth()..pending = response.future;
      await show(tester, ChangePasswordScreen(authApi: auth));
      await passwordValues(tester);
      await tester.ensureVisible(find.text('Confirm password change'));
      await tester.tap(find.text('Confirm password change'));
      await tester.pump();
      expect(auth.calls, 1);
      UserSession.instance.setUserFromMap({
        ...completeUser,
        'id': 99,
        'email': 'other@example.com',
      });
      response.complete();
      await tester.pumpAndSettle();
      expect(UserSession.instance.id, 99);
      expect(UserSession.instance.email, 'other@example.com');
      expect(auth.clearTokenCalls, 0);
      expect(find.text('Password changed. Please log in again.'), findsNothing);
    },
  );
}
