import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_edit_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `MemberPostEditScreen` restyle ala IG "Edit info" + gating review-notice
/// dan status optimistic ke video-only (Task 2). Backend (Task 1) sudah
/// gate photo/carousel edit supaya tetap ACTIVE — test ini pastikan Flutter
/// UI (notice + helper keputusan) match: video aktif → review, foto/
/// carousel aktif → tidak.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  FeedPost videoPost({String status = 'PUBLISHED'}) => FeedPost(
        id: 'post-video-1',
        slug: 'post-video-1',
        videoUrl: 'https://example.com/video.mp4',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        kind: 'USER_VIDEO',
        author: const FeedAuthor(id: 'author-1', name: 'Tester'),
        createdAt: DateTime(2026, 1, 1),
        status: status,
        caption: 'Caption video asli',
      );

  FeedPost photoPost({String status = 'PUBLISHED'}) => FeedPost(
        id: 'post-photo-1',
        slug: 'post-photo-1',
        videoUrl: '',
        thumbnailUrl: 'https://example.com/photo.jpg',
        kind: 'PHOTO',
        author: const FeedAuthor(id: 'author-1', name: 'Tester'),
        createdAt: DateTime(2026, 1, 1),
        status: status,
        caption: 'Caption foto asli',
      );

  // Bounded pump-loop (bukan pumpAndSettle) — CachedNetworkImage/Shimmer tak
  // pernah settle, dan _loadTaggableProducts() (network) gagal diam di test
  // env; screen tetap render. Lihat memory "Widget test shimmer hang".
  Future<void> pumpScreen(WidgetTester tester, FeedPost post) async {
    await tester.pumpWidget(MaterialApp(
      home: MemberPostEditScreen(post: post),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('feedPostEditNeedsReview', () {
    test('video active -> true, foto active -> false, video pending -> false',
        () {
      expect(
        feedPostEditNeedsReview(wasActive: true, isVideo: true),
        isTrue,
      );
      expect(
        feedPostEditNeedsReview(wasActive: true, isVideo: false),
        isFalse,
      );
      expect(
        feedPostEditNeedsReview(wasActive: false, isVideo: true),
        isFalse,
      );
    });
  });

  group('header', () {
    testWidgets('shows X + centang IG header, not old AppBar copy',
        (tester) async {
      await pumpScreen(tester, videoPost());

      expect(find.text('Edit info'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('Edit Postingan'), findsNothing);
      expect(find.text('Simpan Perubahan'), findsNothing);
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('caption field', () {
    testWidgets('is borderless with maxLength 2000', (tester) async {
      await pumpScreen(tester, videoPost());

      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.maxLength, 2000);
      expect(textField.decoration?.border, InputBorder.none);
      expect(textField.decoration?.enabledBorder, InputBorder.none);
      expect(textField.decoration?.focusedBorder, InputBorder.none);
      expect(textField.decoration?.filled, isFalse);
    });
  });

  group('review notice gating (video-only)', () {
    testWidgets('shows for active VIDEO post', (tester) async {
      await pumpScreen(tester, videoPost(status: 'PUBLISHED'));

      expect(
        find.textContaining('masuk review admin lagi'),
        findsOneWidget,
      );
    });

    testWidgets('does NOT show for active PHOTO post', (tester) async {
      await pumpScreen(tester, photoPost(status: 'PUBLISHED'));

      expect(
        find.textContaining('masuk review admin lagi'),
        findsNothing,
      );
    });

    testWidgets('does NOT show for pending VIDEO post', (tester) async {
      await pumpScreen(tester, videoPost(status: 'PENDING_REVIEW'));

      expect(
        find.textContaining('masuk review admin lagi'),
        findsNothing,
      );
    });
  });

  group('produk ditandai row', () {
    testWidgets('is present and tap opens the product picker sheet',
        (tester) async {
      await pumpScreen(tester, videoPost());

      expect(find.text('Produk ditandai'), findsOneWidget);

      await tester.tap(find.text('Produk ditandai'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Produk Ditag').evaluate().isNotEmpty) break;
      }
      expect(find.text('Produk Ditag'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    });
  });
}
