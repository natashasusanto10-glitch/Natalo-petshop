import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/gallery_post_tile.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/saved_posts_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';

FeedPost _post(String id, {String author = 'Tester'}) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'PHOTO',
      'author': {'id': 'a-$id', 'name': author, 'role': 'CUSTOMER'},
      'mediaItems': [
        {'mediaUrl': 'https://e.com/$id.jpg', 'kind': 'PHOTO'}
      ],
      'viewerSaved': true,
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

void main() {
  setUp(feedStore.clear);
  tearDown(feedStore.clear);

  testWidgets('shows title, no tabs, grid tiles', (tester) async {
    final posts = [_post('p1', author: 'Budi'), _post('p2', author: 'Sinta')];
    await tester.pumpWidget(
      MaterialApp(
        home: SavedPostsScreen(
          fetchPosts: ({String? cursor, required int limit}) async =>
              FeedPage(items: posts),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Postingan Tersimpan'), findsOneWidget);
    expect(find.text('Semua'), findsNothing);
    expect(find.text('Belanja'), findsNothing);
    expect(find.byType(GalleryPostTile), findsNWidgets(2));
  });

  testWidgets('tap tile opens MemberPostDetailScreen with full list',
      (tester) async {
    final posts = [_post('p1'), _post('p2')];
    await tester.pumpWidget(
      MaterialApp(
        home: SavedPostsScreen(
          fetchPosts: ({String? cursor, required int limit}) async =>
              FeedPage(items: posts),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(GalleryPostTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
  });
}
