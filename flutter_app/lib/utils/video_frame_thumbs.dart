import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart';

/// Timestamp N frame tersebar merata di `[startMs, startMs+spanMs]` (pure,
/// testable). `count` >= 2; frame pertama = `startMs`, terakhir =
/// `startMs+spanMs`.
List<int> frameTimestampsMs({
  required int startMs,
  required int spanMs,
  required int count,
}) {
  assert(count >= 2, 'count harus >= 2 supaya first/last frame terdefinisi');
  return List<int>.generate(count, (i) {
    // i / (count-1) supaya frame pertama = startMs, terakhir = startMs+spanMs.
    return startMs + ((spanMs * i) / (count - 1)).round();
  });
}

/// Ekstrak frame progresif — `onFrame(i, bytes)` dipanggil per frame jadi.
/// `extractor` injectable untuk test (default `VideoThumbnail.thumbnailData`).
/// Frame yang gagal extract → `bytes` null, TIDAK melempar (skip & lanjut).
Future<void> extractVideoFrameThumbs({
  required String videoPath,
  required int startMs,
  required int spanMs,
  int count = 10,
  int maxWidth = 120,
  int quality = 50,
  required void Function(int index, Uint8List? bytes) onFrame,
  Future<Uint8List?> Function(String path, int timeMs)? extractor,
}) async {
  final doExtract = extractor ??
      (String path, int timeMs) => VideoThumbnail.thumbnailData(
            video: path,
            imageFormat: ImageFormat.JPEG,
            quality: quality,
            maxWidth: maxWidth,
            timeMs: timeMs,
          );
  final timestamps = frameTimestampsMs(
    startMs: startMs,
    spanMs: spanMs,
    count: count,
  );
  for (var i = 0; i < timestamps.length; i++) {
    Uint8List? bytes;
    try {
      bytes = await doExtract(videoPath, timestamps[i]);
    } catch (_) {
      // Skip frame yang gagal extract — tidak melempar ke caller.
      bytes = null;
    }
    onFrame(i, bytes);
  }
}
