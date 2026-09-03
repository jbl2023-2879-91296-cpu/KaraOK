import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
}

String _checksum(Object? value, String field) {
  final checksum = _requiredString(value, field);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
    throw FormatException('$field must be a lowercase SHA-256 value.');
  }
  return checksum;
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object.');
  return Map<String, dynamic>.from(value);
}

bool _hasExactKeys(Map<String, dynamic> json, Set<String> expected) {
  final actual = json.keys.toSet();
  return actual.length == expected.length && actual.containsAll(expected);
}

class ControlPriors {
  const ControlPriors({
    required this.priorVersion,
    required this.artifactChecksum,
    required this.positions,
    required this.requiresPhysicalConfirmation,
  });

  factory ControlPriors.fromJson(Map<String, dynamic> json) {
    if (!_hasExactKeys(json, const {
      'prior_version',
      'artifact_checksum',
      'normalized_scale',
      'positions',
      'requires_physical_confirmation',
    })) {
      throw const FormatException('Control-prior fields do not match schema.');
    }
    final scale = _object(json['normalized_scale'], 'normalized_scale');
    if (!_hasExactKeys(scale, const {'minimum', 'maximum'}) ||
        (scale['minimum'] != 0 && scale['minimum'] != 0.0) ||
        (scale['maximum'] != 100 && scale['maximum'] != 100.0)) {
      throw const FormatException('Control priors must use a 0-100 scale.');
    }
    if (json['requires_physical_confirmation'] is! bool ||
        json['requires_physical_confirmation'] != true) {
      throw const FormatException('Control priors must require confirmation.');
    }
    final positions = KnobSettings.fromJson(
      _object(json['positions'], 'positions'),
      scale: const AmplifierScale(minimum: 0, maximum: 100, step: 1),
    );
    return ControlPriors(
      priorVersion: _requiredString(json['prior_version'], 'prior_version'),
      artifactChecksum: _checksum(
        json['artifact_checksum'],
        'artifact_checksum',
      ),
      positions: positions,
      requiresPhysicalConfirmation: true,
    );
  }

  final String priorVersion;
  final String artifactChecksum;
  final KnobSettings positions;
  final bool requiresPhysicalConfirmation;

  KnobSettings toScale(AmplifierScale scale) => KnobSettings(
    volume: scale.denormalize(positions.volume),
    bass: scale.denormalize(positions.bass),
    treble: scale.denormalize(positions.treble),
    sharpness: scale.denormalize(positions.sharpness),
    flatness: scale.denormalize(positions.flatness),
  );
}

class SettingsProfileMetadata {
  const SettingsProfileMetadata({
    required this.profileVersion,
    required this.profileChecksum,
    required this.qualityProfileVersion,
    required this.qualityProfileChecksum,
    required this.enabledGenres,
    required this.controlPriors,
  });

  factory SettingsProfileMetadata.fromJson(Map<String, dynamic> json) {
    if (!_hasExactKeys(json, const {
      'profile_version',
      'profile_checksum',
      'quality_profile_version',
      'quality_profile_checksum',
      'enabled_genres',
      'control_priors',
    })) {
      throw const FormatException(
        'Settings metadata fields do not match schema.',
      );
    }
    final rawGenres = json['enabled_genres'];
    if (rawGenres is! List || rawGenres.any((value) => value is! String)) {
      throw const FormatException('enabled_genres must be a string list.');
    }
    final genres = rawGenres
        .cast<String>()
        .map((value) => value.trim())
        .toList();
    if (genres.isEmpty ||
        genres.any((value) => value.isEmpty) ||
        genres.toSet().length != genres.length) {
      throw const FormatException(
        'enabled_genres must be non-empty and unique.',
      );
    }
    return SettingsProfileMetadata(
      profileVersion: _requiredString(
        json['profile_version'],
        'profile_version',
      ),
      profileChecksum: _checksum(json['profile_checksum'], 'profile_checksum'),
      qualityProfileVersion: _requiredString(
        json['quality_profile_version'],
        'quality_profile_version',
      ),
      qualityProfileChecksum: _checksum(
        json['quality_profile_checksum'],
        'quality_profile_checksum',
      ),
      enabledGenres: List.unmodifiable(genres),
      controlPriors: ControlPriors.fromJson(
        _object(json['control_priors'], 'control_priors'),
      ),
    );
  }

  final String profileVersion;
  final String profileChecksum;
  final String qualityProfileVersion;
  final String qualityProfileChecksum;
  final List<String> enabledGenres;
  final ControlPriors controlPriors;
}
