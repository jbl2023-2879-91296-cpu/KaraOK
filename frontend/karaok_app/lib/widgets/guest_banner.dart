import 'package:flutter/material.dart';
import '../screens/login_screen.dart';
import '../services/user_session.dart';

/// Shows a dismissible banner when the user is in guest mode.
class GuestBanner extends StatelessWidget {
  const GuestBanner({super.key, required this.userType});
  final String userType;

  @override
  Widget build(BuildContext context) {
    if (!UserSession.instance.isGuest) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: const Color(0xFF2A1A00),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFFF9800), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Guest mode — results will not be saved.',
              style: TextStyle(color: Color(0xFFFF9800), fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LoginScreen(userType: userType),
                ),
              );
            },
            child: const Text(
              'Sign In',
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
  }
}
