import 'package:karaok_app/app/app_theme.dart';
import 'measurement_guide.dart';
import 'package:flutter/material.dart';
import 'package:karaok_app/features/reports/domain/report_values.dart';

class EmpiricalFeatureTable extends StatelessWidget {
  const EmpiricalFeatureTable({
    super.key,
    required this.features,
    this.referenceRecordingCount,
    this.isSample = false,
  });

  final Map<String, dynamic> features;
  final int? referenceRecordingCount;
  final bool isSample;

  static const _labels = {
    'loudness': 'Loudness',
    'bass': 'Bass',
    'treble': 'Treble',
    'sharpness': 'Sharpness',
    'flatness': 'Flatness',
  };

  static const _units = {
    'loudness': 'LUFS',
    'bass': '%',
    'treble': '%',
    'sharpness': '',
    'flatness': '',
  };

  String _measurement(String key, num value) {
    final decimals = key == 'sharpness' || key == 'flatness' ? 6 : 2;
    final unit = _units[key]!;
    return '${value.toDouble().toStringAsFixed(decimals)}${unit.isEmpty ? '' : ' $unit'}';
  }

  String _statusLabel(String status) => switch (status) {
    'good' => 'Good',
    'good_but_needs_improvement' => 'Needs improvement',
    'bad' => 'Bad',
    _ => 'Not evaluated',
  };

  Color _statusColor(String status) => switch (status) {
    'good' => AppColors.success,
    'good_but_needs_improvement' => AppColors.orangeInk,
    'bad' => AppColors.error,
    _ => AppColors.muted,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Empirical five-feature grading',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isSample
                ? 'Illustrative feature values; no recording was analyzed.'
                : referenceRecordingCount == null
                ? 'Reference size unavailable for this saved assessment'
                : 'Reference derived from $referenceRecordingCount analyzed good-audio recordings',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const MeasurementGuide(),
          const SizedBox(height: 12),
          for (final key in _labels.keys) ...[
            Builder(
              builder: (context) {
                final feature = reportMap(features[key]);
                final value = reportNumber(feature['value']);
                final score = reportNumber(feature['score']);
                final status = feature['status']?.toString() ?? 'not_evaluated';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _labels[key]!,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              value == null
                                  ? 'Not measured'
                                  : _measurement(key, value),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${reportScoreLabel(score)}/100',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _statusColor(status),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          _statusLabel(status),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: _statusColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (key != _labels.keys.last)
              const Divider(height: 1, color: AppColors.outline),
          ],
        ],
      ),
    );
  }
}
