import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';

import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';

/// Shows the device-local allowance and sign-in action in guest mode.
///
/// A single compact row: status text on the left, account actions on the
/// right, so the banner never takes more than one line of chrome.
class GuestBanner extends StatelessWidget {
  const GuestBanner({super.key, this.showSignIn = false});

  final bool showSignIn;

  @override
  Widget build(BuildContext context) {
    if (!UserSession.instance.isGuest) return const SizedBox.shrink();

    return FutureBuilder<int>(
      future: GuestAssessmentService.instance.remainingAttempts(),
      builder: (context, snapshot) {
        final remaining = snapshot.data ?? GuestAssessmentService.maxAttempts;
        final textStyle = Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.orangeInk);
        final buttonStyle = TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          textStyle: Theme.of(context).textTheme.labelMedium,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
        return Container(
          width: double.infinity,
          color: AppColors.peach,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: AppColors.orangeInk,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  remaining == 0
                      ? 'Guest limit reached'
                      : 'Guest: $remaining of ${GuestAssessmentService.maxAttempts} evaluations left',
                  style: textStyle,
                ),
              ),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      style: buttonStyle,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignUpScreen()),
                      ),
                      child: const Text('Create Account'),
                    ),
                    if (showSignIn)
                      TextButton(
                        style: buttonStyle,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        ),
                        child: const Text('Sign in'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
