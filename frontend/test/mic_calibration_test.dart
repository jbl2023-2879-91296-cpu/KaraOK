import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';
import 'package:karaok_app/features/calibration/data/mic_calibration_store.dart';
import 'package:karaok_app/features/calibration/presentation/pages/mic_calibration_screen.dart';

const correction = {
  'version': 1,
  'level_offset_db': 1.25,
  'band_centers_hz': [63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000],
  'band_offsets_db': [0, 1, 0, 1, 0, -1, 0, -1, 0],
  'reference_id': 'ref',
  'clamped': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = MicCalibrationStore();
  final now = DateTime.utc(2026, 11, 25);

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('calibration round-trips and can be cleared', () async {
    await store.save(
      MicCalibration(
        measurementId: 'ab12cd34',
        noiseFloorDbfs: -50,
        calibratedAt: now,
        correction: correction,
      ),
    );
    final loaded = (await store.load())!;
    expect(loaded.measurementId, 'ab12cd34');
    expect(loaded.noiseFloorDbfs, -50);
    expect(loaded.correction, correction);
    expect(loaded.calibratedAt, now);
    expect(await store.shouldPrompt(now: now), isFalse);
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('skip expires after seven days and floor-only still prompts', () async {
    await store.save(
      MicCalibration(
        measurementId: 'ab12cd34',
        noiseFloorDbfs: -50,
        calibratedAt: now,
      ),
    );
    expect((await store.load())?.noiseFloorDbfs, -50);
    expect(await store.shouldPrompt(now: now), isTrue);
    await store.skip(now: now);
    expect(
      await store.shouldPrompt(
        now: now.add(const Duration(days: 7, seconds: -1)),
      ),
      isFalse,
    );
    expect(
      await store.shouldPrompt(now: now.add(const Duration(days: 7))),
      isTrue,
    );
  });

  test('noise check raises the threshold only for a higher mic floor', () {
    expect(noisyPrerollThreshold(null), -45);
    expect(noisyPrerollThreshold(-50), -35);
    expect(noisyPrerollThreshold(-75), -45);
  });

  for (final hasReference in [true, false]) {
    testWidgets('setup and result with reference available = $hasReference', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MicCalibrationScreen(
            recordAndMeasure: () async => {
              'measurement_id': 'ab12cd34',
              'noise_floor_dbfs': -50,
              'message':
                  'Measured. No reference phone is set on the server yet.',
              'correction': hasReference ? correction : null,
            },
          ),
        ),
      );
      expect(find.textContaining('1 metre in front'), findsOneWidget);
      expect(find.textContaining('Keep the room quiet'), findsOneWidget);
      await tester.tap(find.text('Start calibration'));
      await tester.pumpAndSettle();
      expect(find.text('Calibration ID: ab12cd34'), findsOneWidget);
      expect(
        find.text('Calibrated'),
        hasReference ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('No reference phone'),
        hasReference ? findsNothing : findsOneWidget,
      );
      expect(
        (await store.load())?.correction,
        hasReference ? correction : null,
      );
    });
  }
}
