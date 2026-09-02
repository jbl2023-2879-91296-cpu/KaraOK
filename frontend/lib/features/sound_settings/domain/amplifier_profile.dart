const amplifierKnobNames = <String>{
  'volume',
  'bass',
  'treble',
  'sharpness',
  'flatness',
};

double _finiteNumber(Object? value, String field) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$field must be a finite number.');
  }
  return value.toDouble();
}

int? _optionalPositiveInt(Object? value, String field) {
  if (value == null) return null;
  if (value is! int || value < 1) {
    throw FormatException('$field must be a positive integer.');
  }
  return value;
}

Map<String, dynamic> _stringMap(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object.');
  return Map<String, dynamic>.from(value);
}

bool _hasExactKeys(Iterable<String> actual, Set<String> expected) {
  final keys = actual.toSet();
  return keys.length == expected.length && keys.containsAll(expected);
}

/// The physical range and increment printed on an amplifier's controls.
class AmplifierScale {
  const AmplifierScale({
    required this.minimum,
    required this.maximum,
    required this.step,
  });

  factory AmplifierScale.fromJson(Map<String, dynamic> json) {
    if (json.keys.toSet().difference(const {
      'minimum',
      'maximum',
      'step',
    }).isNotEmpty) {
      throw const FormatException('Amplifier scale has unsupported fields.');
    }
    final scale = AmplifierScale(
      minimum: _finiteNumber(json['minimum'], 'minimum'),
      maximum: _finiteNumber(json['maximum'], 'maximum'),
      step: _finiteNumber(json['step'], 'step'),
    );
    scale.validate();
    return scale;
  }

  final double minimum;
  final double maximum;
  final double step;

  void validate() {
    if (!minimum.isFinite || !maximum.isFinite || !step.isFinite) {
      throw const FormatException('Amplifier scale values must be finite.');
    }
    if (minimum >= maximum) {
      throw const FormatException(
        'Amplifier scale minimum must be less than maximum.',
      );
    }
    if (step <= 0 || step > maximum - minimum) {
      throw const FormatException(
        'Amplifier scale step must be positive and within the scale range.',
      );
    }
  }

  double validatePosition(double value, [String field = 'position']) {
    validate();
    if (!value.isFinite || value < minimum || value > maximum) {
      throw FormatException('$field must be between $minimum and $maximum.');
    }
    return value;
  }

  double normalize(double value) {
    final checked = validatePosition(value);
    return 100 * (checked - minimum) / (maximum - minimum);
  }

  double denormalize(double normalized) {
    validate();
    if (!normalized.isFinite) {
      throw const FormatException('Normalized position must be finite.');
    }
    final clamped = normalized.clamp(0, 100).toDouble();
    final raw = minimum + clamped * (maximum - minimum) / 100;
    final steps = ((raw - minimum) / step).round();
    final rounded = minimum + steps * step;
    final bounded = rounded.clamp(minimum, maximum).toDouble();
    return double.parse(bounded.toStringAsFixed(12));
  }

  Map<String, dynamic> toJson() => {
    'minimum': minimum,
    'maximum': maximum,
    'step': step,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AmplifierScale &&
          minimum == other.minimum &&
          maximum == other.maximum &&
          step == other.step;

  @override
  int get hashCode => Object.hash(minimum, maximum, step);
}

/// A complete snapshot of the five physical amplifier controls.
class KnobSettings {
  const KnobSettings({
    required this.volume,
    required this.bass,
    required this.treble,
    required this.sharpness,
    required this.flatness,
  });

  factory KnobSettings.fromJson(
    Map<String, dynamic> json, {
    AmplifierScale? scale,
  }) {
    if (!_hasExactKeys(json.keys, amplifierKnobNames)) {
      throw const FormatException(
        'Knob settings must contain exactly all five controls.',
      );
    }
    final settings = KnobSettings(
      volume: _finiteNumber(json['volume'], 'volume'),
      bass: _finiteNumber(json['bass'], 'bass'),
      treble: _finiteNumber(json['treble'], 'treble'),
      sharpness: _finiteNumber(json['sharpness'], 'sharpness'),
      flatness: _finiteNumber(json['flatness'], 'flatness'),
    );
    settings.validate(scale: scale);
    return settings;
  }

  final double volume;
  final double bass;
  final double treble;
  final double sharpness;
  final double flatness;

  Map<String, double> toJson() => {
    'volume': volume,
    'bass': bass,
    'treble': treble,
    'sharpness': sharpness,
    'flatness': flatness,
  };

  void validate({AmplifierScale? scale}) {
    for (final entry in toJson().entries) {
      if (!entry.value.isFinite) {
        throw FormatException('${entry.key} must be a finite number.');
      }
      scale?.validatePosition(entry.value, entry.key);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KnobSettings &&
          volume == other.volume &&
          bass == other.bass &&
          treble == other.treble &&
          sharpness == other.sharpness &&
          flatness == other.flatness;

  @override
  int get hashCode => Object.hash(volume, bass, treble, sharpness, flatness);
}

/// A named server-owned or device-local amplifier configuration.
class AmplifierProfile {
  const AmplifierProfile({
    this.id,
    required this.name,
    required this.scale,
    this.lastPositions,
    this.createdAt,
    this.updatedAt,
  });

  factory AmplifierProfile.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Amplifier profile name is required.');
    }
    final scale = AmplifierScale.fromJson({
      'minimum': json['scale_min'],
      'maximum': json['scale_max'],
      'step': json['scale_step'],
    });
    final rawPositions = json['last_positions'];
    final profile = AmplifierProfile(
      id: _optionalPositiveInt(json['id'], 'id'),
      name: name.trim(),
      scale: scale,
      lastPositions: rawPositions == null
          ? null
          : KnobSettings.fromJson(
              _stringMap(rawPositions, 'last_positions'),
              scale: scale,
            ),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
    profile.validate();
    return profile;
  }

  final int? id;
  final String name;
  final AmplifierScale scale;
  final KnobSettings? lastPositions;
  final String? createdAt;
  final String? updatedAt;

  void validate() {
    if (id != null && id! < 1) {
      throw const FormatException('Amplifier profile id must be positive.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('Amplifier profile name is required.');
    }
    scale.validate();
    lastPositions?.validate(scale: scale);
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      if (id != null) 'id': id,
      'name': name.trim(),
      'scale_min': scale.minimum,
      'scale_max': scale.maximum,
      'scale_step': scale.step,
      'last_positions': lastPositions?.toJson(),
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AmplifierProfile &&
          id == other.id &&
          name == other.name &&
          scale == other.scale &&
          lastPositions == other.lastPositions &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, name, scale, lastPositions, createdAt, updatedAt);
}
