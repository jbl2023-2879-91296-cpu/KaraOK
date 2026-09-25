import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stubs only native decoding; staging and duration validation stay real.
class AudioPlatformStub {
  Duration duration = const Duration(seconds: 20);

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (call) async {
        if (call.method == 'init') {
          final id = (call.arguments as Map)['id'];
          for (final kind in ['events', 'data']) {
            messenger.setMockMethodCallHandler(
              MethodChannel('com.ryanheise.just_audio.$kind.$id'),
              (_) async => null,
            );
          }
          messenger.setMockMethodCallHandler(
            MethodChannel('com.ryanheise.just_audio.methods.$id'),
            (call) async {
              if (call.method == 'load') {
                messenger.handlePlatformMessage(
                  'com.ryanheise.just_audio.events.$id',
                  const StandardMethodCodec().encodeSuccessEnvelope({
                    'processingState': 3,
                    'updateTime': DateTime.now().millisecondsSinceEpoch,
                    'updatePosition': 0,
                    'bufferedPosition': duration.inMicroseconds,
                    'duration': duration.inMicroseconds,
                    'currentIndex': 0,
                  }),
                  (_) {},
                );
                await Future<void>.delayed(const Duration(milliseconds: 1));
                return {'duration': duration.inMicroseconds};
              }
              return <String, dynamic>{};
            },
          );
        }
        return <String, dynamic>{};
      },
    );
  }
}
