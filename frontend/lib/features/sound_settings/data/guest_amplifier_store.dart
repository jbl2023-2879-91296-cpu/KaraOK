import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';

/// Device-local storage for the single amplifier configured by a guest.
class GuestAmplifierStore {
  GuestAmplifierStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final GuestAmplifierStore instance = GuestAmplifierStore();

  final Future<Directory> Function() _directoryProvider;

  Future<Directory> _guestDirectory({required bool create}) async {
    final support = await _directoryProvider();
    final directory = Directory(path.join(support.path, 'karaok_guest'));
    if (create && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _profileFile({required bool createDirectory}) async => File(
    path.join(
      (await _guestDirectory(create: createDirectory)).path,
      'amplifier-profile.json',
    ),
  );

  Future<AmplifierProfile?> read() async {
    try {
      final file = await _profileFile(createDirectory: false);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return AmplifierProfile.fromJson(Map<String, dynamic>.from(decoded));
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(AmplifierProfile profile) async {
    profile.validate();
    final destination = await _profileFile(createDirectory: true);
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(profile.toJson()), flush: true);
      await temporary.rename(destination.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
}
