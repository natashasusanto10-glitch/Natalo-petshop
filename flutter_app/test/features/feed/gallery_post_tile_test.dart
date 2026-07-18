import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/gallery_post_tile.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

FeedPost _video(String id) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'VIDEO',
      'author': {'id': 'a', 'name': 'Tester', 'role': 'CUSTOMER'},
      'mediaItems': [
        {'mediaUrl': 'https://e.com/$id.mp4', 'kind': 'VIDEO'}
      ],
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

void main() {
  testWidgets('renders video badge and fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GalleryPostTile(
            key: GlobalKey(),
            post: _video('v1'),
            onTap: () => tapped = true,
            showStatusBadge: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byType(GalleryPostTile));
    expect(tapped, isTrue);
  });
}
