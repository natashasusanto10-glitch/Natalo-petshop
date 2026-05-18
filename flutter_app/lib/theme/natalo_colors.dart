import 'package:flutter/material.dart';

/// Palette warna brand Natalo Petshop. Semua warna yang dipakai di lebih dari
/// satu tempat ditarik ke sini supaya konsisten dan gampang theme-switch.
class NataloColors {
  NataloColors._();

  // ── Base ──
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  // ── Brand primary (biru Natalo) ──
  /// Existing Natalo blue. Dipertahankan sebagai primary agar redesign lama
  /// tidak berubah drastis saat sistem warna dirapikan.
  static const Color primary = Color(0xFF1E5FBF);
  static const Color primaryDark = Color(0xFF0B7FEA);
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color primarySoft = Color(0xFFEEF4FF);
  static const Color primaryNavy = Color(0xFF1E3A8A);
  static const Color primaryNavyDark = Color(0xFF1E2E6B);
  static const Color accent = Color(0xFFF2A93B);
  static const Color accentOrange = Color(0xFFFF6B35);
  static const Color accentSoft = Color(0xFFFFF1EB);
  static const Color accentDark = Color(0xFFE55520);

  /// Alias `primary` untuk legacy reference `NataloColors.nataloBlue`.
  static const Color nataloBlue = primary;

  // ── Neutral scale ──
  static const Color grey50 = Color(0xFFFAFAFA);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFE5E7EB);
  static const Color grey300 = Color(0xFFD1D5DB);
  static const Color grey400 = Color(0xFF9CA3AF);
  static const Color grey500 = Color(0xFF6B7280);
  static const Color grey600 = Color(0xFF4B5563);
  static const Color grey700 = Color(0xFF374151);
  static const Color grey800 = Color(0xFF1F2937);
  static const Color grey900 = Color(0xFF111827);

  // ── Surfaces (light) ──
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color surfaceVariant = grey50;

  /// Alias `border` untuk legacy reference `NataloColors.divider`.
  static const Color divider = border;

  // ── Surfaces (dark) — slightly warm hint-blue tone (less eye strain di OLED) ──
  // Detail audit di DARKMODE_AUDIT.md.
  static const Color backgroundDark = Color(0xFF0A0F1A);
  static const Color surfaceDark = Color(0xFF1A1F2E);
  static const Color surfaceElevatedDark = Color(0xFF1F2937);
  static const Color surfaceVariantDark = Color(0xFF22293A);
  static const Color borderDark = Color(0xFF2A3142);

  // ── Text ──
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textTertiary = Color(0xFF94A3B8);

  /// Alias `textTertiary` untuk legacy reference `NataloColors.textMuted`.
  static const Color textMuted = textTertiary;

  static const Color textPrimaryDark = Color(0xFFF1F5F9);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textTertiaryDark = Color(0xFF94A3B8);
  static const Color textMutedDark = Color(0xFF64748B);

  // ── Semantic ──
  static const Color success = Color(0xFF22C55E);
  static const Color successSoft = Color(0xFFECFDF5);
  static const Color successDark = Color(0xFF16A34A);

  /// Alias `success` untuk legacy reference `NataloColors.successGreen`.
  static const Color successGreen = success;

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSoft = Color(0xFFFFFBEB);
  static const Color warningDark = Color(0xFFD97706);

  static const Color danger = Color(0xFFEF4444);
  static const Color dangerSoft = Color(0xFFFEF2F2);
  static const Color dangerDark = Color(0xFFDC2626);

  /// Alias `danger` untuk legacy reference `NataloColors.discountRed`.
  static const Color discountRed = danger;

  static const Color info = Color(0xFF3B82F6);
  static const Color infoSoft = Color(0xFFEFF6FF);
  static const Color infoDark = Color(0xFF2563EB);

  // ── Category colors ──
  static const Color catKucingBg = primarySoft;
  static const Color catKucingIcon = primaryNavy;
  static const Color catAnjingBg = Color(0xFFFFF7E6);
  static const Color catAnjingIcon = warningDark;
  static const Color catPasirBg = Color(0xFFF3F4F6);
  static const Color catPasirIcon = grey500;
  static const Color catVitaminBg = Color(0xFFFFE4E6);
  static const Color catVitaminIcon = Color(0xFFE11D48);
  static const Color catVoucherBg = Color(0xFFFCE7F3);
  static const Color catVoucherIcon = Color(0xFFBE185D);
  static const Color catPoinBg = warningSoft;
  static const Color catPoinIcon = warningDark;
  static const Color catGroomingBg = successSoft;
  static const Color catGroomingIcon = success;
  static const Color catBlogBg = Color(0xFFFEF3C7);
  static const Color catBlogIcon = Color(0xFF92400E);

  // ── Legacy soft aliases ──
  static const Color softBlue = primarySoft;
  static const Color softCyan = Color(0xFFEAFBFF);
  static const Color softMint = successSoft;

  // ── Price / e-commerce semantic ──
  /// Warna utama harga produk (sama dengan `textPrimary` untuk konsistensi).
  static const Color priceText = textPrimary;

  /// Warna harga coret (lebih muted, untuk old price strikethrough).
  static const Color oldPriceText = textTertiary;

  // ── Feed (immersive black) ──
  static const Color feedBlack = Color(0xFF000000);
  static const Color feedOverlay = Color(0xCC000000);

  /// Alias `feedBlack` — beberapa code pakai `feedDark`.
  static const Color feedDark = feedBlack;

  /// Muted text di feed (dark theme reels).
  static const Color feedTextMuted = Color(0xFFB0B7C3);
}

class NataloTextStyles {
  const NataloTextStyles._();

  static const TextStyle productPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.3,
  );

  static const TextStyle productDetailPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.3,
  );

  static const TextStyle cartPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );

  static const TextStyle totalPaymentPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );

  static const TextStyle oldPrice = TextStyle(
    color: NataloColors.oldPriceText,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.lineThrough,
  );

  static const TextStyle discountText = TextStyle(
    color: NataloColors.discountRed,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle freeShippingText = TextStyle(
    color: NataloColors.successGreen,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
}
