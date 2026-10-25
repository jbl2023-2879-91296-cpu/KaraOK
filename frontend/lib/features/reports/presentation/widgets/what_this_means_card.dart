import 'package:flutter/material.dart';
import 'package:karaok_app/features/reports/domain/measurement_glossary.dart';
import 'package:karaok_app/features/reports/domain/report_values.dart';

class WhatThisMeansCard extends StatelessWidget {
  const WhatThisMeansCard({
    super.key,
    required this.features,
    this.isSample = false,
  });
  final Map<String, dynamic> features;
  final bool isSample;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    var compared = 0;
    for (final entry in measurementLabels.entries) {
      final direction = measurementDirection(reportMap(features[entry.key]));
      if (direction == null) continue;
      compared++;
      if (direction != 'within' && lines.length < 3) {
        lines.add(
          '${entry.value}: ${measurementMeaning(entry.value, direction)}',
        );
      }
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What this means',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (isSample)
              const Text(
                'Example only; these are not measurements of your audio.',
              ),
            if (lines.isEmpty)
              Text(
                compared == measurementLabels.length
                    ? 'All sound measurements are within their usual ranges.'
                    : compared == 0
                    ? 'There are no saved ranges to compare with this recording.'
                    : 'The measurements we could compare are within range. Some comparisons are unavailable.',
              ),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line),
              ),
          ],
        ),
      ),
    );
  }
}
