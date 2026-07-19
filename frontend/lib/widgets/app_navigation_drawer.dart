import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/user_session.dart';

class AppDrawerButton extends StatelessWidget {
  const AppDrawerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Show menu',
      icon: const Icon(Icons.menu, color: Colors.white),
      onPressed: () => Scaffold.of(context).openDrawer(),
    );
  }
}

class AppNavigationDrawer extends StatelessWidget {
  const AppNavigationDrawer({super.key});

  static const _background = Color(0xFF151520);

  void _openRoute(
    BuildContext context,
    String route, {
    bool clearHistory = false,
  }) {
    final navigator = Navigator.of(context);
    navigator.pop();
    if (clearHistory) {
      navigator.pushNamedAndRemoveUntil(route, (current) => false);
    } else {
      navigator.pushNamed(route);
    }
  }

  Future<void> _logOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    try {
      await ApiService().logout();
    } catch (_) {
      // Local logout must still complete when the server is unavailable.
    } finally {
      UserSession.instance.clear();
    }
    navigator.pushNamedAndRemoveUntil('/', (current) => false);
  }

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;
    final accent = session.userType == 'owner'
        ? const Color(0xFFFF8C00)
        : const Color(0xFF4A90D9);
    final role = session.userType == 'owner' ? 'Owner' : 'Technician';

    return Drawer(
      backgroundColor: _background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: accent.withValues(alpha: 0.18),
                    child: Icon(Icons.person, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.name ?? 'Guest',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          session.isGuest ? '$role guest' : role,
                          style: const TextStyle(
                            color: Color(0xFF999999),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close menu',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFFAAAAAA)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF2A2A3E)),
            _DrawerItem(
              icon: Icons.home_outlined,
              label: 'Home',
              onTap: () => _openRoute(context, '/home', clearHistory: true),
            ),
            _DrawerItem(
              icon: Icons.bar_chart_outlined,
              label: 'Reports',
              onTap: () => _openRoute(context, '/reports'),
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              subtitle: session.isGuest
                  ? 'Sign in to manage account settings'
                  : 'Account and password',
              onTap: () =>
                  _openRoute(context, session.isGuest ? '/login' : '/settings'),
            ),
            const Spacer(),
            const Divider(height: 1, color: Color(0xFF2A2A3E)),
            if (session.isGuest)
              _DrawerItem(
                icon: Icons.login,
                label: 'Sign In',
                color: accent,
                onTap: () => _openRoute(context, '/login'),
              )
            else
              _DrawerItem(
                icon: Icons.logout,
                label: 'Log Out',
                color: const Color(0xFFF44336),
                onTap: () => _logOut(context),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
            ),
      onTap: onTap,
    );
  }
}
