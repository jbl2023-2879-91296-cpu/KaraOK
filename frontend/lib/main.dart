import 'package:flutter/material.dart';
import 'screens/change_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/owner_home_screen.dart';
import 'screens/owner_previous_results_screen.dart';
import 'screens/previous_results_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/technician_home_screen.dart';
import 'services/user_session.dart';

void main() {
  runApp(const KaraOKApp());
}

class KaraOKApp extends StatelessWidget {
  const KaraOKApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KaraOK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4A90D9),
          secondary: Color(0xFFFF8C00),
          surface: Color(0xFF1A1A2E),
        ),
        fontFamily: 'Roboto',
      ),
      // Named routes so any screen can logout → '/'
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/home': (_) => UserSession.instance.userType == 'owner'
            ? const OwnerHomeScreen()
            : const TechnicianHomeScreen(),
        '/reports': (_) => UserSession.instance.userType == 'owner'
            ? const OwnerPreviousResultsScreen()
            : const PreviousResultsScreen(),
        '/settings': (_) => const ChangePasswordScreen(),
      },
    );
  }
}
