import 'package:flutter/material.dart';
import '../services/user_session.dart';
import 'login_screen.dart';
import 'owner_home_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              _logo(),
              const SizedBox(height: 16),
              const Text(
                'Analyze and improve your\nkaraoke sound quality',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 14, height: 1.5),
              ),
              const Spacer(flex: 3),
              const Text('Get started', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                  icon: const Icon(Icons.lock_outline, color: Colors.white),
                  label: const Text('Log In / Register', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A90D9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    UserSession.instance.setGuest('owner');
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OwnerHomeScreen()));
                  },
                  icon: const Icon(Icons.visibility_outlined, color: Color(0xFFAAAAAA)),
                  label: const Text('Continue as Guest', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 15, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF3A3A5E), width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _logo() => RichText(
        text: const TextSpan(
          children: [
            TextSpan(text: 'karaO', style: TextStyle(color: Color(0xFF4A90D9), fontSize: 52, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
            TextSpan(text: 'K', style: TextStyle(color: Color(0xFFFF8C00), fontSize: 52, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
          ],
        ),
      );
}
