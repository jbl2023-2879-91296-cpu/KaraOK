import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/reports/domain/report_values.dart';

void main() {
  test('score formatting never rounds a value across a grade boundary', () {
    expect(reportScoreLabel(79.999), '79.999');
    expect(reportScoreLabel(49.999), '49.999');
    expect(reportScoreLabel(99.999), '99.999');
    expect(reportScoreLabel(88.5), '88.5');
  });
}
