import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/reports/domain/measurement_glossary.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/detailed_report_screen.dart';
import 'package:karaok_app/features/reports/presentation/widgets/what_this_means_card.dart';
import 'package:karaok_app/features/reports/presentation/widgets/empirical_feature_table.dart';
import 'package:karaok_app/features/reports/presentation/widgets/measurement_guide.dart';

Map<String, dynamic> features({bool high = false}) => {
  for (final key in measurementLabels.keys)
    key: {
      'value': high ? 3 : 1,
      'target_lower': 0,
      'target_upper': 2,
      'score': 80,
      'status': 'good',
    },
};
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.instance.clear();
  });
  for (final entry in {
    'good': 85,
    'good_but_needs_improvement': 65,
    'bad': 35,
    'not_evaluated': null,
  }.entries) {
    testWidgets('plain interpretation for ${entry.key} on results and guest', (
      tester,
    ) async {
      for (final guest in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: ResultsScreen(
              score: entry.value,
              empiricalStatus: entry.key,
              isGuest: guest,
            ),
          ),
        );
        expect(
          find.text(reportInterpretation(entry.value, entry.key)),
          findsOneWidget,
        );
        expect(find.byType(WhatThisMeansCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('all five inside range produce one clear line', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WhatThisMeansCard(features: features())),
      ),
    );
    expect(
      find.text('All sound measurements are within their usual ranges.'),
      findsOneWidget,
    );
  });
  testWidgets('summary caps out-of-range lines at three', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WhatThisMeansCard(features: features(high: true))),
      ),
    );
    for (final label in ['Loudness', 'Bass', 'Treble']) {
      expect(
        find.text('$label: ${measurementMeaning(label, 'above')}'),
        findsOneWidget,
      );
    }
    expect(find.textContaining('Sharpness:'), findsNothing);
    expect(find.textContaining('Flatness:'), findsNothing);
  });
  testWidgets('missing ranges never claim that every feature is good', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WhatThisMeansCard(features: {})),
      ),
    );
    expect(
      find.text('There are no saved ranges to compare with this recording.'),
      findsOneWidget,
    );
  });
  testWidgets('rows show shared definitions and range statuses', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EmpiricalFeatureTable(
              features: {
                'bass': {'value': 3, 'target_lower': 0, 'target_upper': 2},
                'treble': {'value': -1, 'target_lower': 0, 'target_upper': 2},
                'sharpness': {'value': 1, 'target_lower': 0, 'target_upper': 2},
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text(glossaryEntry('Bass').definition), findsOneWidget);
    expect(find.text('Too high'), findsOneWidget);
    expect(find.text('Too low'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
  });
  testWidgets('detail shares interpretation and summary', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DetailedReportScreen(
          score: 85,
          empiricalStatus: 'good',
          featureResults: features(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(reportInterpretation(85, 'good')), findsOneWidget);
    expect(find.byType(WhatThisMeansCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final label in ['Noise level', 'Distortion risk']) {
    testWidgets('$label estimate sheet uses shared meaning and tip', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => MeasurementGuide.showEstimate(
                  context,
                  label: label,
                  value: '20',
                  meaning: 'Some risk',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text(glossaryEntry(label).definition), findsOneWidget);
      expect(
        find.text("What's good: ${glossaryEntry(label).good}"),
        findsOneWidget,
      );
      expect(find.text(glossaryEntry(label).tip), findsOneWidget);
    });
  }
}
