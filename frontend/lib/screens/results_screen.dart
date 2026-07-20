import 'package:flutter/material.dart';
import '../widgets/app_navigation_drawer.dart';
import '../widgets/guest_banner.dart';
import '../services/user_session.dart';
import 'detailed_report_screen.dart';
import 'audio_test_screen.dart';
import 'login_screen.dart';

num? _resultNumber(Object? value) =>
    value is num ? value : num.tryParse('$value');

Map<String, dynamic> _resultMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    this.testName = 'Test #4',
    this.score,
    this.noiseLevelDb,
    this.distortionLevel,
    this.empiricalStatus,
    this.featureResults = const {},
    this.isGuest = false,
  });

  factory ResultsScreen.fromRecord(
    Map<dynamic, dynamic> record, {
    bool isGuest = false,
  }) {
    final empirical = _resultMap(record['empirical_quality']);
    final features = _resultMap(empirical['features']);
    return ResultsScreen(
      testName: (record['test_name'] ?? record['file_name'] ?? 'Audio test')
          .toString(),
      score:
          _resultNumber(empirical['overall_score']) ??
          _resultNumber(record['score']),
      noiseLevelDb: _resultNumber(record['noise_level']),
      distortionLevel: _resultNumber(record['distortion_level']),
      empiricalStatus: empirical['overall_status']?.toString(),
      featureResults: features,
      isGuest: isGuest,
    );
  }

  final String testName;
  final num? score;
  final num? noiseLevelDb;
  final num? distortionLevel;
  final String? empiricalStatus;
  final Map<String, dynamic> featureResults;
  final bool isGuest;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  String get _grade {
    if (widget.empiricalStatus == 'good') return 'GOOD';
    if (widget.empiricalStatus == 'good_but_needs_improvement') {
      return 'NEEDS IMPROVEMENT';
    }
    if (widget.empiricalStatus == 'bad') return 'BAD';
    final score = widget.score;
    if (score == null) return 'NOT SCORED';
    if (score >= 80) return 'GOOD';
    if (score >= 50) return 'NEEDS IMPROVEMENT';
    return 'BAD';
  }

  Color get _gradeColor {
    final score = widget.score;
    if (score == null) return const Color(0xFF888888);
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 50) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  String get _scoreLabel => widget.score?.toDouble().toStringAsFixed(1) ?? '--';

  String get _interpretation => switch (widget.empiricalStatus) {
    'good' =>
      'All five measurements produced a weighted score of at least 80 against the 30-recording good-audio reference.',
    'good_but_needs_improvement' =>
      'The weighted result is usable but one or more measurements are outside the central P05–P95 good range.',
    'bad' =>
      'The weighted score is below 50 or one or more measurements fall outside the observed good-audio envelope.',
    _ =>
      'A score is unavailable because a required audio measurement is missing.',
  };

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      drawer: const AppNavigationDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: const AppDrawerButton(),
        title: const Text(
          'Results',
          style: TextStyle(
            color: Color(0xFF4A90D9),
            fontSize: 18,
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
        child: Column(
          children: [
            // Guest warning banner
            GuestBanner(userType: session.userType ?? 'technician'),
            // Main scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    // Score card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C2E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Audio Quality Score : ${widget.testName}',
                            style: const TextStyle(
                              color: Color(0xFFCCCCCC),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: _scoreLabel,
                                  style: TextStyle(
                                    color: _gradeColor,
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: '/100',
                                  style: TextStyle(
                                    color: _gradeColor.withValues(alpha: 0.7),
                                    fontSize: 28,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _grade,
                            style: TextStyle(
                              color: _gradeColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _interpretation,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (widget.featureResults.isNotEmpty)
                      _EmpiricalFeatureTable(features: widget.featureResults),
                    if (widget.featureResults.isNotEmpty)
                      const SizedBox(height: 20),
                    _MeasuredValue(
                      label: 'Estimated noise level',
                      value: widget.noiseLevelDb == null
                          ? 'Not measured'
                          : '${widget.noiseLevelDb!.toDouble().toStringAsFixed(2)} dBFS',
                    ),
                    const SizedBox(height: 10),
                    _MeasuredValue(
                      label: 'Distortion risk',
                      value: widget.distortionLevel == null
                          ? 'Not measured'
                          : '${widget.distortionLevel!.toDouble().toStringAsFixed(2)}/100',
                    ),
                    const SizedBox(height: 20),
                    // Status row
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C2E),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'STATUS',
                            style: TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 13,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                _grade,
                                style: TextStyle(
                                  color: _gradeColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                widget.score == null
                                    ? Icons.help
                                    : _grade == 'GOOD'
                                    ? Icons.check_circle
                                    : _grade == 'NEEDS IMPROVEMENT'
                                    ? Icons.warning
                                    : Icons.cancel,
                                color: _gradeColor,
                                size: 20,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    // View Visual Report
                    if (widget.score != null)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DetailedReportScreen(
                                  testName: widget.testName,
                                  score: widget.score!.round(),
                                  noiseLevelDb:
                                      widget.noiseLevelDb?.toDouble() ?? 0.0,
                                  distortionLevel:
                                      widget.distortionLevel?.toDouble() ?? 0.0,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E5BB5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'View Visual Report',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Test another audio
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () {
                          if (widget.isGuest) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                              (route) => false,
                            );
                            return;
                          }
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AudioTestScreen(),
                            ),
                            (route) => route.isFirst,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color(0xFF3A3A5E),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          widget.isGuest
                              ? 'Sign in to assess another audio'
                              : 'Test another audio',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    // Guest sign-in nudge
                    if (widget.isGuest) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF3A3A5E),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Guest assessment complete',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'This device has used its one guest assessment. Sign in or create an account to continue.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF888888),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4A90D9),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'Create Account / Sign In',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Metric bar ────────────────────────────────────────────────────────────────

class _EmpiricalFeatureTable extends StatelessWidget {
  const _EmpiricalFeatureTable({required this.features});

  final Map<String, dynamic> features;

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
    'good' => const Color(0xFF4CAF50),
    'good_but_needs_improvement' => const Color(0xFFFF9800),
    'bad' => const Color(0xFFF44336),
    _ => const Color(0xFF888888),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
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
            'Empirical five-feature grading',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Compared with 30 analyzed good-audio recordings',
            style: TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
          const SizedBox(height: 12),
          for (final key in _labels.keys) ...[
            Builder(
              builder: (context) {
                final feature = _resultMap(features[key]);
                final value = _resultNumber(feature['value']);
                final score = _resultNumber(feature['score']);
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
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              value == null
                                  ? 'Not measured'
                                  : _measurement(key, value),
                              style: const TextStyle(
                                color: Color(0xFF888888),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          score == null
                              ? '--/100'
                              : '${score.toDouble().toStringAsFixed(1)}/100',
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
              const Divider(height: 1, color: Color(0xFF303044)),
          ],
        ],
      ),
    );
  }
}

class _MeasuredValue extends StatelessWidget {
  const _MeasuredValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFAAAAAA))),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
