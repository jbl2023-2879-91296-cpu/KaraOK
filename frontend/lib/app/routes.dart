import 'package:flutter/material.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/splash_screen.dart';
import 'package:karaok_app/features/home/presentation/pages/owner_home_screen.dart';
import 'package:karaok_app/features/home/presentation/pages/technician_home_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/owner_previous_results_screen.dart';
import 'package:karaok_app/features/reports/presentation/pages/previous_results_screen.dart';

abstract final class AppRoutes {
  static const root = '/';
  static const login = '/login';
  static const home = '/home';
  static const reports = '/reports';
  static const settings = '/settings';

  static Map<String, WidgetBuilder> get routes => {
    root: (_) => const SplashScreen(),
    login: (_) => const LoginScreen(),
    home: (_) => UserSession.instance.userType == 'owner'
        ? const OwnerHomeScreen()
        : const TechnicianHomeScreen(),
    reports: (_) => UserSession.instance.userType == 'owner'
        ? const OwnerPreviousResultsScreen()
        : const PreviousResultsScreen(),
    settings: (_) => const ChangePasswordScreen(),
  };
}
