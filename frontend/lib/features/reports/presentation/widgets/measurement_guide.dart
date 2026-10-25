import 'package:karaok_app/features/reports/domain/measurement_glossary.dart';
import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/features/reports/domain/report_values.dart';

/// Explanations describe measurements; they do not introduce scoring rules.
class MeasurementGuide extends StatelessWidget {
  const MeasurementGuide({super.key});

  static final definitions = {
    for (final label in measurementLabels.values)
      label: glossaryEntry(label).definition,
  };
  static final explanations = {
    for (final label in measurementLabels.values)
      label: glossaryEntry(label).why,
  };

  static String _tip(String label, String? direction) {
    if (direction == null) {
      return 'Keep the same song section, phone position and volume when recording again so you can compare fairly.';
    }
    if (direction == 'within') {
      return 'Keep this setting for now. Use the same song section and phone position to check that the result is repeatable.';
    }
    final high = direction == 'above';
    return switch (label) {
      'Loudness' =>
        high
            ? 'Try lowering playback volume one small step, then record the same section from the same distance.'
            : 'Check the recording distance first. If playback sounds too quiet, raise the volume one small step and record again.',
      'Bass' =>
        high
            ? 'If the sound feels boomy, move the speaker a little farther from the wall or reduce bass one small step, then record again.'
            : 'If low notes sound thin, try raising bass one small step and record the same section again.',
      'Treble' =>
        high
            ? 'If cymbals or voices sound hissy, lower treble one small step and record the same section again.'
            : 'If voices sound muffled, try raising treble one small step and record the same section again.',
      'Sharpness' =>
        high
            ? 'If high notes feel piercing, try lowering treble one small step and compare the same section again.'
            : 'If high notes sound dull, check that the phone microphone is uncovered before changing treble.',
      'Flatness' =>
        high
            ? 'Listen for fan noise or hiss. Record again in a quieter room before changing speaker settings.'
            : 'Try the same song section again. Clear sustained notes can lower this measure; do not add noise to raise it.',
      _ =>
        'Change one setting at a time and compare the same song section again.',
    };
  }

  static Future<void> showEstimate(
    BuildContext context, {
    required String label,
    required String value,
    required String meaning,
  }) {
    final entry = glossaryEntry(label);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        minChildSize: .35,
        maxChildSize: .95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          children: [
            Text(label, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(entry.definition),
            const SizedBox(height: 16),
            Text('Estimated value: $value'),
            const SizedBox(height: 12),
            Text(meaning),
            const SizedBox(height: 12),
            Text(entry.why),
            const SizedBox(height: 12),
            Text("What's good: ${entry.good}"),
            const SizedBox(height: 12),
            Text(entry.tip),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> showMetric(
    BuildContext context, {
    required String label,
    required Map<String, dynamic> feature,
    required String Function(num) format,
    bool isSample = false,
  }) {
    final value = reportNumber(feature['value']);
    final lower = reportNumber(feature['target_lower']);
    final upper = reportNumber(feature['target_upper']);
    final hasRange = lower != null && upper != null && lower <= upper;
    final direction = value == null || !hasRange
        ? null
        : value < lower
        ? 'below'
        : value > upper
        ? 'above'
        : 'within';
    final sound = switch (label) {
      'Loudness' => ('quieter overall', 'louder overall'),
      'Bass' => ('less deep bass', 'more deep bass'),
      'Treble' => ('less high, bright sound', 'more high, bright sound'),
      'Sharpness' => ('less brightness or edge', 'more brightness or edge'),
      'Flatness' => ('more note-like sound', 'more noise-like sound'),
      _ => ('a lower reading', 'a higher reading'),
    };
    final sentence = switch (direction) {
      'above' =>
        'High for this reference range: the recording may have ${sound.$2}.',
      'below' =>
        'Low for this reference range: the recording may have ${sound.$1}.',
      'within' =>
        'Within this reference range: this part of the sound is in line with the reference recordings.',
      _ =>
        value == null
            ? 'No measured value is available, so a comparison cannot be made.'
            : 'The target range is unavailable for this saved assessment, so high, low or within cannot be determined.',
    };
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        minChildSize: .35,
        maxChildSize: .95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              definitions[label] ?? '',
              style: const TextStyle(color: AppColors.muted),
            ),
            if (isSample)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Illustrative values only; no recording was analyzed.',
                ),
              ),
            const SizedBox(height: 20),
            Text(
              'Measured value: ${value == null ? 'Unavailable' : format(value)}',
            ),
            const SizedBox(height: 8),
            Text(
              'Target lower: ${lower == null ? 'Unavailable' : format(lower)}',
            ),
            const SizedBox(height: 8),
            Text(
              'Target upper: ${upper == null ? 'Unavailable' : format(upper)}',
            ),
            if (!hasRange && lower != null && upper != null)
              const Text(
                'The saved target bounds are inconsistent; no comparison is available.',
              ),
            const SizedBox(height: 20),
            Text(
              sentence,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (direction == 'above' || direction == 'below')
              Text('$label: ${measurementMeaning(label, direction!)}'),
            const SizedBox(height: 12),
            Text("What's good: ${glossaryEntry(label).good}"),
            const SizedBox(height: 12),
            Text(_tip(label, direction)),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('More detail'),
              children: [
                Text(
                  '${explanations[label]}\n\nThe target bounds come from the saved feature data. They describe a reference range, not an ideal setting for every recording. Missing values are unavailable, not zero.',
                ),
                const SizedBox(height: 16),
              ],
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ExpansionTile(
      title: const Text('Understand these measurements'),
      subtitle: const Text('Tap a feature for its meaning and limitations'),
      children: [
        for (final entry in explanations.entries)
          ListTile(
            minVerticalPadding: 12,
            minTileHeight: 48,
            title: Text(entry.key),
            subtitle: Text(definitions[entry.key]!),
            trailing: const Icon(Icons.info_outline),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(entry.key),
                scrollable: true,
                content: Text(
                  '${definitions[entry.key]}\n\nMore detail\n${entry.value}\n\nThe saved feature score describes agreement with its reference recordings. Missing values are unavailable, not zero.',
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
