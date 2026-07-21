import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/constants/official_brand.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';
import 'package:visibility_detector/visibility_detector.dart';

FeedPost _post(String id, String authorName, {Map<String, dynamic>? author}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'PHOTO',
    'author': author ?? {'id': 'a-$id', 'name': authorName, 'role': 'CUSTOMER'},
    'mediaItems': [
      {'mediaUrl': 'https://example.com/$id.jpg', 'kind': 'PHOTO'}
    ],
    'viewerSaved': true,
    'createdAt': '2026-07-15T00:00:00.000Z',
  });
}

void main() {
  setUp(() {
    feedStore.clear();
    // WAJIB: post-visibility VisibilityDetector (lihat member_post_detail_
    // screen.dart) butuh updateInterval=0 supaya timer internalnya tak
    // pending saat widget tree di-dispose akhir test.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(feedStore.clear);

  testWidgets('authorPerPost shows each post own author, not "Pengguna"',
      (tester) async {
    final posts = [_post('p1', 'Budi'), _post('p2', 'Sinta')];

    await tester.pumpWidget(
      MaterialApp(
        home: MemberPostDetailScreen(
          post: posts[0],
          posts: posts,
          initialIndex: 0,
          isOwner: false,
          authorPerPost: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Budi'), findsWidgets);
    expect(find.text('Pengguna'), findsNothing);
  });

  testWidgets(
      'authorPerPost renders brand name for official author, never the '
      'raw owner name', (tester) async {
    // Official posts commonly arrive as role ADMIN with `isOfficial` unset —
    // FeedAuthor.isOfficialAccount (isAdmin || isOfficial) must still treat
    // this as official. The real owner's name must never leak to the UI.
    final officialPost = _post(
      'p1',
      'Natasha Owner',
      author: {
        'id': 'a-official',
        'name': 'Natasha Owner',
        'role': 'ADMIN',
      },
    );
    final posts = [officialPost, _post('p2', 'Sinta')];

    await tester.pumpWidget(
      MaterialApp(
        home: MemberPostDetailScreen(
          post: posts[0],
          posts: posts,
          initialIndex: 0,
          isOwner: false,
          authorPerPost: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(kOfficialBrandName), findsWidgets);
    expect(find.text('Natasha Owner'), findsNothing);
  });
}
