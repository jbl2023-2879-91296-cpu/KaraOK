import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karaok_app/core/network/api_service.dart';
import 'package:karaok_app/features/assessments/data/assessment_api.dart';
import 'package:karaok_app/features/assessments/data/audio_staging_service.dart';
import 'package:karaok_app/features/assessments/presentation/pages/recording_checklist.dart';

void main() {
  test('recordings need ten seconds of song after the noise check', () {
    expect(
      () => AudioStagingService.validateDuration(
        const Duration(milliseconds: 12999),
        noisePrerollSeconds: 3,
      ),
      throwsA(isA<AudioStagingException>()),
    );
    AudioStagingService.validateDuration(
      const Duration(seconds: 13),
      noisePrerollSeconds: 3,
    );
    AudioStagingService.validateDuration(const Duration(seconds: 10));
  });

  testWidgets('checklist shows the placement tip', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: RecordingChecklist()),
        ),
      ),
    );
    await tester.tap(find.text('Before you record'));
    await tester.pumpAndSettle();
    expect(find.text('Point the microphone at the speaker'), findsOneWidget);
    expect(
      find.text('For uncalibrated recordings, start about 30 cm (1 ft) away.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Phone is in the same spot and distance used for calibration (1 m)',
      ),
      findsOneWidget,
    );
  });

  test('submitAudio sends noise_preroll_seconds only when > 0', () async {
    final bodies = <String>[];
    final api = AssessmentApi(
      client: ApiService.withClient(
        MockClient((request) async {
          bodies.add(request.body);
          return http.Response('{}', 200);
        }),
      ),
    );
    await api.submitAudio(
      filePath: '',
      fileName: 'picked.wav',
      fileBytes: Uint8List(4),
      durationSeconds: 20,
      guest: true,
    );
    await api.submitAudio(
      filePath: '',
      fileName: 'recorded.wav',
      fileBytes: Uint8List(4),
      durationSeconds: 20,
      guest: true,
      noisePrerollSeconds: 3,
    );
    expect(bodies.first, isNot(contains('noise_preroll_seconds')));
    expect(
      bodies.last,
      contains('name="noise_preroll_seconds"\r\n\r\n3.0\r\n'),
    );
  });
}
