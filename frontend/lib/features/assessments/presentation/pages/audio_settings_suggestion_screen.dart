import 'package:flutter/material.dart';

import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/sound_settings/data/guest_amplifier_store.dart';
import 'package:karaok_app/features/sound_settings/data/settings_api.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';
import 'package:karaok_app/features/sound_settings/presentation/pages/settings_setup_screen.dart';

typedef AudioScreenBuilder = Widget Function(SettingsSuggestionInput input);

/// Orchestrates amplifier setup before opening the shared recording flow.
class AudioSettingsSuggestionScreen extends StatefulWidget {
  const AudioSettingsSuggestionScreen({
    super.key,
    this.settingsApi,
    this.guestStore,
    this.audioScreenBuilder,
  });

  final SettingsApi? settingsApi;
  final GuestAmplifierStore? guestStore;
  final AudioScreenBuilder? audioScreenBuilder;

  @override
  State<AudioSettingsSuggestionScreen> createState() =>
      _AudioSettingsSuggestionScreenState();
}

class _AudioSettingsSuggestionScreenState
    extends State<AudioSettingsSuggestionScreen> {
  bool _limitDialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkGuestLimit());
  }

  Future<void> _checkGuestLimit() async {
    if (!UserSession.instance.isGuest ||
        await GuestAssessmentService.instance.canAssess() ||
        !mounted ||
        _limitDialogVisible) {
      return;
    }
    _limitDialogVisible = true;
    final signIn = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Guest evaluation limit reached'),
        content: const Text(
          'This device has used all three guest audio evaluations. Sign in or create an account to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
    _limitDialogVisible = false;
    if (signIn == true && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _continueToRecording(SettingsSuggestionInput input) {
    final destination =
        widget.audioScreenBuilder?.call(input) ??
        AudioTestScreen(
          purpose: AudioAnalysisPurpose.settingsSuggestion,
          genre: input.genre,
          settingsSuggestion: input,
        );
    Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) => SettingsSetupScreen(
    settingsApi: widget.settingsApi,
    guestStore: widget.guestStore,
    onContinue: _continueToRecording,
  );
}
