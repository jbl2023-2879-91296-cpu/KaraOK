import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/assessments/data/audio_staging_service.dart';
import 'support/audio_platform_stub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final browser in [false, true]) {
    test(
      'duration boundaries preserve prior audio on rejection (browser: $browser)',
      () async {
        final platform = AudioPlatformStub()..install();
        final directory = await Directory.systemTemp.createTemp(
          'karaok-duration-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = await File(
          '${directory.path}/sample.wav',
        ).writeAsBytes([1, 2, 3]);
        final service = AudioStagingService();
        Future<StagedAudio> stage() => browser
            ? service.stageBrowserRecording(file.path, 'sample.wav')
            : service.stagePath(
                file.path,
                AudioSourceType.recording,
                temporary: false,
              );
        final original = await stage();
        for (final milliseconds in [0, 1000, 9990, 300001]) {
          platform.duration = Duration(milliseconds: milliseconds);
          await expectLater(stage(), throwsA(isA<AudioStagingException>()));
          expect(service.current, same(original));
        }
        for (final seconds in [10, 300]) {
          platform.duration = Duration(seconds: seconds);
          final staged = await stage();
          expect(staged.duration, Duration(seconds: seconds));
          expect(service.current, same(staged));
        }
      },
    );
  }
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
