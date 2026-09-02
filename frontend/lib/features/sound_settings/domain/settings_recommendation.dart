import 'dart:convert';

import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';

const _confidenceLevels = {'high', 'medium', 'low', 'unavailable'};

double _number(Object? value, String field) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$field must be a finite number.');
  }
  return value.toDouble();
}

double? _nullableNumber(Object? value, String field) =>
    value == null ? null : _number(value, field);

int? _nullablePositiveInt(Object? value, String field) {
  if (value == null) return null;
  if (value is! int || value < 1) {
    throw FormatException('$field must be a positive integer.');
  }
  return value;
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object.');
  return Map<String, dynamic>.from(value);
}

bool _hasAllKnobs(Iterable<String> keys) {
  final actual = keys.toSet();
  return actual.length == amplifierKnobNames.length &&
      actual.containsAll(amplifierKnobNames);
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
}

String _normalizeGenre(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('_', ' ');
  if (normalized.isEmpty) throw ArgumentError.value(value, 'genre');
  final compact = normalized.replaceAll(RegExp(r'[\s-]+'), '');
  return switch (compact) {
    'hiphop' => 'hip-hop',
    'classic' || 'classical' => 'classical',
    'r&b' || 'rnb' || 'soulrnb' => 'r&b',
    'other' || 'general' || 'general/other' => 'general',
    _ => normalized.replaceAll(RegExp(r'\s+'), '-'),
  };
}

/// Fields that accompany an audio upload requesting amplifier suggestions.
class SettingsSuggestionInput {
  factory SettingsSuggestionInput({
    required String genre,
    required KnobSettings currentSettings,
    AmplifierScale? amplifierScale,
    int? amplifierProfileId,
    int? verificationOf,
    String? verificationToken,
  }) {
    if ((amplifierScale == null) == (amplifierProfileId == null)) {
      throw ArgumentError(
        'Provide exactly one of amplifierScale or amplifierProfileId.',
      );
    }
    if (amplifierProfileId != null && amplifierProfileId < 1) {
      throw ArgumentError.value(
        amplifierProfileId,
        'amplifierProfileId',
        'Must be positive.',
      );
    }
    if (verificationOf != null && verificationOf < 1) {
      throw ArgumentError.value(
        verificationOf,
        'verificationOf',
        'Must be positive.',
      );
    }
    final token = verificationToken?.trim();
    if (verificationOf != null && token != null && token.isNotEmpty) {
      throw ArgumentError(
        'verificationOf and verificationToken are mutually exclusive.',
      );
    }
    if (amplifierScale != null && verificationOf != null) {
      throw ArgumentError('Guest verification must use verificationToken.');
    }
    if (amplifierProfileId != null && token != null && token.isNotEmpty) {
      throw ArgumentError(
        'Authenticated verification must use verificationOf.',
      );
    }
    if (verificationToken != null && (token == null || token.isEmpty)) {
      throw ArgumentError.value(
        verificationToken,
        'verificationToken',
        'Must be non-empty.',
      );
    }
    amplifierScale?.validate();
    currentSettings.validate(scale: amplifierScale);
    return SettingsSuggestionInput._(
      genre: _normalizeGenre(genre),
      currentSettings: currentSettings,
      amplifierScale: amplifierScale,
      amplifierProfileId: amplifierProfileId,
      verificationOf: verificationOf,
      verificationToken: token,
    );
  }

  const SettingsSuggestionInput._({
    required this.genre,
    required this.currentSettings,
    this.amplifierScale,
    this.amplifierProfileId,
    this.verificationOf,
    this.verificationToken,
  });

  final String genre;
  final KnobSettings currentSettings;
  KnobSettings get current => currentSettings;
  final AmplifierScale? amplifierScale;
  final int? amplifierProfileId;
  final int? verificationOf;
  final String? verificationToken;

  Map<String, String> toMultipartFields() => {
    'genre': genre,
    if (amplifierScale != null)
      'amplifier_scale': jsonEncode(amplifierScale!.toJson()),
    if (amplifierProfileId != null)
      'amplifier_profile_id': amplifierProfileId.toString(),
    'current_settings': jsonEncode(currentSettings.toJson()),
    if (verificationOf != null) 'verification_of': verificationOf.toString(),
    'verification_token': ?verificationToken,
  };
}

class KnobAdjustment {
  const KnobAdjustment({
    required this.current,
    required this.recommended,
    required this.delta,
    required this.deltaNormalized,
    required this.reasonCode,
    required this.confidence,
  });

  factory KnobAdjustment.fromJson(
    Map<String, dynamic> json, {
    required AmplifierScale scale,
    required String knob,
  }) {
    final current = _number(json['current'], '$knob.current');
    final recommended = _nullableNumber(
      json['recommended'],
      '$knob.recommended',
    );
    scale.validatePosition(current, '$knob.current');
    if (recommended != null) {
      scale.validatePosition(recommended, '$knob.recommended');
    }
    final confidence = _requiredString(json['confidence'], '$knob.confidence');
    if (!_confidenceLevels.contains(confidence)) {
      throw FormatException('Unsupported confidence: $confidence.');
    }
    return KnobAdjustment(
      current: current,
      recommended: recommended,
      delta: _nullableNumber(json['delta'], '$knob.delta'),
      deltaNormalized: _nullableNumber(
        json['delta_normalized'],
        '$knob.delta_normalized',
      ),
      reasonCode: _requiredString(json['reason_code'], '$knob.reason_code'),
      confidence: confidence,
    );
  }

  final double current;
  final double? recommended;
  final double? delta;
  final double? deltaNormalized;
  final String reasonCode;
  final String confidence;

  Map<String, dynamic> toJson() => {
    'current': current,
    'recommended': recommended,
    'delta': delta,
    'delta_normalized': deltaNormalized,
    'reason_code': reasonCode,
    'confidence': confidence,
  };
}

class SettingsRecommendation {
  SettingsRecommendation._({
    required this.id,
    required this.persisted,
    required this.assessmentId,
    required this.amplifierProfileId,
    required this.parentRecommendationId,
    required this.status,
    required this.genre,
    required this.profileVersion,
    required this.algorithmVersion,
    required this.overallConfidence,
    required this.scale,
    required this.current,
    required Map<String, double?> recommended,
    required Map<String, KnobAdjustment> adjustments,
    required this.originalScore,
    required this.verificationScore,
    required this.beforeScore,
    required this.afterScore,
    required this.scoreChange,
    required this.verificationStatus,
    required this.rollbackRecommended,
    required this.verificationToken,
    required this.createdAt,
    required this.appliedAt,
  }) : recommended = Map.unmodifiable(recommended),
       adjustments = Map.unmodifiable(adjustments);

  factory SettingsRecommendation.fromJson(Map<String, dynamic> json) {
    final scale = AmplifierScale.fromJson(_object(json['scale'], 'scale'));
    final current = KnobSettings.fromJson(
      _object(json['current'], 'current'),
      scale: scale,
    );
    final rawRecommended = _object(json['recommended'], 'recommended');
    final rawAdjustments = _object(json['adjustments'], 'adjustments');
    if (!_hasAllKnobs(rawRecommended.keys) ||
        !_hasAllKnobs(rawAdjustments.keys)) {
      throw const FormatException(
        'Recommendation must contain exactly all five controls.',
      );
    }
    final recommended = <String, double?>{};
    final adjustments = <String, KnobAdjustment>{};
    final currentValues = current.toJson();
    for (final knob in amplifierKnobNames) {
      recommended[knob] = _nullableNumber(
        rawRecommended[knob],
        'recommended.$knob',
      );
      if (recommended[knob] case final value?) {
        scale.validatePosition(value, 'recommended.$knob');
      }
      adjustments[knob] = KnobAdjustment.fromJson(
        _object(rawAdjustments[knob], 'adjustments.$knob'),
        scale: scale,
        knob: knob,
      );
      if (adjustments[knob]!.current != currentValues[knob]) {
        throw FormatException('Current $knob values do not match.');
      }
      if (adjustments[knob]!.recommended != recommended[knob]) {
        throw FormatException('Recommended $knob values do not match.');
      }
    }

    final status = _requiredString(json['status'], 'status');
    if (status != 'generated' &&
        status != 'unavailable' &&
        status != 'applied' &&
        status != 'verified' &&
        status != 'reverted') {
      throw FormatException('Unsupported recommendation status: $status.');
    }
    final confidence = _requiredString(
      json['overall_confidence'],
      'overall_confidence',
    );
    if (!_confidenceLevels.contains(confidence)) {
      throw FormatException('Unsupported confidence: $confidence.');
    }
    final persisted = json['persisted'];
    final rollback = json['rollback_recommended'];
    if (persisted is! bool || rollback is! bool) {
      throw const FormatException(
        'Recommendation boolean fields are malformed.',
      );
    }
    final token = json['verification_token'];
    if (token != null && token is! String) {
      throw const FormatException('verification_token must be a string.');
    }

    return SettingsRecommendation._(
      id: _nullablePositiveInt(json['id'], 'id'),
      persisted: persisted,
      assessmentId: _nullablePositiveInt(
        json['assessment_id'],
        'assessment_id',
      ),
      amplifierProfileId: _nullablePositiveInt(
        json['amplifier_profile_id'],
        'amplifier_profile_id',
      ),
      parentRecommendationId: _nullablePositiveInt(
        json['parent_recommendation_id'],
        'parent_recommendation_id',
      ),
      status: status,
      genre: _requiredString(json['genre'], 'genre'),
      profileVersion: _requiredString(
        json['profile_version'],
        'profile_version',
      ),
      algorithmVersion: _requiredString(
        json['algorithm_version'],
        'algorithm_version',
      ),
      overallConfidence: confidence,
      scale: scale,
      current: current,
      recommended: recommended,
      adjustments: adjustments,
      originalScore: _number(json['original_score'], 'original_score'),
      verificationScore: _nullableNumber(
        json['verification_score'],
        'verification_score',
      ),
      beforeScore: _number(json['before_score'], 'before_score'),
      afterScore: _nullableNumber(json['after_score'], 'after_score'),
      scoreChange: _nullableNumber(json['score_change'], 'score_change'),
      verificationStatus: _requiredString(
        json['verification_status'],
        'verification_status',
      ),
      rollbackRecommended: rollback,
      verificationToken: token as String?,
      createdAt: json['created_at']?.toString(),
      appliedAt: json['applied_at']?.toString(),
    );
  }

  final int? id;
  final bool persisted;
  final int? assessmentId;
  final int? amplifierProfileId;
  final int? parentRecommendationId;
  final String status;
  final String genre;
  final String profileVersion;
  final String algorithmVersion;
  final String overallConfidence;
  final AmplifierScale scale;
  final KnobSettings current;
  final Map<String, double?> recommended;
  final Map<String, KnobAdjustment> adjustments;
  final double originalScore;
  final double? verificationScore;
  final double beforeScore;
  final double? afterScore;
  final double? scoreChange;
  final String verificationStatus;
  final bool rollbackRecommended;
  final String? verificationToken;
  final String? createdAt;
  final String? appliedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'persisted': persisted,
    'assessment_id': assessmentId,
    'amplifier_profile_id': amplifierProfileId,
    'parent_recommendation_id': parentRecommendationId,
    'status': status,
    'genre': genre,
    'profile_version': profileVersion,
    'algorithm_version': algorithmVersion,
    'overall_confidence': overallConfidence,
    'scale': scale.toJson(),
    'current': current.toJson(),
    'recommended': recommended,
    'adjustments': {
      for (final entry in adjustments.entries) entry.key: entry.value.toJson(),
    },
    'original_score': originalScore,
    'verification_score': verificationScore,
    'before_score': beforeScore,
    'after_score': afterScore,
    'score_change': scoreChange,
    'verification_status': verificationStatus,
    'rollback_recommended': rollbackRecommended,
    'verification_token': verificationToken,
    if (createdAt != null) 'created_at': createdAt,
    if (appliedAt != null) 'applied_at': appliedAt,
  };
}
