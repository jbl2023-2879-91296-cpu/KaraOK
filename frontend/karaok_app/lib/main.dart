import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

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
      home: const SplashScreen(),
    );
  }
}
