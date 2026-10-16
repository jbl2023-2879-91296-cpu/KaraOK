import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/home/presentation/pages/user_home_screen.dart';
import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';

void main() {
  setUp(
    () => UserSession.instance.setUser(
      id: 31,
      name: '',
      email: 'user@example.com',
      userType: 'user',
      username: 'new-user',
    ),
  );
  tearDown(() => UserSession.instance.clear());

  testWidgets('incomplete profile can skip and continue using Home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: UserHomeScreen(resultsLoader: () async => [])),
    );
    await tester.pumpAndSettle();
    expect(find.text('Complete your profile'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(find.text('Complete your profile'), findsNothing);
    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
  });

  testWidgets('completion opens existing editor with empty personal fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: UserHomeScreen(resultsLoader: () async => [])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete profile'));
    await tester.pumpAndSettle();
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Last name'), findsOneWidget);
    expect(UserSession.instance.firstName, isNull);
    expect(UserSession.instance.birthday, isNull);
  });

  test('empty display name falls back to username', () {
    expect(UserSession.instance.name, 'new-user');
  });

  test('completed profile does not need a photo', () {
    UserSession.instance.setUserFromMap({
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
    });
    expect(UserSession.instance.needsProfileCompletion, isFalse);
    UserSession.instance.setGuest('user');
    expect(UserSession.instance.needsProfileCompletion, isFalse);
  });
}
