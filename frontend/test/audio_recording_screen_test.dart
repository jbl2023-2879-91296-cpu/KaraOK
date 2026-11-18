import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';
import 'package:karaok_app/features/assessments/data/audio_staging_service.dart';
import 'package:path/path.dart' as p;

import 'support/audio_platform_stub.dart';

void main() {
  const checks = {
    'quiet': 'recording starts with a 3-second noise check',
    'noisy': 'noisy noise check shows the placement warning',
    'pause': 'pause is disabled during the noise check',
    'config': 'recorder config disables phone processing',
    'fractional': 'pause excludes fractional seconds from the minimum',
    'minimum': 'stop is blocked until 13 s when a noise check was recorded',
  };
  for (final outcome in [
    ...checks.keys,
    'cancel',
    'denied',
    'short',
    'valid',
    'limit',
  ]) {
    testWidgets(
      checks[outcome] ??
          'Record Again uses microphone and handles $outcome replacement',
      (tester) async {
        tester.view.physicalSize = const Size(900, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        UserSession.instance.setUser(
          id: 7,
          name: 'Test',
          email: 't@example.com',
          userType: 'user',
        );
        addTearDown(UserSession.instance.clear);
        final directory = Directory.systemTemp.createTempSync(
          'karaok-recorder-',
        );
        final originalProvider = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _Documents(directory.path);
        addTearDown(() {
          PathProviderPlatform.instance = originalProvider;
          directory.deleteSync(recursive: true);
        });
        final audio = AudioPlatformStub()..install();
        final staging = _RecordingStaging(audio);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        var granted = true;
        var starts = 0;
        var stops = 0;
        Map? config;
        String? path;
        messenger.setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => <int, int>{7: granted ? 1 : 0},
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (call) async {
            final args = call.arguments as Map;
            if (call.method == 'create') {
              messenger.setMockMethodCallHandler(
                MethodChannel(
                  'com.llfbandit.record/events/${args['recorderId']}',
                ),
                (_) async => null,
              );
            }
            if (call.method == 'start') {
              config = args;
              starts++;
              path = args['path'] as String;
              File(path!).writeAsBytesSync([1, 2, 3]);
            }
            if (call.method == 'isRecording') return true;
            if (call.method == 'getAmplitude') {
              final level = outcome == 'noisy' ? -30.0 : -60.0;
              return {'current': level, 'max': level};
            }
            if (call.method == 'stop') {
              stops++;
              return path;
            }
            return null;
          },
        );
        await tester.pumpWidget(
          MaterialApp(home: AudioTestScreen(stagingService: staging)),
        );
        await _tapAndWait(
          tester,
          'Record Audio',
          () => find.text('Cancel recording').evaluate().isNotEmpty,
        );
        if (outcome == 'quiet') {
          expect(
            find.text(
              "Stay quiet, checking background noise. Don't start the song yet.",
            ),
            findsOneWidget,
          );
          await tester.pump(const Duration(seconds: 3));
          expect(find.text('Start the song now.'), findsOneWidget);
          expect(
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Pause'),
                )
                .onPressed,
            isNotNull,
          );
        } else if (outcome == 'noisy') {
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pump(const Duration(milliseconds: 2850));
          expect(
            find.text(
              "It's noisy here. Hold the phone about 30 cm (1 ft) from the speaker, pointed at it.",
            ),
            findsOneWidget,
          );
        } else if (outcome == 'pause') {
          expect(
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Pause'),
                )
                .onPressed,
            isNull,
          );
        } else if (outcome == 'config') {
          for (final option in ['autoGain', 'echoCancel', 'noiseSuppress']) {
            expect(config![option], isFalse, reason: option);
          }
        } else if (outcome == 'fractional') {
          await tester.pump(const Duration(milliseconds: 12050));
          await tester.tap(find.text('Pause'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 880));
          await tester.tap(find.text('Resume'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          await tester.tap(find.text('Stop'));
          await tester.pump();
          expect(stops, 0);
          await tester.pump(const Duration(milliseconds: 850));
          await _tapAndWait(tester, 'Stop', () => staging.current != null);
          expect(stops, 1);
        } else if (outcome == 'minimum') {
          await tester.pump(const Duration(seconds: 12));
          await tester.tap(find.text('Stop'));
          await tester.pump();
          expect(stops, 0);
          expect(
            find.textContaining('Audio must be at least 10 seconds'),
            findsOneWidget,
          );
          await tester.pump(const Duration(seconds: 1));
          await _tapAndWait(tester, 'Stop', () => staging.current != null);
          expect(stops, 1);
          expect(staging.current!.noisePrerollSeconds, 3);
        }
        if (checks.containsKey(outcome)) {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          return;
        }
        await tester.pump(const Duration(seconds: 13));
        await _tapAndWait(
          tester,
          'Stop',
          () => find.text('Remove').evaluate().isNotEmpty,
        );
        final previousName = p.basename(path!);
        expect(find.text(previousName), findsOneWidget);
        if (outcome == 'denied') granted = false;
        await _tapAndWait(
          tester,
          'Record Again',
          () => outcome == 'denied'
              ? find
                    .text('Microphone permission is required to record audio.')
                    .evaluate()
                    .isNotEmpty
              : find.text('Cancel recording').evaluate().isNotEmpty,
        );
        expect(starts, outcome == 'denied' ? 1 : 2);
        if (outcome == 'limit') {
          audio.duration = const Duration(minutes: 5);
          await tester.pump(const Duration(minutes: 4, seconds: 59));
          expect(stops, 1);
          expect(find.text('Cancel recording'), findsOneWidget);
          await tester.pump(const Duration(seconds: 1));
          for (
            var attempt = 0;
            attempt < 100 && staging.current?.duration != audio.duration;
            attempt++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(stops, 2);
          expect(staging.current?.duration, audio.duration);
          expect(
            find.text('Recording stopped at the 5-minute limit.'),
            findsOneWidget,
          );
          await tester.pump(const Duration(seconds: 2));
          expect(stops, 2);
        } else if (outcome == 'cancel') {
          await _tapAndWait(
            tester,
            'Cancel recording',
            () => find.text('Remove').evaluate().isNotEmpty,
          );
        } else if (outcome == 'short' || outcome == 'valid') {
          await tester.pump(const Duration(seconds: 13));
          audio.duration = Duration(seconds: outcome == 'short' ? 1 : 20);
          await _tapAndWait(
            tester,
            'Stop',
            () => find.text('Remove').evaluate().isNotEmpty,
          );
        }
        expect(
          find.text(previousName),
          outcome == 'valid' || outcome == 'limit'
              ? findsNothing
              : findsOneWidget,
        );
        if (outcome == 'short') {
          expect(
            find.textContaining('Audio must be at least 10 seconds'),
            findsOneWidget,
          );
        }
        expect(find.text('Choose Another File'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}

Future<void> _tapAndWait(
  WidgetTester tester,
  String label,
  bool Function() ready,
) async {
  expect(find.text(label), findsOneWidget);
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(
    ready(),
    isTrue,
    reason:
        'Timed out after tapping $label: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(" | ")}',
  );
}

class _Documents extends PathProviderPlatform {
  _Documents(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

// Decoder metadata is controlled here; the real staging service's duration
// boundaries and file preservation are exercised in audio_staging_service_test.
class _RecordingStaging extends AudioStagingService {
  _RecordingStaging(this.audio);
  final AudioPlatformStub audio;
  @override
  Future<StagedAudio> stagePath(
    String path,
    AudioSourceType source, {
    required bool temporary,
    double noisePrerollSeconds = 0,
  }) async {
    AudioStagingService.validateDuration(
      audio.duration,
      noisePrerollSeconds: noisePrerollSeconds,
    );
    await discard();
    return current = StagedAudio(
      fileName: p.basename(path),
      path: path,
      sizeBytes: 3,
      duration: audio.duration,
      format: 'WAV',
      source: source,
      temporary: temporary,
      noisePrerollSeconds: noisePrerollSeconds,
    );
  }
}
