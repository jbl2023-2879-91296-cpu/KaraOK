import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:karaok_app/core/network/api_exception.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/assessments/data/raw_recording_config.dart';
import 'package:karaok_app/features/calibration/data/mic_calibration_api.dart';
import 'package:karaok_app/features/calibration/data/mic_calibration_store.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum _Step { setup, silence, play, upload, result }

class MicCalibrationScreen extends StatefulWidget {
  const MicCalibrationScreen({
    super.key,
    this.store = MicCalibrationStore.instance,
    this.recordAndMeasure,
  });

  final MicCalibrationStore store;
  final Future<Map<String, dynamic>> Function()? recordAndMeasure;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const MicCalibrationScreen()));

  @override
  State<MicCalibrationScreen> createState() => _MicCalibrationScreenState();
}

class _MicCalibrationScreenState extends State<MicCalibrationScreen> {
  _Step _step = _Step.setup;
  bool _playHere = false;
  bool _busy = false;
  int _seconds = 0;
  String? _error;
  String? _message;
  MicCalibration? _measurement;

  Future<void> _countdown(_Step step, int seconds) async {
    final clock = Stopwatch()..start();
    for (var left = seconds; left > 0; left--) {
      if (!mounted) return;
      setState(() {
        _step = step;
        _seconds = left;
      });
      await Future<void>.delayed(
        Duration(seconds: seconds - left + 1) - clock.elapsed,
      );
    }
  }

  Future<Map<String, dynamic>> _recordAndMeasure() async {
    final recorder = AudioRecorder();
    final player = _playHere
        ? AudioPlayer(handleAudioSessionActivation: false)
        : null;
    String? temporary;
    final guest = UserSession.instance.isGuest;
    try {
      if (!await recorder.hasPermission()) {
        throw const ApiException(
          0,
          'Microphone permission is required to calibrate.',
        );
      }
      if (!await recorder.isEncoderSupported(AudioEncoder.wav)) {
        throw const ApiException(
          0,
          'This device cannot record calibration audio in WAV format.',
        );
      }
      await player?.setAsset('assets/calibration/karaok_pink_noise_30s.wav');
      if (!kIsWeb) {
        temporary = path.join(
          (await getTemporaryDirectory()).path,
          'karaok_calibration_${DateTime.now().microsecondsSinceEpoch}.wav',
        );
      }
      await recorder.start(rawRecordingConfig, path: temporary ?? '');
      await _countdown(_Step.silence, 5);
      if (!mounted) throw StateError('Calibration closed');
      final playback = player?.play();
      Object? playbackError;
      if (playback != null) {
        unawaited(
          playback.catchError((Object error) {
            playbackError = error;
          }),
        );
      }
      await _countdown(_Step.play, 15);
      final recording = await recorder.stop();
      await player?.stop();
      if (playbackError != null) throw playbackError!;
      if (!mounted || recording == null) {
        throw const ApiException(
          0,
          'The calibration recording was interrupted. Try again.',
        );
      }
      setState(() => _step = _Step.upload);
      final bytes = kIsWeb ? await XFile(recording).readAsBytes() : null;
      return await MicCalibrationApi().measure(
        recording,
        bytes: bytes,
        guest: guest,
      );
    } finally {
      try {
        await recorder.dispose();
      } finally {
        try {
          await player?.dispose();
        } finally {
          if (temporary != null) {
            final file = File(temporary);
            if (await file.exists()) await file.delete();
          }
        }
      }
    }
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await (widget.recordAndMeasure ?? _recordAndMeasure)();
      final measurement = MicCalibration.fromJson(response, DateTime.now());
      final existing = await widget.store.load();
      if (measurement.correction != null || existing?.correction == null) {
        await widget.store.save(measurement);
      }
      if (!mounted) return;
      setState(() {
        _measurement = measurement;
        _message = response['message'] as String?;
        _step = _Step.result;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Calibration could not be completed. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    setState(() => _busy = true);
    try {
      await widget.store.skip();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The reminder preference could not be saved.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).pop();
      }
    }
  }

  Widget _setup() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '1. Put the phone 1 metre in front of the KaraOK speaker, at speaker height, microphone end pointing at the speaker.',
          ),
          const SizedBox(height: 12),
          const Text(
            '2. Set the machine volume to your marked calibration level, EQ/bass/treble knobs at the middle, echo off.',
          ),
          const SizedBox(height: 12),
          const Text(
            "3. Have the reference sound ready on a laptop or another phone connected to the machine (file: karaok_pink_noise_30s.wav), or connect THIS phone to the machine and use 'Play on this phone'.",
          ),
          const SizedBox(height: 12),
          const Text('4. Keep the room quiet.'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Play on this phone'),
            value: _playHere,
            onChanged: _busy
                ? null
                : (value) => setState(() => _playHere = value ?? false),
          ),
          FilledButton(
            onPressed: _busy ? null : _run,
            child: const Text('Start calibration'),
          ),
          TextButton(
            onPressed: _busy ? null : _skip,
            child: const Text('Skip for now'),
          ),
        ],
      ),
    ),
  );

  Widget _result() {
    final measurement = _measurement!;
    final correction = measurement.correction;
    final centers = correction?['band_centers_hz'] as List?;
    final offsets = correction?['band_offsets_db'] as List?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (correction == null)
          Text(_message ?? 'The server has no reference phone.')
        else ...[
          const Text(
            'Calibrated',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            'Level offset ${(correction['level_offset_db'] as num).toStringAsFixed(1)} dB',
          ),
          if (centers != null && offsets != null)
            for (final (index, offset) in offsets.cast<num>().indexed)
              Row(
                children: [
                  SizedBox(width: 82, child: Text('${centers[index]} Hz')),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (offset.abs() / 12).clamp(0.0, 1.0),
                    ),
                  ),
                  SizedBox(
                    width: 74,
                    child: Text(
                      '${offset.toStringAsFixed(1)} dB',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
        ],
        const SizedBox(height: 16),
        SelectableText('Calibration ID: ${measurement.measurementId}'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Microphone calibration')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                if (_error case final error?) ...[
                  Text(error),
                  FilledButton(onPressed: _run, child: const Text('Try again')),
                  TextButton(
                    onPressed: () => setState(() {
                      _error = null;
                      _step = _Step.setup;
                    }),
                    child: const Text('Back to setup'),
                  ),
                ] else
                  switch (_step) {
                    _Step.setup => _setup(),
                    _Step.silence || _Step.play => Column(
                      children: [
                        Text(
                          _step == _Step.silence
                              ? 'Stay quiet. Measuring this phone\'s microphone…'
                              : 'Start the reference sound now',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text('$_seconds s'),
                      ],
                    ),
                    _Step.upload => const Column(
                      children: [
                        CircularProgressIndicator(),
                        Text('Measuring microphone response…'),
                      ],
                    ),
                    _Step.result => _result(),
                  },
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
