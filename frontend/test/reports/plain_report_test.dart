import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/reports/domain/measurement_glossary.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/detailed_report_screen.dart';
import 'package:karaok_app/features/reports/presentation/widgets/what_this_means_card.dart';
import 'package:karaok_app/features/reports/presentation/widgets/empirical_feature_table.dart';
import 'package:karaok_app/features/reports/presentation/widgets/measurement_guide.dart';
import 'package:karaok_app/features/reports/presentation/widgets/noise_guard_card.dart';
import 'package:karaok_app/features/reports/presentation/widgets/report_measurements.dart';

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
const expectedInterpretations = {
  'good':
      "Your karaoke sound is in good shape. It's close to the well-tuned systems we compared it with.",
  'good_but_needs_improvement':
      'Your sound is okay but could be better. See the items marked below for what to adjust.',
  'bad': 'Your sound needs adjusting. Start with the items marked below.',
  'not_evaluated': "We couldn't score this recording.",
};

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.instance.clear();
  });
  testWidgets(
    'results and details explain unreliable flatness without blaming it',
    (tester) async {
      const note = 'Background noise may affect this measurement.';
      await tester.pumpWidget(
        MaterialApp(
          home: ResultsScreen.fromRecord({
            'score': 85,
            'flatness_reliable': false,
            'flatness_reliability_note': note,
            'empirical_quality': {
              'features': {
                ...features(),
                'flatness': {
                  ...features(high: true)['flatness'] as Map<String, dynamic>,
                  'score': 0,
                  'status': 'bad',
                },
              },
            },
          }, isGuest: true),
        ),
      );
      void checkFlatness() {
        expect(find.text(note), findsOneWidget);
        expect(find.text('Unreliable'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('0.0/100')).style?.color,
          AppColors.muted,
        );
        expect(find.text('Too high'), findsNothing);
        expect(find.textContaining('Flatness:'), findsNothing);
        expect(
          find.textContaining('Some comparisons are unavailable'),
          findsOneWidget,
        );
      }

      checkFlatness();
      await tester.ensureVisible(find.text('View Visual Report'));
      await tester.tap(find.text('View Visual Report'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailedReportScreen), findsOneWidget);
      checkFlatness();
    },
  );
  for (final fromHistory in [false, true]) {
    testWidgets(
      'both reports show quality failure and advice, history=$fromHistory',
      (tester) async {
        const failure =
            'Background noise was too loud for a reliable result. Move closer to the speaker or record somewhere quieter.';
        const warning =
            '42% of the recording had sudden noises and was skipped.';
        final assessment = {
          'status': 'failed',
          'failures': [failure],
        };
        await tester.pumpWidget(
          MaterialApp(
            home: ResultsScreen.fromRecord({
              'score': 11.32,
              'noise_level': -34,
              'noise_reliable': true,
              'distortion_level': 5,
              'noise_guard_usable_percentage': 58,
              'noise_guard_confidence': 'low',
              'noise_guard_warnings': [warning],
              'empirical_quality': {
                'overall_status': 'bad',
                'features': features(),
              },
              if (fromHistory)
                'quality_assessment': assessment
              else
                'analysis_dump': {
                  'analysis': {'quality_assessment': assessment},
                },
            }),
          ),
        );
        void checkFailure() {
          expect(find.text('Audio quality check failed'), findsOneWidget);
          expect(find.text(failure), findsOneWidget);
          expect(find.text('Problematic'), findsNothing);
          expect(find.text('Audio quality score'), findsNothing);
          expect(find.text('Overall Audio Quality Score'), findsNothing);
          expect(find.text('What this means'), findsNothing);
        }

        checkFailure();
        expect(find.text(warning), findsNothing);
        await tester.tap(find.text('View Detailed Report'));
        await tester.pumpAndSettle();
        expect(find.byType(DetailedReportScreen), findsOneWidget);
        checkFailure();
        expect(find.text('Waveform Analysis'), findsOneWidget);
        expect(find.text('Spectrogram Analysis'), findsOneWidget);
        expect(find.text('Estimated noise level'), findsOneWidget);
        expect(find.text('Estimated distortion risk'), findsOneWidget);
        expect(find.text('Noise guard: Low confidence'), findsOneWidget);
        expect(find.text('58% of the recording was used'), findsOneWidget);
        expect(find.byType(EmpiricalFeatureTable), findsNothing);
        final warningText = find.descendant(
          of: find.byType(NoiseGuardCard),
          matching: find.text(warning),
        );
        await tester.ensureVisible(warningText);
        await tester.pumpAndSettle();
        expect(warningText.hitTestable(), findsOneWidget);
      },
    );
  }
  for (final sample in [
    (
      name: 'reliable quiet',
      value: -65,
      reliable: true,
      band: 'Quiet background',
    ),
    (
      name: 'reliable noisy',
      value: -10,
      reliable: true,
      band: 'Noisy background — you may hear hiss, hum or room noise',
    ),
    (name: 'unreliable', value: -10, reliable: false, band: null),
    (name: 'legacy unknown', value: -10, reliable: null, band: null),
  ]) {
    for (final guest in [false, true]) {
      testWidgets(
        '${sample.name} survives results and detail navigation guest=$guest',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: ResultsScreen.fromRecord({
                'noise_level': sample.value,
                if (sample.reliable != null) 'noise_reliable': sample.reliable,
                'score': 80,
              }, isGuest: guest),
            ),
          );
          void checkNoise() {
            final measurements = find.byType(ReportMeasurements).last;
            final scope = find.descendant(
              of: measurements,
              matching: find.byType(Text),
            );
            if (sample.band != null) {
              expect(
                find.descendant(
                  of: measurements,
                  matching: find.text(sample.band!),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: measurements,
                  matching: find.textContaining('Not enough quiet moments'),
                ),
                findsNothing,
              );
            } else {
              expect(
                find.descendant(
                  of: measurements,
                  matching: find.textContaining(
                    'Not enough quiet moments to judge background noise.',
                  ),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: measurements,
                  matching: find.textContaining('Noisy background'),
                ),
                findsNothing,
              );
            }
            expect(scope, findsWidgets);
            expect(
              tester.widget<ReportMeasurements>(measurements).noiseReliable,
              sample.reliable,
            );
          }

          checkNoise();
          await tester.ensureVisible(find.text('View Visual Report'));
          await tester.tap(find.text('View Visual Report'));
          await tester.pumpAndSettle();
          expect(find.byType(DetailedReportScreen), findsOneWidget);
          checkNoise();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final invalid in ['true', 'false', 1, 0, {}, []]) {
    testWidgets('malformed reliability $invalid stays unknown', (tester) async {
      final screen = ResultsScreen.fromRecord({
        'noise_level': -10,
        'noise_reliable': invalid,
      });
      expect(screen.noiseReliable, isNull);
      await tester.pumpWidget(MaterialApp(home: screen));
      expect(
        find.textContaining(
          'Not enough quiet moments to judge background noise.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Noisy background'), findsNothing);
    });
  }
  testWidgets(
    'summary never treats noise as a problem from an uncertain recording',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WhatThisMeansCard(
              features: {
                ...features(),
                'flatness': {'value': 3, 'target_lower': 0, 'target_upper': 2},
                'noise': {
                  'value': -10,
                  'target_lower': -60,
                  'target_upper': -45,
                  'reliable': false,
                },
              },
            ),
          ),
        ),
      );
      expect(find.textContaining('Noisy background'), findsNothing);
      expect(find.textContaining('hiss or room noise'), findsNothing);
      expect(find.textContaining('Noise:'), findsNothing);
      expect(
        find.text(
          'Flatness: more noise-like sound than usual — compare the same song section again.',
        ),
        findsOneWidget,
      );
    },
  );
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
        expect(find.text(expectedInterpretations[entry.key]!), findsOneWidget);
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
    for (final line in [
      'Loudness: louder than usual \u2014 the sound may be tiring.',
      'Bass: more deep bass than usual \u2014 the sound may feel boomy.',
      'Treble: more bright sound than usual \u2014 voices may sound hissy.',
    ]) {
      expect(find.text(line), findsOneWidget);
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
    expect(
      find.text(
        "Your karaoke sound is in good shape. It's close to the well-tuned systems we compared it with.",
      ),
      findsOneWidget,
    );
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
