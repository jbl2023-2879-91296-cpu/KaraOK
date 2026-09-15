import 'package:flutter/material.dart';

/// Explanations describe measurements; they do not introduce scoring rules.
class MeasurementGuide extends StatelessWidget {
  const MeasurementGuide({super.key});

  static const explanations = {
    'Loudness':
        'Loudness is reported in LUFS. It describes the recorded audio level, not the sound pressure in the room. Louder does not automatically mean better.',
    'Bass':
        'Bass is the percentage of measured energy in the low-frequency band used by the analysis. It is not a recommended bass knob position.',
    'Treble':
        'Treble is the percentage of measured energy in the high-frequency band used by the analysis. It is not a recommended treble knob position.',
    'Sharpness':
        'Sharpness describes the high-frequency character of the recording using the analysis algorithm. Compare it with the saved reference-based grade; a higher value is not automatically better.',
    'Flatness':
        'Spectral flatness describes how evenly energy is distributed across frequencies. It does not mean the speaker has a flat frequency response. A higher value is not automatically better.',
  };

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ExpansionTile(
      title: const Text('Understand these measurements'),
      subtitle: const Text('Tap a feature for its meaning and limitations'),
      children: [
        for (final entry in explanations.entries)
          ListTile(
            title: Text(entry.key),
            trailing: const Icon(Icons.info_outline),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(entry.key),
                scrollable: true,
                content: Text(
                  '${entry.value}\n\nThe saved feature score describes agreement with its reference recordings. Missing values are unavailable, not zero.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
