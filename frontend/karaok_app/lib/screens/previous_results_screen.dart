import 'package:flutter/material.dart';
import '../widgets/bottom_nav_bar.dart';
import 'results_screen.dart';

class PreviousResultsScreen extends StatefulWidget {
  const PreviousResultsScreen({super.key});

  @override
  State<PreviousResultsScreen> createState() => _PreviousResultsScreenState();
}

class _PreviousResultsScreenState extends State<PreviousResultsScreen> {
  int _selectedNavIndex = 2;
  String _filter = 'All'; // All | Acceptable | Problematic

  final List<_TestResult> _results = [
    _TestResult(name: 'Test #1', date: 'May 1, 2025 10:30AM', score: 79, status: 'Acceptable'),
    _TestResult(name: 'Test #2', date: 'May 1, 2025 11:00AM', score: 80, status: 'Acceptable'),
    _TestResult(name: 'Test #3', date: 'May 1, 2025 11:30AM', score: 79, status: 'Acceptable'),
    _TestResult(name: 'Test #4', date: 'May 1, 2025 11:45AM', score: 80, status: 'Acceptable'),
  ];

  List<_TestResult> get _filtered {
    if (_filter == 'All') return _results;
    return _results.where((r) => r.status == _filter).toList();
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
          'Reports',
          style: TextStyle(
            color: Color(0xFF4A90D9),
            fontSize: 18,
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
            // Filter tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: ['All', 'Acceptable', 'Problematic'].map((f) {
                  final selected = _filter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filter = f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF4A90D9)
                              : const Color(0xFF1C1C2E),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          f,
                          style: TextStyle(
                            color: selected ? Colors.white : const Color(0xFF888888),
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
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
                          builder: (_) => ResultsScreen(
                            testName: item.name,
                            score: item.score,
                          ),
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
                                item.status,
                                style: const TextStyle(
                                  color: Color(0xFF4CAF50),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${item.score}/100',
                                style: const TextStyle(
                                  color: Color(0xFF4CAF50),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 6),
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
}

class _TestResult {
  const _TestResult({
    required this.name,
    required this.date,
    required this.score,
    required this.status,
  });
  final String name;
  final String date;
  final int score;
  final String status;
}
