import 'package:flutter/material.dart';
import 'package:karaok_app/features/reports/domain/report_values.dart';
import 'package:karaok_app/features/reports/presentation/widgets/empirical_feature_table.dart';
import 'package:karaok_app/features/reports/presentation/widgets/report_measurements.dart';
import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/detailed_report_screen.dart';
import 'package:karaok_app/shared/widgets/guest_banner.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    this.testName = 'Audio test',
    this.score,
    this.noiseLevelDb,
    this.distortionLevel,
    this.empiricalStatus,
    this.referenceRecordingCount,
    this.featureResults = const {},
    this.isGuest = false,
    this.assessmentId,
    this.visualizationImages = const {},
  });

  factory ResultsScreen.fromRecord(
    Map<dynamic, dynamic> record, {
    bool isGuest = false,
  }) {
    final empirical = reportMap(record['empirical_quality']);
    final features = reportMap(empirical['features']);
    final visualizationValues = reportMap(record['visualizations']);
    return ResultsScreen(
      testName: (record['test_name'] ?? record['file_name'] ?? 'Audio test')
          .toString(),
      score:
          reportNumber(empirical['overall_score']) ??
          reportNumber(record['score']),
      noiseLevelDb: reportNumber(record['noise_level']),
      distortionLevel: reportNumber(record['distortion_level']),
      empiricalStatus: empirical['overall_status']?.toString(),
      referenceRecordingCount: reportReferenceCount(
        empirical['reference_recording_count'] ??
            record['reference_recording_count'],
      ),
      featureResults: features,
      isGuest: isGuest,
      assessmentId: isGuest
          ? null
          : reportNumber(record['assessment_id'] ?? record['id'])?.toInt(),
      visualizationImages: isGuest
          ? visualizationValues.map(
              (key, value) => MapEntry(key, value.toString()),
            )
          : const {},
    );
  }

  final String testName;
  final num? score;
  final num? noiseLevelDb;
  final num? distortionLevel;
  final String? empiricalStatus;
  final int? referenceRecordingCount;
  final Map<String, dynamic> featureResults;
  final bool isGuest;
  final int? assessmentId;
  final Map<String, String> visualizationImages;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppShell(initialIndex: 0)),
      (route) => false,
    );
  }

  String get _grade => reportGrade(widget.score, widget.empiricalStatus);

  Color get _gradeColor => switch (_grade) {
    'GOOD' => const Color(0xFF4CAF50),
    'NEEDS IMPROVEMENT' => const Color(0xFFFF9800),
    'BAD' => const Color(0xFFF44336),
    _ => const Color(0xFF888888),
  };

  String get _scoreLabel => reportScoreLabel(widget.score);

  String get _interpretation {
    if (_grade == 'NOT SCORED') {
      return 'No valid score is available for this assessment.';
    }
    return switch (widget.empiricalStatus) {
      'good' =>
        'The saved weighted score is at least 80 against its good-audio reference. Individual feature grades are shown separately.',
      'good_but_needs_improvement' =>
        'The saved weighted score is at least 50 and below 80 against its good-audio reference.',
      'bad' =>
        'The saved weighted score is below 50 against its good-audio reference. This comparison is not a validated perceptual diagnosis.',
      _ =>
        'This is a saved score. Detailed reference information is unavailable for this assessment.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Back to Home',
            onPressed: _goHome,
            icon: const Icon(Icons.arrow_back),
          ),
          backgroundColor: const Color(0xFF0D0D0D),
          elevation: 0,
          title: const Text(
            'Results',
            style: TextStyle(
              color: Color(0xFF4A90D9),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Guest warning banner
              const GuestBanner(),
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
                      if (widget.featureResults.isNotEmpty ||
                          widget.referenceRecordingCount != null)
                        EmpiricalFeatureTable(
                          features: widget.featureResults,
                          referenceRecordingCount:
                              widget.referenceRecordingCount,
                        ),
                      if (widget.featureResults.isNotEmpty ||
                          widget.referenceRecordingCount != null)
                        const SizedBox(height: 20),
                      ReportMeasurements(
                        noiseLevelDb: widget.noiseLevelDb,
                        distortionLevel: widget.distortionLevel,
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
                                    score: widget.score,
                                    empiricalStatus: widget.empiricalStatus,
                                    featureResults: widget.featureResults,
                                    referenceRecordingCount:
                                        widget.referenceRecordingCount,
                                    noiseLevelDb: widget.noiseLevelDb,
                                    distortionLevel: widget.distortionLevel,
                                    assessmentId: widget.assessmentId,
                                    visualizationImages:
                                        widget.visualizationImages,
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
                          onPressed: () async {
                            if (widget.isGuest) {
                              final remaining = await GuestAssessmentService
                                  .instance
                                  .remainingAttempts();
                              if (!context.mounted) return;
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => remaining > 0
                                      ? const AudioTestScreen()
                                      : const LoginScreen(),
                                ),
                                (route) => remaining > 0 && route.isFirst,
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
                          child: widget.isGuest
                              ? FutureBuilder<int>(
                                  future: GuestAssessmentService.instance
                                      .remainingAttempts(),
                                  builder: (context, snapshot) => Text(
                                    (snapshot.data ?? 0) > 0
                                        ? 'Evaluate another audio'
                                        : 'Create Account or Log In',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : const Text(
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
                                'Guest assessment complete',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              FutureBuilder<int>(
                                future: GuestAssessmentService.instance
                                    .remainingAttempts(),
                                builder: (context, snapshot) {
                                  final remaining = snapshot.data ?? 0;
                                  return Text(
                                    remaining > 0
                                        ? '$remaining of ${GuestAssessmentService.maxAttempts} guest audio evaluations remain. Create an account anytime to save future records.'
                                        : 'All three guest audio evaluations are used. Create an account or log in to continue.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF888888),
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  );
                                },
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
      ),
    );
  }
}

// ── Metric bar ────────────────────────────────────────────────────────────────
