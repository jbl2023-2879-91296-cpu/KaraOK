import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';

import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';

/// Shows the device-local allowance and sign-in action in guest mode.
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
        return Container(
          width: double.infinity,
          color: AppColors.peach,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppColors.orangeInk,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      remaining == 0
                          ? 'Guest limit reached. Create an account to continue.'
                          : 'Guest mode: $remaining of ${GuestAssessmentService.maxAttempts} audio evaluations left.',
                      style: const TextStyle(
                        color: AppColors.orangeInk,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignUpScreen()),
                    ),
                    child: const Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (showSignIn)
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      child: const Text(
                        'Sign in',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
