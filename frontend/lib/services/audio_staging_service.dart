import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AudioSourceType { recording, selectedFile }

class StagedAudio {
  const StagedAudio({
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    required this.duration,
    required this.format,
    required this.source,
    required this.temporary,
    this.bytes,
  });
  final String fileName;
  final String path;
  final int sizeBytes;
  final Duration duration;
  final String format;
  final AudioSourceType source;
  final bool temporary;
  final Uint8List? bytes;

  bool get isMemoryBacked => bytes != null;
}

class AudioStagingException implements Exception {
  const AudioStagingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AudioStagingService {
  static const maxBytes = 25 * 1024 * 1024;
  static const maxDuration = Duration(minutes: 5);
  static const supportedExtensions = {
    'wav',
    'mp3',
    'm4a',
    'aac',
    'ogg',
    'flac',
  };

  StagedAudio? current;

  Future<StagedAudio?> pickAudio() async {
    final selectedFile = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: 'audio', extensions: supportedExtensions.toList()),
      ],
    );
    if (selectedFile == null) return null;
    if (kIsWeb) {
      return _stageBrowserFile(
        selectedFile,
        source: AudioSourceType.selectedFile,
      );
    }
    final selectedPath = selectedFile.path;
    final source = File(selectedPath);
    if (!await source.exists()) {
      throw const AudioStagingException('The selected file no longer exists.');
    }
    final stagingDir = await _stagingDirectory();
    final destination = File(
      p.join(
        stagingDir.path,
        'selected_${DateTime.now().millisecondsSinceEpoch}_${p.basename(selectedPath)}',
      ),
    );
    await source.copy(destination.path);
    return stagePath(
      destination.path,
      AudioSourceType.selectedFile,
      temporary: true,
    );
  }

  Future<StagedAudio> stageBrowserRecording(String blobUrl, String fileName) =>
      _stageBrowserFile(
        XFile(blobUrl, name: fileName, mimeType: 'audio/wav'),
        source: AudioSourceType.recording,
      );

  Future<StagedAudio> _stageBrowserFile(
    XFile selectedFile, {
    required AudioSourceType source,
  }) async {
    final fileName = selectedFile.name;
    final extension = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw const AudioStagingException('This audio format is not supported.');
    }
    final size = await selectedFile.length();
    if (size == 0) {
      throw const AudioStagingException('The audio file is empty.');
    }
    if (size > maxBytes) {
      throw const AudioStagingException(
        'The audio file exceeds the 25 MB limit.',
      );
    }

    final player = AudioPlayer();
    Duration? duration;
    try {
      duration = await player.setUrl(selectedFile.path);
    } catch (_) {
      throw const AudioStagingException(
        'The audio file is corrupted or unreadable.',
      );
    } finally {
      await player.dispose();
    }
    if (duration == null || duration == Duration.zero) {
      throw const AudioStagingException(
        'Could not determine the audio duration.',
      );
    }
    if (duration > maxDuration) {
      throw const AudioStagingException(
        'The audio exceeds the five-minute limit.',
      );
    }

    final bytes = await selectedFile.readAsBytes();
    if (bytes.isEmpty) {
      throw const AudioStagingException('The audio file is empty.');
    }
    await discard();
    current = StagedAudio(
      fileName: fileName,
      path: selectedFile.path,
      sizeBytes: bytes.length,
      duration: duration,
      format: extension.toUpperCase(),
      source: source,
      temporary: false,
      bytes: bytes,
    );
    return current!;
  }

  Future<StagedAudio> stagePath(
    String path,
    AudioSourceType source, {
    required bool temporary,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const AudioStagingException('The audio file is missing.');
    }
    final size = await file.length();
    if (size == 0) {
      throw const AudioStagingException('The audio file is empty.');
    }
    if (size > maxBytes) {
      throw const AudioStagingException(
        'The audio file exceeds the 25 MB limit.',
      );
    }
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw const AudioStagingException('This audio format is not supported.');
    }
    final player = AudioPlayer();
    Duration? duration;
    try {
      duration = await player.setFilePath(path);
    } catch (_) {
      throw const AudioStagingException(
        'The audio file is corrupted or unreadable.',
      );
    } finally {
      await player.dispose();
    }
    if (duration == null || duration == Duration.zero) {
      throw const AudioStagingException(
        'Could not determine the audio duration.',
      );
    }
    if (duration > maxDuration) {
      throw const AudioStagingException(
        'The audio exceeds the five-minute limit.',
      );
    }
    await discard();
    current = StagedAudio(
      fileName: p.basename(path),
      path: path,
      sizeBytes: size,
      duration: duration,
      format: extension.toUpperCase(),
      source: source,
      temporary: temporary,
    );
    return current!;
  }

  Future<Directory> recordingDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'karaok_recordings'));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<void> discard() async {
    final item = current;
    current = null;
    if (item?.temporary == true && item?.bytes == null) {
      final file = File(item!.path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<bool> currentIsAvailable() async {
    final item = current;
    if (item == null) return false;
    if (item.bytes != null) return item.bytes!.isNotEmpty;
    return File(item.path).exists();
  }

  Future<Directory> _stagingDirectory() async {
    final temp = await getTemporaryDirectory();
    final dir = Directory(p.join(temp.path, 'audio_staging'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
