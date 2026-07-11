import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/video_frame_thumbs.dart';

void main() {
  test('frameTimestampsMs merata: pertama=start, terakhir=start+span', () {
    final ts = frameTimestampsMs(startMs: 40000, spanMs: 20000, count: 5);
    expect(ts, [40000, 45000, 50000, 55000, 60000]);
  });

  test('extractVideoFrameThumbs memanggil extractor dengan timestamp absolut '
      'dan meneruskan hasil per-frame', () async {
    final calls = <int>[];
    final got = <int, Uint8List?>{};
    await extractVideoFrameThumbs(
      videoPath: 'v.mp4', startMs: 1000, spanMs: 4000, count: 3,
      extractor: (path, timeMs) async {
        calls.add(timeMs);
        return timeMs == 3000 ? null : Uint8List.fromList([1]);
      },
      onFrame: (i, bytes) => got[i] = bytes,
    );
    expect(calls, [1000, 3000, 5000]);
    expect(got[0], isNotNull);
    expect(got[1], isNull); // frame gagal → null, tidak melempar
    expect(got[2], isNotNull);
  });
}
