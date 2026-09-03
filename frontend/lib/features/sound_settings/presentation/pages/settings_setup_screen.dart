import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:karaok_app/core/network/api_exception.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/sound_settings/data/guest_amplifier_store.dart';
import 'package:karaok_app/features/sound_settings/data/settings_api.dart';
import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_profile_metadata.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';

enum _ScalePreset { zeroToTen, zeroToHundred, custom }

enum _ScaleChangeChoice { keepValues, rescaleValues }

const _newProfileSelection = -1;

const _knobLabels = <String, String>{
  'volume': 'Volume',
  'bass': 'Bass',
  'treble': 'Treble',
  'sharpness': 'Sharpness',
  'flatness': 'Flatness',
};

const _genreLabels = <String, String>{
  'rock': 'Rock',
  'pop': 'Pop',
  'ballad': 'Ballad',
  'hip-hop': 'Hip-Hop',
  'classical': 'Classical',
  'r&b': 'R&B',
  'general': 'General / Other',
};

/// Collects the amplifier and controlled-recording context required by the
/// settings recommendation upload flow.
class SettingsSetupScreen extends StatefulWidget {
  const SettingsSetupScreen({
    super.key,
    required this.onContinue,
    this.settingsApi,
    this.guestStore,
  });

  final ValueChanged<SettingsSuggestionInput> onContinue;
  final SettingsApi? settingsApi;
  final GuestAmplifierStore? guestStore;

  @override
  State<SettingsSetupScreen> createState() => _SettingsSetupScreenState();
}

class _SettingsSetupScreenState extends State<SettingsSetupScreen> {
  static const _zeroToTen = AmplifierScale(minimum: 0, maximum: 10, step: 0.5);
  static const _zeroToHundred = AmplifierScale(
    minimum: 0,
    maximum: 100,
    step: 1,
  );

  late final SettingsApi _settingsApi;
  late final GuestAmplifierStore _guestStore;
  final _positionControllers = <String, TextEditingController>{
    for (final name in amplifierKnobNames) name: TextEditingController(),
  };
  final _minimumController = TextEditingController(text: '0');
  final _maximumController = TextEditingController(text: '10');
  final _stepController = TextEditingController(text: '0.5');

  bool _loading = true;
  bool _submitting = false;
  bool _featureDisabled = false;
  String? _loadError;
  String? _profilesLoadError;
  String? _genreError;
  String? _positionError;
  String? _scaleError;
  SettingsProfileMetadata? _metadata;
  List<String> _enabledGenres = const [];
  List<AmplifierProfile> _profiles = const [];
  AmplifierProfile? _selectedProfile;
  String? _genre;
  _ScalePreset _preset = _ScalePreset.zeroToTen;
  AmplifierScale _scale = _zeroToTen;

  bool get _isGuest => UserSession.instance.isGuest;

  @override
  void initState() {
    super.initState();
    _settingsApi = widget.settingsApi ?? SettingsApi();
    _guestStore = widget.guestStore ?? GuestAmplifierStore.instance;
    _load();
  }

  @override
  void dispose() {
    for (final controller in _positionControllers.values) {
      controller.dispose();
    }
    _minimumController.dispose();
    _maximumController.dispose();
    _stepController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final metadata = await _settingsApi.getProfileMetadata();

      if (_isGuest) {
        final stored = await _guestStore.read();
        if (stored != null) _useProfile(stored);
      } else {
        try {
          final profiles = await _settingsApi.listProfiles();
          _profiles = profiles;
          if (profiles.isNotEmpty) {
            _selectedProfile = profiles.first;
            _useProfile(profiles.first);
          }
        } catch (_) {
          _profilesLoadError =
              'Saved amplifier profiles could not be loaded. '
              'You can still create a new amplifier.';
        }
      }
      if (!mounted) return;
      setState(() {
        _metadata = metadata;
        _enabledGenres = metadata.enabledGenres;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (error.statusCode == 404) {
          _featureDisabled = true;
        } else {
          _loadError = 'Could not load settings profiles.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load settings profiles.';
      });
    }
  }

  Future<void> _retryLoad() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _featureDisabled = false;
      _loadError = null;
      _profilesLoadError = null;
    });
    await _load();
  }

  void _useProfile(AmplifierProfile profile) {
    _scale = profile.scale;
    _preset = _presetFor(profile.scale);
    _minimumController.text = _formatNumber(profile.scale.minimum);
    _maximumController.text = _formatNumber(profile.scale.maximum);
    _stepController.text = _formatNumber(profile.scale.step);
    final positions = profile.lastPositions?.toJson();
    if (positions != null) {
      for (final entry in positions.entries) {
        _positionControllers[entry.key]!.text = _formatNumber(entry.value);
      }
    }
  }

  _ScalePreset _presetFor(AmplifierScale scale) {
    if (scale == _zeroToTen) return _ScalePreset.zeroToTen;
    if (scale == _zeroToHundred) return _ScalePreset.zeroToHundred;
    return _ScalePreset.custom;
  }

  Future<void> _selectProfile(int? id) async {
    if (id == null) return;
    if (id == _newProfileSelection) {
      setState(() {
        _selectedProfile = null;
        _scale = _zeroToTen;
        _preset = _ScalePreset.zeroToTen;
        _minimumController.text = '0';
        _maximumController.text = '10';
        _stepController.text = '0.5';
        for (final controller in _positionControllers.values) {
          controller.clear();
        }
        _clearPositionErrors();
      });
      return;
    }
    final profile = _profiles.firstWhere((item) => item.id == id);
    if (!mounted) return;
    setState(() {
      _selectedProfile = profile;
      _clearPositionErrors();
      _useProfile(profile);
    });
  }

  Future<void> _changePreset(_ScalePreset next) async {
    if (next == _preset) return;
    final oldScale = _effectiveScaleOrNull() ?? _scale;
    final newScale = switch (next) {
      _ScalePreset.zeroToTen => _zeroToTen,
      _ScalePreset.zeroToHundred => _zeroToHundred,
      _ScalePreset.custom => oldScale,
    };
    var choice = _ScaleChangeChoice.keepValues;
    if (next != _ScalePreset.custom &&
        _positionControllers.values.any(
          (controller) => controller.text.trim().isNotEmpty,
        )) {
      final selected = await showDialog<_ScaleChangeChoice>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change amplifier scale?'),
          content: const Text(
            'Keep the entered knob numbers, or explicitly rescale them to the new range.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _ScaleChangeChoice.keepValues),
              child: const Text('Keep Values'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _ScaleChangeChoice.rescaleValues),
              child: const Text('Rescale Values'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      choice = selected;
    }

    setState(() {
      _preset = next;
      _scale = newScale;
      _minimumController.text = _formatNumber(newScale.minimum);
      _maximumController.text = _formatNumber(newScale.maximum);
      _stepController.text = _formatNumber(newScale.step);
      if (choice == _ScaleChangeChoice.rescaleValues) {
        for (final controller in _positionControllers.values) {
          final value = double.tryParse(controller.text.trim());
          if (value == null ||
              value < oldScale.minimum ||
              value > oldScale.maximum) {
            continue;
          }
          controller.text = _formatNumber(
            newScale.denormalize(oldScale.normalize(value)),
          );
        }
      }
      _clearPositionErrors();
    });
  }

  AmplifierScale? _effectiveScaleOrNull() {
    if (_preset != _ScalePreset.custom) return _scale;
    final minimum = double.tryParse(_minimumController.text.trim());
    final maximum = double.tryParse(_maximumController.text.trim());
    final step = double.tryParse(_stepController.text.trim());
    if (minimum == null || maximum == null || step == null) return null;
    final scale = AmplifierScale(
      minimum: minimum,
      maximum: maximum,
      step: step,
    );
    try {
      scale.validate();
      return scale;
    } on FormatException {
      return null;
    }
  }

  void _clearPositionErrors() {
    _positionError = null;
    _scaleError = null;
  }

  KnobSettings? _readPositions(AmplifierScale scale) {
    final values = <String, double>{};
    if (_positionControllers.values.any(
      (controller) => controller.text.trim().isEmpty,
    )) {
      _positionError = 'Enter all five current knob positions.';
      return null;
    }
    for (final entry in _positionControllers.entries) {
      final value = double.tryParse(entry.value.text.trim());
      if (value == null ||
          !value.isFinite ||
          value < scale.minimum ||
          value > scale.maximum) {
        _positionError =
            'Use positions between ${_formatNumber(scale.minimum)} and ${_formatNumber(scale.maximum)}.';
        return null;
      }
      final steps = (value - scale.minimum) / scale.step;
      if ((steps - steps.round()).abs() > 1e-7) {
        _positionError =
            'Use increments of ${_formatNumber(scale.step)} for every position.';
        return null;
      }
      values[entry.key] = value;
    }
    return KnobSettings(
      volume: values['volume']!,
      bass: values['bass']!,
      treble: values['treble']!,
      sharpness: values['sharpness']!,
      flatness: values['flatness']!,
    );
  }

  Future<void> _continue() async {
    final scale = _effectiveScaleOrNull();
    _genreError = _genre == null ? 'Select a genre.' : null;
    _scaleError = scale == null ? 'Enter a valid amplifier scale.' : null;
    _positionError = null;
    final positions = scale == null ? null : _readPositions(scale);
    setState(() {});
    if (_genreError != null ||
        _scaleError != null ||
        positions == null ||
        scale == null) {
      return;
    }

    setState(() => _submitting = true);
    try {
      final profile = AmplifierProfile(
        id: _selectedProfile?.id,
        name: _selectedProfile?.name ?? 'My Amplifier',
        scale: scale,
        lastPositions: positions,
      );
      late final SettingsSuggestionInput input;
      if (_isGuest) {
        await _guestStore.save(profile);
        input = SettingsSuggestionInput(
          genre: _genre!,
          amplifierScale: scale,
          currentSettings: positions,
        );
      } else {
        final saved = _selectedProfile == null
            ? await _settingsApi.createProfile(profile)
            : await _settingsApi.updateProfile(_selectedProfile!.id!, profile);
        input = SettingsSuggestionInput(
          genre: _genre!,
          amplifierProfileId: saved.id,
          currentSettings: positions,
        );
      }
      if (!mounted) return;
      widget.onContinue(input);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _positionError = 'Could not save the amplifier setup. Try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canContinue =
        !_loading &&
        !_featureDisabled &&
        _loadError == null &&
        _metadata != null &&
        !_submitting;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: const Text('Set Up Your Amplifier'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_featureDisabled)
                      const _Notice(
                        icon: Icons.block,
                        message: 'Settings generation is not enabled',
                      ),
                    if (_loadError case final error?) ...[
                      _Notice(icon: Icons.cloud_off, message: error),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          key: const Key('settings-load-retry'),
                          onPressed: _retryLoad,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_profilesLoadError case final error?)
                      _Notice(icon: Icons.cloud_off, message: error),
                    Text(
                      'Tell KaraOK how your physical controls are set now.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('1. Amplifier'),
                    if (!_isGuest && _profiles.isNotEmpty)
                      DropdownButtonFormField<int>(
                        key: const Key('amplifier-profile-dropdown'),
                        isExpanded: true,
                        initialValue:
                            _selectedProfile?.id ?? _newProfileSelection,
                        dropdownColor: const Color(0xFF242424),
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration('Saved amplifier'),
                        items: [
                          const DropdownMenuItem(
                            value: _newProfileSelection,
                            child: Text('Create My Amplifier'),
                          ),
                          for (final profile in _profiles)
                            DropdownMenuItem(
                              value: profile.id,
                              child: Text(profile.name),
                            ),
                        ],
                        onChanged: _submitting ? null : _selectProfile,
                      )
                    else
                      Text(
                        _isGuest
                            ? 'Saved on this device as My Amplifier.'
                            : 'A profile named My Amplifier will be created.',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<_ScalePreset>(
                      key: const Key('scale-preset-dropdown'),
                      isExpanded: true,
                      initialValue: _preset,
                      dropdownColor: const Color(0xFF242424),
                      style: const TextStyle(color: Colors.white),
                      decoration: _decoration('Control scale'),
                      items: const [
                        DropdownMenuItem(
                          value: _ScalePreset.zeroToTen,
                          child: Text('0–10'),
                        ),
                        DropdownMenuItem(
                          value: _ScalePreset.zeroToHundred,
                          child: Text('0–100'),
                        ),
                        DropdownMenuItem(
                          value: _ScalePreset.custom,
                          child: Text('Custom'),
                        ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) {
                              if (value != null) _changePreset(value);
                            },
                    ),
                    if (_preset == _ScalePreset.custom) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _customScaleField(
                              key: const Key('scale-minimum'),
                              label: 'Minimum',
                              controller: _minimumController,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _customScaleField(
                              key: const Key('scale-maximum'),
                              label: 'Maximum',
                              controller: _maximumController,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _customScaleField(
                              key: const Key('scale-step'),
                              label: 'Increment',
                              controller: _stepController,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_scaleError case final error?) _errorText(error),
                    const SizedBox(height: 24),
                    _sectionTitle('2. Genre'),
                    DropdownButtonFormField<String>(
                      key: const Key('genre-dropdown'),
                      isExpanded: true,
                      initialValue: _genre,
                      dropdownColor: const Color(0xFF242424),
                      style: const TextStyle(color: Colors.white),
                      decoration: _decoration('Song genre'),
                      items: [
                        for (final genre in _enabledGenres)
                          DropdownMenuItem(
                            value: genre,
                            child: Text(_genreLabel(genre)),
                          ),
                      ],
                      onChanged: canContinue
                          ? (value) => setState(() {
                              _genre = value;
                              _genreError = null;
                            })
                          : null,
                    ),
                    if (_genreError case final error?) _errorText(error),
                    const SizedBox(height: 24),
                    _sectionTitle('3. Current knob positions'),
                    Text(
                      'Enter every current position before recording.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white60),
                    ),
                    const SizedBox(height: 12),
                    for (final name in amplifierKnobNames) _knobControl(name),
                    if (_positionError case final error?) _errorText(error),
                    const SizedBox(height: 20),
                    _sectionTitle('4. Keep the comparison controlled'),
                    const _GuidanceItem(
                      text: 'Use the same song section for both recordings.',
                    ),
                    const _GuidanceItem(
                      text:
                          'Record in the same room with similar background noise.',
                    ),
                    const _GuidanceItem(
                      text:
                          'Keep the same phone position and microphone direction.',
                    ),
                    const _GuidanceItem(
                      text: 'Keep the same playback level and singer distance.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const Key('settings-continue'),
                      onPressed: canContinue ? _continue : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C00),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mic),
                      label: const Text('Continue to Recording'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _customScaleField({
    required Key key,
    required String label,
    required TextEditingController controller,
  }) => TextFormField(
    key: key,
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    style: const TextStyle(color: Colors.white),
    decoration: _decoration(label),
    onChanged: (_) => setState(() {
      _scaleError = null;
      final scale = _effectiveScaleOrNull();
      if (scale != null) _scale = scale;
    }),
  );

  Widget _knobControl(String name) {
    final scale = _effectiveScaleOrNull() ?? _scale;
    final controller = _positionControllers[name]!;
    final parsed = double.tryParse(controller.text.trim());
    final sliderValue = (parsed ?? scale.minimum)
        .clamp(scale.minimum, scale.maximum)
        .toDouble();
    final rawDivisions = ((scale.maximum - scale.minimum) / scale.step).round();
    final divisions = math.max(1, math.min(rawDivisions, 1000));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _knobLabels[name]!,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: sliderValue,
                  min: scale.minimum,
                  max: scale.maximum,
                  divisions: divisions,
                  activeColor: const Color(0xFFFF8C00),
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() {
                          controller.text = _formatNumber(value);
                          _positionError = null;
                        }),
                ),
              ),
              SizedBox(
                width: 92,
                child: TextFormField(
                  key: Key('knob-$name'),
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration('Position'),
                  onChanged: (_) => setState(() => _positionError = null),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFFFF8C00),
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white60),
    filled: true,
    fillColor: const Color(0xFF1C1C1C),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.white24),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFFF8C00)),
    ),
  );

  Widget _errorText(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: const TextStyle(color: Colors.redAccent)),
  );

  String _genreLabel(String key) {
    final known = _genreLabels[key];
    if (known != null) return known;
    if (key.isEmpty) return key;
    return '${key[0].toUpperCase()}${key.substring(1)}';
  }

  String _formatNumber(double value) {
    if ((value - value.round()).abs() < 1e-9) return value.round().toString();
    return value
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.orange.withValues(alpha: 0.45)),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.orange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class _GuidanceItem extends StatelessWidget {
  const _GuidanceItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.check_circle_outline,
            color: Color(0xFFFF8C00),
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );
}
