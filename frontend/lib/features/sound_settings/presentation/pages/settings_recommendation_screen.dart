import 'package:flutter/material.dart';

import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/sound_settings/data/guest_amplifier_store.dart';
import 'package:karaok_app/features/sound_settings/data/settings_api.dart';
import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';

typedef SettingsVerificationCallback = ValueChanged<SettingsSuggestionInput>;

const _knobLabels = <String, String>{
  'volume': 'Volume',
  'bass': 'Bass',
  'treble': 'Treble',
  'sharpness': 'Sharpness',
  'flatness': 'Flatness',
};

/// Displays physical amplifier targets and coordinates optional verification.
class SettingsRecommendationScreen extends StatefulWidget {
  const SettingsRecommendationScreen({
    super.key,
    required this.recommendation,
    this.settingsApi,
    this.guestStore,
    this.onVerify,
    this.safetySignals = const {},
  });

  final SettingsRecommendation recommendation;
  final SettingsApi? settingsApi;
  final GuestAmplifierStore? guestStore;
  final SettingsVerificationCallback? onVerify;
  final Map<String, dynamic> safetySignals;

  @override
  State<SettingsRecommendationScreen> createState() =>
      _SettingsRecommendationScreenState();
}

class _SettingsRecommendationScreenState
    extends State<SettingsRecommendationScreen> {
  late final SettingsApi _settingsApi;
  late final GuestAmplifierStore _guestStore;
  late SettingsRecommendation _recommendation;
  late bool _applied;
  bool _applying = false;
  String? _applyError;

  bool get _isGuest => UserSession.instance.isGuest;

  bool get _canOfferVerification {
    if (_recommendation.status == 'unavailable' ||
        _recommendation.status == 'verified' ||
        _recommendation.status == 'reverted' ||
        _recommendation.parentRecommendationId != null) {
      return false;
    }
    if (_isGuest) return _recommendation.verificationToken != null;
    return _recommendation.id != null &&
        _recommendation.amplifierProfileId != null;
  }

  @override
  void initState() {
    super.initState();
    _settingsApi = widget.settingsApi ?? SettingsApi();
    _guestStore = widget.guestStore ?? GuestAmplifierStore.instance;
    _recommendation = widget.recommendation;
    _applied =
        _recommendation.status == 'applied' ||
        _recommendation.appliedAt != null;
  }

  KnobSettings? get _recommendedSettings {
    final values = _recommendation.recommended;
    if (values.values.any((value) => value == null)) return null;
    return KnobSettings(
      volume: values['volume']!,
      bass: values['bass']!,
      treble: values['treble']!,
      sharpness: values['sharpness']!,
      flatness: values['flatness']!,
    );
  }

  Future<void> _apply() async {
    final targets = _recommendedSettings;
    if (targets == null || _applying) return;
    setState(() {
      _applying = true;
      _applyError = null;
    });
    try {
      if (_isGuest) {
        final existing = await _guestStore.read();
        await _guestStore.save(
          AmplifierProfile(
            id: existing?.id,
            name: existing?.name ?? 'My Amplifier',
            scale: _recommendation.scale,
            lastPositions: targets,
          ),
        );
      } else {
        final id = _recommendation.id;
        if (id == null) {
          throw const FormatException(
            'Authenticated recommendation ID is missing.',
          );
        }
        _recommendation = await _settingsApi.applyRecommendation(id);
      }
      if (!mounted) return;
      setState(() => _applied = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applyError = 'Could not mark these settings as applied. Try again.';
      });
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  SettingsSuggestionInput _nextInput({required bool verification}) {
    final positions = verification
        ? _recommendedSettings!
        : _recommendation.current;
    if (_isGuest) {
      return SettingsSuggestionInput(
        genre: _recommendation.genre,
        amplifierScale: _recommendation.scale,
        currentSettings: positions,
        verificationToken: verification
            ? _recommendation.verificationToken
            : null,
      );
    }
    return SettingsSuggestionInput(
      genre: _recommendation.genre,
      amplifierProfileId: _recommendation.amplifierProfileId,
      currentSettings: positions,
      verificationOf: verification ? _recommendation.id : null,
    );
  }

  void _verify() {
    if (!_applied || !_canOfferVerification) return;
    widget.onVerify?.call(_nextInput(verification: true));
  }

  void _recordAgain() {
    widget.onVerify?.call(_nextInput(verification: false));
  }

  Future<void> _finish() async {
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final unavailable = _recommendation.status == 'unavailable';
    final verificationResult =
        _recommendation.parentRecommendationId != null ||
        _recommendation.verificationScore != null;
    final warnings = _safetyWarnings(_recommendation, widget.safetySignals);
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: Text(
          verificationResult ? 'Verification Result' : 'Generated Settings',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScoreSummary(recommendation: _recommendation),
              const SizedBox(height: 16),
              if (_recommendation.rollbackRecommended) ...[
                const _Notice(
                  icon: Icons.undo,
                  color: Color(0xFFF44336),
                  message: 'Return to your previous settings',
                ),
                const SizedBox(height: 12),
              ],
              for (final warning in warnings) ...[
                _Notice(
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFFFA726),
                  message: warning,
                ),
                const SizedBox(height: 12),
              ],
              if (unavailable) ...[
                _Notice(
                  icon: Icons.info_outline,
                  color: const Color(0xFFFFA726),
                  message: _blockerMessage(_recommendation),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _recordAgain,
                  icon: const Icon(Icons.mic),
                  label: const Text('Record Again'),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _finish, child: const Text('Finish')),
              ] else ...[
                Text(
                  'Set each physical knob yourself. KaraOK does not move your amplifier controls.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                for (final name in amplifierKnobNames) ...[
                  _AdjustmentCard(
                    knob: name,
                    label: _knobLabels[name]!,
                    adjustment: _recommendation.adjustments[name]!,
                    scale: _recommendation.scale,
                  ),
                  const SizedBox(height: 10),
                ],
                if (_applyError case final error?) ...[
                  const SizedBox(height: 4),
                  Text(error, style: const TextStyle(color: Color(0xFFF44336))),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('apply-settings'),
                  onPressed: _applied || _applying ? null : _apply,
                  icon: _applying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_applied ? Icons.check : Icons.tune),
                  label: Text(
                    _applied
                        ? 'Settings Marked as Applied'
                        : "I've Applied These Settings",
                  ),
                ),
                if (_canOfferVerification) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('verify-settings'),
                    onPressed: _applied ? _verify : null,
                    icon: const Icon(Icons.mic),
                    label: const Text('Record Again to Verify'),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _finish,
                  child: Text(
                    _canOfferVerification
                        ? 'Finish Without Verification'
                        : 'Finish',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreSummary extends StatelessWidget {
  const _ScoreSummary({required this.recommendation});

  final SettingsRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final scoreChange = recommendation.scoreChange;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quality score: ${recommendation.originalScore.toStringAsFixed(1)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_genreLabel(recommendation.genre)} profile • ${recommendation.overallConfidence} confidence',
            style: const TextStyle(color: Colors.white70),
          ),
          if (recommendation.verificationScore case final after?) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Before: ${recommendation.beforeScore.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                Text(
                  'After: ${after.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (scoreChange != null) ...[
            const SizedBox(height: 8),
            Text(
              'Score change: ${_signed(scoreChange, 1)}',
              style: TextStyle(
                color: scoreChange < 0
                    ? const Color(0xFFF44336)
                    : const Color(0xFF4CAF50),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdjustmentCard extends StatelessWidget {
  const _AdjustmentCard({
    required this.knob,
    required this.label,
    required this.adjustment,
    required this.scale,
  });

  final String knob;
  final String label;
  final KnobAdjustment adjustment;
  final AmplifierScale scale;

  @override
  Widget build(BuildContext context) {
    final delta = adjustment.delta ?? 0;
    final direction = delta > 0
        ? 'increase'
        : delta < 0
        ? 'decrease'
        : 'unchanged';
    final icon = delta > 0
        ? Icons.arrow_upward
        : delta < 0
        ? Icons.arrow_downward
        : Icons.remove;
    final recommended = adjustment.recommended;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                icon,
                key: Key('direction-$knob-$direction'),
                color: const Color(0xFFFF8C00),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_physical(adjustment.current, scale)} → ${recommended == null ? '—' : _physical(recommended, scale)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                adjustment.delta == null
                    ? '—'
                    : _signed(adjustment.delta!, _decimalPlaces(scale.step)),
                style: const TextStyle(
                  color: Color(0xFFFF8C00),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _reasonMessage(adjustment.reasonCode),
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            '${adjustment.confidence} confidence',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

List<String> _safetyWarnings(
  SettingsRecommendation recommendation,
  Map<String, dynamic> signals,
) {
  final warnings = <String>[];
  final reasons = recommendation.adjustments.values
      .map((adjustment) => adjustment.reasonCode)
      .toSet();
  if (signals['clipping'] == true ||
      reasons.contains('volume_increase_blocked_by_clipping')) {
    warnings.add('Clipping was detected, so KaraOK will not increase volume.');
  }
  if (signals['excessive_noise'] == true) {
    warnings.add(
      'Background noise is high and may reduce recommendation confidence.',
    );
  }
  if (signals['excessive_distortion'] == true) {
    warnings.add(
      'Distortion is high and may reduce recommendation confidence.',
    );
  } else if (reasons.contains('volume_increase_blocked_by_distortion')) {
    warnings.add(
      'Excessive distortion was detected, so KaraOK will not increase volume.',
    );
  }
  return warnings;
}

String _blockerMessage(SettingsRecommendation recommendation) {
  final reason = recommendation.adjustments.values.first.reasonCode;
  return switch (reason) {
    'genre_profile_unavailable' =>
      'No supported audio profile is available for this genre.',
    'silent_recording' => 'The recording is silent. Record the song again.',
    'corrupt_recording' => 'The recording could not be decoded safely.',
    'recording_too_short' =>
      'The usable recording is too short. Record a longer song section.',
    'low_confidence_measurement' =>
      'The audio measurements are not reliable enough to adjust your amplifier.',
    'missing_required_measurement' || 'non_finite_measurement' =>
      'A required audio measurement is unavailable. Record the song again.',
    'invalid_genre_profile' || 'missing_required_profile_metric' =>
      'The selected genre profile cannot generate safe settings.',
    _ => 'KaraOK could not generate safe amplifier settings.',
  };
}

String _reasonMessage(String reasonCode) => switch (reasonCode) {
  'below_genre_range' => 'This measurement is below the genre target range.',
  'above_genre_range' => 'This measurement is above the genre target range.',
  'within_genre_range' => 'This measurement is already in the target range.',
  'volume_increase_blocked_by_clipping' =>
    'Volume stays unchanged because clipping was detected.',
  'volume_increase_blocked_by_distortion' =>
    'Volume stays unchanged because distortion was detected.',
  _ => 'This target follows the measured genre profile.',
};

String _genreLabel(String value) {
  if (value == 'hip-hop') return 'Hip-Hop';
  if (value == 'r&b') return 'R&B';
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

int _decimalPlaces(double step) {
  final text = step.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
  final separator = text.indexOf('.');
  return separator == -1 ? 0 : text.length - separator - 1;
}

String _physical(double value, AmplifierScale scale) =>
    value.toStringAsFixed(_decimalPlaces(scale.step));

String _signed(double value, int digits) {
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(digits)}';
}
