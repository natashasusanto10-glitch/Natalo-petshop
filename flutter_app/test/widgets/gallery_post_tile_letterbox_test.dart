import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/gallery_post_tile.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

FeedPost _post(String kind, {int? w, int? h}) {
  return FeedPost.fromJson({
    'id': 'p1',
    'slug': 'p1',
    'kind': kind,
    'author': {'id': 'a', 'name': 'X', 'role': 'CUSTOMER'},
    'mediaItems': [
      {'mediaUrl': 'https://example.com/m', 'kind': 'video'},
    ],
    if (w != null) 'videoWidth': w,
    if (h != null) 'videoHeight': h,
    'createdAt': '2026-07-15T00:00:00.000Z',
  });
}

void main() {
  group('gridThumbnailFit — paritas IG (video fitWidth, foto cover)', () {
    test('video landscape → fitWidth (letterbox atas-bawah)', () {
      expect(gridThumbnailFit(_post('VIDEO_ONLY', w: 1920, h: 1080)),
          BoxFit.fitWidth);
    });

    test('video portrait → fitWidth (penuh, tanpa bar kiri-kanan)', () {
      expect(gridThumbnailFit(_post('VIDEO_ONLY', w: 1080, h: 1920)),
          BoxFit.fitWidth);
    });

    test('video persegi → fitWidth', () {
      expect(gridThumbnailFit(_post('VIDEO_ONLY', w: 1080, h: 1080)),
          BoxFit.fitWidth);
    });

    test('video tanpa aspect post-level (fallback mediaItems) → fitWidth', () {
      final post = FeedPost.fromJson({
        'id': 'p3',
        'slug': 'p3',
        'kind': 'VIDEO_ONLY',
        'author': {'id': 'a', 'name': 'X', 'role': 'CUSTOMER'},
        'mediaItems': [
          {
            'mediaUrl': 'https://example.com/m.mp4',
            'mediaType': 'video',
            'width': 1920,
            'height': 1080,
          },
        ],
        'createdAt': '2026-07-15T00:00:00.000Z',
      });
      expect(gridThumbnailFit(post), BoxFit.fitWidth);
    });

    test('foto → cover (crop-fill, tak berubah)', () {
      final photo = FeedPost.fromJson({
        'id': 'p2',
        'slug': 'p2',
        'kind': 'PHOTO',
        'author': {'id': 'a', 'name': 'X', 'role': 'CUSTOMER'},
        'mediaItems': [
          {'mediaUrl': 'https://example.com/m', 'kind': 'PHOTO'},
        ],
        'videoWidth': 1920,
        'videoHeight': 1080,
        'createdAt': '2026-07-15T00:00:00.000Z',
      });
      expect(gridThumbnailFit(photo), BoxFit.cover);
      expect(gridVideoUsesBlackBackground(photo), isFalse);
    });

    test('video → latar hitam (bar letterbox rapi)', () {
      expect(
        gridVideoUsesBlackBackground(_post('VIDEO_ONLY', w: 1080, h: 1920)),
        isTrue,
      );
    });
  });
}
