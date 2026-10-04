import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colors drawn from the supplied KaraOK logo, with darker ink tones for
/// readable text and controls on light surfaces.
abstract final class AppColors {
  static const teal = Color(0xFF00CDB5);
  static const primary = Color(0xFF007D70);
  static const orange = Color(0xFFFF9636);
  static const orangeInk = Color(0xFFA64B00);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF0F8F6);
  static const mint = Color(0xFFE0F6F0);
  static const peach = Color(0xFFFFF0DF);
  static const ink = Color(0xFF183B36);
  static const muted = Color(0xFF526B65);
  static const outline = Color(0xFFB8CEC8);
  static const onPrimary = Color(0xFFFFFFFF);
  static const success = Color(0xFF257440);
  static const error = Color(0xFFB3261E);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.teal,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          primaryContainer: AppColors.mint,
          onPrimaryContainer: AppColors.ink,
          secondary: AppColors.orangeInk,
          onSecondary: AppColors.onPrimary,
          secondaryContainer: AppColors.peach,
          onSecondaryContainer: AppColors.orangeInk,
          tertiary: AppColors.orange,
          onTertiary: AppColors.ink,
          surface: AppColors.background,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.muted,
          outline: AppColors.outline,
          error: AppColors.error,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.mint,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: AppColors.muted),
        hintStyle: const TextStyle(color: AppColors.muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
        ),
      ),
      dividerColor: AppColors.outline,
    );
  }
}
