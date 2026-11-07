import 'package:karaok_app/features/reports/domain/measurement_glossary.dart';
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
    final unit = _units[key]!;
    return '${value.toDouble().toStringAsFixed(2)}${unit.isEmpty ? '' : ' $unit'}';
  }

  Color _statusColor(String status) => switch (status) {
    'good' => AppColors.success,
    'good_but_needs_improvement' => AppColors.orangeInk,
    'bad' => AppColors.error,
    _ => AppColors.muted,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your sound measurements', style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isSample
                ? 'Illustrative feature values; no recording was analyzed.'
                : referenceRecordingCount == null
                ? 'Reference size unavailable for this saved assessment'
                : 'Reference derived from $referenceRecordingCount analyzed recordings',
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
          Text(
            'Tap a measurement for its range and a practical tip.',
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          const MeasurementGuide(),
          const Divider(height: 1, color: AppColors.outline),
          for (final key in _labels.keys) ...[
            Builder(
              builder: (context) {
                final feature = reportMap(features[key]);
                final value = reportNumber(feature['value']);
                final direction = measurementDirection(feature);
                final score = reportNumber(feature['score']);
                final status = feature['status']?.toString() ?? 'not_evaluated';
                final directionLabel = switch (direction) {
                  'above' => 'Too high',
                  'below' => 'Too low',
                  'within' => 'Good',
                  _ => 'Unavailable',
                };
                final color = _statusColor(status);
                return InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  onTap: () => MeasurementGuide.showMetric(
                    context,
                    label: _labels[key]!,
                    feature: feature,
                    format: (value) => _measurement(key, value),
                    isSample: isSample,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                _labels[key]!,
                                style: text.titleSmall,
                              ),
                            ),
                            Text(
                              '${reportScoreLabel(score)}/100',
                              style: text.titleSmall?.copyWith(color: color),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          glossaryEntry(_labels[key]!).definition,
                          style: text.bodySmall?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                value == null
                                    ? 'Not measured'
                                    : _measurement(key, value),
                                style: text.labelMedium?.copyWith(
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            Text(
                              directionLabel,
                              style: text.labelMedium?.copyWith(
                                color: direction == null
                                    ? AppColors.muted
                                    : color,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
