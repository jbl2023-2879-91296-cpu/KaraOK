import 'package:flutter/material.dart';

/// Custom painter that draws a bar-style audio waveform.
/// [bars] is a list of normalized values (0.0 – 1.0).
class WaveformPainter extends CustomPainter {
  WaveformPainter({required this.bars});

  final List<double> bars;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    final barWidth = (size.width / bars.length) * 0.6;
    final gap = (size.width / bars.length) * 0.4;
    final centerY = size.height / 2;

    for (int i = 0; i < bars.length; i++) {
      final barHeight = (bars[i] * size.height).clamp(4.0, size.height);
      final x = i * (barWidth + gap) + barWidth / 2;

      // Gradient colour: pink on outer bars → blue on inner
      final t = (i / bars.length - 0.5).abs() * 2; // 0 centre → 1 edge
      final color = Color.lerp(
        const Color(0xFF4A90D9), // blue centre
        const Color(0xFFE91E8C), // pink edges
        t,
      )!;

      final paint = Paint()
        ..color = color
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) => true;
}
