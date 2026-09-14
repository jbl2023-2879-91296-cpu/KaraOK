import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/reports/presentation/pages/detailed_report_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    UserSession.instance.clear();
  });

  Future<void> openDetails(
    WidgetTester tester,
    Map<String, dynamic> record,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ResultsScreen.fromRecord(record)),
    );
    await tester.ensureVisible(find.text('View Visual Report'));
    await tester.tap(find.text('View Visual Report'));
    await tester.pumpAndSettle();
  }

  testWidgets('visual report keeps the stored decimal score and grade', (
    tester,
  ) async {
    await openDetails(tester, {
      'test_name': 'Recorded instrumental',
      'score': 79.96,
      'empirical_quality': {
        'overall_score': 79.96,
        'overall_status': 'good_but_needs_improvement',
      },
    });
    expect(find.text('NEEDS IMPROVEMENT'), findsOneWidget);
    expect(find.text('80'), findsNothing);
    expect(find.text('79.96'), findsOneWidget);
    expect(find.text('Recorded instrumental'), findsOneWidget);
  });

  testWidgets('missing measurements stay missing when opening visual report', (
    tester,
  ) async {
    await openDetails(tester, {'test_name': 'Legacy report', 'score': 55});
    expect(find.text('Not measured'), findsWidgets);
    expect(find.text('0.0 dB'), findsNothing);
    expect(find.text('low'), findsNothing);
    expect(find.text('acceptable'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('NEEDS IMPROVEMENT'), findsOneWidget);
  });

  testWidgets(
    'measured noise and distortion use correct units and limitations',
    (tester) async {
      await openDetails(tester, {
        'test_name': 'Reference recording 1',
        'score': 85,
        // Actual extracted values from results/1/...093733..._analysis.json.
        'noise_level': -13.583767802006799,
        'distortion_level': 11.740938609178784,
      });
      expect(find.text('-13.58 dBFS'), findsOneWidget);
      expect(find.text('11.74 / 100'), findsOneWidget);
      expect(find.textContaining('not a THD measurement'), findsOneWidget);
      expect(find.textContaining('quiet section'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('visual report has no demonstration defaults', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DetailedReportScreen()));
    await tester.pumpAndSettle();
    expect(find.text('NOT SCORED'), findsOneWidget);
    expect(find.text('82'), findsNothing);
    expect(find.textContaining('-4.8'), findsNothing);
    expect(find.text('Not measured'), findsWidgets);
  });

  testWidgets('precise scores fit a narrow visual report', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(
        home: DetailedReportScreen(
          score: 79.9999999999,
          empiricalStatus: 'good_but_needs_improvement',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('79.9999999999'), findsOneWidget);
  });

  testWidgets('non-finite values are not displayed as scores or measurements', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen.fromRecord({
          'score': 'NaN',
          'noise_level': 'Infinity',
          'distortion_level': double.nan,
        }),
      ),
    );
    expect(find.text('NOT SCORED'), findsWidgets);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
  });

  testWidgets('reference count comes from the saved assessment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen.fromRecord({
          'empirical_quality': {
            'overall_score': 84,
            'overall_status': 'good',
            'reference_recording_count': 42,
          },
        }),
      ),
    );
    expect(find.textContaining('42 analyzed'), findsOneWidget);
    expect(find.textContaining('30-recording'), findsNothing);
    expect(find.textContaining('30 analyzed'), findsNothing);
  });

  testWidgets('a saved status without a valid score makes no numeric claim', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen.fromRecord({
          'empirical_quality': {
            'overall_score': null,
            'overall_status': 'good',
          },
        }),
      ),
    );
    expect(find.text('NOT SCORED'), findsWidgets);
    expect(find.textContaining('at least 80'), findsNothing);
    expect(find.textContaining('No valid score'), findsOneWidget);
  });

  testWidgets('feature scores retain precision near grade boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen.fromRecord({
          'empirical_quality': {
            'overall_score': 79.96,
            'overall_status': 'good_but_needs_improvement',
            'features': {
              'loudness': {
                'value': -13.5,
                'score': 79.96,
                'status': 'good_but_needs_improvement',
              },
            },
          },
        }),
      ),
    );
    expect(find.text('79.96/100'), findsOneWidget);
    expect(find.text('80.0/100'), findsNothing);
  });

  testWidgets('visual report preserves the saved five-feature measurements', (
    tester,
  ) async {
    await openDetails(tester, {
      'empirical_quality': {
        'overall_score': 83,
        'overall_status': 'good',
        'reference_recording_count': 30,
        'features': {
          'loudness': {
            'value': -10.739151474973323,
            'score': 84.6,
            'status': 'good',
          },
          'bass': {'value': 61.73133359678683, 'score': 90.5, 'status': 'good'},
        },
      },
    });
    expect(find.text('Empirical five-feature grading'), findsOneWidget);
    expect(find.text('-10.74 LUFS'), findsOneWidget);
    expect(find.text('61.73 %'), findsOneWidget);
    expect(find.textContaining('30 analyzed'), findsOneWidget);
  });
}
