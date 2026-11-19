import 'package:flutter/material.dart';

class NoiseGuardCard extends StatelessWidget {
  const NoiseGuardCard({
    super.key,
    required this.usablePercentage,
    required this.confidence,
    required this.prerollNoiseDbfs,
    this.warnings = const [],
  });

  final double? usablePercentage;
  final String? confidence;
  final double? prerollNoiseDbfs;
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    if (usablePercentage == null &&
        confidence == null &&
        prerollNoiseDbfs == null) {
      return const SizedBox.shrink();
    }

    final title = switch (confidence) {
      'high' => 'Noise guard: High confidence',
      'medium' => 'Noise guard: Medium confidence',
      'low' => 'Noise guard: Low confidence',
      _ => 'Noise guard',
    };

    return SizedBox(
      width: double.infinity,
      child: Card(
        margin: const EdgeInsets.only(top: 20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (usablePercentage case final percentage?)
                Text(
                  '${percentage.toStringAsFixed(0)}% of the recording was used',
                ),
              if (prerollNoiseDbfs == null)
                const Text('No usable background-noise check'),
              if (confidence == 'low')
                const Text(
                  'Results may be affected by background noise. Try again closer to the speaker.',
                ),
              for (final warning in warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(warning),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
