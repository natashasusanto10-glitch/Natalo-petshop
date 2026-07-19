// T3a — verifikasi wiring inline video ↔ PostVideoCoordinator di halaman
// Postingan TANPA plugin native: `debugPostVideoSessionFactory` menyuntik
// fake [PlaybackSession] (tak butuh video_player), jadi kita bisa memeriksa
// attach/setActive/play, always-autoplay Postingan, dan sinkronisasi
// mute — semua lewat interaksi widget nyata.
//
// Gotcha test repo ini: JANGAN pumpAndSettle (shimmer/AppProductImage tak
// pernah settle) → pakai bounded pump loop. SharedPreferences.setMockInitialValues
// + VisibilityDetector.updateInterval = 0.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_detail_transition_session.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_warm_handoff.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/services/video_quality_service.dart';
import 'package:natalo_petshop_flutter/state/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _FakeSession implements PlaybackSession {
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;
  double volume = -1;
  bool playing = false;
  Duration _pos = Duration.zero;

  @override
  Future<void> play() async {
    playCount++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    playing = false;
  }

  @override
  Future<void> seekTo(Duration position) async => _pos = position;

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> dispose() async => disposeCount++;

  @override
  Duration get position => _pos;
}

class _WarmSession extends VideoPlayerSession {
  _WarmSession()
      : super(
          url: 'https://example.com/post-1.mp4',
          debugInitAttempt: (_) async {},
        );
}

class _TransitionSource implements PostDetailTransitionSourceAdapter {
  @override
  bool mounted = true;

  @override
  void mergePage(FeedPage page) {}

  @override
  Future<PostPageSourceTarget?> prepareTarget(
    FeedPost post, {
    required int generation,
  }) async =>
      null;

  @override
  PostPageSourceTarget? resolveTarget(FeedPost post) => null;

  @override
  PostPageMediaProxy resolveProxy(FeedPost post) =>
      PostPageMediaProxy(placeholderColor: const Color(0xFF123456));

  @override
  void setPendingReturnPostId(String? postId) {}

  @override
  void setTileSuppressed(String postId, bool suppressed) {}
}

FeedPost _fakeVideoPost({String id = 'post-1', String? videoDataSaverUrl}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/$id.mp4',
    if (videoDataSaverUrl != null) 'videoDataSaverUrl': videoDataSaverUrl,
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

FeedPost _fakePostWithVideoMedia({
  String id = 'post-1',
  String mediaUrl = 'https://example.com/media-1/playlist.m3u8',
  String? mediaDataSaverUrl,
}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'PHOTO_CAROUSEL',
    'videoUrl': '',
    'mediaItems': [
      {
        'id': 'media-1',
        'mediaType': 'video',
        'mediaUrl': mediaUrl,
        if (mediaDataSaverUrl != null) 'videoDataSaverUrl': mediaDataSaverUrl,
        'sortOrder': 0,
      },
    ],
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  late Map<String, _FakeSession> sessions;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    debugPostDetailReadinessClock = () => Duration.zero;
    debugPostDetailReadinessFrameFuture = null;
    sessions = {};
    debugPostVideoSessionFactory = (id) {
      final s = _FakeSession();
      sessions[id] = s;
      return s;
    };
    // State default eksplisit — appSettingsStore singleton bisa bawa nilai
    // dari test sebelumnya di isolate yang sama.
    await appSettingsStore.setFeedAutoplay(true);
    await appSettingsStore.setFeedMuted(true);
  });

  tearDown(() {
    debugPostVideoSessionFactory = null;
    debugPostVideoSessionUrlObserver = null;
    debugScopedFeedPostFetcher = null;
    debugPostDetailReadinessClock = null;
    debugPostDetailReadinessFrameFuture = null;
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<FeedPost>? posts,
    PostDetailTransitionSession? transitionSession,
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
          transitionSession: transitionSession,
        ),
      ),
    );
    // Bounded pump — biarkan VisibilityDetector fire + coordinator wiring.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets(
    'session factory resolves a fresh URL after network tier changes',
    (tester) async {
      final createdUrls = <String, List<String>>{};
      debugPostVideoSessionUrlObserver = (sessionId, url) {
        createdUrls.putIfAbsent(sessionId, () => <String>[]).add(url);
      };
      final posts = [
        _fakeVideoPost(),
        _fakeVideoPost(
          id: 'post-2',
          videoDataSaverUrl: 'https://example.com/post-2/play_480p.mp4',
        ),
        for (var index = 3; index <= 20; index++)
          _fakeVideoPost(
            id: 'post-$index',
            videoDataSaverUrl: 'https://example.com/post-$index/play_480p.mp4',
          ),
      ];
      await pumpScreen(tester, posts: posts);
      final state =
          tester.state(find.byType(MemberPostDetailScreen)) as dynamic;
      final coordinator = state.debugVideoCoordinator as PostVideoCoordinator;

      state.debugSetPlaybackNetworkTier(NetworkTier.wifi);
      coordinator.setPreloadWindow(const ['post-20']);
      expect(createdUrls['post-20']?.last, 'https://example.com/post-20.mp4');

      coordinator.setPreloadWindow(const ['post-17', 'post-18', 'post-19']);
      coordinator.setPreloadWindow(const ['post-14', 'post-15', 'post-16']);
      expect(coordinator.sessionFor('post-20'), isNull,
          reason: 'the WiFi session must be evicted before recreation');

      state.debugSetPlaybackNetworkTier(NetworkTier.cellularFast);
      coordinator.setPreloadWindow(const ['post-20']);
      expect(createdUrls['post-20']?.last,
          'https://example.com/post-20/play_480p.mp4');

      await disposeTree(tester);
    },
  );

  testWidgets(
    'warm video is adopted before attach and bypasses normal factory',
    (tester) async {
      await appSettingsStore.setFeedVideoQuality('data_saver');
      var factoryCalls = 0;
      debugPostVideoSessionFactory = (_) {
        factoryCalls++;
        return _FakeSession();
      };
      final warm = _WarmSession();
      final post = _fakeVideoPost(
        videoDataSaverUrl: 'https://example.com/post-1-480.mp4',
      );
      final qualityUrl = post.videoPlaybackUrlForQuality(
        appSettingsStore.feedVideoQuality,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MemberPostDetailScreen(
            post: post,
            posts: [post],
            warmVideoHandoff: PostVideoWarmHandoff(
              postId: post.id,
              url: qualityUrl,
              hasAudio: post.hasAudio != false,
              session: warm,
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(factoryCalls, 0);
      final state =
          tester.state(find.byType(MemberPostDetailScreen)) as dynamic;
      expect(state.debugVideoCoordinator.sessionFor(post.id), same(warm));
      expect(state.debugVideoUrlForSession(post.id), qualityUrl);
      await disposeTree(tester);
    },
  );

  testWidgets(
    'refresh signed URL keeps current video quality preference',
    (tester) async {
      await appSettingsStore.setFeedVideoQuality('data_saver');
      final original = _fakeVideoPost(
        videoDataSaverUrl: 'https://example.com/post-1-480-old.mp4',
      );
      final fresh = _fakeVideoPost(
        videoDataSaverUrl: 'https://example.com/post-1-480-fresh.mp4',
      );
      debugScopedFeedPostFetcher = (_) async => fresh;
      await tester.pumpWidget(
        MaterialApp(
          home: MemberPostDetailScreen(post: original, posts: [original]),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      final state =
          tester.state(find.byType(MemberPostDetailScreen)) as dynamic;
      final refreshed = await state.debugRefreshVideoUrlForTest(original.id);

      expect(refreshed, 'https://example.com/post-1-480-fresh.mp4');
      expect(
        state.debugVideoUrlForSession(original.id),
        'https://example.com/post-1-480-fresh.mp4',
      );
      await disposeTree(tester);
    },
  );

  testWidgets(
    'refresh signed URL keeps current media video quality preference',
    (tester) async {
      await appSettingsStore.setFeedVideoQuality('data_saver');
      final original = _fakePostWithVideoMedia(
        mediaDataSaverUrl: 'https://example.com/media-1-480-old.mp4',
      );
      final fresh = _fakePostWithVideoMedia(
        mediaDataSaverUrl: 'https://example.com/media-1-480-fresh.mp4',
      );
      debugScopedFeedPostFetcher = (_) async => fresh;
      await tester.pumpWidget(
        MaterialApp(
          home: MemberPostDetailScreen(post: original, posts: [original]),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      final state =
          tester.state(find.byType(MemberPostDetailScreen)) as dynamic;
      final refreshed = await state.debugRefreshVideoUrlForTest('post-1-0');

      expect(refreshed, 'https://example.com/media-1-480-fresh.mp4');
      expect(
        state.debugVideoUrlForSession('post-1-0'),
        'https://example.com/media-1-480-fresh.mp4',
      );
      await disposeTree(tester);
    },
  );

  testWidgets(
    'transition playback gate keeps poster dormant until the route opens',
    (tester) async {
      final post = _fakeVideoPost();
      final transitionSession = PostDetailTransitionSession(
        initialPost: post,
        source: _TransitionSource(),
      );

      await pumpScreen(
        tester,
        posts: [post],
        transitionSession: transitionSession,
      );

      expect(
        sessions,
        isEmpty,
        reason: 'a preparing route must not attach or activate inline video',
      );

      transitionSession.setPlaybackAllowed(true);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(sessions['post-1']?.playing, isTrue);
      final playCount = sessions['post-1']!.playCount;

      transitionSession.setPlaybackAllowed(false);
      await tester.pump(const Duration(milliseconds: 30));

      expect(sessions['post-1']!.playing, isFalse);
      expect(
        sessions['post-1']!.playCount,
        playCount,
        reason: 'visibility callbacks while gated must not reactivate video',
      );

      await disposeTree(tester);
      transitionSession.dispose();
    },
  );

  testWidgets(
    'closed replacement gate shows poster without spinner and rewires session',
    (tester) async {
      final post = _fakeVideoPost();
      final firstSession = PostDetailTransitionSession(
        initialPost: post,
        source: _TransitionSource(),
      )..setPlaybackAllowed(true);
      final replacementSession = PostDetailTransitionSession(
        initialPost: post,
        source: _TransitionSource(),
      );

      await pumpScreen(tester, posts: [post], transitionSession: firstSession);
      expect(sessions['post-1']?.playing, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: MemberPostDetailScreen(
            post: post,
            posts: [post],
            transitionSession: replacementSession,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 30));

      expect(sessions['post-1']?.playing, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      replacementSession.setPlaybackAllowed(true);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(sessions['post-1']?.playing, isTrue);

      await disposeTree(tester);
      firstSession.dispose();
      replacementSession.dispose();
    },
  );

  testWidgets(
    'autoplay ON: inline attach + setActive → sesi dibuat & di-play, muted '
    'mengikuti feedMuted',
    (tester) async {
      await pumpScreen(tester);

      expect(sessions.containsKey('post-1'), isTrue,
          reason: 'inline yang terlihat harus attach → factory dipanggil');
      final s = sessions['post-1']!;
      expect(s.playCount, greaterThan(0),
          reason: 'setActive coordinator harus memutar sesi aktif');
      expect(s.playing, isTrue);
      // feedMuted true → sesi aktif volume 0 (§2.2).
      expect(s.volume, 0);

      await disposeTree(tester);
      // Coordinator dispose halaman → sesi di-dispose (satu-satunya pemilik).
      expect(s.disposeCount, 1);
    },
  );

  testWidgets(
    'Postingan tetap autoplay saat global feed autoplay OFF tanpa center play',
    (tester) async {
      await appSettingsStore.setFeedAutoplay(false);
      await pumpScreen(tester);

      expect(sessions.containsKey('post-1'), isTrue);
      expect(sessions['post-1']!.playing, isTrue,
          reason: 'Postingan mengabaikan preference autoplay feed umum');
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing,
          reason: 'inline Postingan tidak punya center play control');

      await disposeTree(tester);
    },
  );

  testWidgets(
    'mute global re-apply ke sesi aktif (unmute → volume 1)',
    (tester) async {
      await pumpScreen(tester);
      final s = sessions['post-1']!;
      expect(s.volume, 0, reason: 'mula-mula muted');

      // Unmute global (ekuivalen tap tombol mute inline) → coordinator
      // listener menaikkan volume sesi AKTIF ke 1.
      await appSettingsStore.setFeedMuted(false);
      await tester.pump(const Duration(milliseconds: 20));
      expect(s.volume, 1);

      await appSettingsStore.setFeedMuted(true);
      await tester.pump(const Duration(milliseconds: 20));
      expect(s.volume, 0);

      await disposeTree(tester);
    },
  );
}
