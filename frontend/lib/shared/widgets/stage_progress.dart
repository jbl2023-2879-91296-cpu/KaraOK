import 'dart:math';

import 'package:flutter/material.dart';

enum AnalysisStage { preparing, uploading, analyzing, finishing }

double analysisProgress({
  required AnalysisStage stage,
  double uploadFraction = 0,
  Duration elapsedAnalyzing = Duration.zero,
  required Duration audioLength,
}) {
  final expected = max(20.0, audioLength.inMilliseconds / 1000 * .6);
  return switch (stage) {
    AnalysisStage.preparing => .05,
    AnalysisStage.uploading => .05 + .35 * uploadFraction.clamp(0, 1),
    AnalysisStage.analyzing => min(
      .949,
      .40 +
          .55 *
              (1 -
                  exp(
                    -max(0.0, elapsedAnalyzing.inMilliseconds / 1000) /
                        expected,
                  )),
    ),
    AnalysisStage.finishing => 1.0,
  };
}

class StageProgress extends StatelessWidget {
  const StageProgress({
    super.key,
    required this.stage,
    required this.value,
    required this.label,
  });

  final AnalysisStage stage;
  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final percent = '${(value * 100).floor()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          label: label,
          child: ExcludeSemantics(child: Text(label)),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: value,
          semanticsLabel: label,
          semanticsValue: percent,
        ),
        const SizedBox(height: 4),
        Text(percent, textAlign: TextAlign.end),
      ],
    );
  }
}
