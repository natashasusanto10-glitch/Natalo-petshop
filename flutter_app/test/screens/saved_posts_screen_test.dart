import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/saved_posts_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';

FeedPost _post(String id, {bool withProduct = false}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'PHOTO',
    'author': {'id': 'author-$id', 'name': 'Tester'},
    'viewerSaved': true,
    'products': [
      if (withProduct)
        {
          'id': 'product-$id',
          'slug': 'product-$id',
          'name': 'Produk $id',
          'price': 30000,
        },
    ],
    'createdAt': '2026-07-15T00:00:00.000Z',
  });
}

void main() {
  setUp(feedStore.clear);
  tearDown(feedStore.clear);

  testWidgets('shows Semua and filters Belanja to posts with products', (
    tester,
  ) async {
    final posts = [_post('plain'), _post('shopping', withProduct: true)];

    await tester.pumpWidget(
      MaterialApp(
        home: SavedPostsScreen(
          fetchPosts: ({String? cursor, required int limit}) async =>
              FeedPage(items: posts),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Semua'), findsOneWidget);
    expect(find.text('Belanja'), findsOneWidget);
    expect(find.byKey(const ValueKey('saved-post-plain')), findsOneWidget);
    expect(find.byKey(const ValueKey('saved-post-shopping')), findsOneWidget);

    await tester.tap(find.text('Belanja'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const ValueKey('saved-post-plain')), findsNothing);
    expect(find.byKey(const ValueKey('saved-post-shopping')), findsOneWidget);
  });

  testWidgets('shows a useful empty saved state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SavedPostsScreen(
          fetchPosts: ({String? cursor, required int limit}) async =>
              const FeedPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Belum ada postingan tersimpan'), findsOneWidget);
    expect(find.textContaining('Tap ikon simpan'), findsOneWidget);
  });
}
