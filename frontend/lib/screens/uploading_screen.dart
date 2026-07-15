import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/bottom_nav_bar.dart';
import 'results_screen.dart';

class UploadingScreen extends StatefulWidget {
  const UploadingScreen({super.key});

  @override
  State<UploadingScreen> createState() => _UploadingScreenState();
}

class _UploadingScreenState extends State<UploadingScreen>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  Timer? _timer;
  int _selectedNavIndex = 1;
  late AnimationController _iconBounce;

  @override
  void initState() {
    super.initState();
    _iconBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      if (_progress >= 1.0) {
        _timer?.cancel();
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ResultsScreen()),
          );
        });
        return;
      }
      setState(() => _progress += 0.008);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _iconBounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).clamp(0, 100).toInt();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Uploading Audio',
          style: TextStyle(
            color: Color(0xFFFF8C00),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated cloud upload icon
            AnimatedBuilder(
              animation: _iconBounce,
              builder: (_, __) => Transform.translate(
                offset: Offset(0, -6 * _iconBounce.value),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  size: 110,
                  color: Color(0xFFFF8C00),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Uploading Audio...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'please wait',
              style: TextStyle(color: Color(0xFF888888), fontSize: 13),
            ),
            const SizedBox(height: 36),
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 10,
                  backgroundColor: const Color(0xFF2A2A3E),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFFF8C00),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '$pct%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedNavIndex,
        onTap: (i) => setState(() => _selectedNavIndex = i),
      ),
    );
  }
}
