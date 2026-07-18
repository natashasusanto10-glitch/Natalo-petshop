import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_store.dart';

FeedPost _post(String id, String authorName) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'PHOTO',
    'author': {'id': 'a-$id', 'name': authorName, 'role': 'CUSTOMER'},
    'mediaItems': [
      {'mediaUrl': 'https://example.com/$id.jpg', 'kind': 'PHOTO'}
    ],
    'viewerSaved': true,
    'createdAt': '2026-07-15T00:00:00.000Z',
  });
}

void main() {
  setUp(feedStore.clear);
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
}
