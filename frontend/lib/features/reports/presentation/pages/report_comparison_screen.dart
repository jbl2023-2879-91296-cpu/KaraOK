import 'package:flutter/material.dart';
import '../../domain/report_history.dart';
import '../../domain/report_values.dart';

class ReportComparisonScreen extends StatefulWidget {
  const ReportComparisonScreen({super.key, required this.entries});

  final List<ReportHistoryEntry> entries;

  @override
  State<ReportComparisonScreen> createState() => _ReportComparisonScreenState();
}

class _ReportComparisonScreenState extends State<ReportComparisonScreen> {
  int _a = 0;
  int _b = 1;

  String _label(int index) {
    final entry = widget.entries[index];
    final date = entry.createdAt?.toLocal().toString() ?? 'Date unavailable';
    return '${index + 1}. ${entry.name ?? 'Name unavailable'} · $date';
  }

  Widget _selector(
    String label,
    int selected,
    int other,
    ValueChanged<int> change,
  ) {
    return DropdownButtonFormField<int>(
      key: Key('comparison$label$selected'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: 'Report $label'),
      items: [
        for (var i = 0; i < widget.entries.length; i++)
          if (i != other)
            DropdownMenuItem(
              value: i,
              child: Text(
                _label(i),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
      ],
      onChanged: (value) {
        if (value != null) setState(() => change(value));
      },
    );
  }

  num? _value(ReportHistoryEntry entry, String key) {
    final empirical = reportMap(entry.raw['empirical_quality']);
    if (key == 'score') {
      return reportNumber(empirical['overall_score']) ?? entry.score;
    }
    if (key == 'noise_level' || key == 'distortion_level') {
      return reportNumber(entry.raw[key]);
    }
    return reportNumber(
      reportMap(reportMap(empirical['features'])[key])['value'],
    );
  }

  Widget _metric(String key, String title, String unit, int decimals) {
    final a = _value(widget.entries[_a], key);
    final b = _value(widget.entries[_b], key);
    String format(num? value) => value == null
        ? 'Unavailable'
        : '${value.toStringAsFixed(decimals)}${unit.isEmpty ? '' : ' $unit'}';
    final delta = a == null || b == null ? null : b - a;
    final finiteDelta = reportNumber(delta);
    final difference = finiteDelta == null
        ? 'Unavailable'
        : '${finiteDelta > 0 ? '+' : ''}${format(finiteDelta)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'A: ${key == 'score' && a != null ? '${reportScoreLabel(a)}/100' : format(a)}',
            ),
            Text(
              'B: ${key == 'score' && b != null ? '${reportScoreLabel(b)}/100' : format(b)}',
            ),
            Text('Difference (B − A): $difference'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare reports')),
      body: widget.entries.length < 2
          ? const Center(
              child: Text('Two saved reports are needed to compare.'),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _selector('A', _a, _b, (value) => _a = value),
                const SizedBox(height: 16),
                _selector('B', _b, _a, (value) => _b = value),
                TextButton.icon(
                  onPressed: () => setState(() {
                    final previousA = _a;
                    _a = _b;
                    _b = previousA;
                  }),
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Swap A and B'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Differences use saved values. A higher measurement does not necessarily mean better audio. Compare similar recordings and recording conditions. Scores may use different reference profiles.',
                ),
                const SizedBox(height: 12),
                _metric('score', 'Overall score', 'points', 2),
                _metric('loudness', 'Loudness', 'LUFS', 2),
                _metric('bass', 'Bass', '%', 2),
                _metric('treble', 'Treble', '%', 2),
                _metric('sharpness', 'Sharpness', '', 6),
                _metric('flatness', 'Flatness', '', 6),
                _metric('noise_level', 'Estimated noise level', 'dBFS', 2),
                _metric('distortion_level', 'Distortion estimate', 'points', 2),
                const Text(
                  'Noise may be unreliable without a true quiet section. Distortion is a heuristic score, not measured THD.',
                ),
              ],
            ),
    );
  }
}
