import 'package:flutter/material.dart';

class RecordingChecklist extends StatelessWidget {
  const RecordingChecklist({super.key});

  @override
  Widget build(BuildContext context) => const Card(
    child: ExpansionTile(
      title: Text('Before you record'),
      subtitle: Text('Keep comparisons consistent'),
      children: [
        ListTile(
          leading: Icon(Icons.music_note),
          title: Text('Use the same song segment'),
          subtitle: Text(
            'Different songs and sections can produce different measurements.',
          ),
        ),
        ListTile(
          leading: Icon(Icons.mic),
          title: Text('Keep the recording setup consistent'),
          subtitle: Text(
            'Use the same phone, microphone, position, and distance. Keep the microphone uncovered.',
          ),
        ),
        ListTile(
          leading: Icon(Icons.tune),
          title: Text('Change one setting at a time'),
          subtitle: Text(
            'Keep playback volume and other settings consistent unless they are what you are testing.',
          ),
        ),
        ListTile(
          leading: Icon(Icons.hearing),
          title: Text('Check the surroundings'),
          subtitle: Text(
            'Avoid handling the phone or adding unrelated sounds while recording.',
          ),
        ),
        ListTile(
          leading: Icon(Icons.play_arrow),
          title: Text('Listen before evaluating'),
          subtitle: Text(
            'Preview the recording to check that it contains the intended audio. This checklist does not calibrate the microphone.',
          ),
        ),
      ],
    ),
  );
}
