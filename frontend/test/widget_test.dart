import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/main.dart';

void main() {
  testWidgets('KaraOK starts on the get-started screen', (tester) async {
    await tester.pumpWidget(const KaraOKApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Log In / Register'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
  });
}
