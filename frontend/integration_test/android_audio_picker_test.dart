// Android 10+ debug build. Select each PICKER_READY file in Downloads.
// flutter test integration_test/android_audio_picker_test.dart -d <device>
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/features/assessments/data/audio_staging_service.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [
    (name: '60-minute', seconds: 3600, mp3: false, sizeRejected: true),
    (
      name: '60-minute-low-bitrate',
      seconds: 3600,
      mp3: true,
      sizeRejected: false,
    ),
    (name: '6-minute', seconds: 360, mp3: false, sizeRejected: false),
    (name: '3-minute', seconds: 180, mp3: false, sizeRejected: false),
  ]) {
    testWidgets('real Android picker: ${scenario.name}', (tester) async {
      expect(Platform.isAndroid, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Text('Audio picker check')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final cache = await getTemporaryDirectory();
        final name =
            'karaok-picker-${scenario.name}.${scenario.mp3 ? 'mp3' : 'wav'}';
        final source = File('${cache.path}/$name');
        final staging = AudioStagingService();
        String? uri;
        final copied = <FileSystemEvent>[];
        final pickerCache = Directory('${cache.path}/karaok_audio_picker');
        await pickerCache.create(recursive: true);
        final watcher = pickerCache
            .watch(events: FileSystemEvent.create)
            .listen(copied.add);
        try {
          await _fixture(source, scenario.seconds, mp3: scenario.mp3);
          expect(
            await source.length(),
            scenario.sizeRejected
                ? greaterThan(AudioStagingService.maxBytes)
                : lessThan(AudioStagingService.maxBytes),
          );
          uri = await AudioStagingService.androidPicker.invokeMethod<String>(
            'publishPickerTestFixture',
            {'path': source.path, 'name': name},
          );
          expect(uri, isNotNull);
          debugPrint('PICKER_READY: select $name in Downloads');
          if (scenario.seconds > 300) {
            await expectLater(
              staging.pickAudio(),
              throwsA(
                isA<AudioStagingException>().having(
                  (error) => error.message,
                  'rejection message',
                  scenario.sizeRejected
                      ? 'The audio file exceeds the 25 MB limit.'
                      : AudioStagingService.durationLimitMessage,
                ),
              ),
            );
            expect(staging.current, isNull);
            if (scenario.sizeRejected) {
              // Detect even a cache copy that was subsequently deleted.
              await Future<void>.delayed(const Duration(milliseconds: 100));
              expect(
                copied,
                isEmpty,
                reason: 'Reject metadata before creating a copy',
              );
            }
            expect(await pickerCache.list().toList(), isEmpty);
          } else {
            final selected = await staging.pickAudio();
            expect(selected, isNotNull);
            expect(selected!.fileName, name);
            expect(selected.duration, const Duration(minutes: 3));
            expect(await File(selected.path).length(), await source.length());
          }
          debugPrint('PICKER_PASSED: $name');
        } finally {
          await watcher.cancel();
          await staging.discard();
          if (uri != null) {
            await AudioStagingService.androidPicker.invokeMethod<void>(
              'deletePickerTestFixture',
              {'uri': uri},
            );
          }
          if (await source.exists()) await source.delete();
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

Future<void> _fixture(File file, int seconds, {required bool mp3}) async {
  final output = await file.open(mode: FileMode.write);
  try {
    if (mp3) {
      // MPEG-2 Layer III, 8 kbps, 22050 Hz, 576 samples per frame.
      final frame = Uint8List(72000 * 8 ~/ 22050)..setAll(0, [255, 243, 16, 0]);
      final frames = (seconds * 22050 / 576).ceil();
      final chunk = Uint8List(frame.length * 1000);
      for (var i = 0; i < 1000; i++) {
        chunk.setAll(i * frame.length, frame);
      }
      for (var remaining = frames; remaining > 0;) {
        final count = remaining < 1000 ? remaining : 1000;
        await output.writeFrom(chunk, 0, count * frame.length);
        remaining -= count;
      }
      return;
    }
    // Mono PCM at 8 kHz: an hour exceeds 25 MB; shorter cases do not.
    final dataBytes = seconds * 16000;
    final header = ByteData(44);
    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    header.setUint32(4, 36 + dataBytes, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 8000, Endian.little);
    header.setUint32(28, 16000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    text(36, 'data');
    header.setUint32(40, dataBytes, Endian.little);
    await output.writeFrom(header.buffer.asUint8List());
    final chunk = Uint8List(64 * 1024);
    for (var remaining = dataBytes; remaining > 0;) {
      final count = remaining < chunk.length ? remaining : chunk.length;
      await output.writeFrom(chunk, 0, count);
      remaining -= count;
    }
  } finally {
    await output.close();
  }
}
