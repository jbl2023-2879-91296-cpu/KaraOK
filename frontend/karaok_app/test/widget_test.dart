import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/main.dart';

void main() {
  testWidgets('KaraOK starts on the role-selection screen', (tester) async {
    await tester.pumpWidget(const KaraOKApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Technician'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
  });
}
