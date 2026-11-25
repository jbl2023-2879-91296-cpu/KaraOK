import 'package:karaok_app/features/calibration/data/mic_calibration_store.dart';
import 'package:karaok_app/features/assessments/data/raw_recording_config.dart';
import 'dart:math' as math;
import 'package:karaok_app/shared/widgets/adaptive_layout.dart';
import 'package:karaok_app/shared/widgets/stage_progress.dart';
import 'package:karaok_app/shared/widgets/app_widgets.dart';
import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'recording_checklist.dart';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/storage/guest_assessment_store.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/assessments/data/assessment_api.dart';
import 'package:karaok_app/features/assessments/data/audio_staging_service.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/reports/domain/report_values.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';
import 'package:karaok_app/features/sound_settings/presentation/pages/settings_recommendation_screen.dart';

const kNoisePreroll = Duration(seconds: 3);
const kNoisyPrerollDbfs = -45.0;

double noisyPrerollThreshold(double? floor) =>
    floor == null ? kNoisyPrerollDbfs : math.max(kNoisyPrerollDbfs, floor + 15);

enum AudioInputState {
  idle,
  requestingPermission,
  noiseCheck,
  recording,
  paused,
  processing,
  selecting,
  staged,
  uploading,
  success,
  failed,
}

enum AudioAnalysisPurpose { qualityEvaluation, settingsSuggestion }

extension AudioAnalysisPurposeDetails on AudioAnalysisPurpose {
  String get pageTitle => switch (this) {
    AudioAnalysisPurpose.qualityEvaluation => 'Evaluate Audio Quality',
    AudioAnalysisPurpose.settingsSuggestion => 'Generate Settings Suggestion',
  };

  String get description => switch (this) {
    AudioAnalysisPurpose.qualityEvaluation =>
      'Record audio or select an audio file to evaluate its sound quality.',
    AudioAnalysisPurpose.settingsSuggestion =>
      'Record playback at your entered knob positions. Evaluate its genre balance, then view Bass and Treble suggestions from the same recording.',
  };

  String get submitLabel => switch (this) {
    AudioAnalysisPurpose.qualityEvaluation => 'Evaluate Audio Quality',
    AudioAnalysisPurpose.settingsSuggestion =>
      'Evaluate Audio and Suggest Settings',
  };

  String get requestValue => switch (this) {
    AudioAnalysisPurpose.qualityEvaluation => 'quality_evaluation',
    AudioAnalysisPurpose.settingsSuggestion => 'settings_suggestion',
  };

  String get successMessage => switch (this) {
    AudioAnalysisPurpose.qualityEvaluation =>
      'Audio uploaded and analyzed successfully.',
    AudioAnalysisPurpose.settingsSuggestion =>
      'Audio uploaded and analyzed for settings successfully.',
  };
}

/// Chooses the result experience without changing the quality-evaluation flow.
Widget audioResultDestination({
  required Map<dynamic, dynamic> record,
  required AudioAnalysisPurpose purpose,
  required bool isGuest,
  bool showEvaluationFirst = false,
  ValueChanged<SettingsSuggestionInput>? onVerify,
}) {
  final rawRecommendation = record['settings_recommendation'];
  if (purpose == AudioAnalysisPurpose.settingsSuggestion &&
      !showEvaluationFirst &&
      reportQualityFailures(record).isEmpty &&
      rawRecommendation is Map) {
    final rawSafetySignals = record['safety_signals'];
    return SettingsRecommendationScreen(
      recommendation: SettingsRecommendation.fromJson(
        Map<String, dynamic>.from(rawRecommendation),
      ),
      safetySignals: rawSafetySignals is Map
          ? Map<String, dynamic>.from(rawSafetySignals)
          : const {},
      onVerify: onVerify,
      assessmentBuilder: (_) =>
          ResultsScreen.fromRecord(record, isGuest: isGuest),
    );
  }
  return ResultsScreen.fromRecord(record, isGuest: isGuest);
}

class AudioTestScreen extends StatefulWidget {
  const AudioTestScreen({
    super.key,
    this.genre,
    this.selectFileOnOpen = false,
    this.purpose = AudioAnalysisPurpose.qualityEvaluation,
    this.settingsSuggestion,
    this.stagingService,
  });
  final String? genre;
  final bool selectFileOnOpen;
  final AudioAnalysisPurpose purpose;
  final SettingsSuggestionInput? settingsSuggestion;
  final AudioStagingService? stagingService;

  @override
  State<AudioTestScreen> createState() => _AudioTestScreenState();
}

class _AudioTestScreenState extends State<AudioTestScreen>
    with WidgetsBindingObserver {
  static const _limit = AudioStagingService.maxDuration;
  static const _interruptionMessage =
      'Recording stopped because the microphone was interrupted. Play the song from another device and try again.';
  static const _backgroundMessage =
      'Recording stopped because KaraOK left the screen. Keep KaraOK open while recording, and play the song from another device.';
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  late final AudioStagingService _staging;
  AudioInputState _state = AudioInputState.idle;
  Duration _elapsed = Duration.zero;
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;
  String? _previewPath;
  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;
  late final _recordingClock = WidgetsBinding.instance.samplingClock
      .stopwatch();
  Timer? _timer;
  Timer? _noiseCheckTimer;
  Timer? _limitTimer;
  StreamSubscription<RecordState>? _recorderStates;
  StreamSubscription<Amplitude>? _amplitudes;
  bool _startingRecorder = false;
  String? _interruptedDuringStart;
  bool _changingPause = false;
  bool _noisy = false;
  String? _message;
  String? _recordingFileName;
  bool _guestLimitDialogVisible = false;

  bool get _recording =>
      _state == AudioInputState.noiseCheck ||
      _state == AudioInputState.recording ||
      _state == AudioInputState.paused;

  bool get _busy => const {
    AudioInputState.requestingPermission,
    AudioInputState.processing,
    AudioInputState.selecting,
    AudioInputState.uploading,
  }.contains(_state);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _staging = widget.stagingService ?? AudioStagingService();
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!await _guestCanAssess()) return;
      if (widget.selectFileOnOpen) await _selectFile();
    });
  }

  Future<bool> _guestCanAssess() async {
    if (!UserSession.instance.isGuest) return true;
    if (await GuestAssessmentService.instance.canAssess()) return true;
    if (!mounted || _guestLimitDialogVisible) return false;

    _guestLimitDialogVisible = true;
    final signIn = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Guest evaluation limit reached'),
        content: const Text(
          'This device has used all three guest audio evaluations. Sign in or create an account to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
    _guestLimitDialogVisible = false;
    if (signIn != true && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    }
    if (signIn == true && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _analysisTicker?.cancel();
    _noiseCheckTimer?.cancel();
    _limitTimer?.cancel();
    _amplitudes?.cancel();
    _recorderStates?.cancel();
    _playerStateSubscription.cancel();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _interruptRecording(background: true);
    }
  }

  void _interruptRecording({bool background = false}) {
    if (!mounted) return;
    final message = background ? _backgroundMessage : _interruptionMessage;
    if (_startingRecorder) {
      if (background || _interruptedDuringStart == null) {
        _interruptedDuringStart = message;
      }
    } else if (_recording) {
      unawaited(_cancelRecording(interruptionMessage: message));
    }
  }

  Future<void> _start() async {
    if (!await _guestCanAssess()) return;
    if (!mounted || _busy || _recording) return;
    setState(() {
      _state = AudioInputState.requestingPermission;
      _message = null;
    });
    try {
      final permission = kIsWeb ? null : await Permission.microphone.request();
      final permissionGranted = kIsWeb
          ? await _recorder.hasPermission()
          : permission!.isGranted;
      if (!permissionGranted) {
        if (!mounted) return;
        setState(() {
          _state = AudioInputState.failed;
          _message = permission?.isPermanentlyDenied == true
              ? 'Microphone permission is permanently denied. Enable it in Settings.'
              : 'Microphone permission is required to record audio.';
        });
        return;
      }
      await _resetPreview();
      _recordingFileName =
          'recording_${DateTime.now().microsecondsSinceEpoch}.wav';
      final path = kIsWeb
          ? ''
          : p.join(
              (await _staging.recordingDirectory()).path,
              _recordingFileName,
            );
      if (!mounted) return;
      _recorderStates ??= _recorder.onStateChanged().listen(
        (state) {
          if (state == RecordState.stop ||
              (state == RecordState.pause &&
                  _state != AudioInputState.paused)) {
            _interruptRecording();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          developer.log(
            'Recorder state error',
            error: error,
            stackTrace: stackTrace,
          );
          _interruptRecording();
        },
      );
      final micFloor =
          (await MicCalibrationStore.instance.load())?.noiseFloorDbfs;
      if (!mounted) return;
      _startingRecorder = true;
      _interruptedDuringStart = null;
      try {
        await _recorder.start(rawRecordingConfig, path: path);
      } finally {
        _startingRecorder = false;
      }
      if (!mounted) return;
      _elapsed = Duration.zero;
      _noisy = false;
      setState(() => _state = AudioInputState.noiseCheck);
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final interruptionMessage =
          lifecycle == AppLifecycleState.hidden ||
              lifecycle == AppLifecycleState.paused
          ? _backgroundMessage
          : _interruptedDuringStart;
      if (interruptionMessage != null) {
        await _cancelRecording(interruptionMessage: interruptionMessage);
        return;
      }
      var levelSum = 0.0;
      var samples = 0;
      _amplitudes = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            if (_state == AudioInputState.noiseCheck &&
                amplitude.current.isFinite) {
              levelSum += amplitude.current;
              samples++;
            }
          });
      _recordingClock
        ..reset()
        ..start();
      _noiseCheckTimer = Timer(kNoisePreroll, () {
        if (!mounted || _state != AudioInputState.noiseCheck) return;
        _amplitudes?.cancel();
        _amplitudes = null;
        setState(() {
          _noisy =
              samples > 0 &&
              levelSum / samples > noisyPrerollThreshold(micFloor);
          _state = AudioInputState.recording;
          _message = 'Start the song now.';
        });
      });
      _scheduleRecordingTimers();
    } catch (e, st) {
      developer.log(
        'Recording initialization failed',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _state = AudioInputState.failed;
          _message = 'Recording could not be started.';
        });
      }
    }
  }

  void _scheduleRecordingTimers() {
    _limitTimer = Timer(
      _limit - _recordingClock.elapsed,
      () => _stop(atLimit: true),
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = _recordingClock.elapsed);
    });
  }

  void _freezeRecordingTime() {
    _recordingClock.stop();
    _elapsed = _recordingClock.elapsed;
    _timer?.cancel();
    _limitTimer?.cancel();
  }

  Future<void> _pauseResume() async {
    if (_changingPause) return;
    _changingPause = true;
    try {
      if (_state == AudioInputState.recording) {
        // The plugin emits the same pause state for both user and OS pauses.
        _freezeRecordingTime();
        setState(() => _state = AudioInputState.paused);
        await _recorder.pause();
      } else if (_state == AudioInputState.paused) {
        await _recorder.resume();
        if (!mounted || _state != AudioInputState.paused) return;
        _recordingClock.start();
        _scheduleRecordingTimers();
        setState(() => _state = AudioInputState.recording);
      }
    } catch (e, st) {
      developer.log('Pause/resume failed', error: e, stackTrace: st);
      _interruptRecording();
    } finally {
      _changingPause = false;
    }
  }

  Future<void> _stop({bool atLimit = false}) async {
    if (!_recording || _changingPause) return;
    if (_recordingClock.elapsed <
        AudioStagingService.minDuration + kNoisePreroll) {
      setState(() => _message = AudioStagingService.tooShortMessage);
      return;
    }
    _freezeRecordingTime();
    _noiseCheckTimer?.cancel();
    setState(() => _state = AudioInputState.processing);
    try {
      final path = await _recorder.stop();
      if (path == null) {
        throw const AudioStagingException(
          'The recorder did not create a file.',
        );
      }
      final staged = kIsWeb
          ? await _staging.stageBrowserRecording(
              path,
              _recordingFileName ?? 'recording.wav',
              noisePrerollSeconds: kNoisePreroll.inSeconds.toDouble(),
            )
          : await _staging.stagePath(
              path,
              AudioSourceType.recording,
              temporary: true,
              noisePrerollSeconds: kNoisePreroll.inSeconds.toDouble(),
            );
      _recordingFileName = null;
      if (mounted) {
        setState(() {
          _elapsed = staged.duration;
          _state = AudioInputState.staged;
          _message = atLimit
              ? 'Recording stopped at the 5-minute limit.'
              : kIsWeb
              ? 'Recording is ready for this browser session.'
              : 'Recording saved in the app\'s local storage.';
        });
      }
    } catch (e, st) {
      developer.log(
        'Stopping/staging recording failed',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _state = AudioInputState.failed;
          _message = e.toString();
        });
      }
    }
  }

  Future<void> _cancelRecording({String? interruptionMessage}) async {
    if (!_recording) return;
    _freezeRecordingTime();
    _noiseCheckTimer?.cancel();
    setState(() {
      _state = AudioInputState.processing;
      _elapsed = Duration.zero;
      if (interruptionMessage != null) _message = interruptionMessage;
    });
    try {
      unawaited(_amplitudes?.cancel());
      _amplitudes = null;
      await _recorder.cancel();
    } catch (error, stackTrace) {
      developer.log(
        'Recorder cancellation failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _recordingFileName = null;
      if (mounted) {
        setState(() {
          _state = _staging.current == null
              ? AudioInputState.idle
              : AudioInputState.staged;
          _message = interruptionMessage ?? 'Recording cancelled.';
        });
      }
    }
  }

  Future<bool> _confirmReplace() async {
    if (_staging.current == null) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace staged audio?'),
            content: const Text(
              'Your current audio will be kept until a valid replacement is ready.',
            ),
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
    if (!await _guestCanAssess()) return;
    if (_busy ||
        _state == AudioInputState.noiseCheck ||
        _state == AudioInputState.recording ||
        _state == AudioInputState.paused ||
        !await _confirmReplace()) {
      return;
    }
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
      if (mounted) {
        setState(() {
          _state = AudioInputState.failed;
          _message = e.message;
        });
      }
    } catch (e, st) {
      developer.log('File selection failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _state = AudioInputState.failed;
          _message = 'The selected file could not be opened.';
        });
      }
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
        final duration = item.isMemoryBacked
            ? await _player.setUrl(item.path)
            : await _player.setFilePath(item.path);
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
    if (mounted) {
      setState(() {
        _state = AudioInputState.idle;
        _elapsed = Duration.zero;
        _message = null;
      });
    }
  }

  void _openVerification(SettingsSuggestionInput input) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioTestScreen(
          purpose: AudioAnalysisPurpose.settingsSuggestion,
          genre: input.genre,
          settingsSuggestion: input,
        ),
      ),
    );
  }

  AnalysisStage _analysisStage = AnalysisStage.preparing;
  double _uploadFraction = 0;
  final _analysisElapsed = Stopwatch();
  Timer? _analysisTicker;

  void _uploadProgress(int sent, int total) {
    if (!mounted || total <= 0) return;
    final fraction = sent / total;
    if (sent >= total) {
      _analysisElapsed
        ..reset()
        ..start();
      _analysisTicker ??= Timer.periodic(const Duration(milliseconds: 500), (
        _,
      ) {
        if (mounted) setState(() {});
      });
      setState(() => _analysisStage = AnalysisStage.analyzing);
    } else if (_analysisStage != AnalysisStage.uploading ||
        (fraction - _uploadFraction).abs() >= .01) {
      _analysisElapsed.stop();
      setState(() {
        _analysisStage = AnalysisStage.uploading;
        _uploadFraction = fraction;
      });
    }
  }

  Future<void> _send() async {
    final item = _staging.current;
    if (item == null ||
        _busy ||
        _state == AudioInputState.noiseCheck ||
        _state == AudioInputState.recording ||
        _state == AudioInputState.paused) {
      return;
    }
    try {
      AudioStagingService.validateDuration(
        item.duration,
        noisePrerollSeconds: item.noisePrerollSeconds,
      );
    } on AudioStagingException catch (error) {
      setState(() => _message = error.message);
      return;
    }
    if (!await _guestCanAssess() || !mounted || _busy) return;
    final isGuest = UserSession.instance.isGuest;
    final available = await _staging.currentIsAvailable();
    if (!mounted || _busy || _staging.current != item) return;
    if (!available) {
      setState(() {
        _state = AudioInputState.failed;
        _message = 'The staged file is no longer available.';
      });
      return;
    }
    setState(() {
      _state = AudioInputState.uploading;
      _analysisStage = AnalysisStage.preparing;
      _uploadFraction = 0;
      _message = null;
    });
    try {
      await _resetPreview();
      final response = await AssessmentApi().submitAudio(
        filePath: item.path,
        fileName: item.fileName,
        fileBytes: item.bytes,
        durationSeconds: item.duration.inSeconds,
        noisePrerollSeconds: item.noisePrerollSeconds,
        genre: widget.settingsSuggestion?.genre ?? widget.genre,
        analysisPurpose: widget.purpose.requestValue,
        guest: isGuest,
        settingsSuggestion: widget.settingsSuggestion,
        onUploadProgress: _uploadProgress,
      );
      if (mounted) setState(() => _analysisStage = AnalysisStage.finishing);
      final completed = response['status'] == 'Completed';
      final result = Map<String, dynamic>.from(response)
        ..['test_name'] = item.fileName
        ..['status'] = response['result_status']
        ..['analysis_purpose'] = widget.purpose.requestValue;
      final isInitialSettingsEvaluation =
          widget.purpose == AudioAnalysisPurpose.settingsSuggestion &&
          widget.settingsSuggestion?.verificationOf == null &&
          widget.settingsSuggestion?.verificationToken == null;
      final destination = completed
          ? audioResultDestination(
              record: result,
              purpose: widget.purpose,
              showEvaluationFirst: isInitialSettingsEvaluation,
              isGuest: isGuest,
              onVerify: _openVerification,
            )
          : null;
      int? guestRemaining;
      if (completed && isGuest) {
        try {
          await GuestAssessmentStore.instance.saveCompleted(result);
        } catch (e, st) {
          developer.log(
            'Guest report could not be stored locally',
            error: e,
            stackTrace: st,
          );
        }
        try {
          await GuestAssessmentService.instance.markAssessmentUsed();
        } catch (e, st) {
          developer.log(
            'Guest allowance could not be persisted',
            error: e,
            stackTrace: st,
          );
        }
        guestRemaining = await GuestAssessmentService.instance
            .remainingAttempts();
      }
      await _staging.discard();
      if (mounted) {
        setState(() {
          _state = completed ? AudioInputState.success : AudioInputState.failed;
          _message = completed
              ? isGuest
                    ? guestRemaining == 0
                          ? '${widget.purpose.successMessage} Create an account to continue.'
                          : '${widget.purpose.successMessage} $guestRemaining guest evaluations left.'
                    : widget.purpose.successMessage
              : 'Audio was uploaded, but analysis could not be completed.';
        });
        if (completed) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => destination!),
          );
        }
      }
    } on TimeoutException catch (e, st) {
      developer.log('Audio upload timed out', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _state = AudioInputState.failed;
          _message =
              'The request timed out. Your audio is still available. Check Records before retrying; analysis may have completed.';
        });
      }
    } on ApiException catch (e, st) {
      developer.log('Audio upload rejected', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _state = AudioInputState.failed;
          _message = e.statusCode == 401
              ? e is SessionExpiredException
                    ? e.message
                    : 'We could not confirm your sign-in. Retry.'
              : e.message;
        });
      }
    } catch (e, st) {
      developer.log(
        'Unexpected audio upload failure',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _state = AudioInputState.failed;
          _message =
              'Could not complete the request. Check your connection and Records before retrying. Your audio has been kept.';
        });
      }
    } finally {
      _analysisTicker?.cancel();
      _analysisTicker = null;
      _analysisElapsed.stop();
    }
  }

  String _time(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final item = _staging.current;
    final recording = _recording;
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Row(
            children: [
              Icon(
                widget.purpose == AudioAnalysisPurpose.qualityEvaluation
                    ? Icons.graphic_eq
                    : Icons.tune,
                color: widget.purpose == AudioAnalysisPurpose.qualityEvaluation
                    ? AppColors.primary
                    : AppColors.orangeInk,
                size: 28,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  widget.purpose.description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
        if (!recording && !_busy) ...[
          const SizedBox(height: AppSpacing.md),
          const RecordingChecklist(),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Play the song from a separate device or karaoke machine.',
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          '${_time(_elapsed)} / 05:00',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Record at least 10 seconds of music after the 3-second noise check. Maximum 5 minutes total. For better results, record 20–30 seconds of continuous music.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (recording) ...[
          if (_state == AudioInputState.noiseCheck)
            const Text(
              "Stay quiet, checking background noise. Don't start the song yet.",
            ),
          if (_noisy)
            const Text(
              "It's noisy here. Hold the phone about 30 cm (1 ft) from the speaker, pointed at it.",
            ),
          LinearProgressIndicator(
            value: _elapsed.inSeconds / _limit.inSeconds,
            color: AppColors.orangeInk,
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _state == AudioInputState.noiseCheck
                      ? null
                      : _pauseResume,
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
        ] else if (item == null) ...[
          AppPrimaryButton(
            onPressed: _busy ? null : _start,
            icon: Icons.mic,
            label: 'Record Audio',
          ),
          const SizedBox(height: AppSpacing.md),
          AppSecondaryButton(
            onPressed: _busy ? null : _selectFile,
            icon: Icons.audio_file,
            label: 'Select Audio File',
          ),
        ],
        if (_busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: StageProgress(
              stage: _state == AudioInputState.uploading
                  ? _analysisStage
                  : AnalysisStage.preparing,
              value: analysisProgress(
                stage: _state == AudioInputState.uploading
                    ? _analysisStage
                    : AnalysisStage.preparing,
                uploadFraction: _uploadFraction,
                elapsedAnalyzing: _analysisElapsed.elapsed,
                audioLength: item?.duration ?? Duration.zero,
              ),
              label: switch (_state) {
                AudioInputState.uploading => switch (_analysisStage) {
                  AnalysisStage.preparing => 'Preparing audio.',
                  AnalysisStage.uploading => 'Uploading audio…',
                  AnalysisStage.analyzing =>
                    'Analyzing audio. Keep this screen open.',
                  AnalysisStage.finishing => 'Preparing your results.',
                },
                AudioInputState.requestingPermission =>
                  'Waiting for microphone permission.',
                AudioInputState.selecting =>
                  'Preparing the selected audio file.',
                _ => 'Preparing your recording.',
              },
            ),
          ),
      ],
    );
    final showStaged =
        item != null &&
        !recording &&
        (!_busy || _state == AudioInputState.uploading);
    return AppPageScaffold(
      title: widget.purpose.pageTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showStaged)
            AdaptiveColumns(
              primary: controls,
              secondary: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSectionHeader(title: item.fileName),
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
                                        .clamp(
                                          0,
                                          _previewDuration.inMilliseconds,
                                        )
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
                            onPressed: _busy ? null : _preview,
                            icon: Icon(
                              _player.playing ? Icons.pause : Icons.play_arrow,
                            ),
                            label: Text(
                              _player.playing
                                  ? 'Pause'
                                  : _previewPosition > Duration.zero
                                  ? 'Resume'
                                  : 'Play',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _busy ? null : _start,
                            icon: const Icon(Icons.mic),
                            label: const Text('Record Again'),
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
                            label: const Text('Choose Another File'),
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
                                : widget.purpose.submitLabel,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            controls,
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: _message == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: Semantics(
                      liveRegion: true,
                      child: AppStatusChip(
                        label: _message!,
                        status: _state == AudioInputState.success
                            ? AppStatus.success
                            : AppStatus.warning,
                      ),
                    ),
                  ),
          ),
          if (_state == AudioInputState.success &&
              UserSession.instance.isGuest) ...[
            const SizedBox(height: 12),
            FutureBuilder<int>(
              future: GuestAssessmentService.instance.remainingAttempts(),
              builder: (context, snapshot) {
                if ((snapshot.data ?? 0) > 0) {
                  return const SizedBox.shrink();
                }
                return FilledButton.icon(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  ),
                  icon: const Icon(Icons.login),
                  label: const Text('Create Account or Log In'),
                );
              },
            ),
          ],
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
