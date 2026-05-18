import 'package:flutter/material.dart';

import 'natalo_colors.dart';

/// Reusable text style constants — dipakai di sticky_add_to_cart_bar dll.
class NataloTextStyles {
  NataloTextStyles._();

  static const TextStyle productPrice = TextStyle(
    color: NataloColors.primary,
    fontWeight: FontWeight.w900,
    fontSize: 16,
    height: 1.2,
  );

  static const TextStyle productTitle = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 14,
    height: 1.3,
  );

  static const TextStyle caption = TextStyle(
    color: NataloColors.textSecondary,
    fontWeight: FontWeight.w500,
    fontSize: 12,
  );
}

/// Material 3 themes Natalo Petshop. NataloTheme.lightTheme + .darkTheme
/// dipasang di MaterialApp di main.dart, switching via appSettingsStore.
class NataloTheme {
  NataloTheme._();

  static const String fontFamily = 'NunitoSans';

  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: NataloColors.primary,
      brightness: brightness,
      primary: NataloColors.primary,
      surface: isLight ? NataloColors.background : NataloColors.backgroundDark,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: isLight
            ? NataloColors.surfaceElevated
            : NataloColors.surfaceElevatedDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isLight ? NataloColors.border : NataloColors.borderDark,
            width: 1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight
            ? NataloColors.surface
            : NataloColors.surfaceElevatedDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLight ? NataloColors.border : NataloColors.borderDark,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NataloColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
