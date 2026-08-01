import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:karaok_app/core/security/session_manager.dart';

/// App-private, per-user persistence for history metadata and report images.
class AnalysisCache {
  AnalysisCache({Future<Directory> Function()? supportDirectoryProvider})
    : _supportDirectoryProvider =
          supportDirectoryProvider ?? getApplicationSupportDirectory;

  static final AnalysisCache instance = AnalysisCache();

  final Future<Directory> Function() _supportDirectoryProvider;
  final Map<String, Future<Uint8List>> _inFlightVisualizations = {};

  Future<Directory?> _userDirectory({bool create = true}) async {
    final userId = UserSession.instance.id;
    if (userId == null) return null;
    final support = await _supportDirectoryProvider();
    final directory = Directory(
      path.join(support.path, 'karaok_cache', 'users', '$userId'),
    );
    if (create && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<List<dynamic>?> readHistory() async {
    try {
      final directory = await _userDirectory(create: false);
      if (directory == null) return null;
      final file = File(path.join(directory.path, 'history.json'));
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is List ? List<dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveHistory(List<dynamic> history) async {
    try {
      final directory = await _userDirectory();
      if (directory == null) return;
      final file = File(path.join(directory.path, 'history.json'));
      await file.writeAsString(jsonEncode(history), flush: true);
    } catch (_) {
      // Caching is an optimization and must never break the server response.
    }
  }

  Future<Uint8List> visualization({
    required int assessmentId,
    required String kind,
    required Future<Uint8List> Function() fetch,
  }) async {
    final userId = UserSession.instance.id;
    if (userId == null) return fetch();
    final cacheKey = '$userId:$assessmentId:$kind';
    final existing = _inFlightVisualizations[cacheKey];
    if (existing != null) return existing;

    final future = _loadOrFetchVisualization(
      assessmentId: assessmentId,
      kind: kind,
      fetch: fetch,
    );
    _inFlightVisualizations[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inFlightVisualizations.remove(cacheKey);
    }
  }

  Future<Uint8List> _loadOrFetchVisualization({
    required int assessmentId,
    required String kind,
    required Future<Uint8List> Function() fetch,
  }) async {
    File? cacheFile;
    try {
      final directory = await _userDirectory();
      if (directory != null) {
        final visualizationDirectory = Directory(
          path.join(directory.path, 'visualizations'),
        );
        await visualizationDirectory.create(recursive: true);
        cacheFile = File(
          path.join(visualizationDirectory.path, '$assessmentId-$kind.bin'),
        );
        if (await cacheFile.exists() && await cacheFile.length() > 0) {
          return cacheFile.readAsBytes();
        }
      }
    } catch (_) {
      cacheFile = null;
    }

    final bytes = await fetch();
    if (bytes.isEmpty || cacheFile == null) return bytes;
    try {
      await cacheFile.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Return the downloaded report even when local persistence is unavailable.
    }
    return bytes;
  }

  Future<void> saveVisualization({
    required int assessmentId,
    required String kind,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) return;
    try {
      final directory = await _userDirectory();
      if (directory == null) return;
      final visualizationDirectory = Directory(
        path.join(directory.path, 'visualizations'),
      );
      await visualizationDirectory.create(recursive: true);
      await File(
        path.join(visualizationDirectory.path, '$assessmentId-$kind.bin'),
      ).writeAsBytes(bytes, flush: true);
    } catch (_) {
      // The imported server copy remains authoritative if local copying fails.
    }
  }

  Future<void> removeAssessment(int assessmentId) async {
    try {
      final directory = await _userDirectory(create: false);
      if (directory == null) return;
      final history = await readHistory();
      if (history != null) {
        history.removeWhere(
          (item) =>
              item is Map &&
              (item['assessment_id'] == assessmentId ||
                  item['id'] == assessmentId),
        );
        await saveHistory(history);
      }
      final visualizationDirectory = Directory(
        path.join(directory.path, 'visualizations'),
      );
      for (final kind in const ['waveform', 'spectrogram']) {
        final file = File(
          path.join(visualizationDirectory.path, '$assessmentId-$kind.bin'),
        );
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // Server-side deletion remains authoritative.
    }
  }

  Future<void> clearCurrentUser() async {
    try {
      final directory = await _userDirectory(create: false);
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Logout/password changes still complete if cache cleanup is unavailable.
    }
  }
}
