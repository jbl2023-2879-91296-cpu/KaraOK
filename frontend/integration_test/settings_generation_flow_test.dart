import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/assessments/data/assessment_api.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/sound_settings/data/settings_api.dart';
import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';
import 'package:karaok_app/features/sound_settings/presentation/pages/settings_recommendation_screen.dart';
import 'package:karaok_app/features/sound_settings/presentation/pages/settings_setup_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'generates, persists, reloads, and renders five amplifier targets',
    (tester) async {
      final authApi = AuthApi();
      final settingsApi = SettingsApi();
      final assessmentApi = AssessmentApi();
      File? recording;

      await authApi.clearTokens();
      UserSession.instance.clear();
      addTearDown(() async {
        final temporaryRecording = recording;
        if (temporaryRecording != null && await temporaryRecording.exists()) {
          await temporaryRecording.delete();
        }
        await authApi.clearTokens();
        UserSession.instance.clear();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.binding.setSurfaceSize(const Size(900, 1800));

      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final uniquePart = suffix.substring(suffix.length - 12);
      final email = 'settings-e2e-$uniquePart@example.test';
      final registration = await authApi.startRegistration(
        username: 'e2e_$uniquePart',
        firstName: 'Settings',
        lastName: 'Integration',
        email: email,
        password: 'Aa1!bcde',
        address: '1 Integration Lane',
        city: 'Manila',
        stateProvince: 'Metro Manila',
        areaCode: '1000',
        country: 'Philippines',
        countryCode: 'PH',
        phoneNumber: '+639$uniquePart',
        birthday: '1995-01-15',
      );
      final developmentCode = registration['development_code'];
      expect(
        developmentCode,
        isA<String>(),
        reason:
            'The isolated backend must expose the registration OTP in development mode.',
      );
      final user = await authApi.verifyRegistration(
        email: email,
        code: developmentCode as String,
      );
      UserSession.instance.setUserFromMap(user);

      final metadata = await settingsApi.getProfileMetadata();
      final enabledGenres = List<String>.from(
        metadata['enabled_genres'] as List,
      );
      expect(enabledGenres, isNotEmpty);
      final genre = enabledGenres.contains('rock')
          ? 'rock'
          : enabledGenres.first;

      const scale = AmplifierScale(minimum: 0, maximum: 10, step: 0.5);
      const initialPositions = KnobSettings(
        volume: 4,
        bass: 4.5,
        treble: 5,
        sharpness: 5.5,
        flatness: 6,
      );
      final profile = await settingsApi.createProfile(
        AmplifierProfile(
          name: 'Integration Amplifier $uniquePart',
          scale: scale,
          lastPositions: initialPositions,
        ),
      );
      expect(profile.id, isNotNull);

      SettingsSuggestionInput? capturedInput;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsSetupScreen(
            settingsApi: settingsApi,
            onContinue: (input) => capturedInput = input,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final genreDropdown = find.byKey(const Key('genre-dropdown'));
      await tester.ensureVisible(genreDropdown);
      await tester.tap(genreDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_genreLabel(genre), skipOffstage: false).last);
      await tester.pumpAndSettle();

      for (final entry in initialPositions.toJson().entries) {
        final field = find.byKey(Key('knob-${entry.key}'));
        await tester.ensureVisible(field);
        await tester.enterText(field, _physical(entry.value, scale));
      }
      final continueButton = find.byKey(const Key('settings-continue'));
      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      final suggestionInput =
          capturedInput ??
          (throw StateError('The setup screen did not emit its input.'));
      expect(suggestionInput.genre, genre);
      expect(suggestionInput.amplifierProfileId, profile.id);
      expect(suggestionInput.currentSettings, initialPositions);

      recording = await _writeDeterministicWav(uniquePart);
      final upload = await assessmentApi.submitAudio(
        filePath: recording.path,
        fileName: recording.uri.pathSegments.last,
        durationSeconds: 4,
        genre: suggestionInput.genre,
        analysisPurpose: 'settings_suggestion',
        guest: false,
        settingsSuggestion: suggestionInput,
      );
      final rawRecommendation = Map<String, dynamic>.from(
        upload['settings_recommendation'] as Map,
      );
      final generated = SettingsRecommendation.fromJson(rawRecommendation);
      expect(generated.id, isNotNull);
      expect(generated.persisted, isTrue);
      expect(generated.adjustments.keys.toSet(), amplifierKnobNames);
      expect(generated.recommended.length, 5);
      expect(generated.recommended.values, everyElement(isNotNull));

      final assessmentId = upload['assessment_id'];
      expect(assessmentId, isA<int>());
      final storedAssessment = await assessmentApi.getAudioTest(
        assessmentId as int,
      );
      final stored = SettingsRecommendation.fromJson(
        Map<String, dynamic>.from(
          storedAssessment['settings_recommendation'] as Map,
        ),
      );
      expect(stored.id, generated.id);
      expect(stored.persisted, isTrue);
      expect(stored.adjustments.keys.toSet(), amplifierKnobNames);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsRecommendationScreen(
            recommendation: stored,
            settingsApi: settingsApi,
          ),
        ),
      );
      await tester.pumpAndSettle();

      const labels = {
        'volume': 'Volume',
        'bass': 'Bass',
        'treble': 'Treble',
        'sharpness': 'Sharpness',
        'flatness': 'Flatness',
      };
      for (final knob in amplifierKnobNames) {
        expect(find.text(labels[knob]!), findsOneWidget);
        final adjustment = stored.adjustments[knob]!;
        final expectedValues =
            '${_physical(adjustment.current, stored.scale)} → '
            '${_physical(adjustment.recommended!, stored.scale)}';
        expect(find.text(expectedValues), findsWidgets);
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<File> _writeDeterministicWav(String suffix) async {
  const sampleRate = 44100;
  const durationSeconds = 4;
  const channelCount = 1;
  const bitsPerSample = 16;
  const sampleCount = sampleRate * durationSeconds;
  const bytesPerSample = bitsPerSample ~/ 8;
  const dataLength = sampleCount * channelCount * bytesPerSample;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);

  _writeAscii(bytes, 0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  _writeAscii(bytes, 8, 'WAVE');
  _writeAscii(bytes, 12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channelCount, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channelCount * bytesPerSample, Endian.little);
  data.setUint16(32, channelCount * bytesPerSample, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  _writeAscii(bytes, 36, 'data');
  data.setUint32(40, dataLength, Endian.little);

  for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
    final time = sampleIndex / sampleRate;
    final sample =
        0.32 * math.sin(2 * math.pi * 220 * time) +
        0.18 * math.sin(2 * math.pi * 880 * time) +
        0.08 * math.sin(2 * math.pi * 3520 * time);
    final pcm = (sample.clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(44 + sampleIndex * bytesPerSample, pcm, Endian.little);
  }

  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'karaok-settings-e2e-$suffix.wav';
  return File(path)..writeAsBytesSync(bytes, flush: true);
}

void _writeAscii(Uint8List bytes, int offset, String value) {
  for (var index = 0; index < value.length; index++) {
    bytes[offset + index] = value.codeUnitAt(index);
  }
}

String _genreLabel(String genre) => switch (genre) {
  'hip-hop' => 'Hip-Hop',
  'r&b' => 'R&B',
  'general' => 'General / Other',
  _ => '${genre[0].toUpperCase()}${genre.substring(1)}',
};

String _physical(double value, AmplifierScale scale) {
  final step = scale.step.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
  final separator = step.indexOf('.');
  final decimals = separator == -1 ? 0 : step.length - separator - 1;
  return value.toStringAsFixed(decimals);
}
