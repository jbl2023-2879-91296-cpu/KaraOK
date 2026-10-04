import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';

import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';
import 'package:karaok_app/features/home/presentation/pages/user_home_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/previous_results_screen.dart';

/// The app's single top-level surface.
///
/// Primary destinations switch in place so the user never has to open a side
/// menu or navigate through a stack just to move around the app.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _currentIndex;
  int _recordsRefreshToken = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 2);
  }

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.orangeInk;
    final home = UserHomeScreen(onOpenRecords: () => _selectTab(1));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          home,
          PreviousResultsScreen(
            title: 'Records',
            accentColor: accent,
            refreshToken: _recordsRefreshToken,
          ),
          const ChangePasswordScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.mint,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Records',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  void _selectTab(int index) => setState(() {
    _currentIndex = index;
    if (index == 1) _recordsRefreshToken++;
  });
}
