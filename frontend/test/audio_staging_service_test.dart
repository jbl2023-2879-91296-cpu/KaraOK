import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/assessments/data/audio_staging_service.dart';

void main() {
  test('symbolic MIDI files explain that rendered audio is required', () async {
    final directory = await Directory.systemTemp.createTemp(
      'karaok-midi-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    for (final extension in ['mid', 'midi']) {
      final file = File('${directory.path}/sample.$extension');
      await file.writeAsBytes([0x4d, 0x54, 0x68, 0x64]);
      await expectLater(
        AudioStagingService().stagePath(
          file.path,
          AudioSourceType.selectedFile,
          temporary: false,
        ),
        throwsA(
          isA<AudioStagingException>().having(
            (error) => error.message,
            'message',
            midiRenderedAudioMessage,
          ),
        ),
      );
    }
  });

  test(
    'unrelated extensions retain generic unsupported-format behavior',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'karaok-unsupported-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/sample.txt');
      await file.writeAsBytes([0x61]);

      await expectLater(
        AudioStagingService().stagePath(
          file.path,
          AudioSourceType.selectedFile,
          temporary: false,
        ),
        throwsA(
          isA<AudioStagingException>().having(
            (error) => error.message,
            'message',
            'This audio format is not supported.',
          ),
        ),
      );
    },
  );
}
