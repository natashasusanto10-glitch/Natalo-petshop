import 'package:flutter/material.dart';

import 'natalo_colors.dart';

/// Gradient tokens for Natalo Petshop.
///
/// Keep reusable gradients here so screens do not need to hardcode color
/// combinations. This follows the existing `theme/` structure instead of
/// introducing a parallel `core/theme/` tree.
class NataloGradients {
  NataloGradients._();

  static const LinearGradient logo = LinearGradient(
    colors: [NataloColors.primary, NataloColors.primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bannerPromo = LinearGradient(
    colors: [
      NataloColors.accent,
      Color(0xFFFF8E53),
      Color(0xFFFFA500),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primary = LinearGradient(
    colors: [NataloColors.primary, NataloColors.primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Wash biru pucat untuk header layar konfirmasi/perayaan (mis. header
  /// "Pesanan Berhasil"). Sengaja jauh lebih terang dari [primary]: latarnya
  /// menaungi teks gelap, bukan teks putih.
  static const LinearGradient headerWash = LinearGradient(
    colors: [Color(0xFFD7E9FF), Color(0xFFF7FBFF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient rankGold = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient rankSilver = LinearGradient(
    colors: [Color(0xFFC0C0C0), Color(0xFF808080)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient rankBronze = LinearGradient(
    colors: [Color(0xFFCD7F32), Color(0xFF8B4513)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient? rank(int value) {
    switch (value) {
      case 1:
        return rankGold;
      case 2:
        return rankSilver;
      case 3:
        return rankBronze;
      default:
        return null;
    }
  }
}
