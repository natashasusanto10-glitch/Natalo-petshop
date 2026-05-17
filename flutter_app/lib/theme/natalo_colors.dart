import 'package:flutter/material.dart';

/// Palette warna brand Natalo Petshop. Semua warna yang dipakai di lebih dari
/// satu tempat ditarik ke sini supaya konsisten dan gampang theme-switch.
class NataloColors {
  NataloColors._();

  // ── Brand primary (biru Natalo) ──
  static const Color primary = Color(0xFF1E5FBF);
  static const Color primaryDark = Color(0xFF0B7FEA);
  static const Color accent = Color(0xFFF2A93B);

  // ── Surfaces (light) ──
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);

  // ── Surfaces (dark) ──
  static const Color backgroundDark = Color(0xFF0A0F1A);
  static const Color surfaceDark = Color(0xFF111827);
  static const Color surfaceElevatedDark = Color(0xFF1F2937);
  static const Color borderDark = Color(0xFF374151);

  // ── Text ──
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFFCBD5E1);
  static const Color textTertiaryDark = Color(0xFF94A3B8);

  // ── Semantic ──
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ── Feed (immersive black) ──
  static const Color feedBlack = Color(0xFF000000);
  static const Color feedOverlay = Color(0xCC000000);
}
