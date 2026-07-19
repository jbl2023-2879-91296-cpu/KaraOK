import 'package:flutter/material.dart';
import '../widgets/app_navigation_drawer.dart';
import '../services/api_service.dart';

class RecommendedSettingsScreen extends StatefulWidget {
  const RecommendedSettingsScreen({super.key, this.genre = 'Ballad'});
  final String genre;

  @override
  State<RecommendedSettingsScreen> createState() =>
      _RecommendedSettingsScreenState();
}

class _RecommendedSettingsScreenState extends State<RecommendedSettingsScreen> {
  bool _loading = true;
  bool _saving = false;

  late double _volume;
  late double _bass;
  late double _treble;
  late double _flatness;
  late double _sharpness;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
    _fetchFromApi();
  }

  void _loadDefaults() {
    switch (widget.genre) {
      case 'Rock':
        _volume = 0.85;
        _bass = 0.70;
        _treble = 0.75;
        _flatness = 0.55;
        _sharpness = 0.90;
        break;
      case 'Pop':
        _volume = 0.80;
        _bass = 0.60;
        _treble = 0.70;
        _flatness = 0.65;
        _sharpness = 0.80;
        break;
      case 'HipHop':
        _volume = 0.90;
        _bass = 0.85;
        _treble = 0.50;
        _flatness = 0.60;
        _sharpness = 0.75;
        break;
      case 'Classic':
        _volume = 0.65;
        _bass = 0.45;
        _treble = 0.70;
        _flatness = 0.80;
        _sharpness = 0.60;
        break;
      case 'R&B':
        _volume = 0.78;
        _bass = 0.72;
        _treble = 0.62;
        _flatness = 0.68;
        _sharpness = 0.82;
        break;
      default:
        _volume = 0.75;
        _bass = 0.55;
        _treble = 0.65;
        _flatness = 0.70;
        _sharpness = 0.90;
    }
  }

  Future<void> _fetchFromApi() async {
    try {
      final data = await ApiService().getGenreSettings(widget.genre);
      if (!mounted) return;
      setState(() {
        _volume = (data['volume'] as num) / 100.0;
        _bass = (data['bass'] as num) / 100.0;
        _treble = (data['treble'] as num) / 100.0;
        _flatness = (data['flatness'] as num) / 100.0;
        _sharpness = (data['sharpness'] as num) / 100.0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService().saveGenreSettings(
        genre: widget.genre,
        volume: (_volume * 100).round(),
        bass: (_bass * 100).round(),
        treble: (_treble * 100).round(),
        flatness: (_flatness * 100).round(),
        sharpness: (_sharpness * 100).round(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      drawer: const AppNavigationDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: const AppDrawerButton(),
        title: const Text(
          'Recommended Settings',
          style: TextStyle(
            color: Color(0xFFFF8C00),
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    // Genre badge
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2A4A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.music_note,
                            color: Color(0xFFFF8C00),
                            size: 28,
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Genre',
                                style: TextStyle(
                                  color: Color(0xFF888888),
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                widget.genre,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Sliders
                    Expanded(
                      child: ListView(
                        children: [
                          _SliderRow(
                            label: 'Volume',
                            value: _volume,
                            onChanged: (v) => setState(() => _volume = v),
                          ),
                          _SliderRow(
                            label: 'Bass',
                            value: _bass,
                            onChanged: (v) => setState(() => _bass = v),
                          ),
                          _SliderRow(
                            label: 'Treble',
                            value: _treble,
                            onChanged: (v) => setState(() => _treble = v),
                          ),
                          _SliderRow(
                            label: 'Flatness',
                            value: _flatness,
                            onChanged: (v) => setState(() => _flatness = v),
                          ),
                          _SliderRow(
                            label: 'Sharpness',
                            value: _sharpness,
                            onChanged: (v) => setState(() => _sharpness = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Save button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_alt, color: Colors.white),
                        label: Text(
                          _saving ? 'Saving...' : 'Save',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE07B00),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Discard button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Colors.white,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Discard',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).toInt();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Text(
                '$pct%',
                style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFF8C00),
              inactiveTrackColor: const Color(0xFF2A2A3E),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: SliderComponentShape.noOverlay,
              trackHeight: 5,
            ),
            child: Slider(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
