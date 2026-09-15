import 'package:flutter/material.dart';

class LaunchAnimation extends StatefulWidget {
  const LaunchAnimation({super.key});

  @override
  State<LaunchAnimation> createState() => _LaunchAnimationState();
}

class _LaunchAnimationState extends State<LaunchAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
          ),
          child: Image.asset(
            'assets/branding/karaok-icon.png',
            width: 200,
            height: 200,
            excludeFromSemantics: true,
          ),
        ),
        const Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Kara',
                style: TextStyle(color: Color(0xFF4A90D9)),
              ),
              TextSpan(
                text: 'OK',
                style: TextStyle(color: Color(0xFFFF8C00)),
              ),
            ],
          ),
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          semanticsLabel: 'KaraOK',
        ),
        const SizedBox(height: 24),
        Semantics(
          liveRegion: true,
          child: Text('Getting KaraOK ready…', textAlign: TextAlign.center),
        ),
      ],
    ),
  );
}
