import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';

void main() {
  test('fetchHashtagPosts parse name+postCount+posts+cursor', () async {
    final result = HashtagPageResult.fromJson({
      'name': 'kucing',
      'postCount': 3,
      'posts': [
        {
          'id': 'p1',
          'slug': 'p1',
          'kind': 'PHOTO_CAROUSEL',
          'author': {'id': 'u1', 'name': 'Budi'},
          'createdAt': '2026-07-23T00:00:00.000Z',
        }
      ],
      'nextCursor': 'p1',
    });
    expect(result.name, 'kucing');
    expect(result.postCount, 3);
    expect(result.posts.single.id, 'p1');
    expect(result.nextCursor, 'p1');
  });

  test('HashtagSuggestion parse + list kosong aman', () {
    final s = HashtagSuggestion.fromJson({'name': 'kucing', 'postCount': 24});
    expect(s.name, 'kucing');
    expect(s.postCount, 24);
  });
}
