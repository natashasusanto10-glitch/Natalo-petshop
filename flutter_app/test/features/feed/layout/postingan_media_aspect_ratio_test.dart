import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/layout/postingan_media_aspect_ratio.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

void main() {
  group('resolvePostinganMediaAspectRatio', () {
    group('video', () {
      test('clamps video taller than 3:5 to the portrait limit', () {
        final ratio = resolvePostinganMediaAspectRatio(
          width: 1080,
          height: 2160,
          type: FeedContentType.video,
        );

        expect(ratio, closeTo(3 / 5, 0.000001));
      });

      test('preserves video ratios inside the supported range', () {
        // 9:16 (0.5625) kini lebih tinggi dari batas IG 3:5 (0.6), jadi
        // di-clamp ke 3:5.
        expect(
          resolvePostinganMediaAspectRatio(
            width: 1080,
            height: 1920,
            type: FeedContentType.video,
          ),
          closeTo(3 / 5, 0.000001),
        );
        expect(
          resolvePostinganMediaAspectRatio(
            width: 1080,
            height: 1350,
            type: FeedContentType.video,
          ),
          closeTo(4 / 5, 0.000001),
        );
        expect(
          resolvePostinganMediaAspectRatio(
            width: 1080,
            height: 1080,
            type: FeedContentType.video,
          ),
          1,
        );
        expect(
          resolvePostinganMediaAspectRatio(
            width: 1920,
            height: 1080,
            type: FeedContentType.video,
          ),
          closeTo(16 / 9, 0.000001),
        );
      });

      test('clamps overly wide video and uses 3:5 for invalid metadata', () {
        expect(
          resolvePostinganMediaAspectRatio(
            width: 2000,
            height: 1000,
            type: FeedContentType.video,
          ),
          1.91,
        );
        expect(
          resolvePostinganMediaAspectRatio(
            width: 0,
            height: 0,
            type: FeedContentType.video,
          ),
          closeTo(3 / 5, 0.000001),
        );
      });
    });

    group('photo and carousel', () {
      test('clamps tall media to the 3:4 inline portrait limit', () {
        for (final type in [
          FeedContentType.photo,
          FeedContentType.carousel,
        ]) {
          expect(
            resolvePostinganMediaAspectRatio(
              width: 1080,
              height: 1920,
              type: type,
            ),
            closeTo(3 / 4, 0.000001),
          );
        }
      });

      test('preserves common ratios inside the supported range', () {
        for (final dimensions in [
          (width: 900, height: 1200, expected: 3 / 4),
          (width: 1080, height: 1350, expected: 4 / 5),
          (width: 1080, height: 1080, expected: 1.0),
          (width: 1920, height: 1080, expected: 16 / 9),
        ]) {
          expect(
            resolvePostinganMediaAspectRatio(
              width: dimensions.width,
              height: dimensions.height,
              type: FeedContentType.photo,
            ),
            closeTo(dimensions.expected, 0.000001),
          );
        }
      });

      test('clamps overly wide media and uses 3:4 for invalid metadata', () {
        expect(
          resolvePostinganMediaAspectRatio(
            width: 2000,
            height: 1000,
            type: FeedContentType.carousel,
          ),
          1.91,
        );
        expect(
          resolvePostinganMediaAspectRatio(
            width: -1,
            height: 0,
            type: FeedContentType.photo,
          ),
          closeTo(3 / 4, 0.000001),
        );
      });
    });
  });

  group('resolvePostinganVideoBoxAspectRatio — pilih ukuran asli vs fallback', () {
    // fallback landscape 16:9 = 1.7778 (mensimulasikan metadata SALAH).
    const fallbackLandscape = 16 / 9;

    test('liveSize null (controller belum siap) → pakai fallback', () {
      expect(
        resolvePostinganVideoBoxAspectRatio(
          fallbackAspectRatio: fallbackLandscape,
          liveSize: null,
        ),
        fallbackLandscape,
      );
    });

    test('KUNCI: liveSize portrait walau fallback landscape → rasio portrait '
        'DI-CLAMP ke batas 3:5 (kotak tak melompat tinggi saat controller '
        'siap; video 9:16 di-crop cover, sama seperti fallback & IG)', () {
      final r = resolvePostinganVideoBoxAspectRatio(
        fallbackAspectRatio: fallbackLandscape,
        liveSize: const Size(1080, 1920),
      );
      expect(r, closeTo(3 / 5, 1e-9));
    });

    test('liveSize landscape lebih lebar dari 1.91 → clamp 1.91 '
        '(kotak dibatasi; sisi kelebihan video di-crop oleh BoxFit.cover '
        'di player, bukan letterbox)', () {
      final r = resolvePostinganVideoBoxAspectRatio(
        fallbackAspectRatio: 9 / 16,
        liveSize: const Size(2560, 1080), // 2.37
      );
      expect(r, closeTo(1.91, 1e-9));
    });

    test('liveSize 0/invalid → pakai fallback', () {
      expect(
        resolvePostinganVideoBoxAspectRatio(
          fallbackAspectRatio: fallbackLandscape,
          liveSize: const Size(0, 0),
        ),
        fallbackLandscape,
      );
    });

    test('liveSize portrait normal 9:16, fallback juga sudah 3:5 (biasa) → '
        'tetap di-clamp ke 3:5, kotak stabil', () {
      final r = resolvePostinganVideoBoxAspectRatio(
        fallbackAspectRatio: 3 / 5,
        liveSize: const Size(1080, 1920),
      );
      expect(r, closeTo(3 / 5, 1e-9));
    });

    test('liveSize sedikit lebih kurus dari batas min (mis. 0.58) → '
        'di-clamp ke 3:5, bukan dibiarkan lebih kurus', () {
      final r = resolvePostinganVideoBoxAspectRatio(
        fallbackAspectRatio: 3 / 5,
        liveSize: const Size(1080, 1862), // 0.58...
      );
      expect(r, closeTo(3 / 5, 1e-9));
    });
  });
}
