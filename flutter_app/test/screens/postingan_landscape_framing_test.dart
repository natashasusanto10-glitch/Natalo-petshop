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
    test('video portrait → overlay (true)', () {
      expect(postVideoUsesOverlay(_post('VIDEO_ONLY', w: 1080, h: 1920)),
          isTrue);
    });

    test('video landscape → baris terpisah (false)', () {
      expect(postVideoUsesOverlay(_post('VIDEO_ONLY', w: 1920, h: 1080)),
          isFalse);
    });

    test('video persegi → overlay (true, diperlakukan seperti portrait)', () {
      expect(postVideoUsesOverlay(_post('VIDEO_ONLY', w: 1080, h: 1080)),
          isTrue);
    });

    test('video tanpa dimensi → overlay (default portrait)', () {
      expect(postVideoUsesOverlay(_post('VIDEO_ONLY')), isTrue);
    });

    test('foto → tak pernah overlay (false)', () {
      expect(
        postVideoUsesOverlay(_post('PHOTO', mediaKind: 'PHOTO')),
        isFalse,
      );
    });
  });

  group('resolveFeedCoverFit — letterbox fullscreen landscape', () {
    test('fullscreen + landscape → contain (letterbox)', () {
      expect(
        resolveFeedCoverFit(
          framing: FeedVideoFraming.fullscreenFeed,
          isLandscape: true,
        ),
        BoxFit.contain,
      );
    });

    test('fullscreen + portrait → cover (isi penuh)', () {
      expect(
        resolveFeedCoverFit(
          framing: FeedVideoFraming.fullscreenFeed,
          isLandscape: false,
        ),
        BoxFit.cover,
      );
    });

    test('mainFeed + landscape → tetap cover (feed utama tak diubah)', () {
      expect(
        resolveFeedCoverFit(
          framing: FeedVideoFraming.mainFeed,
          isLandscape: true,
        ),
        BoxFit.cover,
      );
    });
  });
}
