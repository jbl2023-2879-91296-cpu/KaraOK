import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';
import 'package:karaok_app/features/reports/domain/measurement_glossary.dart';
import 'package:karaok_app/features/reports/presentation/pages/glossary_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';
import 'package:karaok_app/features/reports/presentation/widgets/measurement_guide.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.instance.clear();
  });

  testWidgets(
    'Results info button opens glossary and back returns to Results',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ResultsScreen(score: 85)),
      );
      await tester.tap(find.byTooltip('Glossary of terms'));
      await tester.pumpAndSettle();
      expect(find.byType(GlossaryScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Results'), findsOneWidget);
    },
  );

  for (final guest in [false, true]) {
    testWidgets('Settings glossary navigation with guest=$guest', (
      tester,
    ) async {
      UserSession.instance.isGuest = guest;
      await tester.pumpWidget(const MaterialApp(home: ChangePasswordScreen()));
      await tester.ensureVisible(find.text('Glossary of terms'));
      await tester.tap(find.text('Glossary of terms'));
      await tester.pumpAndSettle();
      expect(find.byType(GlossaryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('measurement panel ends with glossary link', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MeasurementGuide())),
      ),
    );
    await tester.tap(find.text('Understand these measurements'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Glossary of terms'));
    await tester.tap(find.text('Glossary of terms'));
    await tester.pumpAndSettle();
    expect(find.byType(GlossaryScreen), findsOneWidget);
  });

  testWidgets(
    'all required terms share definition, karaoke meaning and good range',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GlossaryScreen()));
      for (final entry in measurementGlossary) {
        await tester.enterText(find.byType(TextField), entry.term);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ExpansionTile),
            matching: find.text(entry.term),
          ),
          findsOneWidget,
        );
        expect(find.text(entry.definition), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(ExpansionTile),
            matching: find.text(entry.term),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Why it matters for karaoke: ${entry.why}'),
          findsOneWidget,
        );
        expect(find.text("What's good: ${entry.good}"), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('search ignores case and spaces and handles no matches', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GlossaryScreen()));
    await tester.enterText(find.byType(TextField), '  BASS  ');
    await tester.pumpAndSettle();
    expect(find.text('Bass'), findsOneWidget);
    expect(find.text('Treble'), findsNothing);
    await tester.enterText(find.byType(TextField), 'no matching audio term');
    await tester.pumpAndSettle();
    expect(find.text('No matching terms. Try another word.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Amplifier profile'), findsOneWidget);
  });
}
