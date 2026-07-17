import 'package:flutter/painting.dart' show FontWeight;

/// Skala bobot font tunggal (Fase 2 typography). Ganti literal
/// FontWeight.wXXX yang tersebar supaya hierarki konsisten & ringan ala IG
/// (Regular 400 + Semibold 600). HANYA bobot — ukuran/warna/shadow tetap di
/// call-site.
abstract final class NataloWeight {
  /// Basis: body, label, caption, metadata, bio, label statistik,
  /// tab non-aktif. Layar solid.
  static const body = FontWeight.w400;

  /// Hierarki: nama/handle, angka statistik, judul, tombol, link, badge,
  /// inisial avatar, emphasis nama inline, tab aktif. Berlaku juga untuk
  /// nama/emphasis DI ATAS media.
  static const strong = FontWeight.w600;

  /// HANYA body/caption/social-proof DI ATAS media (feed imersif + overlay
  /// author video). Floor lebih tinggi dari `body` supaya teks putih di atas
  /// video tetap terbaca.
  static const onMedia = FontWeight.w500;
}
