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
