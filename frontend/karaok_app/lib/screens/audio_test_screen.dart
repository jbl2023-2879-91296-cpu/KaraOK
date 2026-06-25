import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../widgets/waveform_painter.dart';
import '../widgets/bottom_nav_bar.dart';
import 'processing_screen.dart';

class AudioTestScreen extends StatefulWidget {
  const AudioTestScreen({super.key, this.genre});

  /// Optional genre tag passed from the Owner flow
  final String? genre;

  @override
  State<AudioTestScreen> createState() => _AudioTestScreenState();
}

class _AudioTestScreenState extends State<AudioTestScreen>
    with TickerProviderStateMixin {
  bool _isRecording = false;
  int _elapsedSeconds = 0;
  final int _maxSeconds = 300; // 5 minutes
  Timer? _timer;
  int _selectedNavIndex = 1;

  // Waveform data
  final List<double> _waveformBars = List.filled(40, 0.05);
  final Random _random = Random();
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() => _isRecording = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_elapsedSeconds >= _maxSeconds) {
        _stopRecording();
        return;
      }
      setState(() {
        _elapsedSeconds++;
        _updateWaveform();
      });
    });
  }

  void _stopRecording() {
    _timer?.cancel();
    setState(() => _isRecording = false);
    // Navigate to processing screen instead of showing a dialog
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ProcessingScreen()),
    );
  }

  void _updateWaveform() {
    for (int i = 0; i < _waveformBars.length; i++) {
      _waveformBars[i] = 0.1 + _random.nextDouble() * 0.9;
    }
  }



  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progressValue =>
      _maxSeconds > 0 ? _elapsedSeconds / _maxSeconds : 0;

  @override
  Widget build(BuildContext context) {
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
          'Start Audio Test',
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
            onPressed: () => _showInfoDialog(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Instruction text
            const Text(
              'Place the phone near the karaoke\nspeaker and record a sample',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 36),
            // Microphone circle
            _MicCircle(isRecording: _isRecording, pulseController: _pulseController),
            const SizedBox(height: 32),
            // Timer display
            Text(
              '${_formatTime(_elapsedSeconds)} / 5:00',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Recording time 6 sec – 5 minutes',
              style: TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
            const SizedBox(height: 20),
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progressValue,
                  minHeight: 4,
                  backgroundColor: const Color(0xFF2A2A3E),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _isRecording ? const Color(0xFFE91E8C) : const Color(0xFF4A90D9),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Waveform (visible while recording)
            AnimatedOpacity(
              opacity: _isRecording ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              child: SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: CustomPaint(
                    painter: WaveformPainter(bars: _waveformBars),
                    size: const Size(double.infinity, 64),
                  ),
                ),
              ),
            ),
            const Spacer(),
            // Start / Stop button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: _isRecording ? _StopButton(onTap: _stopRecording) : _StartButton(onTap: _startRecording),
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

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('How it works',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text(
          '1. Place your phone near the karaoke speaker.\n'
          '2. Press Start Recording.\n'
          '3. Record between 6 seconds and 5 minutes.\n'
          '4. Press Stop to analyze the audio quality.',
          style: TextStyle(color: Color(0xFFAAAAAA), height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it', style: TextStyle(color: Color(0xFF4A90D9))),
          ),
        ],
      ),
    );
  }
}

// ── Mic circle widget ─────────────────────────────────────────────────────────

class _MicCircle extends StatelessWidget {
  const _MicCircle({
    required this.isRecording,
    required this.pulseController,
  });

  final bool isRecording;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (_, __) {
        final pulse = isRecording ? (0.94 + pulseController.value * 0.06) : 1.0;
        return Transform.scale(
          scale: pulse,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2A2A2A),
              boxShadow: isRecording
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE91E8C).withOpacity(0.35),
                        blurRadius: 30,
                        spreadRadius: 8,
                      ),
                    ]
                  : [],
            ),
            child: Icon(
              Icons.mic,
              size: 64,
              color: isRecording ? const Color(0xFFE91E8C) : const Color(0xFF888888),
            ),
          ),
        );
      },
    );
  }
}

// ── Buttons ───────────────────────────────────────────────────────────────────

class _StartButton extends StatelessWidget {
  const _StartButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.fiber_manual_record, color: Color(0xFFE91E8C), size: 18),
        label: const Text(
          'Start Recording',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E5BB5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.white, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.transparent,
        ),
        child: const Text(
          'Stop',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
