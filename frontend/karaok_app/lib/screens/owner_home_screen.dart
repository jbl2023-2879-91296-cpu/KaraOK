import 'package:flutter/material.dart';
import '../widgets/bottom_nav_bar.dart';
import 'genre_select_screen.dart';
import 'uploading_screen.dart';
import 'owner_previous_results_screen.dart';

class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  int _selectedNavIndex = 0;

  final List<_AnalysisItem> _recentAnalysis = [
    _AnalysisItem(name: 'Test #1', date: 'May 1, 2025 10:30AM', score: 79, status: 'Acceptable'),
    _AnalysisItem(name: 'Test #2', date: 'May 1, 2025 11:00AM', score: 80, status: 'Acceptable'),
    _AnalysisItem(name: 'Test #3', date: 'May 1, 2025 11:30AM', score: 79, status: 'Acceptable'),
    _AnalysisItem(name: 'Test #4', date: 'May 1, 2025 11:45AM', score: 80, status: 'Acceptable'),
  ];

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
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  MaterialPageRoute(builder: (_) => const GenreSelectScreen()),
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
                  MaterialPageRoute(builder: (_) => const UploadingScreen()),
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
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const OwnerPreviousResultsScreen()),
                    );
                  },
                  child: const Text(
                    'View all',
                    style: TextStyle(color: Color(0xFFFF8C00), fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._recentAnalysis.map((item) => _AnalysisListItem(item: item)),
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

class _AnalysisItem {
  const _AnalysisItem(
      {required this.name,
      required this.date,
      required this.score,
      required this.status});
  final String name;
  final String date;
  final int score;
  final String status;
}

class _AnalysisListItem extends StatelessWidget {
  const _AnalysisListItem({required this.item});
  final _AnalysisItem item;

  @override
  Widget build(BuildContext context) {
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
                Text(item.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(item.date,
                    style: const TextStyle(
                        color: Color(0xFF888888), fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(item.status,
                  style: const TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
              Text('${item.score}/100',
                  style: const TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Color(0xFF666666), size: 20),
        ],
      ),
    );
  }
}
