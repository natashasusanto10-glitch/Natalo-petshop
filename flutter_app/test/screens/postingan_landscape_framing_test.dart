import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';

FeedPost _post(
  String kind, {
  int? w,
  int? h,
  String mediaKind = 'video',
}) {
  return FeedPost.fromJson({
    'id': 'p1',
    'slug': 'p1',
    'kind': kind,
    'author': {'id': 'a', 'name': 'X', 'role': 'CUSTOMER'},
    'mediaItems': [
      {'mediaUrl': 'https://example.com/m', 'kind': mediaKind},
    ],
    if (w != null) 'videoWidth': w,
    if (h != null) 'videoHeight': h,
    'createdAt': '2026-07-15T00:00:00.000Z',
  });
}

void main() {
  group('postVideoUsesOverlay — overlay vs baris author', () {
    test('video 9:16 penuh → overlay (true)', () {
      expect(postVideoUsesOverlay(_post('VIDEO_ONLY', w: 1080, h: 1920)),
          isTrue);
    });

    test('video landscape → baris terpisah (false)', () {
      expect(postVideoUsesOverlay(_post('VIDEO_ONLY', w: 1920, h: 1080)),
          isFalse);
    });

    test('video persegi → baris terpisah juga (false, bukan 9:16 penuh)', () {
      expect(postVideoUsesOverlay(_post('VIDEO_ONLY', w: 1080, h: 1080)),
          isFalse);
    });

    test('video portrait 4:5 (iklan non-native) → baris terpisah (false)', () {
      expect(postVideoUsesOverlay(_post('VIDEO_ONLY', w: 1080, h: 1350)),
          isFalse);
    });

    test('video portrait 3:4 → baris terpisah (false)', () {
      expect(postVideoUsesOverlay(_post('VIDEO_ONLY', w: 1080, h: 1440)),
          isFalse);
    });

    test('video tanpa dimensi → overlay (default 9:16 penuh)', () {
      expect(postVideoUsesOverlay(_post('VIDEO_ONLY')), isTrue);
    });

    test('foto → tak pernah overlay (false)', () {
      expect(
        postVideoUsesOverlay(_post('PHOTO', mediaKind: 'PHOTO')),
        isFalse,
      );
    });
  });

  group('resolveFeedCoverFit — Opsi C (fill 9:16, letterbox sisanya)', () {
    // Viewport iPhone 15 Pro (lebar/tinggi) — layar tinggi 19.5:9.
    const viewport = 393 / 852; // ≈ 0.461

    test('fullscreen + landscape 16:9 → contain (letterbox, tak berubah)', () {
      expect(
        resolveFeedCoverFit(
          framing: FeedVideoFraming.fullscreenFeed,
          mediaAspectRatio: 1920 / 1080,
          viewportAspectRatio: viewport,
        ),
        BoxFit.contain,
      );
    });

    test('fullscreen + portrait 9:16 → cover (full-bleed ala IG)', () {
      expect(
        resolveFeedCoverFit(
          framing: FeedVideoFraming.fullscreenFeed,
          mediaAspectRatio: 1080 / 1920,
          viewportAspectRatio: viewport,
        ),
        BoxFit.cover,
      );
    });

    test('fullscreen + portrait 4:5 → contain (crop terlalu banyak)', () {
      expect(
        resolveFeedCoverFit(
          framing: FeedVideoFraming.fullscreenFeed,
          mediaAspectRatio: 1080 / 1350,
          viewportAspectRatio: viewport,
        ),
        BoxFit.contain,
      );
    });

    test('fullscreen + persegi 1:1 → contain (letterbox)', () {
      expect(
        resolveFeedCoverFit(
          framing: FeedVideoFraming.fullscreenFeed,
          mediaAspectRatio: 1,
          viewportAspectRatio: viewport,
        ),
        BoxFit.contain,
      );
    });

    test('mainFeed + landscape → contain (tak berubah)', () {
      expect(
        resolveFeedCoverFit(
          framing: FeedVideoFraming.mainFeed,
          mediaAspectRatio: 1920 / 1080,
          viewportAspectRatio: viewport,
        ),
        BoxFit.contain,
      );
    });

    test('mainFeed + portrait 9:16 → cover (full-bleed ala IG)', () {
      expect(
        resolveFeedCoverFit(
          framing: FeedVideoFraming.mainFeed,
          mediaAspectRatio: 1080 / 1920,
          viewportAspectRatio: viewport,
        ),
        BoxFit.cover,
      );
    });

    test('immersive → cover (jalur lama, tak lewat kebijakan feed)', () {
      expect(
        resolveFeedCoverFit(
          framing: FeedVideoFraming.immersive,
          mediaAspectRatio: 1080 / 1920,
          viewportAspectRatio: viewport,
        ),
        BoxFit.cover,
      );
    });
  });
}
