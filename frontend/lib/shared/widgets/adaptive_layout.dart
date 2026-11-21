import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_theme.dart';

enum WindowSize { compact, medium, expanded }

WindowSize windowSizeOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < AppBreakpoints.medium) return WindowSize.compact;
  if (width < AppBreakpoints.expanded) return WindowSize.medium;
  return WindowSize.expanded;
}

/// True on tablets and larger windows, where the app shows its sidebar.
bool isTabletOf(BuildContext context) =>
    windowSizeOf(context) != WindowSize.compact;

/// Centres [child] in a readable column on tablets. Phones get [child]
/// untouched, so their layout never changes.
class AdaptiveWidth extends StatelessWidget {
  const AdaptiveWidth({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.expandedContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isTabletOf(context)) return child;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: constraints.maxWidth < maxWidth
              ? constraints.maxWidth
              : maxWidth,
          height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
          child: child,
        ),
      ),
    );
  }
}

class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    super.key,
    required this.primary,
    required this.secondary,
    this.gap = 24,
  });

  final Widget primary, secondary;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (windowSizeOf(context) != WindowSize.expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gap,
        children: [primary, secondary],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: gap,
      children: [
        Expanded(flex: 3, child: primary),
        Expanded(flex: 2, child: secondary),
      ],
    );
  }
}
