import 'package:karaok_app/shared/widgets/app_widgets.dart';
import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';
import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/storage/guest_assessment_store.dart';
import 'package:karaok_app/features/reports/domain/sample_assessments.dart';
import 'package:karaok_app/features/reports/domain/report_values.dart';
import 'package:karaok_app/shared/widgets/brand_logo.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/assessments/data/assessment_api.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_settings_suggestion_screen.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/user_previous_results_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';
import 'package:karaok_app/shared/widgets/adaptive_layout.dart';
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

  bool get _showingSamples =>
      _recentAnalysis.any((item) => item is Map && isSampleAssessment(item));

  Future<void> _openEvaluate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AudioTestScreen()),
    );
    if (mounted) _loadAnalysis();
  }

  Future<void> _openSettingsSuggestion() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AudioSettingsSuggestionScreen()),
    );
    if (mounted) _loadAnalysis();
  }

  void _openAllRecords() {
    if (widget.onOpenRecords != null) {
      widget.onOpenRecords!();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UserPreviousResultsScreen()),
    );
  }

  void _openRecord(dynamic item) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          ResultsScreen.fromRecord(item, isGuest: UserSession.instance.isGuest),
    ),
  );

  Widget _profilePrompt({EdgeInsetsGeometry? margin}) => Card(
    margin: margin ?? const EdgeInsets.only(bottom: AppSpacing.xl),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(title: 'Complete your profile'),
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
                          const ChangePasswordScreen(editProfile: true),
                    ),
                  );
                  if (mounted) setState(() {});
                },
                child: const Text('Complete profile'),
              ),
              TextButton(
                onPressed: () => setState(() => _profilePromptDismissed = true),
                child: const Text('Not now'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  bool get _showProfilePrompt =>
      !_profilePromptDismissed && UserSession.instance.needsProfileCompletion;

  /// Loading, error, empty or sample note: everything except the record list.
  Widget? _recentStatus() {
    if (_loading) return const AppLoadingSkeleton();
    if (_loadError != null) {
      return AppErrorState(
        title: _loadError!,
        message: '',
        onRetry: _loadAnalysis,
      );
    }
    if (_recentAnalysis.isEmpty) {
      return const AppEmptyState(
        title: 'No analyses yet. Evaluate your first audio recording!',
        message: '',
        icon: Icons.graphic_eq,
      );
    }
    return null;
  }

  AppSectionHeader _recentHeader() => AppSectionHeader(
    title: _showingSamples ? 'Sample assessments' : 'Recent Analysis',
    action: TextButton(
      onPressed: _openAllRecords,
      child: const Text('View all'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (isTabletOf(context)) return _buildTablet(context);
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
                    if (_showProfilePrompt) _profilePrompt(),
                    _ActionCard(
                      icon: Icons.graphic_eq,
                      title: 'Evaluate Audio Quality',
                      subtitle: 'Evaluate playback sound quality',
                      color: AppColors.mint,
                      onTap: _openEvaluate,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ActionCard(
                      icon: Icons.tune,
                      title: 'Generate Audio Settings Suggestion',
                      subtitle: 'Enter your positions, evaluate, then adjust',
                      color: AppColors.peach,
                      onTap: _openSettingsSuggestion,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _recentHeader(),
                    if (_showingSamples)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          sampleAssessmentExplanation,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    _recentStatus() ??
                        Column(
                          children: [
                            for (final item in _recentAnalysis)
                              _AnalysisListItem(
                                test: Map<String, dynamic>.from(item as Map),
                                onTap: () => _openRecord(item),
                              ),
                          ],
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tablet dashboard: a greeting header, the two main tasks side by side as
  /// large tiles, and recent analyses in a responsive grid.
  Widget _buildTablet(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final session = UserSession.instance;
    final firstName = (session.firstName ?? '').trim();
    final greeting = session.isGuest || firstName.isEmpty
        ? 'Welcome to KaraOK'
        : 'Welcome back, $firstName';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAnalysis,
          color: AppColors.orangeInk,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.xxl,
            ),
            child: AdaptiveWidth(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 880;
                  final columns = wide ? 3 : 2;
                  const gap = AppSpacing.lg;
                  final tileWidth =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(greeting, style: text.headlineMedium),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Check how your karaoke system sounds, then fine-tune it.',
                        style: text.bodyLarge?.copyWith(color: AppColors.muted),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (session.isGuest)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          child: const GuestBanner(showSignIn: true),
                        ),
                      if (session.isGuest)
                        const SizedBox(height: AppSpacing.xl),
                      if (_showProfilePrompt) _profilePrompt(),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: gap,
                          children: [
                            Expanded(
                              child: _FeatureTile(
                                icon: Icons.graphic_eq,
                                eyebrow: 'Evaluate',
                                title: 'Evaluate Audio Quality',
                                subtitle:
                                    'Record a song and get a quality score with a detailed report.',
                                color: AppColors.mint,
                                accent: AppColors.primary,
                                onTap: _openEvaluate,
                              ),
                            ),
                            Expanded(
                              child: _FeatureTile(
                                icon: Icons.tune,
                                eyebrow: 'Tune',
                                title: 'Generate Audio Settings Suggestion',
                                subtitle:
                                    'Enter your knob positions, evaluate, then adjust.',
                                color: AppColors.peach,
                                accent: AppColors.orangeInk,
                                onTap: _openSettingsSuggestion,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      _recentHeader(),
                      if (_showingSamples)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Text(
                            sampleAssessmentExplanation,
                            style: text.bodyMedium?.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      _recentStatus() ??
                          Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (final item in _recentAnalysis)
                                SizedBox(
                                  width: tileWidth,
                                  child: _AnalysisListItem(
                                    test: Map<String, dynamic>.from(
                                      item as Map,
                                    ),
                                    margin: EdgeInsets.zero,
                                    onTap: () => _openRecord(item),
                                  ),
                                ),
                            ],
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
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
  const _AnalysisListItem({
    required this.test,
    required this.onTap,
    this.margin = const EdgeInsets.only(bottom: AppSpacing.md),
  });
  final Map<String, dynamic> test;
  final VoidCallback onTap;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final name = (test['test_name'] ?? '').toString();
    final date = isSampleAssessment(test)
        ? 'Illustrative sample'
        : (test['created_at'] ?? '').toString();
    final failed = reportQualityFailures(test).isNotEmpty;
    final score = reportNumber(test['score']);
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
        margin: margin,
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
                      label: failed ? 'Check failed' : status,
                      status: failed
                          ? AppStatus.neutral
                          : status == 'Acceptable'
                          ? AppStatus.success
                          : status == 'Needs Improvement'
                          ? AppStatus.warning
                          : AppStatus.error,
                    ),
                    if (!failed)
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

/// Large tablet entry point for one of the app's two main tasks.
class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Color color;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      excludeSemantics: true,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.dialog),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                      ),
                      child: Icon(icon, color: accent, size: 28),
                    ),
                    const Spacer(),
                    Text(
                      eyebrow.toUpperCase(),
                      style: text.labelMedium?.copyWith(
                        color: accent,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(title, style: text.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  subtitle,
                  style: text.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const Spacer(),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Text(
                      'Start',
                      style: text.labelLarge?.copyWith(color: accent),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(Icons.arrow_forward, size: 18, color: accent),
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
