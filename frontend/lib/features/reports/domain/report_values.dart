/// Report parsing and legacy display rules. Never replaces a saved measurement.
num? reportNumber(Object? value) {
  final number = value is num ? value : num.tryParse('$value');
  return number != null && number.isFinite ? number : null;
}

/// Only an explicit JSON boolean can establish measurement reliability.
bool? reportBool(Object? value) => value is bool ? value : null;

Map<String, dynamic> reportMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<String> reportQualityFailures(Map<dynamic, dynamic> record) {
  final dump = reportMap(record['analysis_dump']);
  final analysis = reportMap(dump['analysis'] ?? record['analysis']);
  for (final assessment in [
    reportMap(record['quality_assessment']),
    reportMap(analysis['quality_assessment']),
  ]) {
    final failures = assessment['failures'];
    if (failures is List) {
      final messages = failures
          .whereType<String>()
          .map((message) => message.trim())
          .where((message) => message.isNotEmpty)
          .toList();
      if (messages.isNotEmpty) return messages;
    }
  }
  return const [];
}

String reportGrade(num? score, String? status) {
  if (reportNumber(score) == null || status == 'not_evaluated') {
    return 'NOT SCORED';
  }
  switch (status) {
    case 'good':
      return 'GOOD';
    case 'good_but_needs_improvement':
      return 'NEEDS IMPROVEMENT';
    case 'bad':
      return 'BAD';
  }
  // Legacy records without a status use the existing empirical score rules.
  if (score! >= 80) return 'GOOD';
  if (score >= 50) return 'NEEDS IMPROVEMENT';
  return 'BAD';
}

/// Display wording for [reportGrade], matching the status names used in
/// Home and Records lists.
String reportGradeLabel(String grade) => switch (grade) {
  'GOOD' => 'Acceptable',
  'NEEDS IMPROVEMENT' => 'Needs Improvement',
  'BAD' => 'Problematic',
  _ => 'Not scored',
};

String reportScoreLabel(num? score) {
  final number = reportNumber(score);
  if (number == null) return '--';
  final formatted = number.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  final rounded = num.parse(formatted);
  // Retain extra precision where rounding would imply another grade or 100.
  if ((number < 50 && rounded >= 50) ||
      (number < 80 && rounded >= 80) ||
      (number < 100 && rounded >= 100)) {
    return number.toString();
  }
  return formatted;
}

int? reportReferenceCount(Object? value) {
  final count = reportNumber(value);
  return count != null && count > 0 && count == count.roundToDouble()
      ? count.toInt()
      : null;
}
