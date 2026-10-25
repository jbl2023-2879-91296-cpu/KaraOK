import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AudioSourceType { recording, selectedFile }

const midiRenderedAudioMessage =
    'MIDI event files are not rendered audio. Record the karaoke machine playback or select WAV, MP3, M4A, AAC, OGG, or FLAC.';

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
  static const androidPicker = MethodChannel('karaok/audio_picker');
  static const maxBytes = 25 * 1024 * 1024;
  static const minDuration = Duration(seconds: 10);
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
  static const operationTimeout = Duration(seconds: 15);

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AudioStagingException {
      rethrow;
    } on TimeoutException {
      throw const AudioStagingException(
        'Reading the audio took too long. Please try another file.',
      );
    } catch (_) {
      throw const AudioStagingException(
        'Could not read the audio. Please try again or choose another file.',
      );
    }
  }

  Future<Duration?> _playerDuration(String path, {bool browser = false}) async {
    final player = AudioPlayer();
    try {
      return await (browser ? player.setUrl(path) : player.setFilePath(path))
          .timeout(operationTimeout);
    } finally {
      // A disposal error must not hide the useful staging error.
      try {
        await player.dispose().timeout(operationTimeout);
      } catch (_) {}
    }
  }

  static void validateDuration(Duration? duration) {
    if (duration == null) {
      throw const AudioStagingException(
        'Could not determine the audio duration.',
      );
    }
    if (duration < minDuration) {
      throw const AudioStagingException(
        'Audio must be at least 10 seconds. Record again or choose a longer file.',
      );
    }
    if (duration > maxDuration) {
      throw const AudioStagingException(
        'The audio exceeds the five-minute limit.',
      );
    }
  }

  Future<StagedAudio?> pickAudio() => _guard(_pickAudio);

  Future<StagedAudio?> _pickAudio() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final Map<String, dynamic>? selected;
      try {
        selected = await androidPicker.invokeMapMethod<String, dynamic>(
          'pickAudio',
        );
      } on PlatformException catch (error) {
        throw AudioStagingException(
          error.message ?? 'Could not select the audio file.',
        );
      }
      if (selected == null) return null;
      final path = selected['path'] as String;
      // Only app-owned cache copies are returned by the native bridge.
      try {
        final size = selected['size'] as int;
        if (size > maxBytes) {
          throw const AudioStagingException(
            'The audio file exceeds the 25 MB limit.',
          );
        }
        return await _stagePath(
          path,
          AudioSourceType.selectedFile,
          temporary: true,
          fileName: selected['name'] as String?,
        );
      } catch (_) {
        final cached = File(path);
        if (await cached.exists()) await cached.delete();
        rethrow;
      }
    }
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
    return stagePath(
      source.path,
      AudioSourceType.selectedFile,
      temporary: false,
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
  }) => _guard(() => _readBrowserFile(selectedFile, source: source));

  Future<StagedAudio> _readBrowserFile(
    XFile selectedFile, {
    required AudioSourceType source,
  }) async {
    final fileName = selectedFile.name;
    final extension = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    if (extension == 'mid' || extension == 'midi') {
      throw const AudioStagingException(midiRenderedAudioMessage);
    }
    if (!supportedExtensions.contains(extension)) {
      throw const AudioStagingException('This audio format is not supported.');
    }
    final size = await selectedFile.length().timeout(operationTimeout);
    if (size == 0) {
      throw const AudioStagingException('The audio file is empty.');
    }
    if (size > maxBytes) {
      throw const AudioStagingException(
        'The audio file exceeds the 25 MB limit.',
      );
    }

    final duration = await _playerDuration(selectedFile.path, browser: true);
    validateDuration(duration);

    final bytes = await selectedFile.readAsBytes().timeout(operationTimeout);
    if (bytes.length > maxBytes) {
      throw const AudioStagingException(
        'The audio file exceeds the 25 MB limit.',
      );
    }
    if (bytes.isEmpty) {
      throw const AudioStagingException('The audio file is empty.');
    }
    await discard();
    current = StagedAudio(
      fileName: fileName,
      path: selectedFile.path,
      sizeBytes: bytes.length,
      duration: duration!,
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
  }) => _guard(() => _stagePath(path, source, temporary: temporary));

  Future<StagedAudio> _stagePath(
    String path,
    AudioSourceType source, {
    required bool temporary,
    String? fileName,
  }) async {
    final file = File(path);
    if (!await file.exists().timeout(operationTimeout)) {
      throw const AudioStagingException('The audio file is missing.');
    }
    final size = await file.length().timeout(operationTimeout);
    if (size == 0) {
      throw const AudioStagingException('The audio file is empty.');
    }
    if (size > maxBytes) {
      throw const AudioStagingException(
        'The audio file exceeds the 25 MB limit.',
      );
    }
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (extension == 'mid' || extension == 'midi') {
      throw const AudioStagingException(midiRenderedAudioMessage);
    }
    if (!supportedExtensions.contains(extension)) {
      throw const AudioStagingException('This audio format is not supported.');
    }
    Duration? duration;
    if (extension == 'mp3' || extension == 'wav') {
      try {
        duration = await _headerDuration(file, extension, size);
      } on AudioStagingException catch (error) {
        // Only a confirmed duration violation rejects an MP3 at this stage.
        // Tags, junk, and unsupported headers defer to the native duration probe.
        if (extension != 'mp3' || error.message.contains('five-minute')) {
          rethrow;
        }
      } on TimeoutException {
        if (extension != 'mp3') rethrow;
      }
    }
    duration ??= await _playerDuration(path);
    validateDuration(duration);
    await discard();
    current = StagedAudio(
      fileName: fileName ?? p.basename(path),
      path: path,
      sizeBytes: size,
      duration: duration!,
      format: extension.toUpperCase(),
      source: source,
      temporary: temporary,
    );
    return current!;
  }

  /// Removes recordings owned by this app, including leftovers from prior sessions.
  /// Call after stopping the recorder during logout.
  Future<void> cleanupStaleRecordings() => _guard(() async {
    if (kIsWeb) return;
    await discard();
    final directory = await recordingDirectory();
    final files = await directory
        .list(followLinks: false)
        .toList()
        .timeout(operationTimeout);
    for (final file in files) {
      if (file is File) await file.delete().timeout(operationTimeout);
    }
  });

  Future<Duration?> _headerDuration(
    File file,
    String extension,
    int size,
  ) async {
    final handle = await file.open().timeout(operationTimeout);
    final clock = Stopwatch()..start();
    const invalid = AudioStagingException(
      'The audio header is unsupported or damaged. Please choose another file.',
    );
    Future<Uint8List> read(int offset, int count) async {
      if (clock.elapsed > operationTimeout) {
        throw TimeoutException('Audio header');
      }
      if (offset < 0 || offset + count > size) throw invalid;
      await handle.setPosition(offset).timeout(operationTimeout);
      final bytes = await handle.read(count).timeout(operationTimeout);
      if (bytes.length != count) throw invalid;
      return bytes;
    }

    int u32(Uint8List b, int offset) =>
        ByteData.sublistView(b).getUint32(offset, Endian.little);
    bool tag(Uint8List b, int offset, String text) =>
        String.fromCharCodes(b.sublist(offset, offset + text.length)) == text;
    try {
      if (extension == 'wav') {
        final header = await read(0, 12);
        if (!tag(header, 0, 'RIFF') || !tag(header, 8, 'WAVE')) throw invalid;
        final end = u32(header, 4) + 8;
        if (end > size) throw invalid;
        int? rate;
        int? alignment;
        int? dataSize;
        var offset = 12;
        for (var chunks = 0; offset + 8 <= end && chunks < 256; chunks++) {
          final chunk = await read(offset, 8);
          final length = u32(chunk, 4);
          if (offset + 8 + length > end) throw invalid;
          if (tag(chunk, 0, 'fmt ')) {
            if (length < 16) throw invalid;
            final fmt = ByteData.sublistView(await read(offset + 8, 16));
            var format = fmt.getUint16(0, Endian.little);
            final channels = fmt.getUint16(2, Endian.little);
            final sampleRate = fmt.getUint32(4, Endian.little);
            rate = fmt.getUint32(8, Endian.little);
            alignment = fmt.getUint16(12, Endian.little);
            final bits = fmt.getUint16(14, Endian.little);
            if (format == 0xfffe) {
              // WAVEFORMATEXTENSIBLE requires the complete 22-byte extension.
              // Read only its fixed header, never the audio payload.
              if (length < 40) throw invalid;
              final extended = await read(offset + 8, 40);
              final fields = ByteData.sublistView(extended);
              final extensionSize = fields.getUint16(16, Endian.little);
              final validBits = fields.getUint16(18, Endian.little);
              final channelMask = fields.getUint32(20, Endian.little);
              final subtype = fields.getUint32(24, Endian.little);
              const guidTail = [0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113];
              if (extensionSize < 22 ||
                  18 + extensionSize > length ||
                  (subtype != 1 && subtype != 3) ||
                  validBits == 0 ||
                  validBits > bits ||
                  (subtype == 3 &&
                      (validBits != bits || (bits != 32 && bits != 64)))) {
                throw invalid;
              }
              for (var index = 0; index < guidTail.length; index++) {
                if (extended[28 + index] != guidTail[index]) throw invalid;
              }
              var speakers = 0;
              for (var mask = channelMask; mask != 0; mask >>= 1) {
                speakers += mask & 1;
              }
              if (channelMask != 0 &&
                  (channelMask > 0x3ffff || speakers != channels)) {
                throw invalid;
              }
              format = subtype;
            }
            if ((format != 1 && format != 3) ||
                channels == 0 ||
                bits == 0 ||
                bits % 8 != 0 ||
                alignment != channels * (bits ~/ 8) ||
                sampleRate == 0 ||
                rate != sampleRate * alignment) {
              throw invalid;
            }
          } else if (tag(chunk, 0, 'data')) {
            dataSize = length;
          }
          offset += 8 + length + (length & 1);
        }
        if (rate == null ||
            alignment == null ||
            dataSize == null ||
            dataSize == 0 ||
            dataSize % alignment != 0) {
          throw invalid;
        }
        return Duration(microseconds: (dataSize * 1000000 / rate).round());
      }

      var offset = 0;
      final first = await read(0, 10);
      if (tag(first, 0, 'ID3')) {
        if (first[3] < 2 ||
            first[3] > 4 ||
            first.sublist(6, 10).any((b) => b >= 128)) {
          throw invalid;
        }
        final length =
            (first[6] << 21) | (first[7] << 14) | (first[8] << 7) | first[9];
        offset = 10 + length + ((first[3] == 4 && first[5] & 16 != 0) ? 10 : 0);
      }
      var seconds = 0.0;
      var frames = 0;
      // Search a bounded prefix for a frame sync; real MP3s can have leading
      // encoder junk. Longer/ambiguous prefixes fall back to the duration probe.
      final prefixLength = (size - offset).clamp(0, 64 * 1024);
      if (prefixLength < 4) return null;
      final prefix = await read(offset, prefixLength);
      var leading = 0;
      while (leading + 4 <= prefix.length &&
          !(prefix[leading] == 255 && (prefix[leading + 1] & 224) == 224)) {
        leading++;
      }
      if (leading + 4 > prefix.length) return null;
      offset += leading;
      // Only four bytes per frame are read; payload is skipped, never decoded.
      while (offset + 4 <= size && frames < 20000) {
        final b = await read(offset, 4);
        final version = (b[1] >> 3) & 3;
        final bitrateIndex = b[2] >> 4;
        final sampleIndex = (b[2] >> 2) & 3;
        if (b[0] != 255 ||
            b[1] & 224 != 224 ||
            version == 1 ||
            (b[1] >> 1) & 3 != 1 ||
            bitrateIndex == 0 ||
            bitrateIndex == 15 ||
            sampleIndex == 3) {
          // APEv2, Lyrics3, ID3v1 and padding are not audio frames. A partial
          // frame count is only a lower bound, never a reason to reject a file.
          return null;
        }
        final bitrate = (version == 3
            ? const [
                0,
                32,
                40,
                48,
                56,
                64,
                80,
                96,
                112,
                128,
                160,
                192,
                224,
                256,
                320,
              ]
            : const [
                0,
                8,
                16,
                24,
                32,
                40,
                48,
                56,
                64,
                80,
                96,
                112,
                128,
                144,
                160,
              ])[bitrateIndex];
        final sampleRate =
            const [44100, 48000, 32000][sampleIndex] ~/
            (version == 3 ? 1 : (version == 2 ? 2 : 4));
        final frameSize =
            ((version == 3 ? 144000 : 72000) * bitrate ~/ sampleRate) +
            ((b[2] >> 1) & 1);
        if (offset + frameSize > size) return null;
        seconds += (version == 3 ? 1152 : 576) / sampleRate;
        frames++;
        offset += frameSize;
        if (seconds > maxDuration.inSeconds + 0.001) {
          throw const AudioStagingException(
            'The audio exceeds the five-minute limit.',
          );
        }
      }
      if (frames < 3 || offset != size) return null;
      return Duration(microseconds: (seconds * 1000000).round());
    } finally {
      await handle.close().timeout(operationTimeout);
    }
  }

  Future<Directory> recordingDirectory() => _guard(_recordingDirectory);

  Future<Directory> _recordingDirectory() async {
    final documents = await getApplicationDocumentsDirectory().timeout(
      operationTimeout,
    );
    final directory = Directory(p.join(documents.path, 'karaok_recordings'));
    if (!await directory.exists().timeout(operationTimeout)) {
      await directory.create(recursive: true).timeout(operationTimeout);
    }
    return directory;
  }

  Future<void> discard() => _guard(_discard);

  Future<void> _discard() async {
    final item = current;
    current = null;
    if (item?.temporary == true && item?.bytes == null) {
      final file = File(item!.path);
      if (await file.exists().timeout(operationTimeout)) {
        await file.delete().timeout(operationTimeout);
      }
    }
  }

  Future<bool> currentIsAvailable() async {
    final item = current;
    if (item == null) return false;
    if (item.bytes != null) return item.bytes!.isNotEmpty;
    try {
      return await File(item.path).exists().timeout(operationTimeout);
    } catch (_) {
      return false;
    }
  }
}
