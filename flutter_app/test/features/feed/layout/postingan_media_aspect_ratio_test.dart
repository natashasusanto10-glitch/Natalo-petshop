import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/layout/postingan_media_aspect_ratio.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

void main() {
  group('resolvePostinganMediaAspectRatio', () {
    group('video', () {
      test('clamps video taller than 9:16 to the portrait limit', () {
        final ratio = resolvePostinganMediaAspectRatio(
          width: 1080,
          height: 2160,
          type: FeedContentType.video,
        );

        expect(ratio, closeTo(9 / 16, 0.000001));
      });

      test('preserves video ratios inside the supported range', () {
        expect(
          resolvePostinganMediaAspectRatio(
            width: 1080,
            height: 1920,
            type: FeedContentType.video,
          ),
          closeTo(9 / 16, 0.000001),
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

      test('clamps overly wide video and uses 9:16 for invalid metadata', () {
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
          closeTo(9 / 16, 0.000001),
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
}
