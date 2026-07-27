import 'package:flutter/material.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';
import 'package:karaok_app/features/assessments/data/assessment_api.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';

class PreviousResultsScreen extends StatefulWidget {
  const PreviousResultsScreen({
    super.key,
    this.title = 'Reports',
    this.accentColor = const Color(0xFF4A90D9),
  });

  final String title;
  final Color accentColor;

  @override
  State<PreviousResultsScreen> createState() => _PreviousResultsScreenState();
}

class _PreviousResultsScreenState extends State<PreviousResultsScreen> {
  String _filter = 'All';
  List<dynamic> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (UserSession.instance.isGuest) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    try {
      final tests = await AssessmentApi().getAudioTests();
      if (!mounted) return;
      setState(() {
        _results = tests;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _filtered {
    if (_filter == 'All') return _results;
    return _results.where((r) => r['status'] == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        title: Text(
          widget.title,
          style: TextStyle(
            color: widget.accentColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: UserSession.instance.isGuest
          ? const _GuestRecordsView()
          : SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Filter tabs
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            [
                              'All',
                              'Acceptable',
                              'Needs Improvement',
                              'Problematic',
                            ].map((f) {
                              final selected = _filter == f;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => setState(() => _filter = f),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? widget.accentColor
                                          : const Color(0xFF1C1C2E),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      f,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : const Color(0xFF888888),
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
                  ),
                  const SizedBox(height: 16),
                  // Results list
                  Expanded(
                    child: _loading
                        ? Center(
                            child: CircularProgressIndicator(
                              color: widget.accentColor,
                            ),
                          )
                        : _filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No results found',
                              style: TextStyle(color: Color(0xFF666666)),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: widget.accentColor,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final item = _filtered[i];
                                final score = item['score'] as num?;
                                final status = item['status'] ?? 'Acceptable';
                                final date = (item['created_at'] ?? '')
                                    .toString();
                                final name = item['test_name'] ?? '';
                                final color = status == 'Acceptable'
                                    ? const Color(0xFF4CAF50)
                                    : status == 'Needs Improvement'
                                    ? const Color(0xFFFF9800)
                                    : const Color(0xFFF44336);
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ResultsScreen.fromRecord(
                                              Map<dynamic, dynamic>.from(
                                                item as Map,
                                              ),
                                            ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1C1C2E),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                                date.length > 16
                                                    ? date.substring(0, 16)
                                                    : date,
                                                style: const TextStyle(
                                                  color: Color(0xFF666666),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
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
                                              score == null
                                                  ? '--/100'
                                                  : '${score.round()}/100',
                                              style: TextStyle(
                                                color: color,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.chevron_right,
                                          color: Color(0xFF555555),
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _GuestRecordsView extends StatelessWidget {
  const _GuestRecordsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Color(0xFF4A90D9),
            ),
            const SizedBox(height: 20),
            const Text(
              'Save your evaluation records',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Guest results are not saved. Create a free account to keep your scores and review them anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFAAAAAA), height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SignUpScreen()),
              ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }
}
