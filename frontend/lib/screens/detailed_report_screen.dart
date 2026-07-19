import 'dart:math';
import 'package:flutter/material.dart';
import '../widgets/app_navigation_drawer.dart';
import '../widgets/waveform_painter.dart';

class DetailedReportScreen extends StatefulWidget {
  const DetailedReportScreen({
    super.key,
    this.testName = 'Test #4',
    this.score = 82,
    this.noiseLevelDb = -4.8,
    this.distortionLevel = 0.12,
  });

  final String testName;
  final int score;
  final double noiseLevelDb;
  final double distortionLevel;

  @override
  State<DetailedReportScreen> createState() => _DetailedReportScreenState();
}

class _DetailedReportScreenState extends State<DetailedReportScreen> {
  // Generate pseudo-random waveform bars for display
  final List<double> _waveformBars = List.generate(
    60,
    (i) => 0.2 + Random(i * 31).nextDouble() * 0.8,
  );

  String get _grade {
    if (widget.score >= 80) return 'GOOD';
    if (widget.score >= 60) return 'FAIR';
    return 'POOR';
  }

  Color get _gradeColor {
    if (widget.score >= 80) return const Color(0xFF4CAF50);
    if (widget.score >= 60) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      drawer: const AppNavigationDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: const AppDrawerButton(),
        title: const Text(
          'Detailed Report with Visual',
          style: TextStyle(
            color: Color(0xFF4A90D9),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Waveform Analysis
              const Text(
                'Waveform Analysis',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1628),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E3A5F), width: 1),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Y-axis labels + waveform
                    Expanded(
                      child: Row(
                        children: [
                          // Y-axis labels
                          Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text(
                                '100',
                                style: TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 9,
                                ),
                              ),
                              Text(
                                '50',
                                style: TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 9,
                                ),
                              ),
                              Text(
                                '0',
                                style: TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: CustomPaint(
                              painter: WaveformPainter(bars: _waveformBars),
                              size: const Size(
                                double.infinity,
                                double.infinity,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Spectrogram Analysis
              const Text(
                'Spectogram Analysis',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 130,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0D0030),
                      Color(0xFF4A0080),
                      Color(0xFFAA2200),
                      Color(0xFFFF6600),
                      Color(0xFFFFCC00),
                    ],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CustomPaint(painter: _SpectrogramPainter()),
                ),
              ),
              const SizedBox(height: 20),
              // Noise level bar
              _MetricBar(
                label: 'Noise level',
                tag: 'low',
                tagColor: const Color(0xFF4CAF50),
                value: 0.3,
                valueLabel: '${widget.noiseLevelDb} dB',
              ),
              const SizedBox(height: 14),
              // Distortion level bar
              _MetricBar(
                label: 'Distortion level',
                tag: 'acceptable',
                tagColor: const Color(0xFFFF9800),
                value: 0.45,
                valueLabel: '${widget.distortionLevel}',
              ),
              const SizedBox(height: 20),
              // Overall score card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Overall Audio Quality Score',
                      style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${widget.score}',
                          style: TextStyle(
                            color: _gradeColor,
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '/100',
                          style: TextStyle(
                            color: _gradeColor.withValues(alpha: 0.7),
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _grade,
                          style: TextStyle(
                            color: _gradeColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Spectrogram placeholder painter ──────────────────────────────────────────

class _SpectrogramPainter extends CustomPainter {
  final Random _rng = Random(42);

  @override
  void paint(Canvas canvas, Size size) {
    final cols = 60;
    final rows = 20;
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    for (int c = 0; c < cols; c++) {
      for (int r = 0; r < rows; r++) {
        final intensity = _rng.nextDouble();
        final color = _spectralColor(intensity);
        canvas.drawRect(
          Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH),
          Paint()..color = color,
        );
      }
    }
  }

  Color _spectralColor(double t) {
    if (t < 0.25) {
      return Color.lerp(
        const Color(0xFF0D0030),
        const Color(0xFF4A0080),
        t * 4,
      )!;
    }
    if (t < 0.5) {
      return Color.lerp(
        const Color(0xFF4A0080),
        const Color(0xFFAA2200),
        (t - 0.25) * 4,
      )!;
    }
    if (t < 0.75) {
      return Color.lerp(
        const Color(0xFFAA2200),
        const Color(0xFFFF6600),
        (t - 0.5) * 4,
      )!;
    }
    return Color.lerp(
      const Color(0xFFFF6600),
      const Color(0xFFFFCC00),
      (t - 0.75) * 4,
    )!;
  }

  @override
  bool shouldRepaint(_SpectrogramPainter old) => false;
}

// ── Shared metric bar ─────────────────────────────────────────────────────────

class _MetricBar extends StatelessWidget {
  const _MetricBar({
    required this.label,
    required this.tag,
    required this.tagColor,
    required this.value,
    required this.valueLabel,
  });

  final String label;
  final String tag;
  final Color tagColor;
  final double value;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            Text(
              tag,
              style: TextStyle(
                color: tagColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: const Color(0xFF2A2A3E),
            valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF4CAF50)),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            valueLabel,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
        ),
      ],
    );
  }
}
