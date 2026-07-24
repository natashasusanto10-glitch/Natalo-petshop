import 'dart:ui' show Size;

import '../../../models/feed_post.dart';

// Batas potret video di halaman Postingan disamakan dengan Instagram feed
// (diukur dari screenshot iPhone 15 Pro: frame video IG ≈ 0.60 lebar/tinggi,
// yakni 3:5 — bukan 9:16). Video yang lebih tinggi dari 3:5 di-crop `cover`.
const double postinganVideoMinAspectRatio = 3 / 5;
const double postinganPhotoMinAspectRatio = 3 / 4;
const double postinganMaxAspectRatio = 1.91;

/// Resolves the inline media frame used by the Postingan detail page.
///
/// Video is allowed to be taller than photos so portrait clips keep the
/// immersive Reels-like framing. Photos and carousels use Instagram's 3:4
/// portrait boundary. Media inside each supported range keeps its source
/// ratio; only unusually tall or wide sources are cropped by the caller.
double resolvePostinganMediaAspectRatio({
  required int width,
  required int height,
  required FeedContentType type,
}) {
  final minAspectRatio = type == FeedContentType.video
      ? postinganVideoMinAspectRatio
      : postinganPhotoMinAspectRatio;

  if (width <= 0 || height <= 0) return minAspectRatio;

  final sourceAspectRatio = width / height;
  if (!sourceAspectRatio.isFinite || sourceAspectRatio <= 0) {
    return minAspectRatio;
  }

  return sourceAspectRatio
      .clamp(minAspectRatio, postinganMaxAspectRatio)
      .toDouble();
}

/// Aspect ratio KOTAK video halaman Postingan.
///
/// Pakai ukuran video ASLI [liveSize] (dari `controller.value.size`, sudah
/// dirotasi benar oleh player) begitu tersedia & valid; sebelum controller
/// siap, fallback ke [fallbackAspectRatio] (dari metadata tersimpan).
///
/// KENAPA: sebagian video punya metadata dimensi SALAH (landscape untuk video
/// portrait — sisa bug rotasi Bunny). Membangun kotak dari metadata itu bikin
/// video portrait masuk kotak lebar → bar hitam kiri-kanan. Ukuran asli
/// controller selalu benar, jadi jadikan itu sumber saat ada.
///
/// Rasio live HARUS di-clamp ke batas [postinganVideoMinAspectRatio] yang
/// sama dengan fallback (bukan cuma cap maksimum) — video 9:16 asli (0.5625)
/// lebih kurus dari batas IG 3:5 (0.6); tanpa clamp minimum ini, kotak
/// melompat lebih tinggi tepat saat controller siap (~saat autoplay mulai),
/// karena tinggi kotak = lebar/rasio. IG meng-crop `cover` video vertikal
/// penuh ke bingkai 3:5 — kotak tidak pernah berubah ukuran saat play.
double resolvePostinganVideoBoxAspectRatio({
  required double fallbackAspectRatio,
  Size? liveSize,
}) {
  if (liveSize != null && liveSize.width > 0 && liveSize.height > 0) {
    final sourceAspectRatio = liveSize.width / liveSize.height;
    if (!sourceAspectRatio.isFinite || sourceAspectRatio <= 0) {
      return fallbackAspectRatio;
    }
    return sourceAspectRatio
        .clamp(postinganVideoMinAspectRatio, postinganMaxAspectRatio)
        .toDouble();
  }
  return fallbackAspectRatio;
}
