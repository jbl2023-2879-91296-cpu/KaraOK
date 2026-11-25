import 'package:flutter/material.dart';

class MicCalibrationChip extends StatelessWidget {
  const MicCalibrationChip({super.key, required this.applied});

  final bool applied;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: const Icon(Icons.mic_none, size: 16),
    label: Text(applied ? 'Mic calibrated' : 'Mic not calibrated'),
    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          applied
              ? 'This assessment used the phone’s saved microphone correction.'
              : 'This assessment used the phone’s original microphone response.',
        ),
      ),
    ),
  );
}
