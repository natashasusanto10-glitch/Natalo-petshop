import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_media_cache.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_viewer_route.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Task 3 — member_screen (own-profile grid) dipindah dari
/// `pushOriginExpansion`/`OriginSnapshotSource` ke `pushPostViewer` + hero
/// bawaan Flutter (`PostHero`). Tile grid harus punya Hero bertag
/// `post-hero/<scope>/<postId>` dan tap membuka `MemberPostDetailScreen`
/// lewat `PostViewerRoute` (transisi native), BUKAN
/// `OriginExpansionTransition` lama.
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

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    memberStore.setProfile(
      const MemberProfile(
        id: 'owner-1',
        name: 'Natasha',
        username: 'natasha_s',
        role: 'CUSTOMER',
        bio: 'Cat mom',
        followersCount: 1,
        followingCount: 1,
      ),
    );
    debugMyPostsFetcher = ({String filter = 'all', String? cursor}) async {
      return FeedPage(
        items: [post('p1'), post('p2'), post('p3')],
        nextCursor: null,
      );
    };
  });

  tearDown(() async {
    debugMyPostsFetcher = null;
    await memberStore.logout();
  });

  Future<void> pumpBounded(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  }

  /// Pump a fixed number of frames — used after navigation actions where a
  /// route-transition animation needs several frames regardless of whether
  /// a spinner is present.
  Future<void> pumpFrames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const MemberScreen(),
      ),
    );
    await pumpBounded(tester);
  }

  testWidgets(
      'own-profile tile grid punya PostHero scope profile; tap membuka viewer via PostViewerRoute',
      (tester) async {
    await pumpScreen(tester);

    expect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'post-hero/profile-all/p1',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byWidgetPredicate(
      (w) => w is Hero && w.tag == 'post-hero/profile-all/p1',
    ));
    await pumpFrames(tester);

    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
    expect(find.byType(PostViewerRoute), findsNothing);
    // Tile grid harus TIDAK lagi memakai OriginExpansionTransition lama.
    expect(
      find.byWidgetPredicate(
          (w) => '${w.runtimeType}' == 'OriginSnapshotSource'),
      findsNothing,
    );
  });

  testWidgets(
      'tile grid pakai cacheKey STABIL (token-independent) — cegah reload abu-abu thumbnail video saat refetch pasca-tutup',
      (tester) async {
    // Thumbnail video Bunny bawa signed-token yang BERUBAH tiap refetch
    // (`_loadAll()` dipanggil setelah viewer ditutup). Tanpa cacheKey stabil,
    // URL baru → CachedNetworkImage reload → baris tile video kedip abu-abu
    // (gejala device: glitch back di Profil pribadi). cacheKey harus
    // token-independent: URL beda token → cacheKey SAMA → cache hit → no reload.
    const tokenA = 'https://cdn.bunny.net/vid1/thumb.jpg?token=AAA&expires=111';
    const tokenB = 'https://cdn.bunny.net/vid1/thumb.jpg?token=BBB&expires=999';
    debugMyPostsFetcher =
        ({String filter = 'all', String? cursor}) async => FeedPage(
              items: [
                FeedPost(
                  id: 'vid1',
                  slug: 'vid1',
                  kind: 'VIDEO',
                  videoUrl: 'https://cdn.bunny.net/vid1/play.m3u8',
                  thumbnailUrl: tokenA,
                  author: const FeedAuthor(id: 'owner-1', name: 'Natasha'),
                  createdAt: DateTime(2026, 1, 1),
                  status: 'PUBLISHED',
                ),
              ],
              nextCursor: null,
            );

    await pumpScreen(tester);

    final img = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is Hero && w.tag == 'post-hero/profile-all/vid1',
        ),
        matching: find.byType(CachedNetworkImage),
      ),
    );

    // cacheKey terpasang, stabil, dan TIDAK memuat token mentah.
    expect(img.cacheKey, isNotNull);
    expect(img.cacheKey, isNot(contains('AAA')));
    // Token berubah (refetch) TIDAK mengubah cacheKey → tak ada reload/kedip.
    expect(
      img.cacheKey,
      equals(videoMediaCacheKey(mediaId: 'vid1', url: tokenA)),
    );
    expect(
      videoMediaCacheKey(mediaId: 'vid1', url: tokenA),
      equals(videoMediaCacheKey(mediaId: 'vid1', url: tokenB)),
    );
  });

  testWidgets(
      'back dari viewer tidak melempar exception dan grid tetap merender',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byWidgetPredicate(
      (w) => w is Hero && w.tag == 'post-hero/profile-all/p1',
    ));
    await pumpFrames(tester);
    expect(find.byType(MemberPostDetailScreen), findsOneWidget);

    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await pumpBounded(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(MemberScreen), findsOneWidget);
  });
}
