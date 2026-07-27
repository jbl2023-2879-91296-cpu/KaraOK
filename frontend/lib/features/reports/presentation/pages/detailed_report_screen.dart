import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:karaok_app/features/assessments/data/assessment_api.dart';

class DetailedReportScreen extends StatefulWidget {
  const DetailedReportScreen({
    super.key,
    this.testName = 'Test #4',
    this.score = 82,
    this.noiseLevelDb = -4.8,
    this.distortionLevel = 0.12,
    this.assessmentId,
    this.visualizationImages = const {},
  });

  final String testName;
  final int score;
  final double noiseLevelDb;
  final double distortionLevel;
  final int? assessmentId;
  final Map<String, String> visualizationImages;

  @override
  State<DetailedReportScreen> createState() => _DetailedReportScreenState();
}

class _DetailedReportScreenState extends State<DetailedReportScreen> {
  final AssessmentApi _api = AssessmentApi();
  late final Future<Uint8List> _waveformImage;
  late final Future<Uint8List> _spectrogramImage;

  @override
  void initState() {
    super.initState();
    _waveformImage = _loadVisualization('waveform');
    _spectrogramImage = _loadVisualization('spectrogram');
  }

  Future<Uint8List> _loadVisualization(String kind) async {
    final encoded = widget.visualizationImages[kind];
    if (encoded != null && encoded.isNotEmpty) {
      return base64Decode(encoded);
    }
    final assessmentId = widget.assessmentId;
    if (assessmentId == null) {
      throw StateError('This analysis does not have a saved visualization.');
    }
    return _api.getAudioVisualization(assessmentId, kind);
  }

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
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        title: const Text(
          'Detailed Report with Visual',
          style: TextStyle(
            color: Color(0xFF4A90D9),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
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
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1628),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E3A5F), width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: _VisualizationImage(image: _waveformImage),
              ),
              const SizedBox(height: 20),
              // Spectrogram Analysis
              const Text(
                'Spectrogram Analysis',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF0A1628),
                  border: Border.all(color: const Color(0xFF1E3A5F), width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: _VisualizationImage(image: _spectrogramImage),
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

class _VisualizationImage extends StatelessWidget {
  const _VisualizationImage({required this.image});

  final Future<Uint8List> image;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: image,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
            width: double.infinity,
            gaplessPlayback: true,
          );
        }
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Visualization is unavailable for this analysis.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
            ),
          );
        }
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFF4A90D9)),
        );
      },
    );
  }
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
