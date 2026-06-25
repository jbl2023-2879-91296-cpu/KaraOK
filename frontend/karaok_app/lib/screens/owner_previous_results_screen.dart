import 'package:flutter/material.dart';
import '../widgets/bottom_nav_bar.dart';
import 'recommended_settings_screen.dart';

class OwnerPreviousResultsScreen extends StatefulWidget {
  const OwnerPreviousResultsScreen({super.key});

  @override
  State<OwnerPreviousResultsScreen> createState() =>
      _OwnerPreviousResultsScreenState();
}

class _OwnerPreviousResultsScreenState
    extends State<OwnerPreviousResultsScreen> {
  int _selectedNavIndex = 2;
  String _genreFilter = 'All';

  final List<_AudioResult> _results = [
    _AudioResult(name: 'Audio #1', date: 'Nov 1, 2025 10:30AM', genre: 'Rock'),
    _AudioResult(name: 'Audio #2', date: 'Nov 1, 2025 11:30AM', genre: 'R&B'),
    _AudioResult(name: 'Audio #3', date: 'Nov 1, 2025 11:30AM', genre: 'Pop'),
    _AudioResult(name: 'Audio #4', date: 'Nov 1, 2025 11:30AM', genre: 'Ballad'),
  ];

  final List<String> _genres = ['All', 'Rock', 'Pop', 'R&B', 'Ballad', 'HipHop', 'Classic'];

  List<_AudioResult> get _filtered {
    if (_genreFilter == 'All') return _results;
    return _results.where((r) => r.genre == _genreFilter).toList();
  }

  Color _genreColor(String genre) {
    switch (genre) {
      case 'Rock':    return const Color(0xFFE53935);
      case 'R&B':     return const Color(0xFFE07B00);
      case 'Pop':     return const Color(0xFF5C6BC0);
      case 'Ballad':  return const Color(0xFFD4C03A);
      case 'HipHop':  return const Color(0xFF8E24AA);
      case 'Classic': return const Color(0xFF43A047);
      default:        return const Color(0xFF4A90D9);
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
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Recommendation Records',
          style: TextStyle(
            color: Color(0xFFFF8C00),
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Filter row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // All button
                  GestureDetector(
                    onTap: () => setState(() => _genreFilter = 'All'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _genreFilter == 'All'
                            ? const Color(0xFF4A90D9)
                            : const Color(0xFF1C1C2E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'All',
                        style: TextStyle(
                          color: _genreFilter == 'All'
                              ? Colors.white
                              : const Color(0xFF888888),
                          fontSize: 13,
                          fontWeight: _genreFilter == 'All'
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Genre dropdown
                  GestureDetector(
                    onTap: () => _showGenrePicker(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C2E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _genreFilter == 'All' ? 'Genre' : _genreFilter,
                            style: const TextStyle(
                                color: Color(0xFF888888), fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down,
                              color: Color(0xFF888888), size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Results list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final item = _filtered[i];
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RecommendedSettingsScreen(
                              genre: item.genre),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
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
                                  item.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.date,
                                  style: const TextStyle(
                                      color: Color(0xFF666666),
                                      fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            item.genre,
                            style: TextStyle(
                              color: _genreColor(item.genre),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right,
                              color: Color(0xFF555555), size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedNavIndex,
        onTap: (i) => setState(() => _selectedNavIndex = i),
      ),
    );
  }

  void _showGenrePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _genres.map((g) {
            return ListTile(
              title: Text(g,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              onTap: () {
                setState(() => _genreFilter = g);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _AudioResult {
  const _AudioResult(
      {required this.name, required this.date, required this.genre});
  final String name;
  final String date;
  final String genre;
}
