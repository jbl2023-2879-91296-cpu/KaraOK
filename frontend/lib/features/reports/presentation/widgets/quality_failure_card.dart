import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_theme.dart';

class QualityFailureCard extends StatelessWidget {
  const QualityFailureCard({super.key, required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Audio quality check failed',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.error),
            ),
            for (final message in messages) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(message),
            ],
          ],
        ),
      ),
    );
  }
}
