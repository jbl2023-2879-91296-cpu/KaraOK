import 'package:flutter/material.dart';

import 'previous_results_screen.dart';

class OwnerPreviousResultsScreen extends StatelessWidget {
  const OwnerPreviousResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PreviousResultsScreen(
      title: 'Analysis History',
      accentColor: Color(0xFFFF8C00),
    );
  }
}
