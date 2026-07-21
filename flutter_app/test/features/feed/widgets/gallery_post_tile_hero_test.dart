import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/gallery_post_tile.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

/// Task 4 — GalleryPostTile dukung PostHero opsional lewat `heroScope`.
/// Tag hero WAJIB `post-hero/<scope>/<postId>` (lihat post_hero.dart);
/// tanpa heroScope, tile TIDAK boleh render Hero sama sekali (caller lama —
/// mis. Postingan Tersimpan — tak terpengaruh).
void main() {
  FeedPost post(String id) => FeedPost(
        id: id,
        slug: id,
        kind: 'PHOTO',
        videoUrl: '',
        thumbnailUrl: 'https://example.com/$id.jpg',
        author: const FeedAuthor(id: 'owner-1', name: 'Natasha'),
        createdAt: DateTime(2026, 1, 1),
        status: 'PUBLISHED',
      );

  testWidgets('heroScope set → wraps thumbnail with PostHero tagged scope',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GalleryPostTile(
            key: const ValueKey('tile-p1'),
            post: post('p1'),
            onTap: () {},
            heroScope: 'saved',
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'post-hero/saved/p1',
      ),
      findsOneWidget,
    );
  });

  testWidgets('heroScope null → no Hero rendered', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GalleryPostTile(
            key: const ValueKey('tile-p1'),
            post: post('p1'),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.byType(Hero), findsNothing);
  });
}
