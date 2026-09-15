import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/reports/presentation/widgets/measurement_guide.dart';
import 'package:karaok_app/features/assessments/presentation/pages/recording_checklist.dart';

void main() {
  testWidgets('measurement help opens and closes at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: SingleChildScrollView(child: MeasurementGuide()),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Understand these measurements'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Loudness'));
    await tester.tap(find.text('Loudness'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('not the sound pressure'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('checklist expands to show recording consistency tips', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: RecordingChecklist()),
        ),
      ),
    );
    await tester.tap(find.text('Before you record'));
    await tester.pumpAndSettle();
    expect(find.text('Use the same song segment'), findsOneWidget);
    expect(find.text('Change one setting at a time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
