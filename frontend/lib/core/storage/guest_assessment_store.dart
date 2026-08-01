import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Durable, app-private guest reports. Android backup is disabled so these
/// files survive app restarts but are removed permanently on uninstall.
class GuestAssessmentStore {
  GuestAssessmentStore({Future<Directory> Function()? supportDirectoryProvider})
    : _supportDirectoryProvider =
          supportDirectoryProvider ?? getApplicationSupportDirectory;

  static final GuestAssessmentStore instance = GuestAssessmentStore();

  final Future<Directory> Function() _supportDirectoryProvider;

  Future<Directory> _directory() async {
    final support = await _supportDirectoryProvider();
    final directory = Directory(path.join(support.path, 'karaok_guest'));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _indexFile() async =>
      File(path.join((await _directory()).path, 'assessments.json'));

  Future<List<Map<String, dynamic>>> _readIndex() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<Map<String, dynamic>> entries) async {
    final file = await _indexFile();
    await file.writeAsString(jsonEncode(entries), flush: true);
  }

  Future<void> saveCompleted(Map<String, dynamic> record) async {
    final visualizations = record['visualizations'];
    if (visualizations is! Map) {
      throw const FormatException('Completed guest report is incomplete.');
    }
    final localId = DateTime.now().microsecondsSinceEpoch.toString();
    final directory = await _directory();
    final written = <File>[];
    try {
      for (final kind in const ['waveform', 'spectrogram']) {
        final encoded = visualizations[kind];
        if (encoded is! String || encoded.isEmpty) {
          throw FormatException('$kind visualization is missing.');
        }
        final file = File(path.join(directory.path, '$localId-$kind.png'));
        await file.writeAsBytes(base64Decode(encoded), flush: true);
        written.add(file);
      }
      final stored = Map<String, dynamic>.from(record)
        ..remove('visualizations')
        ..remove('analysis_dump')
        ..remove('guest_import_receipt')
        ..['local_guest_id'] = localId
        ..['created_at'] =
            (record['created_at'] ?? DateTime.now().toUtc().toIso8601String())
                .toString();
      final entries = await _readIndex();
      entries.insert(0, stored);
      await _writeIndex(entries);
    } catch (_) {
      for (final file in written) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _withVisualizations(
    Map<String, dynamic> entry,
  ) async {
    final localId = entry['local_guest_id'].toString();
    final directory = await _directory();
    final images = <String, String>{};
    for (final kind in const ['waveform', 'spectrogram']) {
      final file = File(path.join(directory.path, '$localId-$kind.png'));
      if (await file.exists()) {
        images[kind] = base64Encode(await file.readAsBytes());
      }
    }
    return Map<String, dynamic>.from(entry)..['visualizations'] = images;
  }

  Future<List<dynamic>> guestHistory() async {
    final entries = await _readIndex();
    // Old builds may have marked a report during an interrupted migration.
    // Never expose those records to a later guest session.
    final visible = entries.where((entry) => entry['owner_user_id'] == null);
    return Future.wait(visible.map(_withVisualizations));
  }

  Future<void> clearAll() async {
    final support = await _supportDirectoryProvider();
    final directory = Directory(path.join(support.path, 'karaok_guest'));
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
