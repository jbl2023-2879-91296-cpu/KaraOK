import 'package:flutter/material.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/guest_banner.dart';
import '../services/user_session.dart';
import '../services/api_service.dart';
import 'genre_select_screen.dart';
import 'audio_test_screen.dart';
import 'owner_previous_results_screen.dart';
import 'login_screen.dart';
import 'change_password_screen.dart';

class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  int _selectedNavIndex = 0;
  List<dynamic> _recentAnalysis = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    if (UserSession.instance.isGuest) {
      setState(() {
        _recentAnalysis = [];
        _loading = false;
        _loadError = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final tests = await ApiService().getAudioTests();
      if (!mounted) return;
      setState(() {
        _recentAnalysis = tests.take(4).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load your analysis records.';
      });
    }
  }

  void _onNavTap(int i) {
    setState(() => _selectedNavIndex = i);
    if (i == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OwnerPreviousResultsScreen()),
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
          'Owner',
          style: TextStyle(
            color: Color(0xFFFF8C00),
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
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              child: const Text(
                'Sign In',
                style: TextStyle(
                  color: Color(0xFFFF8C00),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle, color: Colors.white),
              color: const Color(0xFF1C1C2E),
              onSelected: (v) async {
                if (v == 'change_password') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen(),
                    ),
                  );
                } else if (v == 'logout') {
                  await ApiService().logout();
                  if (!context.mounted) return;
                  UserSession.instance.clear();
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/',
                    (route) => false,
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(
                    UserSession.instance.name ?? 'User',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'change_password',
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Change Password'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Color(0xFFF44336), size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Log Out',
                        style: TextStyle(color: Color(0xFFF44336)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnalysis,
        color: const Color(0xFFFF8C00),
        child: Column(
          children: [
            GuestBanner(userType: 'owner'),
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
                    // Start Audio Test card
                    _ActionCard(
                      icon: Icons.mic,
                      title: 'Start Audio Test',
                      subtitle: 'Record and Analyze audio quality',
                      color: const Color(0xFFE07B00),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const GenreSelectScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    // Upload Audio File card
                    _ActionCard(
                      icon: Icons.folder_open,
                      title: 'Upload Audio File',
                      subtitle: '',
                      color: const Color(0xFF1A6B3C),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const AudioTestScreen(selectFileOnOpen: true),
                          ),
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const OwnerPreviousResultsScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            'View all',
                            style: TextStyle(
                              color: Color(0xFFFF8C00),
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
                            color: Color(0xFFFF8C00),
                          ),
                        ),
                      )
                    else if (_loadError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            _loadError!,
                            style: const TextStyle(color: Color(0xFFF44336)),
                          ),
                        ),
                      )
                    else if (_recentAnalysis.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No analyses yet. Start your first audio test!',
                            style: TextStyle(color: Color(0xFF666666)),
                          ),
                        ),
                      )
                    else
                      ..._recentAnalysis.map(
                        (item) => _AnalysisListItem(test: item),
                      ),
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
          ],
        ),
      ),
    );
  }
}

class _AnalysisListItem extends StatelessWidget {
  const _AnalysisListItem({required this.test});
  final Map<dynamic, dynamic> test;

  @override
  Widget build(BuildContext context) {
    final name = (test['test_name'] ?? '').toString();
    final date = (test['created_at'] ?? '').toString();
    final score = test['score'] as num?;
    final status = (test['status'] ?? 'Pending').toString();
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
                  date,
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
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                score == null ? '--/100' : '${score.round()}/100',
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Color(0xFF666666), size: 20),
        ],
      ),
    );
  }
}
