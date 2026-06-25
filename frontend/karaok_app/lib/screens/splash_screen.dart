import 'package:flutter/material.dart';
import 'technician_home_screen.dart';
import 'owner_home_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Logo area
              _buildLogo(),
              const SizedBox(height: 16),
              const Text(
                'Analyze and improve your\nkaraoke sound quality',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 3),
              // Select User Type
              const Text(
                'Select User Type',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              // Technician button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TechnicianHomeScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person, color: Colors.white),
                  label: const Text(
                    'Technician',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E5BB5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Owner button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerHomeScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_outline, color: Colors.white),
                  label: const Text(
                    'Owner',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE07B00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'kara',
                style: TextStyle(
                  color: Color(0xFF4A90D9),
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                ),
              ),
              TextSpan(
                text: 'O',
                style: TextStyle(
                  color: Color(0xFF4A90D9),
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                ),
              ),
              TextSpan(
                text: 'K',
                style: TextStyle(
                  color: Color(0xFFFF8C00),
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _dotDivider(),
            const SizedBox(width: 8),
            const Text(
              'BUILD • TEST • SING',
              style: TextStyle(
                color: Color(0xFFFF8C00),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
            _dotDivider(),
          ],
        ),
      ],
    );
  }

  Widget _dotDivider() {
    return Container(
      width: 24,
      height: 2,
      decoration: BoxDecoration(
        color: const Color(0xFF4A90D9),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
