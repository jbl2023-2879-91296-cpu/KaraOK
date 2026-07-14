import 'dart:async';
import 'package:flutter/material.dart';
import '../services/user_session.dart';
import 'results_screen.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _arcController;
  late Timer _stepTimer;
  int _completedSteps = 0;
  double _progress = 0.0;

  final List<String> _steps = [
    'Loading audio',
    'Preprocessing',
    'Feature Extraction',
    'Threshold Evaluation',
    'Generating results',
  ];

  @override
  void initState() {
    super.initState();
    _arcController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Simulate each step completing every 1.2 seconds
    _stepTimer = Timer.periodic(const Duration(milliseconds: 1200), (t) {
      if (!mounted) return;
      if (_completedSteps < _steps.length) {
        setState(() {
          _completedSteps++;
          _progress = _completedSteps / _steps.length;
        });
      } else {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          // Guest users: results shown but not persisted
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ResultsScreen(
                isGuest: UserSession.instance.isGuest,
              ),
            ),
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _arcController.dispose();
    _stepTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).toInt();

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
          'Processing',
          style: TextStyle(
            color: Color(0xFF4A90D9),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              // Circular progress
              SizedBox(
                width: 160,
                height: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 6,
                        backgroundColor: const Color(0xFF2A2A3E),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF4A90D9),
                        ),
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Processing',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text(
                'please wait',
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
              const SizedBox(height: 36),
              // Step list
              ..._steps.asMap().entries.map((e) {
                final done = e.key < _completedSteps;
                final active = e.key == _completedSteps;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        e.value,
                        style: TextStyle(
                          color: done
                              ? Colors.white
                              : active
                                  ? const Color(0xFFAAAAAA)
                                  : const Color(0xFF555555),
                          fontSize: 14,
                        ),
                      ),
                      done
                          ? const Icon(Icons.check_circle,
                              color: Color(0xFF4CAF50), size: 22)
                          : active
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: const Color(0xFF4A90D9),
                                  ),
                                )
                              : const Icon(Icons.radio_button_unchecked,
                                  color: Color(0xFF444444), size: 22),
                    ],
                  ),
                );
              }),
              const Spacer(),
              // Info box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Please wait while we analyze the\naudio signal',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF888888), fontSize: 13, height: 1.5),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
