import 'package:karaok_app/features/reports/presentation/pages/glossary_screen.dart';
import 'package:karaok_app/features/reports/domain/measurement_glossary.dart';
import 'package:karaok_app/features/reports/presentation/widgets/what_this_means_card.dart';
import 'package:karaok_app/features/reports/domain/sample_assessments.dart';
import 'package:karaok_app/app/app_theme.dart';
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
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    this.testName = 'Audio test',
    this.score,
    this.noiseLevelDb,
    this.noiseReliable,
    this.distortionLevel,
    this.empiricalStatus,
    this.referenceRecordingCount,
    this.featureResults = const {},
    this.isGuest = false,
    this.isSample = false,
    this.assessmentId,
    this.visualizationImages = const {},
    this.settingsRecord,
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
      noiseReliable: reportBool(record['noise_reliable']),
      distortionLevel: reportNumber(record['distortion_level']),
      empiricalStatus: empirical['overall_status']?.toString(),
      referenceRecordingCount: reportReferenceCount(
        empirical['reference_recording_count'] ??
            record['reference_recording_count'],
      ),
      featureResults: features,
      isGuest: isGuest,
      isSample: isSampleAssessment(record),
      assessmentId: isGuest
          ? null
          : reportNumber(record['assessment_id'] ?? record['id'])?.toInt(),
      visualizationImages: isGuest
          ? visualizationValues.map(
              (key, value) => MapEntry(key, value.toString()),
            )
          : const {},
      settingsRecord: record['settings_recommendation'] is Map
          ? Map<String, dynamic>.from(record)
          : null,
    );
  }

  final String testName;
  final num? score;
  final num? noiseLevelDb;
  final bool? noiseReliable;
  final num? distortionLevel;
  final String? empiricalStatus;
  final int? referenceRecordingCount;
  final Map<String, dynamic> featureResults;
  final bool isGuest;
  final bool isSample;
  final int? assessmentId;
  final Map<String, String> visualizationImages;
  final Map<String, dynamic>? settingsRecord;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  void _openGeneratedSettings() {
    final record = widget.settingsRecord;
    if (record == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => audioResultDestination(
          record: record,
          purpose: AudioAnalysisPurpose.settingsSuggestion,
          isGuest: widget.isGuest,
          onVerify: _openVerification,
        ),
      ),
    );
  }

  void _openVerification(SettingsSuggestionInput input) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudioTestScreen(
          purpose: AudioAnalysisPurpose.settingsSuggestion,
          genre: input.genre,
          settingsSuggestion: input,
        ),
      ),
    );
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppShell(initialIndex: 0)),
      (route) => false,
    );
  }

  String get _grade => reportGrade(widget.score, widget.empiricalStatus);

  Color get _gradeColor => switch (_grade) {
    'GOOD' => AppColors.success,
    'NEEDS IMPROVEMENT' => AppColors.orangeInk,
    'BAD' => AppColors.error,
    _ => AppColors.muted,
  };

  String get _scoreLabel => reportScoreLabel(widget.score);

  String get _interpretation =>
      reportInterpretation(widget.score, widget.empiricalStatus);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.isSample,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: widget.isSample ? 'Back' : 'Back to Home',
            onPressed: widget.isSample ? () => Navigator.pop(context) : _goHome,
            icon: const Icon(Icons.arrow_back),
          ),
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('Results'),
          actions: [
            IconButton(
              tooltip: 'Glossary of terms',
              icon: const Icon(Icons.info_outline),
              onPressed: () => GlossaryScreen.open(context),
            ),
          ],
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
                    horizontal: AppSpacing.page,
                    vertical: AppSpacing.lg,
                  ),
                  child: Column(
                    children: [
                      if (widget.isSample) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                sampleAssessmentExplanation,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.muted),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      // Score card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                        ),
                        child: Column(
                          children: [
                            Text(
                              widget.testName,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              'Audio quality score',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.muted),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            RichText(
                              textScaler: MediaQuery.textScalerOf(context),
                              text: TextSpan(
                                style: Theme.of(context).textTheme.bodyMedium,
                                children: [
                                  TextSpan(
                                    text: _scoreLabel,
                                    style: TextStyle(
                                      color: _gradeColor,
                                      fontSize: 56,
                                      height: 1.1,
                                      letterSpacing: 0,
                                      fontWeight: FontWeight.w800,
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
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              reportGradeLabel(_grade),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: _gradeColor),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              widget.isSample
                                  ? 'Example quality score. These are not measurements of your audio.'
                                  : _interpretation,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      WhatThisMeansCard(
                        features: widget.featureResults,
                        isSample: widget.isSample,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (widget.featureResults.isNotEmpty ||
                          widget.referenceRecordingCount != null)
                        EmpiricalFeatureTable(
                          isSample: widget.isSample,
                          features: widget.featureResults,
                          referenceRecordingCount:
                              widget.referenceRecordingCount,
                        ),
                      if (widget.featureResults.isNotEmpty ||
                          widget.referenceRecordingCount != null)
                        const SizedBox(height: AppSpacing.lg),
                      ReportMeasurements(
                        noiseLevelDb: widget.noiseLevelDb,
                        noiseReliable: widget.noiseReliable,
                        distortionLevel: widget.distortionLevel,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // Status row
                      if (widget.settingsRecord != null) ...[
                        OutlinedButton.icon(
                          onPressed: _openGeneratedSettings,
                          icon: const Icon(Icons.tune),
                          label: const Text('Generate Audio Settings'),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      // View Visual Report
                      if (!widget.isSample && widget.score != null)
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 52),
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
                                    noiseReliable: widget.noiseReliable,
                                    distortionLevel: widget.distortionLevel,
                                    assessmentId: widget.assessmentId,
                                    visualizationImages:
                                        widget.visualizationImages,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.mint,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'View Visual Report',
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      // Test another audio
                      if (!widget.isSample)
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 52),
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
                                color: AppColors.outline,
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
                                        color: AppColors.ink,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Test another audio',
                                    style: TextStyle(
                                      color: AppColors.ink,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      // Guest sign-in nudge
                      if (widget.isGuest && !widget.isSample) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                            border: Border.all(
                              color: AppColors.outline,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Guest assessment complete',
                                style: TextStyle(
                                  color: AppColors.ink,
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
                                      color: AppColors.muted,
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
                                    backgroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.control,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'Create Account / Sign In',
                                    style: TextStyle(
                                      color: AppColors.onPrimary,
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
