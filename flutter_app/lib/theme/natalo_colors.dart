import 'package:flutter/material.dart';

/// Natalo Petshop design tokens — single source of truth untuk semua warna.
///
/// Naming follows Tailwind/Material pattern:
/// - `primary*` — brand action color (CTA, links, focus)
/// - `text*` — typography hierarchy
/// - `surface` / `background` — container fills
/// - `border` / `divider` — separators
/// - `success` / `warning` / `danger` — semantic feedback
/// - `feed*` — dark surfaces (TikTok-style reels feed)
///
/// **Migration**: legacy `AppColors.brandBlue` di re-exported supaya
/// existing code tidak break. Prefer pakai `NataloColors.primary` untuk
/// code baru.
class NataloColors {
  const NataloColors._();

  // ── Brand ───────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF1677FF);
  static const Color primaryDark = Color(0xFF0B5ED7);
  static const Color primaryLight = Color(0xFFEAF3FF);
  static const Color nataloBlue = primary;

  // ── Surfaces ────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF7FAFD);
  static const Color backgroundSoft = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);

  // ── Typography ──────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color priceText = textPrimary;
  static const Color oldPriceText = textMuted;

  // ── Lines ───────────────────────────────────────────────────────────
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderSoft = border;
  static const Color divider = Color(0xFFEFF2F6);

  // ── Semantic ────────────────────────────────────────────────────────
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color discountRed = danger;
  static const Color successGreen = success;

  // ── Feed (dark surfaces, TikTok-style reels) ────────────────────────
  static const Color feedBlack = Color(0xFF050505);
  static const Color feedDark = Color(0xFF111111);
  static const Color feedTextMuted = Color(0xFF9CA3AF);

  // ── Dark theme variants ─────────────────────────────────────────────
  // Dipakai di NataloTheme.darkTheme + ke depannya widget-level dark-aware
  // surfaces. Audit gap detail di DARKMODE_AUDIT.md.
  //
  // Tone selection: slightly warm (hint blue) — readable di OLED, less
  // eye strain at night daripada pure black.
  static const Color backgroundDark = Color(0xFF0A0F1A);
  static const Color surfaceDark = Color(0xFF1A1F2E);
  static const Color surfaceVariantDark = Color(0xFF22293A);
  static const Color borderDark = Color(0xFF2A3142);
  static const Color textPrimaryDark = Color(0xFFF1F5F9);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textMutedDark = Color(0xFF64748B);
}

class NataloTextStyles {
  const NataloTextStyles._();

  static const TextStyle productPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const TextStyle productDetailPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.15,
  );

  static const TextStyle cartPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle totalPaymentPrice = TextStyle(
    color: NataloColors.priceText,
    fontSize: 22,
    fontWeight: FontWeight.w800,
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
