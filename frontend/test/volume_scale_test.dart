import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';

void main() {
  test('denormalize clamps to marked steps instead of an off-step maximum', () {
    for (final entry in [
      (const AmplifierScale(minimum: 0, maximum: 1, step: .3), .9),
      (const AmplifierScale(minimum: 0, maximum: 1, step: .4), .8),
      (const AmplifierScale(minimum: -1, maximum: 0, step: .4), -.2),
      (const AmplifierScale(minimum: .1, maximum: 1.1, step: .4), .9),
      (const AmplifierScale(minimum: 0, maximum: 1, step: .1), 1.0),
      (const AmplifierScale(minimum: 0, maximum: .3, step: .1), .3),
    ]) {
      final (scale, lastPosition) = entry;
      expect(scale.denormalize(100), closeTo(lastPosition, 1e-12));
      expect(scale.denormalize(101), closeTo(lastPosition, 1e-12));
      expect(scale.denormalize(-1), scale.minimum);
      // Simulate every slider callback, then validate the next snapshot.
      for (var percent = 0; percent <= 100; percent++) {
        final sliderValue =
            scale.minimum + percent * (scale.maximum - scale.minimum) / 100;
        final position = scale.denormalize(scale.normalize(sliderValue));
        final snapshot = KnobSettings.fromJson({
          'volume': position,
          'bass': 0,
          'treble': 0,
          'sharpness': 0,
          'flatness': 0,
          'volume_scale': scale.toJson(),
        });
        expect(snapshot.volume, position);
        expect(position, inInclusiveRange(scale.minimum, scale.maximum));
      }
    }
  });

  const tone = AmplifierScale(minimum: -10, maximum: 10, step: .5);
  const volume = AmplifierScale(minimum: -80, maximum: 0, step: 2, unit: 'dB');
  const positions = KnobSettings(
    volume: -40,
    bass: -4,
    treble: 2,
    sharpness: 0,
    flatness: 0,
    volumeScale: volume,
  );
  Map<String, dynamic> wire(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  test(
    'explicit volume scale preserves units and range through profile JSON',
    () {
      const profile = AmplifierProfile(
        name: 'Test amp',
        scale: tone,
        lastPositions: positions,
      );
      final restored = AmplifierProfile.fromJson(wire(profile.toJson()));
      expect(restored, profile);
      expect(restored.volumeScale, volume);
      expect(restored.volumeScale.unit, 'dB');
      expect(restored.lastPositions!.volume, -40);
      expect(restored.lastPositions!.controlScale('bass', tone), tone);
      expect(restored.lastPositions!.controlScale('treble', tone), tone);
      expect(
        restored.toJson()['last_positions'],
        containsPair('volume_scale', volume.toJson()),
      );
    },
  );

  test(
    'volume normalizes independently and roundtrips every marked position',
    () {
      final scale = positions.controlScale('volume', tone);
      expect(scale.normalize(-80), 0);
      expect(scale.normalize(-40), 50);
      expect(scale.normalize(0), 100);
      expect(tone.normalize(0), 50);
      for (var value = -80; value <= 0; value += 2) {
        expect(scale.denormalize(scale.normalize(value.toDouble())), value);
      }
      expect(scale.denormalize(-1), -80);
      expect(scale.denormalize(101), 0);
    },
  );

  test('explicit volume bounds do not accidentally use tone bounds', () {
    expect(() => positions.validate(scale: tone), returnsNormally);
    for (final value in [-82, 2, double.nan, double.infinity]) {
      expect(
        () => KnobSettings.fromJson({
          ...positions.toJson(),
          'volume': value,
        }, scale: tone),
        throwsFormatException,
      );
    }
    expect(
      () => KnobSettings.fromJson({
        ...positions.toJson(),
        'bass': -40,
      }, scale: tone),
      throwsFormatException,
    );
  });

  test(
    'explicit volume bounds and marked steps apply without a tone scale',
    () {
      for (final value in [-82, 2, -39, -79]) {
        expect(
          () => KnobSettings.fromJson({...positions.toJson(), 'volume': value}),
          throwsFormatException,
          reason: 'Reject volume $value without a tone scale',
        );
      }
      for (final value in [-80, -40, 0]) {
        expect(
          KnobSettings.fromJson({
            ...positions.toJson(),
            'volume': value,
          }).volume,
          value,
        );
      }
    },
  );

  test('explicit decimal volume steps tolerate floating point roundoff', () {
    const decimal = AmplifierScale(minimum: 0, maximum: 1, step: .1);
    final json = {
      ...positions.toJson(),
      'volume_scale': {...decimal.toJson(), 'unit': ''},
    };
    expect(
      () => KnobSettings.fromJson({...json, 'volume': .1 + .2}),
      returnsNormally,
    );
    expect(
      () => KnobSettings.fromJson({...json, 'volume': .35}),
      throwsFormatException,
    );
  });

  test('invalid explicit scale metadata is rejected', () {
    for (final scale in [
      {...volume.toJson(), 'step': 0},
      {...volume.toJson(), 'maximum': -80},
      {...volume.toJson(), 'unit': 'watts'},
      {...volume.toJson(), 'minimum': double.nan},
    ]) {
      expect(
        () => KnobSettings.fromJson({
          ...positions.toJson(),
          'volume_scale': scale,
        }, scale: tone),
        throwsFormatException,
      );
    }
  });

  test(
    'legacy attenuation survives JSON and retains its marked 10-110 range',
    () {
      const legacy = KnobSettings(
        volume: 60,
        bass: -4,
        treble: 2,
        sharpness: 0,
        flatness: 0,
        volumeAttenuation: true,
      );
      final restored = KnobSettings.fromJson(
        wire(legacy.toJson()),
        scale: tone,
      );
      expect(restored, legacy);
      expect(restored.volumeScale, isNull);
      expect(
        restored.controlScale('volume', tone),
        const AmplifierScale(minimum: 10, maximum: 110, step: 10),
      );
      expect(restored.toJson()['volume_attenuation'], isTrue);
      expect(restored.toJson(), isNot(contains('volume_scale')));
      for (final value in [0, 65, 120]) {
        expect(
          () => KnobSettings.fromJson({
            ...legacy.toJson(),
            'volume': value,
          }, scale: tone),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'explicit scale overrides a legacy attenuation flag when reading JSON',
    () {
      final restored = KnobSettings.fromJson({
        ...positions.toJson(),
        'volume_attenuation': true,
      }, scale: tone);
      expect(restored.volumeScale, volume);
      expect(restored.controlScale('volume', tone), volume);
      expect(restored.volumeAttenuation, isFalse);
      expect(restored.toJson(), isNot(contains('volume_attenuation')));
      expect(
        KnobSettings.fromJson(wire(restored.toJson()), scale: tone),
        restored,
      );
    },
  );

  test('plain scale JSON retains the explicit empty unit', () {
    const numberedVolume = AmplifierScale(minimum: 0, maximum: 100, step: 1);
    const numbered = KnobSettings(
      volume: 60,
      bass: -4,
      treble: 2,
      sharpness: 0,
      flatness: 0,
      volumeScale: numberedVolume,
    );
    final json = wire(numbered.toJson());
    expect(json['volume_scale'], {
      'minimum': 0.0,
      'maximum': 100.0,
      'step': 1.0,
      'unit': '',
    });
    expect(KnobSettings.fromJson(json, scale: tone), numbered);
  });

  test(
    'legacy plain controls still inherit tone scale without added metadata',
    () {
      final json = <String, dynamic>{
        'volume': 5,
        'bass': -4,
        'treble': 2,
        'sharpness': 0,
        'flatness': 0,
      };
      final restored = KnobSettings.fromJson(wire(json), scale: tone);
      expect(restored.volumeAttenuation, isFalse);
      expect(restored.volumeScale, isNull);
      expect(restored.controlScale('volume', tone), tone);
      expect(restored.toJson(), json);
      expect(
        () => KnobSettings.fromJson({...json, 'volume': 60}, scale: tone),
        throwsFormatException,
      );
    },
  );

  test(
    'suggestion multipart carries separate volume scale without changing tone scale',
    () {
      final fields = SettingsSuggestionInput(
        genre: 'Rock',
        amplifierScale: tone,
        currentSettings: positions,
      ).toMultipartFields();
      expect(jsonDecode(fields['amplifier_scale']!), tone.toJson());
      final current =
          jsonDecode(fields['current_settings']!) as Map<String, dynamic>;
      expect(current['volume_scale'], volume.toJson());
      expect(current['volume'], -40);
      expect(KnobSettings.fromJson(current, scale: tone), positions);
    },
  );
}
