import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/api_service.dart';
import '../services/audio_staging_service.dart';
import '../services/user_session.dart';

enum AudioInputState {
  idle,
  requestingPermission,
  recording,
  paused,
  processing,
  selecting,
  staged,
  uploading,
  success,
  failed,
}

class AudioTestScreen extends StatefulWidget {
  const AudioTestScreen({super.key, this.genre, this.selectFileOnOpen = false});
  final String? genre;
  final bool selectFileOnOpen;

  @override
  State<AudioTestScreen> createState() => _AudioTestScreenState();
}

class _AudioTestScreenState extends State<AudioTestScreen> {
  static const _limit = Duration(minutes: 5);
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _staging = AudioStagingService();
  AudioInputState _state = AudioInputState.idle;
  Duration _elapsed = Duration.zero;
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;
  String? _previewPath;
  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;
  Timer? _timer;
  String? _message;

  bool get _busy => const {
    AudioInputState.requestingPermission,
    AudioInputState.processing,
    AudioInputState.selecting,
    AudioInputState.uploading,
  }.contains(_state);

  @override
  void initState() {
    super.initState();
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
      }
      setState(() {});
    });
    _positionSubscription = _player.positionStream.listen((position) {
      if (mounted) setState(() => _previewPosition = position);
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() => _previewDuration = duration);
      }
    });
    if (widget.selectFileOnOpen)
      WidgetsBinding.instance.addPostFrameCallback((_) => _selectFile());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _playerStateSubscription.cancel();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy ||
        _state == AudioInputState.recording ||
        _state == AudioInputState.paused)
      return;
    setState(() {
      _state = AudioInputState.requestingPermission;
      _message = null;
    });
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      if (!mounted) return;
      setState(() {
        _state = AudioInputState.failed;
        _message = permission.isPermanentlyDenied
            ? 'Microphone permission is permanently denied. Enable it in Settings.'
            : 'Microphone permission is required to record audio.';
      });
      return;
    }
    try {
      await _resetPreview();
      await _staging.discard();
      final dir = await _staging.recordingDirectory();
      final path = p.join(
        dir.path,
        'recording_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      _elapsed = Duration.zero;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!mounted || _state != AudioInputState.recording) return;
        setState(() => _elapsed += const Duration(seconds: 1));
        if (_elapsed >= _limit) await _stop();
      });
      if (mounted) setState(() => _state = AudioInputState.recording);
    } catch (e, st) {
      developer.log(
        'Recording initialization failed',
        error: e,
        stackTrace: st,
      );
      if (mounted)
        setState(() {
          _state = AudioInputState.failed;
          _message = 'Recording could not be started.';
        });
    }
  }

  Future<void> _pauseResume() async {
    try {
      if (_state == AudioInputState.recording) {
        await _recorder.pause();
        setState(() => _state = AudioInputState.paused);
      } else if (_state == AudioInputState.paused) {
        await _recorder.resume();
        setState(() => _state = AudioInputState.recording);
      }
    } catch (e, st) {
      developer.log('Pause/resume failed', error: e, stackTrace: st);
      if (mounted) setState(() => _message = 'The recorder was interrupted.');
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    setState(() => _state = AudioInputState.processing);
    try {
      final path = await _recorder.stop();
      if (path == null)
        throw const AudioStagingException(
          'The recorder did not create a file.',
        );
      await _staging.stagePath(
        path,
        AudioSourceType.recording,
        temporary: true,
      );
      if (mounted) setState(() => _state = AudioInputState.staged);
    } catch (e, st) {
      developer.log(
        'Stopping/staging recording failed',
        error: e,
        stackTrace: st,
      );
      if (mounted)
        setState(() {
          _state = AudioInputState.failed;
          _message = e.toString();
        });
    }
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    try {
      await _recorder.cancel();
    } finally {
      if (mounted)
        setState(() {
          _elapsed = Duration.zero;
          _state = AudioInputState.idle;
          _message = 'Recording cancelled.';
        });
    }
  }

  Future<bool> _confirmReplace() async {
    if (_staging.current == null) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace staged audio?'),
            content: const Text('The current staged file will be removed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _selectFile() async {
    if (_busy ||
        _state == AudioInputState.recording ||
        _state == AudioInputState.paused ||
        !await _confirmReplace())
      return;
    setState(() {
      _state = AudioInputState.selecting;
      _message = null;
    });
    try {
      await _resetPreview();
      final item = await _staging.pickAudio();
      if (!mounted) return;
      setState(
        () => _state = item == null
            ? (_staging.current == null
                  ? AudioInputState.idle
                  : AudioInputState.staged)
            : AudioInputState.staged,
      );
    } on AudioStagingException catch (e, st) {
      developer.log(
        'File selection validation failed',
        error: e,
        stackTrace: st,
      );
      if (mounted)
        setState(() {
          _state = AudioInputState.failed;
          _message = e.message;
        });
    } catch (e, st) {
      developer.log('File selection failed', error: e, stackTrace: st);
      if (mounted)
        setState(() {
          _state = AudioInputState.failed;
          _message = 'The selected file could not be opened.';
        });
    }
  }

  Future<void> _preview() async {
    final item = _staging.current;
    if (item == null) return;
    try {
      if (_player.playing) {
        await _player.pause();
        return;
      }
      if (_previewPath != item.path) {
        final duration = await _player.setFilePath(item.path);
        _previewPath = item.path;
        _previewPosition = Duration.zero;
        _previewDuration = duration ?? item.duration;
      } else if (_player.processingState == ProcessingState.completed ||
          _previewPosition >= _previewDuration) {
        await _player.seek(Duration.zero);
      }
      unawaited(_player.play());
    } catch (e, st) {
      developer.log('Preview failed', error: e, stackTrace: st);
      if (mounted) setState(() => _message = 'This audio could not be played.');
    }
  }

  Future<void> _stopPreview() async {
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  Future<void> _seekPreview(double milliseconds) async {
    await _player.seek(Duration(milliseconds: milliseconds.round()));
  }

  Future<void> _resetPreview() async {
    await _player.stop();
    _previewPath = null;
    _previewPosition = Duration.zero;
    _previewDuration = Duration.zero;
  }

  Future<void> _remove() async {
    await _resetPreview();
    await _staging.discard();
    if (mounted)
      setState(() {
        _state = AudioInputState.idle;
        _elapsed = Duration.zero;
        _message = null;
      });
  }

  Future<void> _send() async {
    final item = _staging.current;
    if (item == null || _state == AudioInputState.uploading) return;
    if (UserSession.instance.isGuest) {
      setState(() => _message = 'Sign in before submitting audio.');
      return;
    }
    if (!await File(item.path).exists()) {
      setState(() {
        _state = AudioInputState.failed;
        _message = 'The staged file is no longer available.';
      });
      return;
    }
    setState(() {
      _state = AudioInputState.uploading;
      _message = null;
    });
    try {
      await _resetPreview();
      await ApiService().submitAudio(
        filePath: item.path,
        durationSeconds: item.duration.inSeconds,
        genre: widget.genre,
      );
      await _staging.discard();
      if (mounted)
        setState(() {
          _state = AudioInputState.success;
          _message = 'Audio uploaded successfully and queued for processing.';
        });
    } on TimeoutException catch (e, st) {
      developer.log('Audio upload timed out', error: e, stackTrace: st);
      if (mounted)
        setState(() {
          _state = AudioInputState.failed;
          _message =
              'The upload timed out. Your staged file is ready to retry.';
        });
    } on ApiException catch (e, st) {
      developer.log('Audio upload rejected', error: e, stackTrace: st);
      if (mounted)
        setState(() {
          _state = AudioInputState.failed;
          _message = e.statusCode == 401
              ? 'Your session expired. Sign in and retry.'
              : e.message;
        });
    } catch (e, st) {
      developer.log(
        'Unexpected audio upload failure',
        error: e,
        stackTrace: st,
      );
      if (mounted)
        setState(() {
          _state = AudioInputState.failed;
          _message = 'Upload failed. Your staged file was kept for retry.';
        });
    }
  }

  String _time(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final item = _staging.current;
    final recording =
        _state == AudioInputState.recording || _state == AudioInputState.paused;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(title: const Text('Audio Input'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${_time(_elapsed)} / 05:00',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (recording) ...[
            LinearProgressIndicator(
              value: _elapsed.inSeconds / _limit.inSeconds,
              color: const Color(0xFFE91E8C),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pauseResume,
                    icon: Icon(
                      _state == AudioInputState.paused
                          ? Icons.play_arrow
                          : Icons.pause,
                    ),
                    label: Text(
                      _state == AudioInputState.paused ? 'Resume' : 'Pause',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _cancelRecording,
              icon: const Icon(Icons.close),
              label: const Text('Cancel recording'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: const Icon(Icons.mic),
              label: const Text('Record Audio'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _selectFile,
              icon: const Icon(Icons.audio_file),
              label: const Text('Select Audio File'),
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (item != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${item.source == AudioSourceType.recording ? 'Recorded' : 'Selected'} • ${item.format} • ${(item.sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB • ${_time(item.duration)}',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(_time(_previewPosition)),
                        Expanded(
                          child: Slider(
                            value: _previewDuration.inMilliseconds == 0
                                ? 0
                                : _previewPosition.inMilliseconds
                                      .clamp(0, _previewDuration.inMilliseconds)
                                      .toDouble(),
                            max: _previewDuration.inMilliseconds > 0
                                ? _previewDuration.inMilliseconds.toDouble()
                                : item.duration.inMilliseconds.toDouble(),
                            onChanged: _previewPath == item.path
                                ? _seekPreview
                                : null,
                          ),
                        ),
                        Text(
                          _time(
                            _previewDuration == Duration.zero
                                ? item.duration
                                : _previewDuration,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _preview,
                          icon: Icon(
                            _player.playing ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(
                            _player.playing
                                ? 'Pause preview'
                                : _previewPosition > Duration.zero
                                ? 'Resume preview'
                                : 'Preview',
                          ),
                        ),
                        TextButton.icon(
                          onPressed:
                              _previewPath == item.path &&
                                  _previewPosition > Duration.zero
                              ? _stopPreview
                              : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop'),
                        ),
                        TextButton.icon(
                          onPressed: _state == AudioInputState.uploading
                              ? null
                              : _remove,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove'),
                        ),
                        TextButton.icon(
                          onPressed: _state == AudioInputState.uploading
                              ? null
                              : _selectFile,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Replace'),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _state == AudioInputState.uploading
                            ? null
                            : _send,
                        icon: const Icon(Icons.cloud_upload),
                        label: Text(
                          _state == AudioInputState.uploading
                              ? 'Uploading…'
                              : 'Send for Processing',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _state == AudioInputState.success
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
            ),
          if (_message?.contains('Settings') == true)
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Open Settings'),
            ),
        ],
      ),
    );
  }
}
