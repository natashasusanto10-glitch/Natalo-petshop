import 'package:flutter/material.dart';

import 'app_radius.dart';
import 'app_spacing.dart';
import 'natalo_colors.dart';

const String _nataloFontFamily = 'PlusJakartaSans';

const TextTheme _lightTextTheme = TextTheme(
  displayLarge: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.5,
    color: NataloColors.textPrimary,
  ),
  displayMedium: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.16,
    letterSpacing: -0.5,
    color: NataloColors.textPrimary,
  ),
  displaySmall: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.18,
    letterSpacing: -0.4,
    color: NataloColors.textPrimary,
  ),
  headlineLarge: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.20,
    letterSpacing: -0.4,
    color: NataloColors.textPrimary,
  ),
  headlineMedium: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.24,
    letterSpacing: -0.3,
    color: NataloColors.textPrimary,
  ),
  headlineSmall: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.30,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  titleLarge: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.24,
    letterSpacing: -0.3,
    color: NataloColors.textPrimary,
  ),
  titleMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  titleSmall: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  bodyLarge: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  bodyMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0,
    color: NataloColors.textSecondary,
  ),
  bodySmall: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0,
    color: NataloColors.textSecondary,
  ),
  labelLarge: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: 0,
    color: NataloColors.textPrimary,
  ),
  labelMedium: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
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
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.5,
    color: NataloColors.textPrimaryDark,
  ),
  displayMedium: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.16,
    letterSpacing: -0.5,
    color: NataloColors.textPrimaryDark,
  ),
  displaySmall: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.18,
    letterSpacing: -0.4,
    color: NataloColors.textPrimaryDark,
  ),
  headlineLarge: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.20,
    letterSpacing: -0.4,
    color: NataloColors.textPrimaryDark,
  ),
  headlineMedium: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.24,
    letterSpacing: -0.3,
    color: NataloColors.textPrimaryDark,
  ),
  headlineSmall: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.30,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  titleLarge: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.24,
    letterSpacing: -0.3,
    color: NataloColors.textPrimaryDark,
  ),
  titleMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  titleSmall: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  bodyLarge: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  bodyMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0,
    color: NataloColors.textSecondaryDark,
  ),
  bodySmall: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0,
    color: NataloColors.textSecondaryDark,
  ),
  labelLarge: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: 0,
    color: NataloColors.textPrimaryDark,
  ),
  labelMedium: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
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

/// Material 3 themes Natalo Petshop. NataloTheme.lightTheme + .darkTheme
/// dipasang di MaterialApp di main.dart, switching via appSettingsStore.
class NataloTheme {
  NataloTheme._();

  // PlusJakartaSans di-bundle di pubspec.yaml. Sebelumnya 'NunitoSans' tapi
  // file font-nya tidak ada di assets/fonts/ → iOS fallback ke system font
  // dengan metrics tidak konsisten → Text widget wrap per-character.
  static const String fontFamily = 'PlusJakartaSans';

  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: NataloColors.primary,
      brightness: brightness,
      primary: NataloColors.primary,
      secondary: NataloColors.accentOrange,
      error: NataloColors.danger,
      surface: isLight ? NataloColors.background : NataloColors.backgroundDark,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: const ['Roboto', 'Arial'],
      // SOLID solid white scaffold — bukan `scheme.surface` yang
      // Material 3 bisa blend dengan elevation tint saat ada konten
      // scroll di belakang. Force explicit putih supaya tidak ada
      // efek "blur/tint" di header maupun body.
      scaffoldBackgroundColor:
          isLight ? const Color(0xFFFFFFFF) : NataloColors.backgroundDark,
      textTheme: isLight ? _lightTextTheme : _darkTextTheme,
      primaryTextTheme: isLight ? _lightTextTheme : _darkTextTheme,
      // BUG FIX (v1.0.13): user report header Keranjang / Tukar Poin /
      // Riwayat Poin / Ulasan / Voucher / Alamat tampak "blur" / faded.
      // Root cause Material 3:
      //   - `surfaceTintColor` default = colorScheme.surfaceTint (primary
      //     tone) → di-blend ke background saat ada elevation.
      //   - `scrolledUnderElevation` default = 4.0 → saat content scroll
      //     di belakang AppBar, elevation overlay aktif → header keliatan
      //     tinted/blur, BUKAN solid white.
      // Solusi: kill keduanya (surfaceTintColor → transparent,
      // scrolledUnderElevation → 0) + force backgroundColor solid white +
      // tambah border bottom tipis untuk crisp edge.
      appBarTheme: AppBarTheme(
        backgroundColor:
            isLight ? const Color(0xFFFFFFFF) : NataloColors.surfaceDark,
        // HARDCODED foreground (not scheme.onSurface) — fix5 user report
        // "header tidak ada" suggests scheme.onSurface mungkin resolve ke
        // value yang bermasalah di build production. Explicit hex value
        // jamin title text + back button + actions visible di white bg.
        foregroundColor:
            isLight ? NataloColors.textPrimary : NataloColors.textPrimaryDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(
          color: isLight
              ? NataloColors.textPrimary
              : NataloColors.textPrimaryDark,
          size: 26,
        ),
        actionsIconTheme: IconThemeData(
          color: isLight
              ? NataloColors.textPrimary
              : NataloColors.textPrimaryDark,
          size: 25,
        ),
        shape: isLight
            ? const Border(
                bottom: BorderSide(color: Color(0xFFE5EAF2), width: 1),
              )
            : const Border(
                bottom: BorderSide(
                  color: NataloColors.borderDark,
                  width: 1,
                ),
              ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          height: 1.25,
          letterSpacing: -0.3,
          // EXPLICIT color — jangan rely ke foregroundColor inheritance.
          color:
              isLight ? NataloColors.textPrimary : NataloColors.textPrimaryDark,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.large,
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
          borderRadius: AppRadius.large,
          side: BorderSide(
            color: isLight ? NataloColors.border : NataloColors.borderDark,
            width: 1,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NataloColors.primary,
          foregroundColor: NataloColors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: AppSpacing.buttonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.large,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
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
          padding: AppSpacing.buttonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.large,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
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
            fontWeight: FontWeight.w700,
            height: 1.25,
            letterSpacing: 0,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isLight ? NataloColors.surface : NataloColors.surfaceElevatedDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: BorderSide(
            color: isLight ? NataloColors.border : NataloColors.borderDark,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.medium,
          borderSide: const BorderSide(color: NataloColors.primary, width: 1.5),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: NataloColors.divider,
        thickness: 1,
      ),

      // Page transitions tetap pakai predictive back (Android 13+) +
      // iOS Cupertino style — feel native per platform.
      // Page transitions: Android pakai PredictiveBack (Android 13+), iOS
      // pakai DEFAULT Cupertino slide — tidak perlu specify
      // `CupertinoPageTransitionsBuilder` karena Codemagic Flutter SDK
      // version-nya tidak resolve symbol itu dari material.dart. Default
      // iOS behavior sudah Cupertino slide.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Dark variant — pakai dark variant tokens dari NataloColors (slightly
  /// warm blue-tinted, OLED-friendly). Primary di-lift jadi #38B0FF supaya
  /// kontras AAA di dark. `feedBlack` (#050505) di-reserve hanya untuk Feed
  /// screen (pure black untuk video reels).
  static ThemeData get darkTheme {
    const darkPrimary = NataloColors.primaryLight;
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
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: darkInk,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          height: 1.25,
          letterSpacing: -0.3,
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
          borderRadius: AppRadius.extraLarge,
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkScaffold,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: AppSpacing.buttonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.large,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
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
          padding: AppSpacing.buttonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.large,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
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
            fontWeight: FontWeight.w700,
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
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.large,
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.large,
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.large,
          borderSide: const BorderSide(color: darkPrimary, width: 1.4),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
      ),
      // Page transitions: Android pakai PredictiveBack (Android 13+), iOS
      // pakai DEFAULT Cupertino slide — tidak perlu specify
      // `CupertinoPageTransitionsBuilder` karena Codemagic Flutter SDK
      // version-nya tidak resolve symbol itu dari material.dart. Default
      // iOS behavior sudah Cupertino slide.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
