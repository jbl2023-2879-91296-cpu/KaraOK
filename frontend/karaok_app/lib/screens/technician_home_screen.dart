import 'package:flutter/material.dart';
import 'audio_test_screen.dart';
import 'previous_results_screen.dart';
import 'login_screen.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/guest_banner.dart';
import '../services/user_session.dart';
import '../services/api_service.dart';

class TechnicianHomeScreen extends StatefulWidget {
  const TechnicianHomeScreen({super.key});

  @override
  State<TechnicianHomeScreen> createState() => _TechnicianHomeScreenState();
}

class _TechnicianHomeScreenState extends State<TechnicianHomeScreen> {
  int _selectedNavIndex = 0;
  List<dynamic> _recentTests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTests();
  }

  Future<void> _loadTests() async {
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

  void _onNavTap(int i) {
    setState(() => _selectedNavIndex = i);
    if (i == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PreviousResultsScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {},
        ),
        title: const Text(
          'Technician',
          style: TextStyle(
            color: Color(0xFF4A90D9),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          if (UserSession.instance.isGuest)
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const LoginScreen(userType: 'technician')),
              ),
              child: const Text('Sign In',
                  style: TextStyle(
                      color: Color(0xFF4A90D9), fontWeight: FontWeight.w700)),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle, color: Colors.white),
              color: const Color(0xFF1C1C2E),
              onSelected: (v) {
                if (v == 'logout') {
                  UserSession.instance.clear();
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/', (route) => false);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(
                    UserSession.instance.name ?? 'User',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Color(0xFFF44336), size: 18),
                      SizedBox(width: 8),
                      Text('Log Out',
                          style: TextStyle(color: Color(0xFFF44336))),
                    ],
                  ),
                ),
              ],
            ),
        ],
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ActionCard(
                icon: Icons.mic,
                title: 'Start Audio Test',
                subtitle: 'Record and Analyze audio quality',
                color: const Color(0xFF1E5BB5),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AudioTestScreen()),
                  );
                  _loadTests(); // refresh after returning
                },
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.folder_open,
                title: 'Upload Audio File',
                subtitle: '',
                color: const Color(0xFF1A6B3C),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Upload coming soon')),
                  );
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
                        fontWeight: FontWeight.w600),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PreviousResultsScreen()),
                    ),
                    child: const Text(
                      'View all',
                      style:
                          TextStyle(color: Color(0xFF4A90D9), fontSize: 13),
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
                        color: Color(0xFF4A90D9)),
                  ),
                )
              else if (_recentTests.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No tests yet. Start your first audio test!',
                      style: TextStyle(color: Color(0xFF666666)),
                    ),
                  ),
                )
              else
                ..._recentTests.map((t) => _AnalysisListItem(test: t)),
            ],
          ),
        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedNavIndex,
        onTap: _onNavTap,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xCCFFFFFF), fontSize: 12)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisListItem extends StatelessWidget {
  const _AnalysisListItem({required this.test});
  final Map<String, dynamic> test;

  @override
  Widget build(BuildContext context) {
    final score  = test['score'] ?? 0;
    final status = test['status'] ?? 'Acceptable';
    final date   = test['created_at'] ?? '';
    final name   = test['test_name'] ?? '';
    final color  = status == 'Acceptable'
        ? const Color(0xFF4CAF50)
        : const Color(0xFFF44336);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(date.toString().length > 16
                    ? date.toString().substring(0, 16)
                    : date.toString(),
                    style: const TextStyle(
                        color: Color(0xFF888888), fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(status,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
              Text('$score/100',
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right,
              color: Color(0xFF666666), size: 20),
        ],
      ),
    );
  }
}

