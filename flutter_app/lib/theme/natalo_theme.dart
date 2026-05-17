import 'package:flutter/material.dart';

import 'natalo_colors.dart';

const String _nataloFontFamily = 'NunitoSans';

const TextTheme _lightTextTheme = TextTheme(
  displayLarge: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.20,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  displayMedium: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.22,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  displaySmall: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.24,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  headlineLarge: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.24,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  headlineMedium: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.26,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  headlineSmall: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.28,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  titleLarge: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  titleMedium: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.30,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  titleSmall: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.30,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  bodyLarge: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  bodyMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0,
    color: NataloColors.textSecondary,
  ),
  bodySmall: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
    letterSpacing: 0,
    color: NataloColors.textSecondary,
  ),
  labelLarge: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  labelMedium: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.25,
    letterSpacing: 0,
    color: NataloColors.textSecondary,
  ),
  labelSmall: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.20,
    letterSpacing: 0,
    color: NataloColors.textMuted,
  ),
);

const TextTheme _darkTextTheme = TextTheme(
  displayLarge: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.20,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  displayMedium: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.22,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  displaySmall: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.24,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  headlineLarge: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.24,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  headlineMedium: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.26,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  headlineSmall: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.28,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  titleLarge: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  titleMedium: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.30,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  titleSmall: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.30,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  bodyLarge: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  bodyMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0,
    color: NataloColors.textSecondaryDark,
  ),
  bodySmall: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
    letterSpacing: 0,
    color: NataloColors.textSecondaryDark,
  ),
  labelLarge: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  labelMedium: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.25,
    letterSpacing: 0,
    color: NataloColors.textSecondaryDark,
  ),
  labelSmall: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.20,
    letterSpacing: 0,
    color: NataloColors.textMutedDark,
  ),
);

/// Theme utama Natalo Petshop — clean Material 3 dengan brand palette
/// `NataloColors`. Optimized untuk:
/// - Performance di HP entry-level (no backdrop blur, solid surfaces)
/// - Readability outdoor (high contrast, no transparency)
/// - Convention familiar Tokopedia/Shopee/Lazada (Indonesian e-commerce)
/// - Maintainability (1 file, struktur Material 3 standard)
class NataloTheme {
  const NataloTheme._();

  static ThemeData get lightTheme {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: NataloColors.primary,
      brightness: Brightness.light,
      primary: NataloColors.primary,
      surface: NataloColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NataloColors.background,
      fontFamily: _nataloFontFamily,
      fontFamilyFallback: const ['Roboto', 'Arial'],
      textTheme: _lightTextTheme,
      primaryTextTheme: _lightTextTheme,

      appBarTheme: const AppBarTheme(
        backgroundColor: NataloColors.surface,
        foregroundColor: NataloColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: NataloColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.25,
          letterSpacing: 0,
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: NataloColors.surface,
        selectedItemColor: NataloColors.primary,
        unselectedItemColor: NataloColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: NataloColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: NataloColors.primaryLight,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: NataloColors.primary,
            );
          }

          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: NataloColors.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(
              color: NataloColors.primary,
              size: 24,
            );
          }

          return const IconThemeData(
            color: NataloColors.textMuted,
            size: 23,
          );
        }),
      ),

      cardTheme: CardThemeData(
        color: NataloColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(
            color: NataloColors.border,
            width: 1,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NataloColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.25,
            letterSpacing: 0,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NataloColors.primary,
          side: const BorderSide(color: NataloColors.primary),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.25,
            letterSpacing: 0,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NataloColors.primary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.25,
            letterSpacing: 0,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(
          color: NataloColors.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.35,
          letterSpacing: 0,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: NataloColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: NataloColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: NataloColors.primary,
            width: 1.4,
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: NataloColors.divider,
        thickness: 1,
      ),

      // Page transitions tetap pakai predictive back (Android 13+) +
      // iOS Cupertino style — feel native per platform.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Dark variant — pakai dark variant tokens dari NataloColors (slightly
  /// warm blue-tinted, OLED-friendly). Primary di-lift jadi #38B0FF supaya
  /// kontras AAA di dark. `feedBlack` (#050505) di-reserve hanya untuk Feed
  /// screen (pure black untuk video reels).
  static ThemeData get darkTheme {
    const darkPrimary = Color(0xFF38B0FF);
    const darkScaffold = NataloColors.backgroundDark; // #0A0F1A
    const darkSurface = NataloColors.surfaceDark; // #1A1F2E
    // NataloColors.surfaceVariantDark (#22293A) tersedia untuk elevated/
    // nested cards di masa depan kalau perlu second-tier surface.
    const darkInk = NataloColors.textPrimaryDark; // #F1F5F9
    const darkMuted = NataloColors.textSecondaryDark; // #94A3B8
    const darkBorder = NataloColors.borderDark; // #2A3142

    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: NataloColors.primary,
      brightness: Brightness.dark,
      primary: darkPrimary,
      surface: darkSurface,
      onSurface: darkInk,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkScaffold,
      fontFamily: _nataloFontFamily,
      fontFamilyFallback: const ['Roboto', 'Arial'],
      textTheme: _darkTextTheme,
      primaryTextTheme: _darkTextTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkScaffold,
        foregroundColor: darkInk,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: darkInk,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.25,
          letterSpacing: 0,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: darkPrimary.withValues(alpha: 0.18),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: darkPrimary,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: darkMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: darkPrimary, size: 24);
          }
          return const IconThemeData(color: darkMuted, size: 23);
        }),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkScaffold,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.25,
            letterSpacing: 0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPrimary,
          side: const BorderSide(color: darkPrimary),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.25,
            letterSpacing: 0,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkPrimary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.25,
            letterSpacing: 0,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        hintStyle: const TextStyle(
          color: darkMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.35,
          letterSpacing: 0,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkPrimary, width: 1.4),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
