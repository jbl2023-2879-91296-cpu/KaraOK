import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/reports/presentation/widgets/empirical_feature_table.dart';

Future<void> pumpMeasurements(
  WidgetTester tester,
  Map<String, dynamic> features,
) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: EmpiricalFeatureTable(features: features),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openMeasurement(WidgetTester tester, String label) async {
  final row = find.text(label).first;
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'tapping high bass shows measured value, reference bounds and practical tip at 1.3 text scale',
    (tester) async {
      await pumpMeasurements(tester, {
        'bass': {
          'value': 95,
          'target_lower': 70,
          'target_upper': 90,
          'score': 65,
          'status': 'good_but_needs_improvement',
        },
      });
      await openMeasurement(tester, 'Bass');
      expect(find.text('Measured value: 95.00 %'), findsOneWidget);
      expect(find.text('Target lower: 70.00 %'), findsOneWidget);
      expect(find.text('Target upper: 90.00 %'), findsOneWidget);
      expect(
        find.text(
          'High for this reference range: the recording may have more deep bass.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('reduce bass one small step'), findsOneWidget);
    },
  );

  testWidgets('low loudness sheet explains direction and offers a concrete tip', (
    tester,
  ) async {
    await pumpMeasurements(tester, {
      'loudness': {
        'value': -30,
        'target_lower': -22,
        'target_upper': -14,
        'score': 40,
        'status': 'bad',
      },
    });
    await openMeasurement(tester, 'Loudness');
    expect(find.text('Measured value: -30.00 LUFS'), findsOneWidget);
    expect(find.text('Target lower: -22.00 LUFS'), findsOneWidget);
    expect(find.text('Target upper: -14.00 LUFS'), findsOneWidget);
    expect(
      find.text(
        'Low for this reference range: the recording may have quieter overall.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Check the recording distance first.'),
      findsOneWidget,
    );
  });

  testWidgets('legacy assessment without bounds does not invent a comparison', (
    tester,
  ) async {
    await pumpMeasurements(tester, {
      'treble': {'value': 0.4, 'score': 80, 'status': 'good'},
    });
    await openMeasurement(tester, 'Treble');
    expect(find.text('Measured value: 0.40 %'), findsOneWidget);
    expect(find.text('Target lower: Unavailable'), findsOneWidget);
    expect(find.text('Target upper: Unavailable'), findsOneWidget);
    expect(
      find.textContaining('high, low or within cannot be determined.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'missing measurement and inconsistent bounds are explained honestly',
    (tester) async {
      await pumpMeasurements(tester, {
        'flatness': {'target_lower': 0.5, 'target_upper': 0.1},
      });
      await openMeasurement(tester, 'Flatness');
      expect(find.text('Measured value: Unavailable'), findsOneWidget);
      expect(
        find.text(
          'The saved target bounds are inconsistent; no comparison is available.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'No measured value is available, so a comparison cannot be made.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('all five measurement rows open their explanation sheet', (
    tester,
  ) async {
    await pumpMeasurements(tester, {
      for (final metric in [
        'loudness',
        'bass',
        'treble',
        'sharpness',
        'flatness',
      ])
        metric: {
          'value': 0.2,
          'target_lower': 0.1,
          'target_upper': 0.3,
          'score': 100,
          'status': 'good',
        },
    });
    for (final label in [
      'Loudness',
      'Bass',
      'Treble',
      'Sharpness',
      'Flatness',
    ]) {
      await openMeasurement(tester, label);
      expect(
        find.text(
          'Within this reference range: this part of the sound is in line with the reference recordings.',
        ),
        findsOneWidget,
      );
      final context = tester.element(find.byType(BottomSheet));
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    }
  });
}
