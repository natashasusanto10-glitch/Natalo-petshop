// ignore_for_file: depend_on_referenced_packages
//
// These tests exercise the private `_InlineVideoPlayer` inside
// member_post_detail_screen.dart end-to-end, plus its pause-to-open behavior:
// tapping the inline video pauses it, then the fullscreen control opens the
// immersive, swipeable
// [ScopedVideoFeedScreen] scoped to this user's videos (mirrors the
// "Postingan Terkait" flow). They need a working `VideoPlayerController`,
// which in turn needs a fake `VideoPlayerPlatform` (this repo had none —
// see git history of this file).
//
// The inline player uses `cached_video_player_plus`, which wraps `video_player`
// but first consults `flutter_cache_manager` (disk cache + shared_preferences).
// Under `flutter_test` that caching layer hits unavailable plugins, so we also
// swap in a no-op `CacheManager` + metadata storage that always report "not
// cached" — forcing the wrapper straight onto `VideoPlayerController.networkUrl`,
// which then talks to our fake platform instead of a real device.

import 'dart:async';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/scoped_video_feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

// ─── Fakes ──────────────────────────────────────────────────────────────

/// Minimal in-memory [VideoPlayerPlatform]. Emits an `initialized` event with a
/// non-zero duration immediately on create, tracks per-player position (so
/// `seekTo` sticks and the controller's periodic position poll doesn't clobber
/// it back to zero), and counts how many players were ever created — the latter
/// is how the tests prove the fullscreen overlay ADOPTS the existing controller
/// rather than spinning up a second one.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _streams = {};
  final Map<int, Duration> _positions = {};
  int _nextId = 0;

  /// Total number of players created across this platform's lifetime.
  int createCount = 0;

  /// Per-player dispose counts — a value >1 for any id proves a double
  /// dispose of the same underlying controller.
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

/// Pretends nothing is ever cached, so `cached_video_player_plus` skips its disk
/// cache and plays the raw network URL through our fake platform. `downloadFile`
/// returns a future that never completes — the wrapper fires it and forgets it,
/// and we never want the (mocked-absent) download side effects to run.
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

/// In-memory metadata storage — never touches shared_preferences.
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

FeedPost _fakeVideoPost({String id = 'post-1'}) {
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
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  late _FakeVideoPlayerPlatform fakePlatform;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // VisibilityDetector schedules a throttled Timer that can still be pending at
    // teardown; firing synchronously on paint avoids the "timer still pending"
    // assertion. Same guard the existing feed_video_post_view_test uses.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;

    fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;

    // Neutralize the caching layer so the wrapper falls through to the network
    // controller (which uses our fake platform). Assign the fakes WITHOUT first
    // reading the originals — reading these statics forces lazy construction of
    // the real VideoCacheManager / VideoPlayerMetadataStorage, which touch
    // path_provider / SharedPreferencesAsync and throw under flutter_test. Each
    // test file runs in its own isolate, so there is nothing to restore.
    CachedVideoPlayerPlus.cacheManager = _NoopCacheManager();
    CachedVideoPlayerPlus.metadataStorage = _NoopMetadataStorage();

    // Tap-video kini fetch post feed ASLI by ID sebelum membuka viewer
    // (supaya author/like/komentar lengkap — data profil tidak bawa
    // author). feedService tidak injectable, jadi pakai seam test-only.
    debugScopedFeedPostFetcher = (id) async => _fakeVideoPost(id: id);
  });

  tearDown(() {
    debugScopedFeedPostFetcher = null;
  });

  /// Pumps the screen with a single video post and waits (bounded — NOT
  /// pumpAndSettle, which hangs on shimmer/network-image in this repo) for the
  /// inline video controller to reach `initialized` so a `VideoPlayer` renders.
  Future<VideoPlayerController> pumpAndInitialize(
    WidgetTester tester, {
    List<FeedPost>? posts,
  }) async {
    // Tall phone viewport so the (3:5 immersive) inline video is fully on-screen
    // and tappable — the default 800x600 test window cuts it off.
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

  /// Tears down the widget tree so the video controller's periodic position
  /// Timer (started while "playing") is cancelled before the test ends.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
    'tap pauses inline video; fullscreen control opens scoped feed',
    (tester) async {
      await pumpAndInitialize(tester);

      // No scoped feed viewer yet.
      expect(find.byType(ScopedVideoFeedScreen), findsNothing);

      // Tap the media itself: the first tap must pause immediately and reveal
      // the controls. Navigation is an explicit action so media gestures stay
      // responsive and predictable.
      await tester.tapAt(const Offset(200, 600));
      await tester.pump();
      expect(find.bySemanticsLabel('Putar video'), findsOneWidget);
      expect(find.bySemanticsLabel('Buka layar penuh'), findsOneWidget);
      expect(find.byType(ScopedVideoFeedScreen), findsNothing);

      // Wait until the double-tap window closes before interacting with a
      // paused control. Inline defaults to globally muted.
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.bySemanticsLabel('Aktifkan suara'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Aktifkan suara'));
      await tester.pump();
      expect(find.bySemanticsLabel('Matikan suara'), findsOneWidget,
          reason: 'mute tap should update immediately');
      expect(find.byType(ScopedVideoFeedScreen), findsNothing,
          reason: 'mute tap must not open the scoped feed');

      await tester.tap(find.bySemanticsLabel('Buka layar penuh'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
      }
      expect(find.byType(ScopedVideoFeedScreen), findsOneWidget,
          reason: 'tapping the video area should open the scoped video feed');

      await disposeTree(tester);
    },
  );

  testWidgets(
    'scoped feed is seeded with this user\'s videos and opens at the tapped one',
    (tester) async {
      final posts = [
        _fakeVideoPost(id: 'post-1'),
        _fakeVideoPost(id: 'post-2'),
        _fakeVideoPost(id: 'post-3'),
      ];
      await pumpAndInitialize(tester, posts: posts);

      // The first post is scrolled into view; pause it, then open its explicit
      // fullscreen action. initialIndex resolution is exercised by the
      // widget's own indexWhere; here we assert the viewer has all 3 videos.
      await tester.tapAt(const Offset(200, 600));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.bySemanticsLabel('Buka layar penuh'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
      }

      final scoped = tester.widget<ScopedVideoFeedScreen>(
        find.byType(ScopedVideoFeedScreen),
      );
      expect(scoped.posts.length, 3,
          reason: 'scoped feed should contain every video by this user');
      expect(
          scoped.posts.map((p) => p.id),
          containsAll(<String>[
            'post-1',
            'post-2',
            'post-3',
          ]));

      // Back chevron closes the viewer.
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // morph-out (260ms)
      await tester.pump();
      expect(find.byType(ScopedVideoFeedScreen), findsNothing,
          reason: 'back should close the scoped feed');

      await disposeTree(tester);
    },
  );

  // ── T3b — handoff origin INSTAN via coordinator ──────────────────────

  Future<void> openScopedFeed(WidgetTester tester) async {
    await tester.tapAt(const Offset(200, 600));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.bySemanticsLabel('Buka layar penuh'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
  }

  testWidgets(
    'T3b: opening fullscreen ADOPTS the origin controller — no new player '
    'created (instant handoff), and closing does NOT dispose it',
    (tester) async {
      await pumpAndInitialize(tester);
      // Inline created exactly one underlying player.
      expect(fakePlatform.createCount, 1,
          reason: 'inline origin should create exactly one controller');

      await openScopedFeed(tester);
      // Fullscreen origin item is managed (ownsController:false) and borrows
      // the SAME controller via preloadedController → NO second player.
      expect(fakePlatform.createCount, 1,
          reason:
              'fullscreen origin must reuse the existing controller, not init a '
              'new session');

      // Close the viewer → origin controller must survive (re-attach inline at
      // the same timestamp). No dispose of the shared player yet.
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ScopedVideoFeedScreen).evaluate().isEmpty) break;
      }
      expect(find.byType(ScopedVideoFeedScreen), findsNothing);
      expect(fakePlatform.createCount, 1,
          reason:
              'closing fullscreen must not re-create the origin controller');
      expect(
        fakePlatform.disposeCounts.values.where((c) => c > 0).length,
        0,
        reason: 'origin controller must NOT be disposed when fullscreen closes',
      );
      // Inline still renders the (same) video after return.
      expect(find.byType(VideoPlayer), findsWidgets);

      // Page dispose → coordinator disposes the origin session exactly ONCE
      // (zero double-dispose).
      await disposeTree(tester);
      for (final entry in fakePlatform.disposeCounts.entries) {
        expect(entry.value, lessThanOrEqualTo(1),
            reason:
                'player ${entry.key} disposed ${entry.value}x — expected ≤1 '
                '(no double-dispose)');
      }
    },
  );

  testWidgets(
    'T3b hardening: fetch-fail while app is backgrounded → handoff does NOT '
    'resume (no ghost audio)',
    (tester) async {
      // Fetch returns nothing → scoped feed never opens → _endHandoff(resume).
      debugScopedFeedPostFetcher = (id) async => null;
      final controller = await pumpAndInitialize(tester);

      // Background the app (page observer pauses all sessions).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 20));
      expect(controller.value.isPlaying, isFalse,
          reason: 'background must pause the origin controller');

      // Tap the inline video → handoff starts, fetch fails (empty), finally
      // runs _endHandoff(resume:true) — but lifecycle is paused, so the guard
      // must SKIP resumeAll (otherwise ghost audio behind a backgrounded app).
      await tester.tapAt(const Offset(200, 600));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(ScopedVideoFeedScreen), findsNothing,
          reason: 'empty fetch must not open the viewer');
      expect(controller.value.isPlaying, isFalse,
          reason:
              'resume must be skipped while backgrounded (fetch-fail path)');

      // Empty-fetch shows an AppToast that auto-dismisses via a Timer — flush
      // it so the binding doesn't flag a pending timer at teardown.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await disposeTree(tester);
    },
  );

  // ── T7-integrasi — kembali-dari-fullscreen re-aktifkan ORIGIN ────────────

  testWidgets(
    'T7: swipe away in fullscreen then close re-activates ORIGIN (not stale B); '
    'B is paused (no ghost playback) and origin is not re-created',
    (tester) async {
      final posts = [
        _fakeVideoPost(id: 'post-1'),
        _fakeVideoPost(id: 'post-2'),
        _fakeVideoPost(id: 'post-3'),
      ];
      await pumpAndInitialize(tester, posts: posts);

      final state = tester.state(find.byType(MemberPostDetailScreen));
      final dynamic coordinator = (state as dynamic).debugVideoCoordinator;

      await openScopedFeed(tester);

      // Tapped post-1 → origin pinned + active on open (deterministic; with
      // multiple videos on-screen the pre-open active is scroll-dependent).
      expect(coordinator.originPostId, 'post-1',
          reason: 'tapped video is the handoff origin');
      expect(coordinator.activePostId, 'post-1',
          reason: 'fullscreen opens with origin active');

      // Simulate the user swiping to the next video (B = post-2). The scoped
      // viewer's onPageChanged calls setActive(next); drive the coordinator
      // directly to be deterministic (no reliance on PageView fling timing).
      coordinator.setActive('post-2');
      await tester.pump(const Duration(milliseconds: 50));
      expect(coordinator.activePostId, 'post-2',
          reason: 'swiping made B (post-2) the active session');

      // Close fullscreen → _endHandoff must re-point active back to ORIGIN A.
      final beforeClose = fakePlatform.createCount;
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ScopedVideoFeedScreen).evaluate().isEmpty) break;
      }
      expect(find.byType(ScopedVideoFeedScreen), findsNothing);

      expect(coordinator.activePostId, 'post-1',
          reason: 'closing fullscreen must re-activate origin A, NOT resume '
              'the stale active B');

      // B (post-2) must be paused — no ghost audio/playback in the background.
      final dynamic bSession = coordinator.sessionFor('post-2');
      final dynamic bController = bSession?.controller;
      if (bController != null) {
        expect(bController.value.isPlaying, isFalse,
            reason: 'stale B must not be playing after return to Postingan');
      }

      // No re-init on return (instant re-attach, no thumbnail blink path).
      expect(fakePlatform.createCount, beforeClose,
          reason: 'returning must not re-create any controller');
      expect(find.byType(VideoPlayer), findsWidgets,
          reason: 'origin inline still renders the same video after return');

      await disposeTree(tester);
    },
  );

  testWidgets(
    'T7: no-swipe close keeps origin active and resumes it (no regression)',
    (tester) async {
      final controller = await pumpAndInitialize(tester); // single post-1

      final state = tester.state(find.byType(MemberPostDetailScreen));
      final dynamic coordinator = (state as dynamic).debugVideoCoordinator;
      expect(coordinator.activePostId, 'post-1');

      await openScopedFeed(tester);
      // No swipe — origin stays the active session throughout.
      expect(coordinator.activePostId, 'post-1',
          reason: 'no-swipe: origin remains active in fullscreen');

      final beforeClose = fakePlatform.createCount;
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ScopedVideoFeedScreen).evaluate().isEmpty) break;
      }
      expect(find.byType(ScopedVideoFeedScreen), findsNothing);

      expect(coordinator.activePostId, 'post-1',
          reason: 'no-swipe: origin stays active after close');
      expect(fakePlatform.createCount, beforeClose,
          reason: 'no-swipe close must not re-create controllers');
      // Origin resumes (plays) after returning — unchanged behavior.
      expect(controller.value.isPlaying, isTrue,
          reason: 'origin should resume playing after returning from '
              'fullscreen (no-swipe path)');
      expect(find.byType(VideoPlayer), findsWidgets);

      await disposeTree(tester);
    },
  );
}
