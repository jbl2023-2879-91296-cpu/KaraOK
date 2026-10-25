import 'report_values.dart';

class GlossaryEntry {
  const GlossaryEntry(this.term, this.definition, this.why, this.good);
  final String term;
  final String definition;
  final String why;
  final String good;
  String get tip => switch (term) {
    'Noise level' =>
      'Try a quieter room, switch off nearby fans and keep the phone in the same position when recording again.',
    'Distortion risk' =>
      'Try lowering the volume or microphone gain one small step, then record the same section again.',
    _ =>
      'Change one setting at a time and compare the same song section again.',
  };
}

/// One source for result rows, measurement help and the glossary.
const measurementGlossary = [
  GlossaryEntry(
    'Quality score and grades',
    'A score out of 100 comparing your sound with well-tuned karaoke systems.',
    'It helps you decide what to check first.',
    '80 or more: good. 50 to below 80: needs improvement. Below 50: needs adjusting. Without a valid score, the recording is not scored.',
  ),
  GlossaryEntry(
    'Loudness',
    'How loud the recording sounds overall.',
    'Very quiet sound can hide voices; very loud sound can be tiring.',
    'Within the range shown for your song type. Louder is not always better.',
  ),
  GlossaryEntry(
    'Bass',
    'How much of the sound comes from low, deep notes.',
    'Too much can sound boomy; too little can sound thin.',
    'Within the range shown, with deep notes that do not cover the voice.',
  ),
  GlossaryEntry(
    'Treble',
    'How much of the sound comes from high, bright notes.',
    'Too much can sound hissy; too little can make voices muffled.',
    'Within the range shown, with clear voices that are comfortable to hear.',
  ),
  GlossaryEntry(
    'Sharpness',
    'How bright or piercing the recording may sound.',
    'Piercing high notes can make singing uncomfortable to listen to.',
    'Within the range shown. A higher value is not always better.',
  ),
  GlossaryEntry(
    'Flatness',
    'Whether the sound is more note-like or more noise-like.',
    'It can help you notice hiss or room noise mixed with the music.',
    'Within the range shown. Clear sustained notes can lower this reading; do not add noise to raise it.',
  ),
  GlossaryEntry(
    'Noise level',
    'An estimate of background sound in the recording.',
    'Hiss, hum and room noise can cover quiet parts. Background noise does not change the quality score.',
    'At or below -60 dBFS: quiet background. Above -60 through -45 dBFS: some background noise. Above -45 dBFS: noisy background; you may hear hiss, hum or room noise.',
  ),
  GlossaryEntry(
    'Distortion risk',
    'An estimate of how likely the sound is to crackle or break up.',
    'Loud parts may sound rough if the volume or microphone gain is too high.',
    'Below 20: low risk, with no obvious crackling or clipping. 20 to below 50: some risk; listen for crackle at loud parts. 50 or more: high risk; try lowering the volume or microphone gain.',
  ),
  GlossaryEntry(
    'Reference range',
    'What well-tuned karaoke systems usually measure.',
    'It gives you a useful comparison for your song type, rather than a knob setting.',
    'A reading inside the saved range. Keep the same song section and phone position when comparing.',
  ),
  GlossaryEntry(
    'LUFS',
    'A unit used to describe how loud a recording sounds overall.',
    'It helps compare recordings even when their loudest moments differ.',
    'Use the loudness range in your report. This is not the volume level in the room.',
  ),
  GlossaryEntry(
    'dB / dBFS',
    'Units for sound levels; dBFS compares a recording with its maximum possible level.',
    'For background noise, a more negative number means a quieter recording.',
    'For estimated noise, a lower reading is quieter. Keep recording distance the same when comparing.',
  ),
  GlossaryEntry(
    'Amplifier profile',
    'The amplifier model and control layout used for your suggested settings.',
    'Different amplifiers can sound different at the same knob position.',
    'Choose the profile that matches your amplifier and its controls.',
  ),
  GlossaryEntry(
    'Recommended settings',
    'Suggested starting positions for your amplifier controls.',
    'They help you try small changes based on your recording.',
    'Adjust by ear, then record the same section again to check whether it sounds better.',
  ),
];

GlossaryEntry glossaryEntry(String term) =>
    measurementGlossary.firstWhere((entry) => entry.term == term);

const measurementLabels = {
  'loudness': 'Loudness',
  'bass': 'Bass',
  'treble': 'Treble',
  'sharpness': 'Sharpness',
  'flatness': 'Flatness',
};

String? measurementDirection(Map<String, dynamic> feature) {
  final value = reportNumber(feature['value']);
  final lower = reportNumber(feature['target_lower']);
  final upper = reportNumber(feature['target_upper']);
  if (value == null || lower == null || upper == null || lower > upper) {
    return null;
  }
  return value < lower
      ? 'below'
      : value > upper
      ? 'above'
      : 'within';
}

String measurementMeaning(String label, String direction) {
  final high = direction == 'above';
  return switch (label) {
    'Loudness' =>
      high
          ? 'louder than usual — the sound may be tiring.'
          : 'quieter than usual — voices may be hard to hear.',
    'Bass' =>
      high
          ? 'more deep bass than usual — the sound may feel boomy.'
          : 'less deep bass than usual — the sound may feel thin.',
    'Treble' =>
      high
          ? 'more bright sound than usual — voices may sound hissy.'
          : 'less bright sound than usual — voices may sound muffled.',
    'Sharpness' =>
      high
          ? 'more brightness or edge than usual — high notes may feel piercing.'
          : 'less brightness or edge than usual — high notes may sound dull.',
    'Flatness' =>
      high
          ? 'more noise-like sound than usual — listen for hiss or room noise.'
          : 'more note-like sound than usual — clear sustained notes can cause this.',
    _ => 'Compare the reading with the range shown.',
  };
}

String reportInterpretation(num? score, String? status) => switch (reportGrade(
  score,
  status,
)) {
  'GOOD' =>
    "Your karaoke sound is in good shape. It's close to the well-tuned systems we compared it with.",
  'NEEDS IMPROVEMENT' =>
    'Your sound is okay but could be better. See the items marked below for what to adjust.',
  'BAD' => 'Your sound needs adjusting. Start with the items marked below.',
  _ => "We couldn't score this recording.",
};
