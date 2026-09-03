import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_profile_metadata.dart';

void main() {
  Map<String, dynamic> validJson() => Map<String, dynamic>.from(
    jsonDecode(
          File(
            'test/fixtures/settings_profile_metadata_response.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  );

  test('profile metadata parses all artifact provenance and five priors', () {
    final metadata = SettingsProfileMetadata.fromJson(validJson());

    expect(metadata.enabledGenres, ['hip-hop', 'pop', 'rock']);
    expect(metadata.profileChecksum, hasLength(64));
    expect(metadata.qualityProfileChecksum, hasLength(64));
    expect(metadata.controlPriors.requiresPhysicalConfirmation, isTrue);
    expect(
      metadata.controlPriors.toScale(
        const AmplifierScale(minimum: 0, maximum: 10, step: 0.5),
      ),
      const KnobSettings(
        volume: 4,
        bass: 5,
        treble: 5,
        sharpness: 5,
        flatness: 5,
      ),
    );
  });

  test('metadata rejects a missing checksum', () {
    final json = validJson()..remove('profile_checksum');

    expect(() => SettingsProfileMetadata.fromJson(json), throwsFormatException);
  });

  test('metadata rejects duplicate or empty genres', () {
    for (final genres in <List<String>>[
      ['rock', 'rock'],
      ['rock', ' '],
    ]) {
      final json = validJson()..['enabled_genres'] = genres;

      expect(
        () => SettingsProfileMetadata.fromJson(json),
        throwsFormatException,
      );
    }
  });

  test('control priors reject a non-0-100 normalized scale', () {
    final json = validJson();
    final priors = Map<String, dynamic>.from(json['control_priors'] as Map)
      ..['normalized_scale'] = {'minimum': 0, 'maximum': 10};
    json['control_priors'] = priors;

    expect(() => SettingsProfileMetadata.fromJson(json), throwsFormatException);
  });

  test('control priors reject missing knobs and non-finite positions', () {
    final missingKnob = validJson();
    final missingPositions = Map<String, dynamic>.from(
      (missingKnob['control_priors'] as Map)['positions'] as Map,
    )..remove('flatness');
    final missingPriors = Map<String, dynamic>.from(
      missingKnob['control_priors'] as Map,
    )..['positions'] = missingPositions;
    missingKnob['control_priors'] = missingPriors;

    expect(
      () => SettingsProfileMetadata.fromJson(missingKnob),
      throwsFormatException,
    );

    final nonFinite = validJson();
    final nonFinitePositions = Map<String, dynamic>.from(
      (nonFinite['control_priors'] as Map)['positions'] as Map,
    )..['bass'] = double.nan;
    final nonFinitePriors = Map<String, dynamic>.from(
      nonFinite['control_priors'] as Map,
    )..['positions'] = nonFinitePositions;
    nonFinite['control_priors'] = nonFinitePriors;

    expect(
      () => SettingsProfileMetadata.fromJson(nonFinite),
      throwsFormatException,
    );
  });

  test('control priors require physical confirmation', () {
    final json = validJson();
    final priors = Map<String, dynamic>.from(json['control_priors'] as Map)
      ..['requires_physical_confirmation'] = false;
    json['control_priors'] = priors;

    expect(() => SettingsProfileMetadata.fromJson(json), throwsFormatException);
  });
}
