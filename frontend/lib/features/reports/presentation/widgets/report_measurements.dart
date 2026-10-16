import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:karaok_app/features/reports/domain/report_values.dart';

/// Estimated noise level and distortion risk for the recording.
class ReportMeasurements extends StatelessWidget {
  const ReportMeasurements({
    super.key,
    this.noiseLevelDb,
    this.distortionLevel,
  });

  final num? noiseLevelDb;
  final num? distortionLevel;

  @override
  Widget build(BuildContext context) {
    final noise = reportNumber(noiseLevelDb);
    final distortion = reportNumber(distortionLevel);
    return Column(
      children: [
        _Measurement(
          label: 'Estimated noise level',
          value: noise == null
              ? 'Not measured'
              : '${noise.toStringAsFixed(2)} dBFS',
          explanation:
              'Estimated from quiet frames in the recording. '
              'It may be unreliable when the recording has no true quiet section.',
        ),
        const SizedBox(height: 10),
        _Measurement(
          label: 'Estimated distortion risk',
          value: distortion == null
              ? 'Not measured'
              : '${distortion.toStringAsFixed(2)} / 100',
          explanation:
              'An estimated distortion risk score from 0 to 100. '
              'These estimates do not contribute to the five-feature quality score.',
        ),
      ],
    );
  }
}

class _Measurement extends StatelessWidget {
  const _Measurement({
    required this.label,
    required this.value,
    required this.explanation,
  });

  final String label;
  final String value;
  final String explanation;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          explanation,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}
