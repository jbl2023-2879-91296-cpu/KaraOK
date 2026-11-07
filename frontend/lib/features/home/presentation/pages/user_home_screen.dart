import 'package:karaok_app/shared/widgets/app_widgets.dart';
import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';
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
  bool _profilePromptDismissed = false;

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
                  horizontal: AppSpacing.page,
                  vertical: AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_profilePromptDismissed &&
                        UserSession.instance.needsProfileCompletion)
                      Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.xl),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AppSectionHeader(
                                title: 'Complete your profile',
                              ),
                              const Text(
                                'Add your personal details in Account. You can do this later.',
                              ),
                              Wrap(
                                children: [
                                  TextButton(
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const ChangePasswordScreen(
                                                editProfile: true,
                                              ),
                                        ),
                                      );
                                      if (mounted) setState(() {});
                                    },
                                    child: const Text('Complete profile'),
                                  ),
                                  TextButton(
                                    onPressed: () => setState(
                                      () => _profilePromptDismissed = true,
                                    ),
                                    child: const Text('Not now'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    _ActionCard(
                      icon: Icons.graphic_eq,
                      title: 'Evaluate Audio Quality',
                      subtitle: 'Evaluate playback sound quality',
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
                    const SizedBox(height: AppSpacing.md),
                    _ActionCard(
                      icon: Icons.tune,
                      title: 'Generate Audio Settings Suggestion',
                      subtitle: 'Enter your positions, evaluate, then adjust',
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
                      const SizedBox(height: AppSpacing.xl),
                      AppSectionHeader(
                        title:
                            _recentAnalysis.any(
                              (item) => item is Map && isSampleAssessment(item),
                            )
                            ? 'Sample assessments'
                            : 'Recent Analysis',
                        action: TextButton(
                          onPressed:
                              widget.onOpenRecords ??
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const UserPreviousResultsScreen(),
                                ),
                              ),
                          child: const Text('View all'),
                        ),
                      ),
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
                        const AppLoadingSkeleton()
                      else if (_loadError != null)
                        AppErrorState(
                          title: _loadError!,
                          message: '',
                          onRetry: _loadAnalysis,
                        )
                      else if (_recentAnalysis.isEmpty)
                        const AppEmptyState(
                          title:
                              'No analyses yet. Evaluate your first audio recording!',
                          message: '',
                          icon: Icons.graphic_eq,
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
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          constraints: const BoxConstraints(minHeight: AppSpacing.touchTarget),
          child: Row(
            children: [
              Icon(icon, color: AppColors.ink, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.muted,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  date,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppStatusChip(
                      label: status,
                      status: status == 'Acceptable'
                          ? AppStatus.success
                          : status == 'Needs Improvement'
                          ? AppStatus.warning
                          : AppStatus.error,
                    ),
                    Text(
                      score == null ? '--/100' : '${score.round()}/100',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
