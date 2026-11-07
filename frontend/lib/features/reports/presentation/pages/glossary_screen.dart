import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/features/reports/domain/measurement_glossary.dart';

class GlossaryScreen extends StatefulWidget {
  const GlossaryScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const GlossaryScreen()));

  @override
  State<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends State<GlossaryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final entries =
        measurementGlossary
            .where(
              (entry) =>
                  '${entry.term} ${entry.definition} ${entry.why} ${entry.good}'
                      .toLowerCase()
                      .contains(_query.trim().toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.term.compareTo(b.term));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Glossary of terms')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.lg,
              ),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search terms',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text('No matching terms. Try another word.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page,
                        0,
                        AppSpacing.page,
                        AppSpacing.xl,
                      ),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return Card(
                          key: ValueKey(entry.term),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            title: Text(entry.term),
                            subtitle: Text(entry.definition),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.start,
                            childrenPadding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              0,
                              AppSpacing.lg,
                              AppSpacing.lg,
                            ),
                            children: [
                              Text('Why it matters for karaoke: ${entry.why}'),
                              const SizedBox(height: 12),
                              Text("What's good: ${entry.good}"),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
