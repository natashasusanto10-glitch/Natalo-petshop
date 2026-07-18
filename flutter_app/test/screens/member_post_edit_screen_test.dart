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

    // Matriks lengkap 4 kombinasi (wasActive x isVideo). Ini adalah helper
    // murni yang dipakai _save() untuk memutuskan status optimistic yang
    // ditulis ke feedStore ('PENDING_REVIEW' vs status asal) — mengunci
    // keputusan itu di level unit karena _save() sendiri tidak bisa
    // di-drive end-to-end secara deterministik di widget test (lihat
    // comment di group 'save() status decision' di bawah).
    test('full decision matrix — only wasActive && isVideo needs review', () {
      expect(feedPostEditNeedsReview(wasActive: true, isVideo: true), isTrue);
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

  // Fix 2 (final review): spec's Testing section asked to verify _save()'s
  // optimistic feedStore write picks the right status (PENDING_REVIEW for
  // an active video edit, unchanged for an active photo/carousel edit).
  //
  // Feasibility finding: _save() calls `feedService.updateMyPost(...)`
  // (real HTTP via the module-level `feedService`/`apiClient` singletons —
  // there is no injectable client/service seam anywhere in this codebase,
  // confirmed against member_post_detail_double_tap_test.dart and
  // product_detail_screen_related_posts_test.dart, which document the same
  // gap for feedStore.toggleLike). Under flutter_test's synthetic
  // HttpOverrides that call always throws, so tapping the save button only
  // ever exercises _save()'s `catch` branch (error toast, NO store write) —
  // it never reaches the `feedStore.applyPostUpdate(...)` line the spec
  // wants covered. A "tap save, then assert feedStore" test would therefore
  // pass or fail for the wrong reason (network timing/HttpOverrides
  // behavior), not because the status decision is right or wrong — writing
  // it would be dishonest coverage.
  //
  // What IS deterministic and exercises the exact same decision inputs
  // (wasActive, isVideo) that _save() feeds into feedPostEditNeedsReview
  // before it computes the optimistic status: the review-notice banner
  // above, gated by the identical `feedPostEditNeedsReview(...)` call in
  // build(). This group makes that proxy explicit per-scenario so it reads
  // as the store-write decision test the spec asked for, not just a UI
  // gating check.
  group('save() status decision (proxied via notice banner — see comment '
      'above for why a direct store-write assertion is not feasible)', () {
    testWidgets(
        'ACTIVE VIDEO post: needsReview=true (would set store status to '
        'PENDING_REVIEW)', (tester) async {
      final post = videoPost(status: 'PUBLISHED');
      expect(post.isVideo, isTrue);
      expect(post.statusInfo, FeedPostStatus.active);
      expect(
        feedPostEditNeedsReview(wasActive: true, isVideo: post.isVideo),
        isTrue,
      );

      await pumpScreen(tester, post);
      expect(
        find.textContaining('masuk review admin lagi'),
        findsOneWidget,
        reason: 'notice visible <=> needsReview=true <=> _save() would '
            'write status PENDING_REVIEW to feedStore',
      );
    });

    testWidgets(
        'ACTIVE PHOTO/CAROUSEL post: needsReview=false (store status stays '
        "the post's existing active status)", (tester) async {
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
        reason: 'notice absent <=> needsReview=false <=> _save() would '
            "keep the post's existing active status in feedStore",
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
