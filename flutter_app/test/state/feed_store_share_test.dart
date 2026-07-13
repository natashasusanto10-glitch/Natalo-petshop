import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';

FeedPost _post(String id, {required int shareCount}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/$id.mp4',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'durationSec': 10,
    'aspectRatio': 0.5625,
    'author': {'id': 'author-$id', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': shareCount,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  test('share count remains in the shared store across widget rebuilds', () {
    const id = 'share-store-rebuild-test';
    feedStore.seed([_post(id, shareCount: 0)]);

    expect(feedStore.incrementShareCount(id), 1);
    expect(feedStore.get(id)?.shareCount, 1);

    feedStore.setShareCount(id, 4);
    expect(feedStore.get(id)?.shareCount, 4);
  });

  test('stale feed response cannot overwrite a newer local share', () {
    const id = 'share-store-stale-test';
    feedStore.seed([_post(id, shareCount: 0)]);
    final fetchStartedAt = DateTime.now().subtract(const Duration(seconds: 1));

    feedStore.incrementShareCount(id);
    feedStore.mergeFromServer(
      [_post(id, shareCount: 0)],
      fetchedAt: fetchStartedAt,
    );

    expect(feedStore.get(id)?.shareCount, 1);
  });
}
