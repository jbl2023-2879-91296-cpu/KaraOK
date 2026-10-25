import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:karaok_app/features/assessments/data/audio_staging_service.dart';
import 'support/audio_platform_stub.dart';

class _RecordingService extends AudioStagingService {
  _RecordingService(this.directory);
  final Directory directory;
  @override
  Future<Directory> recordingDirectory() async => directory;
}

class _NoFilesystemService extends AudioStagingService {
  @override
  Future<void> discard() async =>
      throw StateError('Web must not discard files');
  @override
  Future<Directory> recordingDirectory() async =>
      throw StateError('Web must not access recording directories');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('web logout cleanup returns before filesystem operations', () async {
    await _NoFilesystemService().cleanupStaleRecordings();
  }, skip: !kIsWeb);
  test('overlong audio explains the exact trim-and-retry action', () {
    expect(
      () => AudioStagingService.validateDuration(const Duration(minutes: 6)),
      throwsA(
        isA<AudioStagingException>().having(
          (error) => error.message,
          'message',
          'This audio is longer than 5 minutes. Trim it to a 10-second to 5-minute section and try again.',
        ),
      ),
    );
  });
  group('native staging', () {
    Future<File> fixture(String name, List<int> bytes) async {
      final directory = await Directory.systemTemp.createTemp('karaok-header-');
      addTearDown(() => directory.delete(recursive: true));
      return File('${directory.path}/$name').writeAsBytes(bytes);
    }

    Future<StagedAudio> stage(File file) => AudioStagingService().stagePath(
      file.path,
      AudioSourceType.selectedFile,
      temporary: false,
    );

    List<int> mp3(int frames, {bool variable = false}) {
      final bytes = <int>[];
      for (var i = 0; i < frames; i++) {
        // MPEG 2 Layer III, 8/16 kbps, 22050 Hz.
        final high = variable && i.isOdd;
        final length = 72000 * (high ? 16 : 8) ~/ 22050;
        bytes.addAll([255, 243, high ? 32 : 16, 0]);
        bytes.addAll(List.filled(length - 4, 0));
      }
      return bytes;
    }

    test('long low bitrate MP3 is rejected without a native player', () async {
      final file = await fixture('long.mp3', mp3(12000));
      expect(await file.length(), lessThan(AudioStagingService.maxBytes));
      await expectLater(
        stage(file),
        throwsA(
          isA<AudioStagingException>().having(
            (e) => e.message,
            'message',
            AudioStagingService.durationLimitMessage,
          ),
        ),
      );
    });

    test('CBR and VBR MP3 use frame duration without native loading', () async {
      for (final variable in [false, true]) {
        final file = await fixture('valid.mp3', mp3(400, variable: variable));
        final result = await stage(file);
        expect(result.duration.inMilliseconds, closeTo(10449, 1));
      }
    });

    test('ambiguous MP3 headers defer to player duration', () async {
      AudioPlatformStub().install();
      for (final bytes in [
        mp3(400)..removeLast(),
        [73, 68, 51, 4, 0, 0, 128, 0, 0, 0],
        List<int>.filled(20, 0),
      ]) {
        final file = await fixture('bad.mp3', bytes);
        expect((await stage(file)).duration, const Duration(seconds: 20));
      }
    });

    test(
      'APEv2 Lyrics3 padding and leading junk do not reject valid MP3',
      () async {
        final platform = AudioPlatformStub()..install();
        for (final tail in [
          'APETAGEX'.codeUnits + List<int>.filled(40, 0),
          'LYRICSBEGINwordsLYRICS200'.codeUnits,
          List<int>.filled(300, 0),
        ]) {
          final file = await fixture('tagged.mp3', [...mp3(400), ...tail]);
          platform.duration = const Duration(seconds: 20);
          expect((await stage(file)).duration, const Duration(seconds: 20));
          platform.duration = const Duration(hours: 3);
          await expectLater(
            stage(file),
            throwsA(
              isA<AudioStagingException>().having(
                (e) => e.message,
                'duration violation',
                AudioStagingService.durationLimitMessage,
              ),
            ),
          );
        }
        final file = await fixture('leading.mp3', [1, 2, 3, 4, ...mp3(400)]);
        expect((await stage(file)).duration.inMilliseconds, closeTo(10449, 1));
        final long = await fixture('leading-long.mp3', [
          1,
          2,
          3,
          ...mp3(12000),
        ]);
        await expectLater(
          stage(long),
          throwsA(
            isA<AudioStagingException>().having(
              (e) => e.message,
              'duration violation',
              AudioStagingService.durationLimitMessage,
            ),
          ),
        );
      },
    );

    test(
      'Android picker returns metadata and cached path without file-selector bytes',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final file = await fixture('picked.mp3', mp3(400));
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        var calls = 0;
        messenger.setMockMethodCallHandler(AudioStagingService.androidPicker, (
          call,
        ) async {
          expect(call.method, 'pickAudio');
          calls++;
          return {
            'path': file.path,
            'name': 'My recording.mp3',
            'size': await file.length(),
          };
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            AudioStagingService.androidPicker,
            null,
          ),
        );
        final service = AudioStagingService();
        final audio = await service.pickAudio();
        expect(calls, 1);
        expect(audio!.fileName, 'My recording.mp3');
        expect(audio.bytes, isNull);
        expect(audio.temporary, isTrue);
        await service.discard();
        expect(await file.exists(), isFalse);
      },
    );

    test(
      'Android picker rejects size metadata before probing and deletes cache',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final file = await fixture('too-large.mp3', [1]);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          AudioStagingService.androidPicker,
          (_) async => {
            'path': file.path,
            'name': 'too-large.mp3',
            'size': AudioStagingService.maxBytes + 1,
          },
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            AudioStagingService.androidPicker,
            null,
          ),
        );
        await expectLater(
          AudioStagingService().pickAudio(),
          throwsA(
            isA<AudioStagingException>().having(
              (e) => e.message,
              'size violation',
              contains('25 MB'),
            ),
          ),
        );
        expect(await file.exists(), isFalse);
      },
    );

    test(
      'PCM WAV skips data and enforces duration before native loading',
      () async {
        for (final seconds in [10, 300, 301]) {
          final dataLength = seconds * 8000;
          final bytes = Uint8List(44 + dataLength);
          final data = ByteData.sublistView(bytes);
          bytes.setAll(0, 'RIFF'.codeUnits);
          data.setUint32(4, bytes.length - 8, Endian.little);
          bytes.setAll(8, 'WAVEfmt '.codeUnits);
          data.setUint32(16, 16, Endian.little);
          data.setUint16(20, 1, Endian.little);
          data.setUint16(22, 1, Endian.little);
          data.setUint32(24, 8000, Endian.little);
          data.setUint32(28, 8000, Endian.little);
          data.setUint16(32, 1, Endian.little);
          data.setUint16(34, 8, Endian.little);
          bytes.setAll(36, 'data'.codeUnits);
          data.setUint32(40, dataLength, Endian.little);
          final file = await fixture('pcm.wav', bytes);
          if (seconds > 300) {
            await expectLater(
              stage(file),
              throwsA(isA<AudioStagingException>()),
            );
          } else {
            expect((await stage(file)).duration, Duration(seconds: seconds));
          }
        }
      },
    );

    Uint8List extensible({int subtype = 1, int seconds = 10, int bits = 16}) {
      final alignment = 2 * bits ~/ 8;
      final dataLength = seconds * 8000 * alignment;
      final bytes = Uint8List(68 + dataLength);
      final data = ByteData.sublistView(bytes);
      bytes.setAll(0, 'RIFF'.codeUnits);
      data.setUint32(4, bytes.length - 8, Endian.little);
      bytes.setAll(8, 'WAVEfmt '.codeUnits);
      data.setUint32(16, 40, Endian.little);
      data.setUint16(20, 0xfffe, Endian.little);
      data.setUint16(22, 2, Endian.little);
      data.setUint32(24, 8000, Endian.little);
      data.setUint32(28, 8000 * alignment, Endian.little);
      data.setUint16(32, alignment, Endian.little);
      data.setUint16(34, bits, Endian.little);
      data.setUint16(36, 22, Endian.little);
      data.setUint16(38, bits, Endian.little);
      data.setUint32(40, 3, Endian.little);
      data.setUint32(44, subtype, Endian.little);
      bytes.setAll(48, [0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113]);
      bytes.setAll(60, 'data'.codeUnits);
      data.setUint32(64, dataLength, Endian.little);
      return bytes;
    }

    test(
      'extensible PCM and float stage from complete headers without decoder',
      () async {
        for (final bits in [16, 24, 32]) {
          final bytes = extensible(bits: bits);
          // PCM may use fewer valid bits than its container.
          ByteData.sublistView(bytes).setUint16(38, bits - 4, Endian.little);
          expect(
            (await stage(await fixture('pcm-ext.wav', bytes))).duration,
            const Duration(seconds: 10),
          );
        }
        for (final bits in [32, 64]) {
          expect(
            (await stage(
              await fixture(
                'float-ext.wav',
                extensible(subtype: 3, bits: bits),
              ),
            )).duration,
            const Duration(seconds: 10),
          );
        }
      },
    );

    test(
      'extensible WAV rejects overlong audio by header without decoder',
      () async {
        final file = await fixture('long-ext.wav', extensible(seconds: 301));
        expect(await file.length(), lessThan(AudioStagingService.maxBytes));
        await expectLater(
          stage(file),
          throwsA(
            isA<AudioStagingException>().having(
              (e) => e.message,
              'message',
              AudioStagingService.durationLimitMessage,
            ),
          ),
        );
      },
    );

    test(
      'extensible WAV rejects incomplete extension and forged subtype GUIDs',
      () async {
        final mutations = <void Function(Uint8List)>[
          (b) => ByteData.sublistView(b).setUint32(16, 16, Endian.little),
          (b) => ByteData.sublistView(b).setUint32(16, 39, Endian.little),
          (b) => ByteData.sublistView(b).setUint16(36, 21, Endian.little),
          (b) => ByteData.sublistView(b).setUint16(36, 23, Endian.little),
          (b) => ByteData.sublistView(b).setUint16(38, 0, Endian.little),
          (b) => ByteData.sublistView(b).setUint16(38, 17, Endian.little),
          (b) => ByteData.sublistView(b).setUint32(44, 2, Endian.little),
          (b) => b[47] = 1, // All four subtype bytes must match.
          (b) => b[59] = 0, // The entire GUID suffix must match.
          (b) => ByteData.sublistView(b).setUint32(40, 1, Endian.little),
          (b) => ByteData.sublistView(b).setUint32(28, 1, Endian.little),
          (b) => ByteData.sublistView(b).setUint16(32, 1, Endian.little),
        ];
        for (var index = 0; index < mutations.length; index++) {
          final bytes = extensible();
          mutations[index](bytes);
          await expectLater(
            stage(await fixture('invalid-$index.wav', bytes)),
            throwsA(isA<AudioStagingException>()),
            reason: 'Malformed header $index',
          );
        }
        for (final bits in [16, 24]) {
          await expectLater(
            stage(
              await fixture(
                'invalid-float.wav',
                extensible(subtype: 3, bits: bits),
              ),
            ),
            throwsA(isA<AudioStagingException>()),
          );
        }
        await expectLater(
          stage(await fixture('truncated.wav', extensible().sublist(0, 59))),
          throwsA(isA<AudioStagingException>()),
        );
      },
    );

    test(
      'logout cleanup deletes stale recordings but preserves directories',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'karaok-cleanup-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final stale = await File(
          '${directory.path}/stale.wav',
        ).writeAsBytes([1]);
        final nested = await Directory('${directory.path}/nested').create();
        final service = _RecordingService(directory);
        await service.cleanupStaleRecordings();
        expect(await stale.exists(), isFalse);
        expect(await nested.exists(), isTrue);
        expect(service.current, isNull);
        await service.cleanupStaleRecordings();
      },
    );

    test('missing native file and browser recording fail politely', () async {
      await expectLater(
        stage(File('missing.aac')),
        throwsA(isA<AudioStagingException>()),
      );
      await expectLater(
        AudioStagingService().stageBrowserRecording(
          'missing.wav',
          'missing.wav',
        ),
        throwsA(isA<AudioStagingException>()),
      );
    });

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
            '${directory.path}/sample.aac',
          ).writeAsBytes([1, 2, 3]);
          final service = AudioStagingService();
          Future<StagedAudio> stage() => browser
              ? service.stageBrowserRecording(file.path, 'sample.aac')
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
    test(
      'symbolic MIDI files explain that rendered audio is required',
      () async {
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
      },
    );

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
  }, skip: kIsWeb);
}
