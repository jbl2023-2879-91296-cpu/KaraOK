import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/features/reports/domain/measurement_bands.dart';
import 'package:karaok_app/features/reports/presentation/widgets/report_measurements.dart';

void main() {
  for (final entry in <double, String>{
    -61: 'Quiet background',
    -60: 'Quiet background',
    -59.99: 'Some background noise',
    -45: 'Some background noise',
    -44.99: 'Noisy background',
  }.entries) {
    testWidgets('noise band at ${entry.key}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReportMeasurements(
                noiseLevelDb: entry.key,
                noiseReliable: true,
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(find.textContaining(noiseImplication), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final reliability in <bool?>[false, null]) {
    for (final value in [-65, -10]) {
      testWidgets('noise $value has no verdict when reliability is $reliability', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ReportMeasurements(
                  noiseLevelDb: value,
                  noiseReliable: reliability,
                ),
              ),
            ),
          ),
        );
        expect(find.text('Quiet background'), findsNothing);
        expect(find.text('Some background noise'), findsNothing);
        expect(find.textContaining('Noisy background'), findsNothing);
        expect(
          find.text(
            'Not enough quiet moments to judge background noise. To check, record a few seconds of silence before the song starts.',
          ),
          findsOneWidget,
        );
        final number = tester.widget<Text>(
          find.text('${value.toStringAsFixed(2)} dBFS'),
        );
        expect(number.style?.color, AppColors.muted);
        expect(number.style?.fontWeight, FontWeight.normal);
        await tester.tap(find.text('Estimated noise level'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.textContaining(
            'We only judge background noise when there are enough quiet moments',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Not enough quiet moments to judge background noise.',
          ),
          findsWidgets,
        );
      });
    }
  }
  for (final entry in <double, String>{
    0: 'Low risk',
    19.99: 'Low risk',
    20: 'Some risk',
    49: 'Some risk',
    49.99: 'Some risk',
    50: 'High risk',
    100: 'High risk',
  }.entries) {
    testWidgets('distortion band at ${entry.key}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReportMeasurements(distortionLevel: entry.key),
            ),
          ),
        ),
      );
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('both estimate cards explain meaning and tips on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReportMeasurements(noiseLevelDb: -60, distortionLevel: 50),
          ),
        ),
      ),
    );
    for (final label in [
      'Estimated noise level',
      'Estimated distortion risk',
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.textContaining("What's good:"), findsOneWidget);
      expect(find.textContaining('Try'), findsWidgets);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
    }
  });
  testWidgets('missing and non-finite estimates stay unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReportMeasurements(
              noiseLevelDb: double.nan,
              distortionLevel: double.infinity,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Not measured'), findsNWidgets(2));
    expect(find.textContaining('Quiet background'), findsNothing);
    expect(find.textContaining('Low risk'), findsNothing);
  });
}
