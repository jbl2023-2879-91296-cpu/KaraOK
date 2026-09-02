import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/sound_settings/data/guest_amplifier_store.dart';
import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';

void main() {
  late Directory supportDirectory;
  late Future<Directory> Function() provider;

  const profile = AmplifierProfile(
    name: 'Living Room Amp',
    scale: AmplifierScale(minimum: 0, maximum: 10, step: 0.5),
    lastPositions: KnobSettings(
      volume: 5,
      bass: 4,
      treble: 6,
      sharpness: 5,
      flatness: 5,
    ),
  );

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'karaok-guest-amplifier-',
    );
    provider = () async => supportDirectory;
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('guest amplifier profile survives store recreation', () async {
    await GuestAmplifierStore(directoryProvider: provider).save(profile);

    final restored = await GuestAmplifierStore(
      directoryProvider: provider,
    ).read();

    expect(restored, profile);
    expect(
      File(
        '${supportDirectory.path}${Platform.pathSeparator}'
        'karaok_guest${Platform.pathSeparator}amplifier-profile.json',
      ).existsSync(),
      isTrue,
    );
  });

  test(
    'saving replaces the profile without leaving a temporary file',
    () async {
      final store = GuestAmplifierStore(directoryProvider: provider);
      await store.save(profile);
      const updated = AmplifierProfile(
        name: 'Stage Amp',
        scale: AmplifierScale(minimum: 0, maximum: 100, step: 1),
        lastPositions: KnobSettings(
          volume: 55,
          bass: 40,
          treble: 60,
          sharpness: 50,
          flatness: 50,
        ),
      );

      await store.save(updated);

      expect(await store.read(), updated);
      final directory = Directory(
        '${supportDirectory.path}${Platform.pathSeparator}karaok_guest',
      );
      expect(
        directory.listSync().where((entry) => entry.path.endsWith('.tmp')),
        isEmpty,
      );
    },
  );

  test('missing or malformed storage returns no guest profile', () async {
    final store = GuestAmplifierStore(directoryProvider: provider);
    expect(await store.read(), isNull);

    final directory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}karaok_guest',
    );
    await directory.create(recursive: true);
    await File(
      '${directory.path}${Platform.pathSeparator}amplifier-profile.json',
    ).writeAsString('{not-json');

    expect(await store.read(), isNull);
  });
}
