import 'package:flutter/material.dart';
import 'package:karaok_app/app/routes.dart';
import 'package:karaok_app/app/app_theme.dart';

class KaraOKApp extends StatelessWidget {
  const KaraOKApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KaraOK',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: AppTheme.light,
      initialRoute: AppRoutes.root,
      routes: AppRoutes.routes,
    );
  }
}
