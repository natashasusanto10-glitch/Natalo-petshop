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

  // `kind` pakai nilai enum server ASLI (lihat FeedPostKind di
  // lib/models/feed_post.dart doc comment): COMMUNITY = video,
  // PHOTO_CAROUSEL = foto/carousel. Diverifikasi lewat FeedPost.contentType
  // (lib/models/feed_post.dart): COMMUNITY masuk daftar upper-case video
  // kinds -> isVideo true; PHOTO_CAROUSEL dgn mediaItems kosong (default)
  // jatuh ke FeedContentType.photo (bukan carousel, butuh >1 media) ->
  // isVideo false. Kedua fixture menghasilkan isVideo yang sama seperti
  // sebelum fix (kind lama 'USER_VIDEO'/'PHOTO' bukan nilai server asli).
  FeedPost videoPost({String status = 'PUBLISHED'}) => FeedPost(
        id: 'post-video-1',
        slug: 'post-video-1',
        videoUrl: 'https://example.com/video.mp4',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        kind: 'COMMUNITY',
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
        kind: 'PHOTO_CAROUSEL',
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
    // Kebijakan baru: SEMUA konten auto-approve, edit TIDAK pernah re-review
    // (post-moderation.ts `editReTriggersModeration` selalu false). Helper
    // Flutter harus match — false untuk semua kombinasi wasActive x isVideo.
    test('full decision matrix — never needs review anymore', () {
      expect(feedPostEditNeedsReview(wasActive: true, isVideo: true), isFalse);
      expect(
          feedPostEditNeedsReview(wasActive: true, isVideo: false), isFalse);
      expect(
          feedPostEditNeedsReview(wasActive: false, isVideo: true), isFalse);
      expect(
          feedPostEditNeedsReview(wasActive: false, isVideo: false), isFalse);
    });
  });

  group('fixture sanity (real FeedPostKind enum values)', () {
    // Fix 3: fixtures dulu pakai kind: 'USER_VIDEO'/'PHOTO' yang BUKAN
    // nilai enum server asli. Nilai server asli: COMMUNITY (video) dan
    // PHOTO_CAROUSEL (foto/carousel) — lihat doc comment `kind` di
    // lib/models/feed_post.dart. Guard ini mengunci bahwa kedua fixture
    // tetap menghasilkan isVideo yang benar setelah swap ke nilai asli,
    // supaya test lain (review-notice gating, needsReview proxy) di bawah
    // tidak diam-diam jadi salah kalau FeedPost.contentType berubah.
    test('videoPost (kind COMMUNITY) is isVideo == true', () {
      expect(videoPost().isVideo, isTrue);
    });

    test('photoPost (kind PHOTO_CAROUSEL) is isVideo == false', () {
      expect(photoPost().isVideo, isFalse);
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

  group('review notice removed (semua konten auto-approve)', () {
    testWidgets('does NOT show for active VIDEO post', (tester) async {
      await pumpScreen(tester, videoPost(status: 'PUBLISHED'));

      expect(
        find.textContaining('masuk review admin lagi'),
        findsNothing,
      );
    });

    testWidgets('does NOT show for active PHOTO post', (tester) async {
      await pumpScreen(tester, photoPost(status: 'PUBLISHED'));

      expect(
        find.textContaining('masuk review admin lagi'),
        findsNothing,
      );
    });
  });

  // Kebijakan baru: edit tidak pernah re-review. _save() menulis status
  // optimistic = status asal post (tidak pernah PENDING_REVIEW). Diproksikan
  // lewat absennya review-notice banner — gated oleh `feedPostEditNeedsReview`
  // yang sama di build() (kini selalu false untuk semua kombinasi).
  group('save() status decision — edit tidak pernah re-review', () {
    testWidgets('ACTIVE VIDEO post: needsReview=false (status tetap ACTIVE)',
        (tester) async {
      final post = videoPost(status: 'PUBLISHED');
      expect(post.isVideo, isTrue);
      expect(post.statusInfo, FeedPostStatus.active);
      expect(
        feedPostEditNeedsReview(wasActive: true, isVideo: post.isVideo),
        isFalse,
      );

      await pumpScreen(tester, post);
      expect(
        find.textContaining('masuk review admin lagi'),
        findsNothing,
        reason: 'notice absent <=> needsReview=false <=> _save() keeps '
            'the video ACTIVE (auto-approve, tanpa review)',
      );
    });

    testWidgets('ACTIVE PHOTO/CAROUSEL post: needsReview=false (status tetap '
        'ACTIVE)', (tester) async {
      final post = photoPost(status: 'PUBLISHED');
      expect(post.isVideo, isFalse);
      expect(post.statusInfo, FeedPostStatus.active);
      expect(
        feedPostEditNeedsReview(wasActive: true, isVideo: post.isVideo),
        isFalse,
      );

      await pumpScreen(tester, post);
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
