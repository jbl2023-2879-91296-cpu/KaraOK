import 'package:flutter/material.dart';
import '../widgets/app_navigation_drawer.dart';
import '../widgets/guest_banner.dart';
import '../services/user_session.dart';
import 'detailed_report_screen.dart';
import 'audio_test_screen.dart';
import 'login_screen.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    this.testName = 'Test #4',
    this.score = 82,
    this.noiseLevelDb = -4.8,
    this.distortionLevel = 0.12,
    this.isGuest = false,
  });

  final String testName;
  final int score;
  final double noiseLevelDb;
  final double distortionLevel;
  final bool isGuest;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
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

  bool get _pass => widget.score >= 60;

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
                                  text: '${widget.score}',
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
                          const Text(
                            'The audio output is clear, stable, and\nwithin optimal quality thresholds.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _MetricBar(
                      label: 'Noise level',
                      tag: 'low',
                      tagColor: const Color(0xFF4CAF50),
                      value: 0.3,
                      valueLabel: '${widget.noiseLevelDb} dB',
                    ),
                    const SizedBox(height: 14),
                    _MetricBar(
                      label: 'Distortion level',
                      tag: 'acceptable',
                      tagColor: const Color(0xFFFF9800),
                      value: 0.45,
                      valueLabel: '${widget.distortionLevel}',
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
                                _pass ? 'PASS' : 'FAIL',
                                style: TextStyle(
                                  color: _pass
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFF44336),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                _pass ? Icons.check_circle : Icons.cancel,
                                color: _pass
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFF44336),
                                size: 20,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    // View Visual Report
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
                                score: widget.score,
                                noiseLevelDb: widget.noiseLevelDb,
                                distortionLevel: widget.distortionLevel,
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
                        child: const Text(
                          'Test another audio',
                          style: TextStyle(
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
                              'Want to save your results?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Create a free account to keep track of all your audio tests.',
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
