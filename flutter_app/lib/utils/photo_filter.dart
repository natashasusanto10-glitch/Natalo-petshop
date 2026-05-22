import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Preset filter foto untuk feed posting — pakai `ColorFilter.matrix()`
/// built-in Flutter (GPU-accelerated, zero plugin baru).
///
/// Quality target: ~6/10 dibanding IG Clarendon (yang pakai LUT .cube
/// dengan transform non-linear). Untuk pet shop Indonesia, ColorMatrix
/// sudah cukup — user notice ada filter, foto pet kelihatan lebih cakep,
/// goal achieved tanpa overhead native plugin.
///
/// Filter biased ke use case Natalo:
/// - vivid → pet warna cerah, pakan packaging
/// - warm → outdoor / golden hour pet
/// - cool → aquarium, ikan
/// - mono → dramatic shot
/// - soft → pet sleeping, baby pet
enum PhotoFilter {
  none,
  vivid,
  warm,
  cool,
  mono,
  soft;

  /// Display name di filter strip.
  String get label {
    switch (this) {
      case PhotoFilter.none:
        return 'Original';
      case PhotoFilter.vivid:
        return 'Vivid';
      case PhotoFilter.warm:
        return 'Warm';
      case PhotoFilter.cool:
        return 'Cool';
      case PhotoFilter.mono:
        return 'Mono';
      case PhotoFilter.soft:
        return 'Soft';
    }
  }

  /// ColorFilter untuk render preview live (gratis, GPU shader). Return
  /// null untuk `none` supaya widget tidak wrap dengan `ColorFiltered`
  /// (sedikit lebih hemat render pass).
  ColorFilter? get colorFilter {
    final m = matrix;
    if (m == null) return null;
    return ColorFilter.matrix(m);
  }

  /// 4x5 color matrix (20 angka, baris-major: R, G, B, A, masing-masing
  /// dengan 5 koefisien [R, G, B, A, offset]).
  ///
  /// Identity matrix (untuk `none`) di-skip — return null supaya skip
  /// render pass.
  List<double>? get matrix {
    switch (this) {
      case PhotoFilter.none:
        return null;
      case PhotoFilter.vivid:
        // +30% saturation, sedikit contrast bump. Multiply RGB dengan
        // 1.3 di diagonal, balance dengan -15 offset supaya tidak
        // washed-out di highlight.
        return [
          1.3,  -0.15, -0.15, 0, 0,
          -0.15, 1.3,  -0.15, 0, 0,
          -0.15, -0.15, 1.3,  0, 0,
          0,     0,     0,    1, 0,
        ];
      case PhotoFilter.warm:
        // Yellow/orange shift — boost R + G, drop B. Plus subtle warm tint
        // di offset (R +10, G +5).
        return [
          1.15, 0.05, 0,    0, 10,
          0.05, 1.1,  0,    0, 5,
          0,    0,    0.9,  0, -5,
          0,    0,    0,    1, 0,
        ];
      case PhotoFilter.cool:
        // Blue shift — boost B, slight G, drop R. Cocok untuk aquarium
        // / indoor AC vibe.
        return [
          0.9, 0,    0,    0, -5,
          0,   1.05, 0.05, 0, 0,
          0,   0.05, 1.2,  0, 10,
          0,   0,    0,    1, 0,
        ];
      case PhotoFilter.mono:
        // Black & white via luminance weights ITU-R BT.601 (R=0.299,
        // G=0.587, B=0.114). Hasil grayscale natural, bukan equal-weight
        // yang flat.
        return [
          0.299, 0.587, 0.114, 0, 0,
          0.299, 0.587, 0.114, 0, 0,
          0.299, 0.587, 0.114, 0, 0,
          0,     0,     0,     1, 0,
        ];
      case PhotoFilter.soft:
        // Slight desaturate (mix 30% gray) + warm tint + brightness bump
        // (+8 di tiap channel). Vibe "soft golden hour".
        return [
          0.8, 0.15, 0.05, 0, 12,
          0.1, 0.85, 0.05, 0, 10,
          0.1, 0.1,  0.8,  0, 6,
          0,   0,    0,    1, 0,
        ];
    }
  }
}

/// Apply filter ke file image → return new File hasil filter di temp
/// directory. Kalau filter == none, return file asli (skip overhead).
///
/// Cara kerja: decode image bytes → render ke off-screen canvas dengan
/// `ColorFilter.matrix()` applied → encode kembali ke PNG bytes →
/// write ke temp file.
///
/// Output PNG (lossless) supaya tidak compound compression artifact dengan
/// step compress berikutnya di `feed_photo_service` (yang convert ke JPEG
/// quality 75). Net result: 1 lossy step di akhir, bukan 2.
Future<File> applyPhotoFilter(File source, PhotoFilter filter) async {
  if (filter == PhotoFilter.none) return source;
  final matrix = filter.matrix;
  if (matrix == null) return source;

  try {
    final sourceBytes = await source.readAsBytes();
    final filteredBytes = await _bakeFilterToBytes(sourceBytes, matrix);
    if (filteredBytes == null) return source;

    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/feed_filter_${filter.name}_${DateTime.now().millisecondsSinceEpoch}.png';
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(filteredBytes);
    return outputFile;
  } catch (_) {
    // Filter bake fail jangan break flow upload — fallback ke source asli.
    // User dapat foto tanpa filter, lebih baik dari upload gagal total.
    return source;
  }
}

/// Internal: decode bytes → apply matrix → encode PNG bytes. Pure
/// `dart:ui` — no extra package needed.
Future<Uint8List?> _bakeFilterToBytes(
  Uint8List sourceBytes,
  List<double> matrix,
) async {
  final codec = await ui.instantiateImageCodec(sourceBytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..colorFilter = ColorFilter.matrix(matrix);
    canvas.drawImage(image, Offset.zero, paint);
    final picture = recorder.endRecording();
    try {
      final filteredImage = await picture.toImage(image.width, image.height);
      try {
        final byteData =
            await filteredImage.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      } finally {
        filteredImage.dispose();
      }
    } finally {
      picture.dispose();
    }
  } finally {
    image.dispose();
  }
}
