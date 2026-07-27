import 'package:flutter/material.dart';

import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';

/// Shows the device-local allowance and sign-in action in guest mode.
class GuestBanner extends StatelessWidget {
  const GuestBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!UserSession.instance.isGuest) return const SizedBox.shrink();

    return FutureBuilder<int>(
      future: GuestAssessmentService.instance.remainingAttempts(),
      builder: (context, snapshot) {
        final remaining = snapshot.data ?? GuestAssessmentService.maxAttempts;
        return Container(
          width: double.infinity,
          color: const Color(0xFF2A1A00),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: Color(0xFFFF9800),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  remaining == 0
                      ? 'Guest limit reached. Create an account to continue.'
                      : 'Guest mode: $remaining of ${GuestAssessmentService.maxAttempts} audio evaluations left.',
                  style: const TextStyle(
                    color: Color(0xFFFF9800),
                    fontSize: 12,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignUpScreen()),
                  );
                },
                child: const Text(
                  'Create Account',
                  style: TextStyle(
                    color: Color(0xFF4A90D9),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
