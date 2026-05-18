import 'package:flutter/material.dart';

/// Palette warna brand Natalo Petshop. Semua warna yang dipakai di lebih dari
/// satu tempat ditarik ke sini supaya konsisten dan gampang theme-switch.
class NataloColors {
  NataloColors._();

  // ── Brand primary (biru Natalo) ──
  static const Color primary = Color(0xFF1E5FBF);
  static const Color primaryDark = Color(0xFF0B7FEA);
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color accent = Color(0xFFF2A93B);

  /// Alias `primary` untuk legacy reference `NataloColors.nataloBlue`.
  static const Color nataloBlue = primary;

  // ── Surfaces (light) ──
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
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
  /// Alias `success` untuk legacy reference `NataloColors.successGreen`.
  static const Color successGreen = success;

  static const Color warning = Color(0xFFF59E0B);

  static const Color danger = Color(0xFFEF4444);
  /// Alias `danger` untuk legacy reference `NataloColors.discountRed`.
  static const Color discountRed = danger;

  static const Color info = Color(0xFF3B82F6);

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
