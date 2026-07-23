import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

Map<String, dynamic> _postJson({bool? viewerTagHidden}) {
  return {
    'id': 'post-1',
    'slug': 'post-1',
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/video.mp4',
    'author': {'id': 'author-1', 'name': 'Natalo Petshop'},
    'createdAt': '2026-07-15T00:00:00.000Z',
    'taggedUsers': [
      {'userId': 'self1', 'username': 'aku', 'name': 'Aku'},
    ],
    if (viewerTagHidden != null) 'viewerTagHidden': viewerTagHidden,
  };
}

void main() {
  test('fromJson: viewerTagHidden true di-parse apa adanya', () {
    final post = FeedPost.fromJson(_postJson(viewerTagHidden: true));
    expect(post.viewerTagHidden, isTrue);
  });

  test('fromJson: viewerTagHidden false di-parse apa adanya', () {
    final post = FeedPost.fromJson(_postJson(viewerTagHidden: false));
    expect(post.viewerTagHidden, isFalse);
  });

  test('fromJson: viewerTagHidden absen (legacy/anon) → null', () {
    final post = FeedPost.fromJson(_postJson());
    expect(post.viewerTagHidden, isNull);
  });

  // Regresi kritis: copyWith dipanggil SANGAT sering di feed_store.dart
  // (like/comment/share/save count updates) untuk field yang TIDAK
  // berhubungan dengan viewerTagHidden sama sekali. Tanpa
  // `viewerTagHidden: viewerTagHidden ?? this.viewerTagHidden` di copyWith,
  // update APA PUN akan diam-diam me-reset viewerTagHidden ke null,
  // menghapus seed server begitu user like/comment/share/save post ini.
  test(
      'copyWith: viewerTagHidden BERTAHAN saat copyWith field lain dipanggil '
      '(tidak diam-diam ter-reset ke null)', () {
    final original =
        FeedPost.fromJson(_postJson(viewerTagHidden: true));
    final afterLike = original.copyWith(viewerLiked: true, likeCount: 5);
    expect(afterLike.viewerTagHidden, isTrue);

    final falseOriginal =
        FeedPost.fromJson(_postJson(viewerTagHidden: false));
    final afterShare = falseOriginal.copyWith(shareCount: 2);
    expect(afterShare.viewerTagHidden, isFalse);
  });

  test('copyWith: viewerTagHidden bisa di-override eksplisit', () {
    final original = FeedPost.fromJson(_postJson(viewerTagHidden: false));
    final updated = original.copyWith(viewerTagHidden: true);
    expect(updated.viewerTagHidden, isTrue);
  });

  test('toJson: viewerTagHidden round-trip (lossless untuk cache lokal)', () {
    final post = FeedPost.fromJson(_postJson(viewerTagHidden: true));
    final roundTripped = FeedPost.fromJson(post.toJson());
    expect(roundTripped.viewerTagHidden, isTrue);
  });
}
