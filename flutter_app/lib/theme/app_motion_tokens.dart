library;

import 'package:flutter/animation.dart';

/// Motion tokens terpusat — pasangan durasi/kurva standar untuk seluruh app.
///
/// Sebelum token ini, durasi motion tersebar hardcoded di ~140 call site
/// (320/340/360/380/420ms dst). Warna/radius/spacing/type sudah lama
/// ter-token; motion adalah yang terakhir. Gunakan nilai di sini untuk
/// kode baru; migrasi bertahap untuk kode lama (jangan mass-rewrite).
///
/// Prinsip (Emil Kowalski / Material motion):
/// - Aksi frekuensi tinggi (tab, scroll-linked): cepat atau tanpa animasi.
/// - Masuk = ease-out family; keluar boleh ease-in; gerak on-screen = in-out.
/// - UI micro-interaction < 300ms.
abstract final class AppMotionTokens {
  /// Feedback tekan (scale on press) — instan terasa.
  static const Duration press = Duration(milliseconds: 120);

  /// Transisi cepat: swap ikon/label, tooltip kecil.
  static const Duration quick = Duration(milliseconds: 180);

  /// Durasi standar: fade content, collapse nav, chip, tab indicator.
  static const Duration standard = Duration(milliseconds: 240);

  /// Masuk/keluar route & sheet non-kritis.
  static const Duration route = Duration(milliseconds: 260);

  /// Modal/sheet besar + hero flight (atas batas 300ms — disengaja untuk
  /// elemen besar yang butuh waktu terbaca).
  static const Duration modal = Duration(milliseconds: 380);

  /// Kurva masuk standar — ease-out kuat ala iOS decelerate.
  static const Cubic curveEnter = Cubic(0.32, 0.72, 0, 1);

  /// Kurva emphasized untuk gerak on-screen (nav pill dsb).
  static const Cubic curveEmphasized = Cubic(0.22, 1, 0.36, 1);

  /// Kurva keluar halus.
  static const Cubic curveExit = Curves.easeInCubic;
}
