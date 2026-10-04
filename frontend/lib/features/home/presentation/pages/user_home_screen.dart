import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/storage/guest_assessment_store.dart';
import 'package:karaok_app/features/reports/domain/sample_assessments.dart';
import 'package:karaok_app/shared/widgets/brand_logo.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/assessments/data/assessment_api.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_settings_suggestion_screen.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/user_previous_results_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';
import 'package:karaok_app/shared/widgets/guest_banner.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key, this.onOpenRecords, this.resultsLoader});

  final Future<List<dynamic>> Function()? resultsLoader;

  final VoidCallback? onOpenRecords;

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  List<dynamic> _recentAnalysis = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    if (_recentAnalysis.any(
      (item) => item is Map && isSampleAssessment(item),
    )) {
      _recentAnalysis = [];
    }
    if (widget.resultsLoader != null || UserSession.instance.isGuest) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
      try {
        final tests =
            await (widget.resultsLoader?.call() ??
                GuestAssessmentStore.instance.guestHistory());
        final allowSamples =
            !UserSession.instance.isGuest ||
            !await GuestAssessmentService.instance.hasUsedAssessment();
        if (!mounted) return;
        setState(() {
          _recentAnalysis = assessmentHistoryForDisplay(
            tests,
            allowSamples: allowSamples,
          ).take(4).toList();
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadError = 'Could not load your analysis records.';
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });
    final api = AssessmentApi();
    final cached = await api.getCachedAudioTests();
    if (!mounted) return;
    setState(() {
      if (cached != null && cached.isNotEmpty) {
        _recentAnalysis = cached.take(4).toList();
      }
      _loading = cached == null || cached.isEmpty;
    });
    try {
      final tests = await api.getAudioTests();
      if (!mounted) return;
      setState(() {
        _recentAnalysis = assessmentHistoryForDisplay(tests).take(4).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = cached == null || cached.isEmpty
            ? 'Could not load your analysis records.'
            : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const BrandLogo(width: 100, height: 52),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnalysis,
        color: AppColors.orangeInk,
        child: Column(
          children: [
            const GuestBanner(showSignIn: true),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ActionCard(
                      icon: Icons.graphic_eq,
                      title: 'Evaluate Audio Quality',
                      subtitle: 'Record audio or select an audio file',
                      color: AppColors.mint,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AudioTestScreen(),
                          ),
                        );
                        if (mounted) _loadAnalysis();
                      },
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.tune,
                      title: 'Generate Audio Settings Suggestion',
                      subtitle: 'Record or upload audio for suggested settings',
                      color: AppColors.peach,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const AudioSettingsSuggestionScreen(),
                          ),
                        );
                        if (mounted) _loadAnalysis();
                      },
                    ),
                    ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _recentAnalysis.any(
                                    (item) =>
                                        item is Map && isSampleAssessment(item),
                                  )
                                  ? 'Sample assessments'
                                  : 'Recent Analysis',
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap:
                                widget.onOpenRecords ??
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const UserPreviousResultsScreen(),
                                  ),
                                ),
                            child: const Text(
                              'View all',
                              style: TextStyle(
                                color: AppColors.orangeInk,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_recentAnalysis.any(
                        (item) => item is Map && isSampleAssessment(item),
                      ))
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            sampleAssessmentExplanation,
                            style: TextStyle(color: AppColors.muted),
                          ),
                        ),
                      if (_loading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                              color: AppColors.orangeInk,
                            ),
                          ),
                        )
                      else if (_loadError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              _loadError!,
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ),
                        )
                      else if (_recentAnalysis.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No analyses yet. Evaluate your first audio recording!',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ),
                        )
                      else
                        ..._recentAnalysis.map(
                          (item) => _AnalysisListItem(
                            test: Map<String, dynamic>.from(item as Map),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ResultsScreen.fromRecord(
                                  item,
                                  isGuest: UserSession.instance.isGuest,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.ink, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisListItem extends StatelessWidget {
  const _AnalysisListItem({required this.test, required this.onTap});
  final Map<String, dynamic> test;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (test['test_name'] ?? '').toString();
    final date = isSampleAssessment(test)
        ? 'Illustrative sample'
        : (test['created_at'] ?? '').toString();
    final score = test['score'] as num?;
    final status = (test['status'] ?? 'Pending').toString();
    final color = status == 'Acceptable'
        ? AppColors.success
        : status == 'Needs Improvement'
        ? AppColors.orangeInk
        : AppColors.error;
    return Semantics(
      button: true,
      label: 'View analysis $name',
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      status,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      score == null ? '--/100' : '${score.round()}/100',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
