import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_edit_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Baris "Orang ditandai" di MemberPostEditScreen (Spec D Task 4). Fixture
/// dan pola pump disalin dari member_post_edit_screen_test.dart /
/// member_posts_screen_test.dart — bounded pump-loop (bukan pumpAndSettle)
/// supaya tak hang di CachedNetworkImage/Shimmer (lihat memory "Widget test
/// shimmer hang").
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  Future<void> pumpScreen(WidgetTester tester, FeedPost post) async {
    await tester.pumpWidget(MaterialApp(
      home: MemberPostEditScreen(post: post),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  FeedPost photoPostWithTags(List<FeedTaggedUser> taggedUsers) => FeedPost(
        id: 'post-photo-1',
        slug: 'post-photo-1',
        videoUrl: '',
        thumbnailUrl: 'https://example.com/photo.jpg',
        kind: 'PHOTO_CAROUSEL',
        author: const FeedAuthor(id: 'author-1', name: 'Tester'),
        createdAt: DateTime(2026, 1, 1),
        status: 'PUBLISHED',
        caption: 'Caption foto asli',
        taggedUsers: taggedUsers,
      );

  testWidgets('baris Orang ditandai tampil dengan count', (tester) async {
    final post = photoPostWithTags(const [
      FeedTaggedUser(userId: 'u1', username: 'satu', name: 'Satu'),
      FeedTaggedUser(userId: 'u2', username: 'dua', name: 'Dua'),
    ]);

    await pumpScreen(tester, post);

    expect(find.text('Orang ditandai'), findsOneWidget);
    expect(find.text('2 dipilih'), findsOneWidget);
  });

  testWidgets('baris Orang ditandai tampil Tambah kalau post kosong',
      (tester) async {
    final post = photoPostWithTags(const []);

    await pumpScreen(tester, post);

    expect(find.text('Orang ditandai'), findsOneWidget);
    expect(find.text('Tambah'), findsWidgets);
  });
}
