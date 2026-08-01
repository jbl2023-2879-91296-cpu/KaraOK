import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    final receipt = record['guest_import_receipt'];
    if (visualizations is! Map || receipt is! String || receipt.isEmpty) {
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
        ..['local_guest_id'] = localId
        ..['owner_user_id'] = null
        ..['server_assessment_id'] = null
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
    final visible = entries.where((entry) => entry['owner_user_id'] == null);
    return Future.wait(visible.map(_withVisualizations));
  }

  Future<void> claimUnownedForUser(int userId) async {
    final entries = await _readIndex();
    var changed = false;
    for (final entry in entries) {
      if (entry['owner_user_id'] == null) {
        entry['owner_user_id'] = userId;
        changed = true;
      }
    }
    if (changed) await _writeIndex(entries);
  }

  Future<List<Map<String, dynamic>>> pendingForUser(int userId) async {
    final entries = await _readIndex();
    final pending = entries.where(
      (entry) =>
          entry['owner_user_id'] == userId &&
          entry['server_assessment_id'] == null,
    );
    return Future.wait(pending.map(_withVisualizations));
  }

  Future<void> markSynced({
    required String localId,
    required int assessmentId,
  }) async {
    final entries = await _readIndex();
    for (final entry in entries) {
      if (entry['local_guest_id'].toString() == localId) {
        entry['server_assessment_id'] = assessmentId;
      }
    }
    await _writeIndex(entries);
  }

  Future<Uint8List?> visualizationBytes(String localId, String kind) async {
    final directory = await _directory();
    final file = File(path.join(directory.path, '$localId-$kind.png'));
    return await file.exists() ? file.readAsBytes() : null;
  }
}
