import 'package:flutter/material.dart';
import '../widgets/app_navigation_drawer.dart';
import 'audio_test_screen.dart';
import 'audio_settings_suggestion_screen.dart';
import 'previous_results_screen.dart';
import '../widgets/guest_banner.dart';
import '../services/user_session.dart';
import '../services/api_service.dart';
import 'results_screen.dart';

class TechnicianHomeScreen extends StatefulWidget {
  const TechnicianHomeScreen({super.key});

  @override
  State<TechnicianHomeScreen> createState() => _TechnicianHomeScreenState();
}

class _TechnicianHomeScreenState extends State<TechnicianHomeScreen> {
  List<dynamic> _recentTests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTests();
  }

  Future<void> _loadTests() async {
    if (UserSession.instance.isGuest) {
      setState(() {
        _recentTests = [];
        _loading = false;
      });
      return;
    }

    try {
      final tests = await ApiService().getAudioTests();
      if (!mounted) return;
      setState(() {
        _recentTests = tests.take(4).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
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
        title: const Text(
          'Technician',
          style: TextStyle(
            color: Color(0xFF4A90D9),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadTests,
        color: const Color(0xFF4A90D9),
        child: Column(
          children: [
            GuestBanner(userType: 'technician'),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ActionCard(
                      icon: Icons.graphic_eq,
                      title: 'Evaluate Audio Quality',
                      subtitle: 'Record audio or select an audio file',
                      color: const Color(0xFF1E5BB5),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AudioTestScreen(),
                          ),
                        );
                        _loadTests(); // refresh after returning
                      },
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.tune,
                      title: 'Generate Audio Settings Suggestion',
                      subtitle: 'Record or upload audio for suggested settings',
                      color: const Color(0xFFE07B00),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const AudioSettingsSuggestionScreen(),
                          ),
                        );
                        if (mounted) _loadTests();
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent Analysis',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PreviousResultsScreen(),
                            ),
                          ),
                          child: const Text(
                            'View all',
                            style: TextStyle(
                              color: Color(0xFF4A90D9),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: Color(0xFF4A90D9),
                          ),
                        ),
                      )
                    else if (_recentTests.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No tests yet. Evaluate your first audio recording!',
                            style: TextStyle(color: Color(0xFF666666)),
                          ),
                        ),
                      )
                    else
                      ..._recentTests.map(
                        (test) => _AnalysisListItem(
                          test: Map<String, dynamic>.from(test as Map),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ResultsScreen.fromRecord(test),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisListItem extends StatelessWidget {
  const _AnalysisListItem({required this.test, required this.onTap});
  final Map<String, dynamic> test;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final score = test['score'] as num?;
    final status = test['status'] ?? 'Acceptable';
    final date = test['created_at'] ?? '';
    final name = test['test_name'] ?? '';
    final color = status == 'Acceptable'
        ? const Color(0xFF4CAF50)
        : status == 'Needs Improvement'
        ? const Color(0xFFFF9800)
        : const Color(0xFFF44336);

    return Semantics(
      button: true,
      label: 'View analysis $name',
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: const Color(0xFF1C1C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date.toString().length > 16
                            ? date.toString().substring(0, 16)
                            : date.toString(),
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      status,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      score == null ? '--/100' : '${score.round()}/100',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF666666),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
