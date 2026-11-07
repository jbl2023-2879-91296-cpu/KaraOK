/// Illustrative display data only. Never pass these records to persistence or APIs.
bool isSampleAssessment(Map<dynamic, dynamic> record) =>
    record['is_sample'] == true;

List<dynamic> assessmentHistoryForDisplay(
  List<dynamic> records, {
  bool allowSamples = true,
}) => records.isEmpty && allowSamples ? sampleAssessments : records;

const sampleAssessmentExplanation =
    'Illustrative results, not your audio. These three samples disappear after your first assessment.';

final List<Map<String, dynamic>> sampleAssessments = List.unmodifiable([
  _sample(
    'Balanced audio',
    'Acceptable',
    'good',
    91,
    [-14.2, 24.5, 18.3, 0.42, 0.08],
    [93, 90, 92, 89, 91],
    -52,
    0.01,
  ),
  _sample(
    'Audio needs improvement',
    'Needs Improvement',
    'good_but_needs_improvement',
    67,
    [-22.4, 38.1, 9.2, 0.28, 0.19],
    [62, 66, 70, 72, 65],
    -35,
    0.06,
  ),
  _sample(
    'Problematic audio',
    'Problematic',
    'bad',
    38,
    [-29.6, 52.6, 4.8, 0.16, 0.41],
    [31, 35, 42, 46, 36],
    -22,
    0.18,
  ),
]);

Map<String, dynamic> _sample(
  String name,
  String label,
  String status,
  int score,
  List<double> values,
  List<int> featureScores,
  double noise,
  double distortion,
) {
  const names = ['loudness', 'bass', 'treble', 'sharpness', 'flatness'];
  // Illustrative reference ranges so sample rows can say high, low or good.
  const ranges = [
    [-18.0, -12.0],
    [20.0, 35.0],
    [12.0, 25.0],
    [0.30, 0.50],
    [0.05, 0.15],
  ];
  return Map.unmodifiable({
    'is_sample': true,
    'test_name': 'Sample: $name',
    'analysis_purpose': 'quality_evaluation',
    'status': label,
    'score': score,
    'noise_level': noise,
    'distortion_level': distortion,
    'empirical_quality': Map.unmodifiable({
      'overall_score': score,
      'overall_status': status,
      'features': Map.unmodifiable({
        for (var i = 0; i < names.length; i++)
          names[i]: Map.unmodifiable({
            'value': values[i],
            'score': featureScores[i],
            'status': status,
            'target_lower': ranges[i][0],
            'target_upper': ranges[i][1],
          }),
      }),
    }),
  });
}
