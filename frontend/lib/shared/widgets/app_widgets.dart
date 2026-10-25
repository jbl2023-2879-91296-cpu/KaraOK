import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_theme.dart';

// Hallmark · existing brand, light utility UI; hierarchy through type and space.
// Pre-emit critique: Philosophy 4, Hierarchy 4, Execution 4,
// Specificity 4, Restraint 5, Variety 3.

/// A keyboard-safe, scrolling page with a readable content width.
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.automaticallyImplyLeading = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: actions,
      automaticallyImplyLeading: automaticallyImplyLeading,
    ),
    bottomNavigationBar: bottomNavigationBar,
    floatingActionButton: floatingActionButton,
    body: SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentWidth,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle != null) ...[
                    Text(
                      subtitle!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
        if (action != null) ...[const SizedBox(height: AppSpacing.sm), action!],
      ],
    ),
  );
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: isLoading ? null : onPressed,
    child: _ButtonContent(label: label, icon: icon, isLoading: isLoading),
  );
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: isLoading ? null : onPressed,
    child: _ButtonContent(label: label, icon: icon, isLoading: isLoading),
  );
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.isLoading,
    this.icon,
  });
  final String label;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: isLoading,
    label: isLoading ? '$label, in progress' : label,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading || icon != null) ...[
            if (isLoading)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, size: 20),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    ),
  );
}

enum AppStatus { neutral, success, warning, error }

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    super.key,
    required this.label,
    this.status = AppStatus.neutral,
  });
  final String label;
  final AppStatus status;

  @override
  Widget build(BuildContext context) {
    final (foreground, background, icon) = switch (status) {
      AppStatus.neutral => (
        AppColors.muted,
        AppColors.surface,
        Icons.info_outline,
      ),
      AppStatus.success => (
        AppColors.success,
        AppColors.mint,
        Icons.check_circle_outline,
      ),
      AppStatus.warning => (
        AppColors.orangeInk,
        AppColors.peach,
        Icons.warning_amber_rounded,
      ),
      AppStatus.error => (
        AppColors.error,
        AppColors.background,
        Icons.error_outline,
      ),
    };
    return Semantics(
      label: '${status.name}: $label',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: foreground),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The caller supplies the rating; this widget invents no scoring thresholds.
class AppScoreBadge extends StatelessWidget {
  const AppScoreBadge({
    super.key,
    required this.score,
    required this.label,
    this.status = AppStatus.neutral,
  }) : assert(score >= 0 && score <= 100);
  final double score;
  final String label;
  final AppStatus status;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: ${score.round()} out of 100',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${score.round()} / 100',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppStatusChip(label: label, status: status),
          ],
        ),
      ),
    ),
  );
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSpacing.touchTarget, color: AppColors.primary),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.xl),
            action!,
          ],
        ],
      ),
    ),
  );
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = 'Something went wrong',
    this.isRetrying = false,
  });
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: AppEmptyState(
      title: title,
      message: message,
      icon: Icons.error_outline,
      action: AppSecondaryButton(
        label: 'Retry',
        icon: Icons.refresh,
        onPressed: onRetry,
        isLoading: isRetrying,
      ),
    ),
  );
}

/// Static by design: respects reduced motion without starting an animation.
class AppLoadingSkeleton extends StatelessWidget {
  const AppLoadingSkeleton({
    super.key,
    this.lines = 3,
    this.semanticLabel = 'Loading content',
  }) : assert(lines > 0);
  final int lines;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: ExcludeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              FractionallySizedBox(
                widthFactor: i == lines - 1 ? .6 : 1,
                child: Container(
                  height: AppSpacing.lg,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
