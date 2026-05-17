import 'dart:ui';

import 'package:flutter/material.dart';

import 'natalo_colors.dart';

/// **DEPRECATED**: Pakai [NataloColors] untuk code baru.
///
/// Kelas `AppColors` ditahan supaya existing widget yang reference
/// `AppColors.brandBlue` / `AppColors.ink` dll tidak break. Semua field
/// di-alias ke `NataloColors.*` jadi update palette di satu tempat
/// (natalo_colors.dart) auto-propagate ke seluruh app.
class AppColors {
  // Brand
  static const Color brandBlue = NataloColors.primary;
  static const Color brandBlueDark = NataloColors.primaryDark;

  // Typography
  static const Color ink = NataloColors.textPrimary;
  static const Color muted = NataloColors.textSecondary;

  // Lines
  static const Color line = NataloColors.border;

  // Surfaces
  static const Color softBlue = NataloColors.primaryLight;
  static const Color softCyan = Color(0xFFEAFBFF); // legacy, tidak ada di NataloColors
  static const Color softMint = Color(0xFFF0FDF4); // legacy, tidak ada di NataloColors

  // Semantic
  static const Color danger = NataloColors.danger;
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: NataloColors.primary,
      primary: NataloColors.primary,
      secondary: NataloColors.success,
      tertiary: const Color(0xFFDB2777),
      surface: NataloColors.surface,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: 'NunitoSans',
      fontFamilyFallback: const ['Roboto', 'Arial'],
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: NataloColors.surface.withValues(alpha: 0.90),
        foregroundColor: NataloColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        titleTextStyle: const TextStyle(
          color: NataloColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
        iconTheme: const IconThemeData(
          color: NataloColors.textPrimary,
          size: 28,
        ),
        actionsIconTheme: const IconThemeData(
          color: NataloColors.textPrimary,
          size: 27,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: NataloColors.primaryLight,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? NataloColors.primary : NataloColors.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            letterSpacing: 0,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? NataloColors.primary : NataloColors.textMuted,
            size: selected ? 28 : 25,
          );
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NataloColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: NataloColors.primary.withValues(alpha: 0.28),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ).copyWith(
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: 0.12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NataloColors.primary,
          side: BorderSide(color: NataloColors.primary.withValues(alpha: 0.45)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NataloColors.surface.withValues(alpha: 0.92),
        prefixIconColor: NataloColors.primary,
        suffixIconColor: NataloColors.textSecondary,
        labelStyle: const TextStyle(
          color: NataloColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
        floatingLabelStyle: const TextStyle(
          color: NataloColors.primary,
          fontWeight: FontWeight.w900,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: NataloColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: NataloColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: NataloColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: NataloColors.danger),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: NataloColors.surface.withValues(alpha: 0.90),
        selectedColor: NataloColors.primaryLight,
        side: const BorderSide(color: NataloColors.border),
        labelStyle: const TextStyle(
          color: NataloColors.textSecondary,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dividerTheme: const DividerThemeData(
        color: NataloColors.divider,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: NataloColors.surface.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: NataloColors.surface.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: NataloColors.surface.withValues(alpha: 0.96),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: NataloColors.textPrimary.withValues(alpha: 0.92),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Dark theme — mirror struktur light tapi dengan surface gelap.
  /// Brand color jadi sedikit lebih cerah untuk kontras AAA di dark.
  static ThemeData get dark {
    const darkSurface = NataloColors.feedBlack;
    const darkSurfaceVariant = NataloColors.feedDark;
    const darkInk = Color(0xFFF8FAFC);
    const darkMuted = NataloColors.feedTextMuted;
    const darkBorder = Color(0xFF1F2937);
    // Brand color di-lift untuk dark mode (4.5:1 contrast min).
    const darkPrimary = Color(0xFF38B0FF);

    final scheme = ColorScheme.fromSeed(
      seedColor: NataloColors.primary,
      brightness: Brightness.dark,
      primary: darkPrimary,
      secondary: const Color(0xFF22C55E),
      tertiary: const Color(0xFFEC4899),
      surface: darkSurface,
      onSurface: darkInk,
    );

    return ThemeData(
      colorScheme: scheme,
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: 'NunitoSans',
      fontFamilyFallback: const ['Roboto', 'Arial'],
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: darkSurface.withValues(alpha: 0.85),
        foregroundColor: darkInk,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        titleTextStyle: const TextStyle(
          color: darkInk,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
        iconTheme: const IconThemeData(color: darkInk, size: 28),
        actionsIconTheme: const IconThemeData(color: darkInk, size: 27),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkSurface,
          elevation: 0,
          shadowColor: darkPrimary.withValues(alpha: 0.28),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPrimary,
          side: const BorderSide(color: Color(0xFF3B82F6)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceVariant.withValues(alpha: 0.90),
        prefixIconColor: darkPrimary,
        suffixIconColor: darkMuted,
        labelStyle: const TextStyle(
          color: darkMuted,
          fontWeight: FontWeight.w700,
        ),
        floatingLabelStyle: const TextStyle(
          color: darkPrimary,
          fontWeight: FontWeight.w900,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: darkPrimary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: NataloColors.danger),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkSurfaceVariant.withValues(alpha: 0.90),
        selectedColor: const Color(0xFF1E40AF),
        side: const BorderSide(color: darkBorder),
        labelStyle: const TextStyle(
          color: darkMuted,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurfaceVariant.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: darkSurfaceVariant.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: darkSurfaceVariant.withValues(alpha: 0.96),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkInk.withValues(alpha: 0.92),
        contentTextStyle: const TextStyle(
          color: darkSurface,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

/// Backdrop gradient — adaptif ke theme mode.
/// Light: subtle blue gradient pakai NataloColors.background sebagai base.
/// Dark: feed-style deep navy gradient pakai feedBlack/feedDark.
class AppBackdrop extends StatelessWidget {
  final Widget child;

  const AppBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradientColors = isDark
        ? const [
            NataloColors.feedBlack,
            NataloColors.feedDark,
            Color(0xFF111111),
            NataloColors.feedBlack,
          ]
        : const [
            NataloColors.background,
            NataloColors.surface,
            NataloColors.primaryLight,
            NataloColors.background,
          ];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
          stops: const [0, 0.42, 0.72, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 0.2, sigmaY: 0.2),
              child: const SizedBox.expand(),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
