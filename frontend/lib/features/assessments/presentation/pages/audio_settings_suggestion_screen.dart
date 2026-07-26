import 'package:flutter/material.dart';

import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';

/// Settings-suggestion destination with its own purpose and shared audio input.
class AudioSettingsSuggestionScreen extends StatelessWidget {
  const AudioSettingsSuggestionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AudioTestScreen(
      purpose: AudioAnalysisPurpose.settingsSuggestion,
    );
  }
}
