import 'package:record/record.dart';

const rawRecordingConfig = RecordConfig(
  encoder: AudioEncoder.wav,
  sampleRate: 44100,
  numChannels: 1,
  autoGain: false,
  echoCancel: false,
  noiseSuppress: false,
  audioInterruption: AudioInterruptionMode.pause,
);
