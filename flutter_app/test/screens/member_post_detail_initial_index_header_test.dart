import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';

/// Bug report: buka "Postingan" langsung ke post ke-2/ke-3 (dari grid) —
/// media kelihatan "over ke atas" / nembus header transparan, padahal post
/// ke-1 (tanpa initial-jump) selalu rapi di bawah header. Test ini mengukur
/// posisi Y post target setelah initial-jump — harus persis sama dengan
/// `headerInset` (paritas dengan padding-top ListView yang dipakai post-1).
FeedPost _photoPost(String id) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'PHOTO',
    'author': {'id': 'a-$id', 'name': 'Leonardi', 'role': 'CUSTOMER'},
    'mediaItems': [
      {
        'mediaUrl': 'https://example.com/$id.jpg',
        'kind': 'PHOTO',
        'width': 1080,
        'height': 1350,
      },
    ],
    'aspectWidth': 1080,
    'aspectHeight': 1350,
    'createdAt': '2026-07-15T00:00:00.000Z',
  });
}

const _topInset = 47.0; // simulasi safe-area status bar (notch device).

Future<void> _pumpAtIndex(
  WidgetTester tester,
  List<FeedPost> posts,
  int initialIndex,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: _topInset),
        ),
        child: MemberPostDetailScreen(
          post: posts[initialIndex],
          posts: posts,
          initialIndex: initialIndex,
        ),
      ),
    ),
  );
  // Beberapa frame supaya postFrameCallback (_jumpToInitial → ensureVisible
  // → koreksi) selesai jalan, tanpa pumpAndSettle (network image placeholder
  // bisa hang).
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(feedStore.clear);
  tearDown(feedStore.clear);

  const headerInset = _topInset + kToolbarHeight;

  testWidgets('post pertama (initialIndex 0) mendarat pas di bawah header',
      (tester) async {
    final posts = [_photoPost('p1'), _photoPost('p2'), _photoPost('p3')];
    await _pumpAtIndex(tester, posts, 0);

    final state =
        tester.state(find.byType(MemberPostDetailScreen)) as dynamic;
    final key = state.debugPostKeys[0] as GlobalKey;
    final topY = tester.getTopLeft(find.byKey(key)).dy;

    expect(topY, closeTo(headerInset, 1.0));
  });

  testWidgets(
      'post ke-2 (initialIndex 1) via jump juga mendarat pas di bawah header',
      (tester) async {
    final posts = [_photoPost('p1'), _photoPost('p2'), _photoPost('p3')];
    await _pumpAtIndex(tester, posts, 1);

    final state =
        tester.state(find.byType(MemberPostDetailScreen)) as dynamic;
    final key = state.debugPostKeys[1] as GlobalKey;
    final topY = tester.getTopLeft(find.byKey(key)).dy;

    expect(topY, closeTo(headerInset, 1.0));
  });

  testWidgets(
      'post ke-3 (initialIndex 2) via jump juga mendarat pas di bawah header',
      (tester) async {
    final posts = [_photoPost('p1'), _photoPost('p2'), _photoPost('p3')];
    await _pumpAtIndex(tester, posts, 2);

    final state =
        tester.state(find.byType(MemberPostDetailScreen)) as dynamic;
    final key = state.debugPostKeys[2] as GlobalKey;
    final topY = tester.getTopLeft(find.byKey(key)).dy;

    expect(topY, closeTo(headerInset, 1.0));
  });
}
