// ignore_for_file: depend_on_referenced_packages
//
// These tests exercise the private `_InlineVideoPlayer` inside
// member_post_detail_screen.dart end-to-end, plus its tap-to-open behavior:
// tapping the inline video opens the immersive, swipeable
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
          {String? key, Map<String, String>? authHeaders, bool force = false}) =>
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
    return tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller;
  }

  /// Tears down the widget tree so the video controller's periodic position
  /// Timer (started while "playing") is cancelled before the test ends.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
    'tapping inline video opens scoped feed; tapping mute icon does not',
    (tester) async {
      await pumpAndInitialize(tester);

      // Inline player defaults to muted (appSettingsStore.feedMuted == true).
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
      // No scoped feed viewer yet.
      expect(find.byType(ScopedVideoFeedScreen), findsNothing);

      // Tap the mute icon → toggles mute, must NOT navigate away.
      // _toggleMute awaits a SharedPreferences write before setState, so wait
      // (bounded) for the toggled icon to render rather than assuming one frame.
      await tester.tap(find.byIcon(Icons.volume_off_rounded));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byIcon(Icons.volume_up_rounded).evaluate().isNotEmpty) break;
      }
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget,
          reason: 'mute tap should toggle the inline mute state');
      expect(find.byType(ScopedVideoFeedScreen), findsNothing,
          reason: 'mute tap must not open the scoped feed');

      // Tap a point squarely inside the on-screen video area (below the top
      // author overlay, well clear of the bottom-right mute button) → opens
      // the immersive, swipeable scoped feed viewer. Single-tap resolves after
      // the double-tap timeout, then an async pause + morph-in route push runs,
      // so wait (bounded) rather than assuming a fixed frame count.
      await tester.tapAt(const Offset(200, 600));
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

      // The first post is scrolled into view; tapping its inline video opens
      // the scoped feed. (initialIndex resolution is exercised by the widget's
      // own indexWhere; here we assert the viewer is scoped to all 3 videos.)
      await tester.tapAt(const Offset(200, 600));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
      }

      final scoped = tester.widget<ScopedVideoFeedScreen>(
        find.byType(ScopedVideoFeedScreen),
      );
      expect(scoped.posts.length, 3,
          reason: 'scoped feed should contain every video by this user');
      expect(scoped.posts.map((p) => p.id), containsAll(<String>[
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
}
