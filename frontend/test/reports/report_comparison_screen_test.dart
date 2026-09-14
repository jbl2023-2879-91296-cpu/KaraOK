import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/reports/domain/report_history.dart';
import 'package:karaok_app/features/reports/presentation/pages/report_comparison_screen.dart';

void main() {
  testWidgets('compares saved scores and reverses differences when swapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportComparisonScreen(
          entries: [
            ReportHistoryEntry.fromRaw({'test_name': 'First', 'score': 50}),
            ReportHistoryEntry.fromRaw({'test_name': 'Second', 'score': 80}),
          ],
        ),
      ),
    );
    expect(find.text('Difference (B − A): +30.00 points'), findsOneWidget);
    await tester.tap(find.text('Swap A and B'));
    await tester.pumpAndSettle();
    expect(find.text('Difference (B − A): -30.00 points'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing and nonfinite measurements never become zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportComparisonScreen(
          entries: [
            ReportHistoryEntry.fromRaw({'score': 'NaN'}),
            ReportHistoryEntry.fromRaw({'score': 80}),
          ],
        ),
      ),
    );
    expect(find.text('A: Unavailable'), findsWidgets);
    expect(find.text('Difference (B − A): Unavailable'), findsWidgets);
    expect(find.text('Difference (B − A): +80.00 points'), findsNothing);
  });

  testWidgets('requires two reports', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ReportComparisonScreen(entries: [])),
    );
    expect(
      find.text('Two saved reports are needed to compare.'),
      findsOneWidget,
    );
  });
}
