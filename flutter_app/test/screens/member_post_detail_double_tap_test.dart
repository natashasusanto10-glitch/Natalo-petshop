// ignore_for_file: depend_on_referenced_packages
//
// Covers the unified gesture: single-tap on video opens the fullscreen
// scoped feed (deferred by the framework because onDoubleTap lives on the
// same GestureDetector), while double-tap likes without opening fullscreen.
// See member_post_detail_screen_fullscreen_test.dart for the full rationale
// behind the fake video platform / cache manager plumbing copied below.

import 'dart:async';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_post_shared_widgets.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/scoped_video_feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

// ─── Fakes ──────────────────────────────────────────────────────────────

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _streams = {};
  final Map<int, Duration> _positions = {};
  int _nextId = 0;

  int createCount = 0;
  final Map<int, int> disposeCounts = {};

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) => _create();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) => _create();

  Future<int?> _create() async {
    createCount++;
    final id = _nextId++;
    final stream = StreamController<VideoEvent>();
    _streams[id] = stream;
    stream.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(720, 1280),
        duration: const Duration(seconds: 10),
      ),
    );
    return id;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposeCounts[playerId] = (disposeCounts[playerId] ?? 0) + 1;
    await _streams.remove(playerId)?.close();
    _positions.remove(playerId);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
}

class _NoopCacheManager implements CacheManager {
  @override
  Future<FileInfo?> getFileFromCache(String key,
          {bool ignoreMemCache = false}) async =>
      null;

  @override
  Future<FileInfo> downloadFile(String url,
          {String? key,
          Map<String, String>? authHeaders,
          bool force = false}) =>
      Completer<FileInfo>().future; // intentionally never completes

  @override
  Future<void> removeFile(String key) async {}

  @override
  Future<void> emptyCache() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopMetadataStorage implements IVideoPlayerMetadataStorage {
  final Map<String, int> _store = {};

  @override
  Set<String> get keys => _store.keys.toSet();

  @override
  Future<int?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, int value) async => _store[key] = value;

  @override
  Future<void> remove(String key) async => _store.remove(key);

  @override
  Future<void> erase() async => _store.clear();
}

// ─── Fixtures ───────────────────────────────────────────────────────────

FeedPost _fakeVideoPost({
  String id = 'post-1',
  bool withTaggedProduct = false,
}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/$id.mp4',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'durationSec': 10,
    'aspectRatio': 0.5625,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    if (withTaggedProduct)
      'products': [
        {
          'id': 'product-1',
          'slug': 'magic-bites-1kg',
          'name': 'Magic Bites 1KG',
          'imageUrl': 'https://example.com/magic-bites.jpg',
          'price': 85000,
          'discountPrice': 72250,
          'discountSource': 'PROMO_TOKO',
          'stock': 12,
          'weightGram': 1000,
          'isActive': true,
        },
      ],
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  late _FakeVideoPlayerPlatform fakePlatform;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;

    fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;

    CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
    CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();

    debugScopedFeedPostFetcher = (id) async => _fakeVideoPost(id: id);
  });

  tearDown(() {
    debugScopedFeedPostFetcher = null;
  });

  Future<VideoPlayerController> pumpAndInitialize(
    WidgetTester tester, {
    List<FeedPost>? posts,
  }) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final list = posts ?? [_fakeVideoPost()];
    await tester.pumpWidget(
      MaterialApp(
        home: MemberPostDetailScreen(
          post: list.first,
          posts: list,
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(VideoPlayer).evaluate().isNotEmpty) break;
    }
    expect(find.byType(VideoPlayer), findsWidgets,
        reason: 'inline video should initialize via the fake platform');
    return tester
        .widget<VideoPlayer>(find.byType(VideoPlayer).first)
        .controller;
  }

  Future<void> disposeTree(WidgetTester tester) async {
    // A failed toggleLike (real network call, always fails under
    // flutter_test's synthetic HttpOverrides — see comment above the
    // double-tap tests) shows an AppToast with its own ~2.35s dismiss
    // Timer. Let it self-dismiss BEFORE swapping the widget tree, or the
    // binding's teardown invariant check ("Timer still pending") trips.
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  }

  // NB: like-count text ('1') is NOT used as the assertion signal here.
  // _toggleLike round-trips through the real `apiClient`/`http` package
  // (no injectable http.Client exists in this repo — see
  // product_detail_screen_related_posts_test.dart for the same gap
  // documented previously). Under flutter_test's synthetic HttpOverrides
  // that request always fails fast, so the optimistic likeCount=1 flips
  // straight back to 0 (feedStore's rollback-on-error) inside the very
  // same pump that would reveal it, making a `find.text('1')` assertion
  // flaky-to-always-red regardless of the gesture code being correct.
  // The heart-burst overlay (Icons.favorite_rounded, 128px) is fired
  // unconditionally and purely locally inside `_handleDoubleTap` — it
  // does not depend on the network round-trip — so it is the reliable
  // signal that double-tap (not single-tap) was recognized.
  testWidgets('double-tap video likes without opening fullscreen',
      (tester) async {
    await pumpAndInitialize(tester);
    final center = tester.getCenter(find.byType(VideoPlayer).first);

    // Double tap dalam window kDoubleTapTimeout.
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    // The controller's Ticker anchors its start-time reference on the
    // FIRST frame drawn after forward(from: 0) — that frame reports
    // elapsed=0 regardless of the pump duration requested. A second pump
    // is needed for the elapsed-since-forward() progress (into the burst
    // animation's fade-in/plateau, 620ms total, opacity plateaus
    // ~25%-63%) to actually show up.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Heart burst overlay muncul → _handleDoubleTap terpanggil (bukan
    // _handleVideoSingleTap).
    expect(find.byType(FeedPostBurstHeart), findsOneWidget,
        reason: 'double-tap harus memicu heart burst (me-like)');
    // Double-tap TIDAK membuka scoped feed.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ScopedVideoFeedScreen), findsNothing,
        reason: 'double-tap hanya like, bukan fullscreen');

    await disposeTree(tester);
  });

  testWidgets('single tap video still opens scoped feed (deferred)',
      (tester) async {
    await pumpAndInitialize(tester);
    await tester.tapAt(tester.getCenter(find.byType(VideoPlayer).first));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
    await disposeTree(tester);
  });

  // Burst like GANJIL (3 tap): tap ke-3 tak berpasangan resolve jadi
  // single-tap → TANPA guard akan membuka fullscreen tak sengaja. Guard
  // menekan single-tap dalam jendela singkat sesudah double-tap-like.
  testWidgets('burst like ganjil (3 tap) TIDAK membuka fullscreen',
      (tester) async {
    await pumpAndInitialize(tester);
    final center = tester.getCenter(find.byType(VideoPlayer).first);

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center); // double-tap (like) di sini
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center); // tap ganjil
    // Resolve single-tap + beri waktu navigasi seandainya (keliru) terpicu.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ScopedVideoFeedScreen), findsNothing,
        reason: 'burst like tidak boleh membuka fullscreen');

    await disposeTree(tester);
  });

  // Starts from an ALREADY-liked post (viewerLiked: true, likeCount: 1) so
  // the assertion doesn't depend on a real network round-trip at all: per
  // `_handleDoubleTap`'s `if (!widget.liked) _handleLikeTap();` gate, when
  // already liked, `widget.onLike` (→ feedStore.toggleLike → real
  // apiClient/http call) is never invoked, so there is no request to roll
  // back and likeCount is guaranteed to stay exactly '1' throughout.
  testWidgets('double-tap twice keeps liked (never un-likes)',
      (tester) async {
    // Distinct id from the other tests in this file — the shared,
    // module-level `feedStore` singleton persists ACROSS tests within the
    // same isolate (only the widget tree is disposed per test), so reusing
    // the default 'post-1' id here would silently pick up the previous
    // test's rolled-back (unliked) entry instead of this fixture's state.
    final likedPost = _fakeVideoPost(id: 'post-already-liked')
        .copyWith(likeCount: 1, isLiked: true, viewerLiked: true);
    await pumpAndInitialize(tester, posts: [likedPost]);
    final center = tester.getCenter(find.byType(VideoPlayer).first);

    // Dua kali double-tap beruntun. Antar-round butuh jeda >
    // kDoubleTapTimeout (300ms) supaya round kedua tidak ikut ke-coalesce
    // sebagai lanjutan double-tap round pertama; round TERAKHIR memakai
    // jeda pendek (150ms, masih dalam plateau opacity burst 620ms) supaya
    // burst overlay dari _handleDoubleTap sempat ke-render sebelum di-cek.
    for (var round = 0; round < 2; round++) {
      final isLastRound = round == 1;
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      if (isLastRound) {
        // See the comment on the first test above: the burst controller's
        // Ticker anchors elapsed=0 on the first frame after forward(from:
        // 0), so a second pump is required to observe real progress.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
      } else {
        await tester.pump(const Duration(milliseconds: 350));
      }
    }

    // Burst feedback tetap muncul tiap double-tap (tanda handler jalan),
    // tapi count tidak pernah turun ke 0 — tidak ada un-like network call.
    expect(find.byType(FeedPostBurstHeart), findsOneWidget);
    expect(find.text('1'), findsWidgets,
        reason: 'double-tap saat sudah liked tidak boleh un-like');
    expect(find.text('0'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('double-tap shows a flying burst heart overlay', (tester) async {
    await pumpAndInitialize(tester);
    final center = tester.getCenter(find.byType(VideoPlayer).first);

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    // See the comment on the first test above: the burst controller's
    // Ticker anchors elapsed=0 on the first frame after forward(from: 0),
    // so a second pump is required to observe real progress.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.byType(FeedPostBurstHeart), findsOneWidget,
        reason: 'burst heart harus dirender di overlay saat double-tap');

    // Setelah animasi selesai, overlay dibersihkan.
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(FeedPostBurstHeart), findsNothing,
        reason: 'burst heart harus hilang setelah animasi');

    await disposeTree(tester);
  });
}
