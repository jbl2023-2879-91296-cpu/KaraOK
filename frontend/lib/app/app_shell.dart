import 'package:karaok_app/shared/widgets/adaptive_layout.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:karaok_app/core/security/session_manager.dart';

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
    final window = windowSizeOf(context);
    final content = IndexedStack(
      index: _currentIndex,
      children: [
        UserHomeScreen(onOpenRecords: () => _selectTab(1)),
        PreviousResultsScreen(
          title: 'Records',
          refreshToken: _recordsRefreshToken,
        ),
        const ChangePasswordScreen(),
      ],
    );
    final navigation = ListenableBuilder(
      listenable: UserSession.instance,
      builder: (context, _) {
        final settingsBadge = UserSession.instance.needsProfileCompletion;
        final destinations = [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Records',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: settingsBadge,
              child: const Icon(Icons.settings_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: settingsBadge,
              child: const Icon(Icons.settings),
            ),
            label: 'Settings',
          ),
        ];
        if (window == WindowSize.compact) {
          return NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _selectTab,
            backgroundColor: AppColors.background,
            indicatorColor: AppColors.mint,
            destinations: destinations,
          );
        }
        final extended = window == WindowSize.expanded;
        return SafeArea(
          right: false,
          child: NavigationRail(
            extended: extended,
            scrollable: true,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            backgroundColor: AppColors.background,
            indicatorColor: AppColors.mint,
            selectedIndex: _currentIndex,
            onDestinationSelected: _selectTab,
            destinations: [
              for (final item in destinations)
                NavigationRailDestination(
                  icon: item.icon,
                  selectedIcon: item.selectedIcon,
                  label: Text(item.label),
                ),
            ],
          ),
        );
      },
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          if (window != WindowSize.compact) navigation,
          Expanded(child: content),
        ],
      ),
      bottomNavigationBar: window == WindowSize.compact ? navigation : null,
    );
  }

  void _selectTab(int index) => setState(() {
    _currentIndex = index;
    if (index == 1) _recordsRefreshToken++;
  });
}
