import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

Map<String, dynamic> _postJson({
  bool? viewerSaved,
  List<Map<String, dynamic>> products = const [],
}) {
  return {
    'id': 'post-1',
    'slug': 'post-1',
    'kind': 'PHOTO',
    'author': {'id': 'author-1', 'name': 'Tester'},
    'products': products,
    'createdAt': '2026-07-15T00:00:00.000Z',
    if (viewerSaved != null) 'viewerSaved': viewerSaved,
  };
}

void main() {
  test('viewerSaved defaults false for backward-compatible payloads', () {
    final post = FeedPost.fromJson(_postJson());

    expect(post.viewerSaved, isFalse);
  });

  test('viewerSaved parses, copies, and serializes independently of like', () {
    final saved = FeedPost.fromJson(_postJson(viewerSaved: true));
    final removed = saved.copyWith(viewerSaved: false);

    expect(saved.viewerSaved, isTrue);
    expect(saved.viewerLiked, isFalse);
    expect(saved.toJson()['viewerSaved'], isTrue);
    expect(removed.viewerSaved, isFalse);
    expect(removed.viewerLiked, isFalse);
  });

  test('hasLinkedProducts recognizes normalized product collections', () {
    final post = FeedPost.fromJson(
      _postJson(
        products: [
          {
            'id': 'product-1',
            'slug': 'product-1',
            'name': 'Makanan Kucing',
            'price': 25000,
          },
        ],
      ),
    );

    expect(post.hasLinkedProducts, isTrue);
    expect(FeedPost.fromJson(_postJson()).hasLinkedProducts, isFalse);
  });
}
