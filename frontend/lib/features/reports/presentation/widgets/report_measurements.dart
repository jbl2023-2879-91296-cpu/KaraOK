import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:karaok_app/features/reports/domain/report_values.dart';
import 'package:karaok_app/features/reports/domain/measurement_bands.dart';
import 'package:karaok_app/features/reports/presentation/widgets/measurement_guide.dart';

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
          guideLabel: 'Noise level',
          label: 'Estimated noise level',
          value: noise == null
              ? 'Not measured'
              : '${noise.toStringAsFixed(2)} dBFS',
          band: noise == null ? null : noiseBand(noise),
          explanation: '$noiseCaution\n$noiseImplication',
        ),
        const SizedBox(height: 10),
        _Measurement(
          guideLabel: 'Distortion risk',
          label: 'Estimated distortion risk',
          value: distortion == null
              ? 'Not measured'
              : '${distortion.toStringAsFixed(2)} / 100',
          band: distortion == null ? null : distortionBand(distortion),
          explanation:
              'An estimate from 0 to 100; lower is better. '
              'Distortion risk does not change the quality score.',
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
    required this.guideLabel,
    this.band,
  });

  final String label;
  final String value;
  final String explanation;
  final String guideLabel;
  final String? band;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => MeasurementGuide.showEstimate(
        context,
        label: guideLabel,
        value: value,
        meaning: '${band ?? 'No estimate is available.'}\n\n$explanation',
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
                const Icon(
                  Icons.info_outline,
                  size: 20,
                  color: AppColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            if (band != null) ...[
              Text(band!, style: const TextStyle(color: AppColors.ink)),
              const SizedBox(height: 6),
            ],
            Text(
              explanation,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
