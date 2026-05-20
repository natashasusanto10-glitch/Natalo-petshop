import 'package:flutter/material.dart';

/// Theme admin app — pakai palette **coral/orange** mirip Shopee Seller
/// supaya secara visual jelas ini admin (bukan customer app yang biru
/// Natalo `#0B7FEA`).
///
/// - Primary: coral `#EE4D2D` (Shopee orange)
/// - Surface: white / `#F5F5F5` light gray bg
/// - Brand accent text: `#0B7FEA` untuk reference ke Natalo
class AdminColors {
  AdminColors._();

  static const Color primary = Color(0xFFEE4D2D); // Shopee coral
  static const Color primaryDark = Color(0xFFD23F1F);
  static const Color primaryLight = Color(0xFFFFF3F0);

  static const Color natalo = Color(0xFF0B7FEA); // Natalo brand blue accent

  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Colors.white;
  static const Color divider = Color(0xFFEEEEEE);

  static const Color textPrimary = Color(0xFF222222);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textMuted = Color(0xFF999999);

  static const Color success = Color(0xFF26AA99);
  static const Color warning = Color(0xFFFFA000);
  static const Color danger = Color(0xFFEE2C2C);
  static const Color info = Color(0xFF1E88E5);
}

ThemeData adminThemeLight() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AdminColors.primary,
      brightness: Brightness.light,
      primary: AdminColors.primary,
      surface: AdminColors.surface,
      onSurface: AdminColors.textPrimary,
      error: AdminColors.danger,
    ),
    scaffoldBackgroundColor: AdminColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AdminColors.surface,
      foregroundColor: AdminColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: TextStyle(
        color: AdminColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: AdminColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: AdminColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AdminColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AdminColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AdminColors.primary, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AdminColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AdminColors.surface,
      selectedItemColor: AdminColors.primary,
      unselectedItemColor: AdminColors.textMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      showUnselectedLabels: true,
      selectedLabelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      unselectedLabelStyle:
          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
    ),
    dividerTheme: const DividerThemeData(
      color: AdminColors.divider,
      thickness: 1,
      space: 1,
    ),
  );
}

/// Format Rupiah "Rp 1.234.000".
String formatRupiah(num value) {
  final integer = value.round();
  final str = integer.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(str[i]);
  }
  return '${integer < 0 ? '-' : ''}Rp ${buffer.toString()}';
}
