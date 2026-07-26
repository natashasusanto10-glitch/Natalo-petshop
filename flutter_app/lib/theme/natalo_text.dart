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

/// Skala ukuran font tunggal. Pendamping [NataloWeight] — bobot diatur di
/// sana, ukuran di sini.
///
/// Sebelum skala ini ada, halaman transaksi sendirian memakai 17 ukuran
/// berbeda termasuk nilai setengah-poin (10.5 / 11.5 / 12.5 / 13.5 / 14.5).
/// Nilai setengah-poin hampir selalu tambal-sulam overflow, bukan keputusan
/// hierarki: teks kepanjangan lalu dikecilkan sedikit sampai muat. Kalau teks
/// tidak muat, perbaiki layout-nya — jangan tambah ukuran baru di sini.
///
/// UI baru WAJIB pakai token ini, bukan literal `fontSize:`.
abstract final class NataloTextSize {
  /// 11px: label mungil di dalam badge/pill, timestamp, superscript.
  /// Jangan dipakai untuk body — 11 adalah lantai keterbacaan.
  static const double micro = 11;

  /// 12px: caption, metadata, label sekunder. Ukuran teks kecil paling umum.
  static const double caption = 12;

  /// 13px: body default untuk teks padat (baris item, rincian).
  static const double body = 13;

  /// 14px: body utama & label tombol. Basis keterbacaan layar konten.
  static const double bodyLg = 14;

  /// 16px: subjudul section, angka nominal menonjol.
  static const double subtitle = 16;

  /// 18px: judul halaman & judul kartu utama.
  static const double title = 18;

  /// 24px: judul hero layar konfirmasi/perayaan. Satu tingkat di atas
  /// [title]; jangan dipakai sebagai judul halaman biasa.
  static const double headline = 24;

  /// 32px: angka tunggal berukuran hero (mis. total di layar sukses).
  static const double display = 32;
}
