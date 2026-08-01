import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/security/secure_token_store.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/session_bootstrap_screen.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.instance.clear();
  });

  tearDown(UserSession.instance.clear);

  testWidgets('a valid persisted session restores the authenticated user', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionBootstrapScreen(
          authApi: _FakeAuthApi(() async => _user()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(UserSession.instance.id, 42);
    expect(UserSession.instance.email, 'saved@example.com');
    expect(UserSession.instance.isGuest, isFalse);
    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
  });

  testWidgets('a missing or rejected session continues as guest', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionBootstrapScreen(authApi: _FakeAuthApi(() async => null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(UserSession.instance.isGuest, isTrue);
    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
  });

  testWidgets('a temporary outage offers retry without deleting tokens', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'karaok_access_token': 'access-token',
      'karaok_refresh_token': 'refresh-token',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SessionBootstrapScreen(
          authApi: _FakeAuthApi(
            () async => throw ApiException(0, 'Server unavailable'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not restore your session'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(await SecureTokenStore.instance.readRefreshToken(), 'refresh-token');

    await tester.tap(find.text('Continue as Guest'));
    await tester.pumpAndSettle();
    expect(UserSession.instance.isGuest, isTrue);
    expect(await SecureTokenStore.instance.readRefreshToken(), 'refresh-token');
  });

  testWidgets(
    'restored temporary-password users cannot bypass password change',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionBootstrapScreen(
            authApi: _FakeAuthApi(
              () async => _user(requiresPasswordChange: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Password Change Required'), findsOneWidget);
      expect(find.text('Evaluate Audio Quality'), findsNothing);
    },
  );

  test('token cleanup keeps the remembered account', () async {
    await SecureTokenStore.instance.saveTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
    await SecureTokenStore.instance.saveLastIdentifier('saved@example.com');

    await SecureTokenStore.instance.clear();

    expect(await SecureTokenStore.instance.readAccessToken(), isNull);
    expect(await SecureTokenStore.instance.readRefreshToken(), isNull);
    expect(
      await SecureTokenStore.instance.readLastIdentifier(),
      'saved@example.com',
    );
  });

  testWidgets('login prefills and can forget the remembered account', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'karaok_last_identifier': 'saved@example.com',
    });

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('saved@example.com'), findsOneWidget);
    expect(find.byTooltip('Forget saved account'), findsOneWidget);

    await tester.tap(find.byTooltip('Forget saved account'));
    await tester.pumpAndSettle();

    expect(await SecureTokenStore.instance.readLastIdentifier(), isNull);
    expect(find.text('saved@example.com'), findsNothing);
    expect(find.byTooltip('Forget saved account'), findsNothing);
  });
}

Map<String, dynamic> _user({bool requiresPasswordChange = false}) => {
  'id': 42,
  'name': 'Saved User',
  'email': 'saved@example.com',
  'user_type': 'user',
  'username': 'saved-user',
  'first_name': 'Saved',
  'last_name': 'User',
  'address': null,
  'city': null,
  'state_province': null,
  'area_code': null,
  'country': null,
  'country_code': null,
  'phone_number': null,
  'birthday': null,
  'profile_image_base64': null,
  'profile_image_mime': null,
  'requires_password_change': requiresPasswordChange,
};

class _FakeAuthApi extends AuthApi {
  _FakeAuthApi(this.restore);

  final Future<Map<String, dynamic>?> Function() restore;

  @override
  Future<Map<String, dynamic>?> restoreSession() => restore();
}
