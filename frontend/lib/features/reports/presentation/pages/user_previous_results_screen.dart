import 'package:flutter/material.dart';

import 'package:karaok_app/features/reports/presentation/pages/previous_results_screen.dart';

class UserPreviousResultsScreen extends StatelessWidget {
  const UserPreviousResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PreviousResultsScreen(
      title: 'Analysis History',
      accentColor: Color(0xFFFF8C00),
    );
  }
}
