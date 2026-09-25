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
  for (final outcome in ['cancel', 'denied', 'short', 'valid']) {
    testWidgets(
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
              starts++;
              path = args['path'] as String;
              File(path!).writeAsBytesSync([1, 2, 3]);
            }
            if (call.method == 'stop') return path;
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
        if (outcome == 'cancel') {
          await _tapAndWait(
            tester,
            'Cancel recording',
            () => find.text('Remove').evaluate().isNotEmpty,
          );
        } else if (outcome == 'short' || outcome == 'valid') {
          audio.duration = Duration(seconds: outcome == 'short' ? 1 : 20);
          await _tapAndWait(
            tester,
            'Stop',
            () => find.text('Remove').evaluate().isNotEmpty,
          );
        }
        expect(
          find.text(previousName),
          outcome == 'valid' ? findsNothing : findsOneWidget,
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
  }) async {
    AudioStagingService.validateDuration(audio.duration);
    await discard();
    return current = StagedAudio(
      fileName: p.basename(path),
      path: path,
      sizeBytes: 3,
      duration: audio.duration,
      format: 'WAV',
      source: source,
      temporary: temporary,
    );
  }
}
