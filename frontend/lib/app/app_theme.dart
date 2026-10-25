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

/// Shared layout rhythm. Interactive controls never fall below [touchTarget].
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const page = 24.0;
  static const touchTarget = 48.0;
  static const contentWidth = 720.0;
}

abstract final class AppRadii {
  static const sm = 8.0;
  static const control = 12.0;
  static const card = 16.0;
  static const dialog = 24.0;
  static const pill = 999.0;
}

abstract final class AppElevation {
  static const flat = 0.0;
  static const raised = 1.0;
  static const overlay = 4.0;
}

abstract final class AppShadows {
  static const soft = <BoxShadow>[
    BoxShadow(color: Color(0x14183B36), blurRadius: 16, offset: Offset(0, 4)),
  ];
}

abstract final class AppTypography {
  static const textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 48,
      height: 1.15,
      fontWeight: FontWeight.w700,
    ),
    displayMedium: TextStyle(
      fontSize: 40,
      height: 1.15,
      fontWeight: FontWeight.w700,
    ),
    displaySmall: TextStyle(
      fontSize: 36,
      height: 1.2,
      fontWeight: FontWeight.w700,
    ),
    headlineLarge: TextStyle(
      fontSize: 32,
      height: 1.2,
      fontWeight: FontWeight.w700,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      height: 1.25,
      fontWeight: FontWeight.w700,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      height: 1.3,
      fontWeight: FontWeight.w700,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      height: 1.3,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      height: 1.4,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: TextStyle(
      fontSize: 16,
      height: 1.4,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5),
    bodySmall: TextStyle(fontSize: 12, height: 1.5),
    labelLarge: TextStyle(
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w700,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      height: 1.4,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      height: 1.4,
      fontWeight: FontWeight.w600,
    ),
  );
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
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
    );
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(AppSpacing.touchTarget, AppSpacing.touchTarget),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
      ),
      shape: WidgetStatePropertyAll(controlShape),
      textStyle: WidgetStatePropertyAll(AppTypography.textTheme.labelLarge),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: color, width: width),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
      textTheme: AppTypography.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.flat,
        scrolledUnderElevation: AppElevation.flat,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: buttonStyle.copyWith(
          elevation: const WidgetStatePropertyAll(AppElevation.flat),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.outline
                : AppColors.primary,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.muted
                : AppColors.onPrimary,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
      textButtonTheme: TextButtonThemeData(style: buttonStyle),
      iconButtonTheme: IconButtonThemeData(
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(AppSpacing.touchTarget, AppSpacing.touchTarget),
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.all(AppSpacing.lg),
        constraints: const BoxConstraints(minHeight: AppSpacing.touchTarget),
        labelStyle: const TextStyle(color: AppColors.muted),
        hintStyle: const TextStyle(color: AppColors.muted),
        errorMaxLines: 4,
        border: inputBorder(AppColors.outline),
        enabledBorder: inputBorder(AppColors.outline),
        disabledBorder: inputBorder(AppColors.outline),
        focusedBorder: inputBorder(AppColors.primary, 2),
        errorBorder: inputBorder(AppColors.error),
        focusedErrorBorder: inputBorder(AppColors.error, 2),
      ),
      cardTheme: CardThemeData(
        color: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.flat,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.mint,
        disabledColor: AppColors.surface,
        labelStyle: AppTypography.textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        side: const BorderSide(color: AppColors.outline),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
        titleTextStyle: AppTypography.textTheme.headlineSmall?.copyWith(
          color: AppColors.ink,
        ),
        contentTextStyle: AppTypography.textTheme.bodyLarge?.copyWith(
          color: AppColors.muted,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: AppTypography.textTheme.bodyMedium?.copyWith(
          color: AppColors.background,
        ),
        actionTextColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
        elevation: AppElevation.raised,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.flat,
        indicatorColor: AppColors.mint,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppTypography.textTheme.labelMedium!.copyWith(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minTileHeight: AppSpacing.touchTarget,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        iconColor: AppColors.primary,
        textColor: AppColors.ink,
        selectedColor: AppColors.primary,
        selectedTileColor: AppColors.mint,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.outline,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.mint,
        valueIndicatorColor: AppColors.primary,
        valueIndicatorTextStyle: TextStyle(color: AppColors.onPrimary),
        trackHeight: AppSpacing.xs,
        overlayShape: RoundSliderOverlayShape(overlayRadius: AppSpacing.xl),
      ),
      dividerColor: AppColors.outline,
    );
  }
}
