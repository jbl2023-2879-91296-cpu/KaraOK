import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/session_bootstrap_screen.dart';

abstract final class AppRoutes {
  static const root = '/';
  static const login = '/login';
  static const home = '/home';
  static const reports = '/reports';
  static const settings = '/settings';

  static Map<String, WidgetBuilder> get routes => {
    root: (_) => const SessionBootstrapScreen(),
    login: (_) => const LoginScreen(),
    home: (_) => const AppShell(),
    reports: (_) => const AppShell(initialIndex: 1),
    settings: (_) => const AppShell(initialIndex: 2),
  };
}
