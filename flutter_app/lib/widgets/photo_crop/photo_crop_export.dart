import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Args bundle untuk worker isolate [processPhotoInIsolate]. Harus
/// `@immutable` + plain types supaya bisa di-serialize cross-isolate boundary
/// lewat `compute()`. File path di-pass sebagai string; worker baca file dari
/// sana, decode, crop/resize, encode JPEG, dan tulis output ke [tmpDirPath]
/// lalu return path output.
@immutable
class PhotoProcessArgs {
  final String sourcePath;
  final String tmpDirPath;

  /// Aspect target frame crop (lebar/tinggi). Feed picker pakai 4/5 (0.8);
  /// profile picker pakai 1.0 (square).
  final double targetAspect;
  final double scale;
  final double offsetFractionX;
  final double offsetFractionY;

  /// Kalau true, skip crop — hanya bake orientation + resize (dipakai feed
  /// picker mode "fit original"). Profile picker selalu false (selalu crop
  /// square).
  final bool preserveOriginal;
  final int maxLongSide;
  final int jpegQuality;
  final int timestampSuffix;
  final String pathSeparator;

  const PhotoProcessArgs({
    required this.sourcePath,
    required this.tmpDirPath,
    required this.targetAspect,
    required this.scale,
    required this.offsetFractionX,
    required this.offsetFractionY,
    required this.preserveOriginal,
    required this.maxLongSide,
    required this.jpegQuality,
    required this.timestampSuffix,
    required this.pathSeparator,
  });
}

/// Top-level (BUKAN method) supaya bisa dipanggil dari `compute()` — closures
/// di method punya `this` reference yang tidak bisa di-serialize. Heavy work
/// decode + bakeOrientation + crop + resize + encode JPEG semua jalan di
/// background isolate; main thread tetap responsif. Return path file output
/// JPEG di tmpDir.
///
/// Model crop cocok 1:1 dengan render `PhotoCropPreview`: frame dinormalisasi
/// (frameW = [PhotoProcessArgs.targetAspect], frameH = 1.0), image di-cover-fit
/// lalu di-scale + di-offset sesuai transform user, dan crop window dihitung
/// balik ke koordinat source. Karena offset disimpan sebagai fraksi frame,
/// hasilnya identik terlepas dari ukuran piksel preview di device.
String processPhotoInIsolate(PhotoProcessArgs args) {
  final source = File(args.sourcePath);
  final bytes = source.readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    // Fallback: tidak bisa decode → return source path apa adanya. Caller
    // akan upload file original; backend tolak format kalau beneran corrupt.
    return args.sourcePath;
  }
  final oriented = img.bakeOrientation(decoded);

  img.Image processed;
  if (args.preserveOriginal) {
    processed = oriented;
  } else {
    final srcW = oriented.width;
    final srcH = oriented.height;
    final frameW = args.targetAspect;
    const frameH = 1.0;
    final coverScale = math.max(frameW / srcW, frameH / srcH);
    final baseW = srcW * coverScale;
    final baseH = srcH * coverScale;
    final visualScale = args.scale.clamp(1.0, 4.0).toDouble();
    final scaledW = baseW * visualScale;
    final scaledH = baseH * visualScale;
    final offsetX = args.offsetFractionX * frameW;
    final offsetY = args.offsetFractionY * frameH;

    final imageLeft = (frameW - scaledW) / 2 + offsetX;
    final imageTop = (frameH - scaledH) / 2 + offsetY;
    final cropX = (-imageLeft / scaledW) * srcW;
    final cropY = (-imageTop / scaledH) * srcH;
    final cropW = (frameW / scaledW) * srcW;
    final cropH = (frameH / scaledH) * srcH;

    final cropWInt = cropW.round().clamp(1, srcW).toInt();
    final cropHInt = cropH.round().clamp(1, srcH).toInt();
    final cropXInt =
        cropX.round().clamp(0, math.max(0, srcW - cropWInt)).toInt();
    final cropYInt =
        cropY.round().clamp(0, math.max(0, srcH - cropHInt)).toInt();

    processed = img.copyCrop(
      oriented,
      x: cropXInt,
      y: cropYInt,
      width: cropWInt,
      height: cropHInt,
    );
  }

  // Resize ke max long-side kalau perlu (output upload friendly).
  final longSide =
      processed.width > processed.height ? processed.width : processed.height;
  if (longSide > args.maxLongSide) {
    if (processed.height >= processed.width) {
      processed = img.copyResize(
        processed,
        height: args.maxLongSide,
        interpolation: img.Interpolation.linear,
      );
    } else {
      processed = img.copyResize(
        processed,
        width: args.maxLongSide,
        interpolation: img.Interpolation.linear,
      );
    }
  }

  final jpegBytes = img.encodeJpg(processed, quality: args.jpegQuality);
  final ts = DateTime.now().microsecondsSinceEpoch + args.timestampSuffix;
  final outPath = '${args.tmpDirPath}${args.pathSeparator}natalo_crop_$ts.jpg';
  File(outPath).writeAsBytesSync(jpegBytes, flush: true);
  return outPath;
}
