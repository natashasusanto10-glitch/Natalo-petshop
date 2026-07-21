import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/gallery_post_tile.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/saved_posts_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
  setUp(() {
    feedStore.clear();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
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
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
  });

  testWidgets('tile carries hero tag post-hero/saved/<id>', (tester) async {
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

    expect(
        find.byWidgetPredicate(
            (w) => w is Hero && w.tag == 'post-hero/saved/p1'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is Hero && w.tag == 'post-hero/saved/p2'),
        findsOneWidget);
  });

  testWidgets(
      'no OriginSnapshotSource anywhere (pushPostViewer, not origin-expansion)',
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
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // OriginSnapshotSource sudah dihapus total dari codebase (lihat commit
    // "hapus OriginExpansionRoute total") — sebuah runtimeType-string check
    // terhadap tipe yang sudah dihapus akan SELALU findsNothing (vacuous,
    // tak pernah bisa gagal). Sinyal nyata bahwa jalur baru yang dipakai
    // adalah pushPostViewer (bukan origin-expansion lama) cukup dibuktikan
    // dari MemberPostDetailScreen yang tampil normal via route standar.
    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
  });

  testWidgets('pop from viewer closes without exception', (tester) async {
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
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(MemberPostDetailScreen), findsOneWidget);

    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(MemberPostDetailScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
