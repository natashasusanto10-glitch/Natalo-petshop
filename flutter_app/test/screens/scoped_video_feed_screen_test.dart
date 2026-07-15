import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/adaptive_video_preload_policy.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_coordinator.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_video_post_view.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/scoped_video_feed_screen.dart';
import 'package:natalo_petshop_flutter/services/video_quality_service.dart';
import 'package:natalo_petshop_flutter/state/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Fake sesi plugin-free — tak punya controller nyata (bukan VideoPlayerSession)
/// → FeedVideoPostView managed merender thumbnail & tetap melapor intent. Cukup
/// untuk memverifikasi wiring coordinator (setActive/preloadNext/detach/evict).
class _FakeSession implements PlaybackSession {
  _FakeSession(this.postId);
  final String postId;
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;
  double volume = 1;
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
  Future<void> dispose() async => disposeCount++;

  @override
  Duration get position => _pos;
}

FeedPost _fakeVideoPost(String id, {String? videoDataSaverUrl}) {
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

FeedPost _fakePhotoPost(String id) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_PHOTO',
    'mediaUrl': 'https://example.com/$id.jpg',
    'author': {'id': 'author-1', 'name': 'Tester'},
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  setUp(() {
    // Disable VisibilityDetector's internal debounce timer so it doesn't
    // leave a pending Timer past test teardown (it fires synchronously
    // instead when updateInterval is zero).
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('ScopedVideoFeedScreen opens at initialIndex', (tester) async {
    final posts = [
      _fakeVideoPost('a'),
      _fakeVideoPost('b'),
      _fakeVideoPost('c')
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(posts: posts, initialIndex: 1),
      ),
    );
    await tester.pump();
    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller?.initialPage, 1);
    // VisibilityDetector schedules a debounced (500ms) internal timer on
    // paint; flush it so the test binding doesn't flag a pending timer at
    // teardown. pumpAndSettle() is avoided repo-wide because it hangs when
    // video/image/shimmer surfaces render (never settles).
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('loads next profile pages and skips photo-only page',
      (tester) async {
    final requestedCursors = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(
          posts: [_fakeVideoPost('a')],
          initialIndex: 0,
          initialNextCursor: 'page-2',
          loadMorePosts: (cursor) async {
            requestedCursors.add(cursor);
            if (cursor == 'page-2') {
              return FeedPage(
                items: [_fakePhotoPost('photo')],
                nextCursor: 'page-3',
              );
            }
            return FeedPage(
              items: [_fakeVideoPost('b')],
              nextCursor: null,
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final pageView = tester.widget<PageView>(find.byType(PageView));
    final delegate = pageView.childrenDelegate as SliverChildBuilderDelegate;
    expect(requestedCursors, ['page-2', 'page-3']);
    expect(delegate.childCount, 2);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('stops pagination when the server cursor does not advance',
      (tester) async {
    var requestCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(
          posts: [_fakeVideoPost('a')],
          initialIndex: 0,
          initialNextCursor: 'stuck-cursor',
          loadMorePosts: (cursor) async {
            requestCount++;
            return FeedPage(
              items: [_fakePhotoPost('photo-$requestCount')],
              nextCursor: cursor,
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(requestCount, 1);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('stops pagination when cursors form a cycle', (tester) async {
    final requestedCursors = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(
          posts: [_fakeVideoPost('a')],
          initialIndex: 0,
          initialNextCursor: 'cursor-a',
          loadMorePosts: (cursor) async {
            requestedCursors.add(cursor);
            return FeedPage(
              items: [_fakePhotoPost('photo-${requestedCursors.length}')],
              nextCursor: cursor == 'cursor-a' ? 'cursor-b' : 'cursor-a',
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(requestedCursors, ['cursor-a', 'cursor-b']);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('continues pagination after a long run of photo-only pages',
      (tester) async {
    var requestCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(
          posts: [_fakeVideoPost('a')],
          initialIndex: 0,
          initialNextCursor: 'page-1',
          loadMorePosts: (cursor) async {
            requestCount++;
            if (requestCount <= 8) {
              return FeedPage(
                items: [_fakePhotoPost('photo-$requestCount')],
                nextCursor: 'page-${requestCount + 1}',
              );
            }
            return FeedPage(
              items: [_fakeVideoPost('b')],
              nextCursor: null,
            );
          },
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (requestCount == 9) break;
    }

    final pageView = tester.widget<PageView>(find.byType(PageView));
    final delegate = pageView.childrenDelegate as SliverChildBuilderDelegate;
    expect(requestCount, 9);
    expect(delegate.childCount, 2);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('drag past top boundary on first video dismisses the viewer',
      (tester) async {
    final posts = [_fakeVideoPost('a'), _fakeVideoPost('b')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ScopedVideoFeedScreen(posts: posts, initialIndex: 0),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);

    // Drag DOWN well past the 72px overscroll threshold while on the
    // first video → viewer pops (ala IG Reels tarik-turun dari profil).
    await tester.drag(find.byType(PageView), const Offset(0, 300));
    // Pop fires immediately (NavigatorObserver confirms), but the exiting
    // route stays in the overlay through the reverse transition + the
    // overscroll ballistic settle (~600-800ms) — pump bounded until gone.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isEmpty) break;
    }
    expect(find.byType(ScopedVideoFeedScreen), findsNothing,
        reason: 'overscroll drag at the first video should close the viewer');

    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('edge swipe right dismisses and returns last-active payload',
      (tester) async {
    final posts = [_fakeVideoPost('a'), _fakeVideoPost('b')];
    ScopedVideoFeedResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ScopedVideoFeedResult>(
                MaterialPageRoute<ScopedVideoFeedResult>(
                  builder: (_) => ScopedVideoFeedScreen(
                    posts: posts,
                    initialIndex: 1,
                  ),
                ),
              );
            },
            child: const Text('open swipe'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open swipe'));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.dragFrom(const Offset(24, 400), const Offset(220, 0));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isEmpty) break;
    }

    expect(find.byType(ScopedVideoFeedScreen), findsNothing);
    expect(result, isNotNull);
    expect(result!.postId, 'b');
    expect(result!.index, 1);
    expect(result!.timestamp, Duration.zero);
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('horizontal swipe away from left edge does not dismiss',
      (tester) async {
    final posts = [_fakeVideoPost('a')];
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(posts: posts, initialIndex: 0),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.dragFrom(const Offset(100, 400), const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
  });

  testWidgets('short slow edge drag springs back without dismissing',
      (tester) async {
    final posts = [_fakeVideoPost('a')];
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(posts: posts, initialIndex: 0),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final gesture = await tester.startGesture(const Offset(16, 400));
    await gesture.moveBy(const Offset(55, 0));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('scoped-video-page-view')),
          )
          .dx,
      moreOrLessEquals(0),
    );
  });

  testWidgets('pinch beginning at the left edge does not dismiss',
      (tester) async {
    final posts = [_fakeVideoPost('a')];
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(posts: posts, initialIndex: 0),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final firstPointer = await tester.startGesture(const Offset(16, 400));
    final secondPointer = await tester.startGesture(const Offset(180, 400));
    await firstPointer.moveBy(const Offset(80, 0));
    await secondPointer.moveBy(const Offset(-80, 0));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('scoped-video-page-view')),
          )
          .dx,
      moreOrLessEquals(0),
    );

    await firstPointer.up();
    await secondPointer.up();
  });

  testWidgets('edge drag that turns vertical yields to the PageView',
      (tester) async {
    final posts = [_fakeVideoPost('a'), _fakeVideoPost('b')];
    String? activePostId;
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(
          posts: posts,
          initialIndex: 0,
          onActivePostChanged: (postId) => activePostId = postId,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final gesture = await tester.startGesture(const Offset(16, 400));
    await gesture.moveBy(const Offset(18, 2));
    await tester.pump();
    await gesture.moveBy(const Offset(4, -500));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
    expect(activePostId, 'b');
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('scoped-video-page-view')),
          )
          .dx,
      moreOrLessEquals(0),
    );
  });

  test('high rightward velocity dismisses before the distance threshold', () {
    expect(
      ScopedVideoFeedScreen.shouldDismissEdgeSwipe(
        offset: 70,
        width: 400,
        velocity: 1200,
      ),
      isTrue,
    );
    expect(
      ScopedVideoFeedScreen.shouldDismissEdgeSwipe(
        offset: 70,
        width: 400,
        velocity: 500,
      ),
      isFalse,
    );
  });

  testWidgets('fullscreen controls use 48px back target and top scrim',
      (tester) async {
    final posts = [_fakeVideoPost('a')];
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(posts: posts, initialIndex: 0),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      tester.getSize(find.byKey(const ValueKey('scoped-video-back-target'))),
      const Size(48, 48),
    );
    expect(
      find.byKey(const ValueKey('scoped-video-top-scrim')),
      findsOneWidget,
    );
  });

  testWidgets('toolbar back returns typed last-active post payload',
      (tester) async {
    final posts = [_fakeVideoPost('a'), _fakeVideoPost('b')];
    ScopedVideoFeedResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ScopedVideoFeedResult>(
                MaterialPageRoute<ScopedVideoFeedResult>(
                  builder: (_) => ScopedVideoFeedScreen(
                    posts: posts,
                    initialIndex: 1,
                  ),
                ),
              );
            },
            child: const Text('open typed'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open typed'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isNotNull);
    expect(result!.postId, 'b');
    expect(result!.index, 1);
    expect(result!.timestamp, Duration.zero);
  });

  testWidgets('prepare-close failure cannot lock the fullscreen route',
      (tester) async {
    ScopedVideoFeedResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ScopedVideoFeedResult>(
                MaterialPageRoute<ScopedVideoFeedResult>(
                  builder: (_) => ScopedVideoFeedScreen(
                    posts: [_fakeVideoPost('a')],
                    initialIndex: 0,
                    onPrepareClose: (_, __) async => throw StateError('failed'),
                  ),
                ),
              );
            },
            child: const Text('open failing close'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open failing close'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isEmpty) break;
    }

    expect(find.byType(ScopedVideoFeedScreen), findsNothing);
    expect(result?.postId, 'a');
  });

  testWidgets('prepare-close timeout cannot lock the fullscreen route',
      (tester) async {
    ScopedVideoFeedResult? result;
    final neverCompletes = Completer<void>();
    ScopedVideoFeedCloseSignal? closeSignal;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ScopedVideoFeedResult>(
                MaterialPageRoute<ScopedVideoFeedResult>(
                  builder: (_) => ScopedVideoFeedScreen(
                    posts: [_fakeVideoPost('a')],
                    initialIndex: 0,
                    onPrepareClose: (_, signal) {
                      closeSignal = signal;
                      return neverCompletes.future;
                    },
                  ),
                ),
              );
            },
            child: const Text('open hanging close'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open hanging close'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isEmpty) break;
    }

    expect(find.byType(ScopedVideoFeedScreen), findsNothing);
    expect(result?.postId, 'a');
    expect(closeSignal?.isCancelled, isTrue);
    neverCompletes.complete();
    await tester.pump();
  });

  testWidgets('system back returns typed last-active post payload',
      (tester) async {
    final posts = [_fakeVideoPost('a'), _fakeVideoPost('b')];
    ScopedVideoFeedResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ScopedVideoFeedResult>(
                MaterialPageRoute<ScopedVideoFeedResult>(
                  builder: (_) => ScopedVideoFeedScreen(
                    posts: posts,
                    initialIndex: 0,
                  ),
                ),
              );
            },
            child: const Text('open system'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open system'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
    }
    expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, isNotNull);
    expect(result!.postId, 'a');
    expect(result!.index, 0);
    expect(result!.timestamp, Duration.zero);
  });

  // ── T7 — full-managed: adaptive preload, max 5 live sessions
  //    (origin + active + max 3 preload), zero duplicate controllers. ──
  group('T7 full-managed', () {
    late Map<String, _FakeSession> sessions;
    late Map<String, int> createCount;
    late PostVideoCoordinator coordinator;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      sessions = {};
      createCount = {};
      await appSettingsStore.setFeedMuted(true);
      await appSettingsStore.setFeedVideoQuality('auto');
      coordinator = PostVideoCoordinator(
        sessionFactory: (id) {
          createCount[id] = (createCount[id] ?? 0) + 1;
          final s = _FakeSession(id);
          sessions[id] = s;
          return s;
        },
      );
    });

    tearDown(() {
      if (!coordinator.isDisposed) coordinator.dispose();
    });

    Future<void> pumpScoped(
      WidgetTester tester, {
      required List<FeedPost> posts,
      int initialIndex = 0,
      NetworkTier? networkTier,
      Stream<NetworkTier>? tierChanges,
      ValueChanged<NetworkTier>? onNetworkTierChanged,
    }) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Simulasi handoff Postingan: origin (halaman awal) pinned.
      coordinator.setOrigin(posts[initialIndex].id);
      await tester.pumpWidget(
        MaterialApp(
          home: ScopedVideoFeedScreen(
            posts: posts,
            initialIndex: initialIndex,
            coordinator: coordinator,
            originPostId: posts[initialIndex].id,
            debugNetworkTier: networkTier,
            debugTierChanges: tierChanges,
            onNetworkTierChanged: onNetworkTierChanged,
          ),
        ),
      );
      // Bounded pump — postFrameCallback aktivasi awal + VisibilityDetector.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    Future<void> swipeNext(WidgetTester tester) async {
      await tester.drag(find.byType(PageView), const Offset(0, -900),
          warnIfMissed: false);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    testWidgets(
      'aktivasi awal: origin active + preload next (semua item managed)',
      (tester) async {
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
        ];
        await pumpScoped(tester, posts: posts);

        expect(coordinator.activePostId, 'a',
            reason: 'halaman awal jadi active');
        expect(sessions['a']!.playing, isTrue,
            reason: 'origin di-play oleh setActive');
        // Preload next (b) — bukan data saver.
        expect(coordinator.preloadPostId, 'b');
        expect(sessions.containsKey('b'), isTrue);
        expect(sessions['b']!.playing, isFalse,
            reason: 'preload lahir paused + muted');
      },
    );

    testWidgets('wifi window follows direction with two ahead and one behind',
        (tester) async {
      final posts = [
        _fakeVideoPost('a'),
        _fakeVideoPost('b'),
        _fakeVideoPost('c'),
        _fakeVideoPost('d'),
      ];
      await pumpScoped(
        tester,
        posts: posts,
        initialIndex: 1,
        networkTier: NetworkTier.wifi,
      );
      expect(coordinator.preloadPostIds, {'c', 'd', 'a'});

      await tester.drag(find.byType(PageView), const Offset(0, 900),
          warnIfMissed: false);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(coordinator.activePostId, 'a');
      expect(coordinator.preloadPostIds, isEmpty,
          reason: 'the only valid behind target is already pinned as origin');
    });

    testWidgets(
      'tier change resets cellular buffer eligibility and refreshes window',
      (tester) async {
        final tierChanges = StreamController<NetworkTier>.broadcast();
        addTearDown(tierChanges.close);
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
          _fakeVideoPost('d'),
        ];
        await pumpScoped(
          tester,
          posts: posts,
          initialIndex: 1,
          networkTier: NetworkTier.wifi,
          tierChanges: tierChanges.stream,
        );
        expect(coordinator.preloadPostIds, {'c', 'd', 'a'});

        tierChanges.add(NetworkTier.cellularFast);
        await tester.pump();

        expect(coordinator.preloadPostIds, isEmpty,
            reason: 'new cellular tier must earn fresh buffer eligibility');
        expect(sessions['c']!.disposeCount, 1);
        expect(sessions['d']!.disposeCount, 1);

        tierChanges.add(NetworkTier.wifi);
        await tester.pump();

        expect(coordinator.preloadPostIds, {'c', 'd', 'a'});
        expect(createCount['c'], 2,
            reason: 'evicted prior-tier preload is recreated');
        expect(createCount['d'], 2,
            reason: 'evicted prior-tier preload is recreated');
      },
    );

    testWidgets(
      'tier change evicts preload before callback and recreates it at 480p',
      (tester) async {
        final tierChanges = StreamController<NetworkTier>.broadcast();
        addTearDown(tierChanges.close);
        var resolverTier = NetworkTier.wifi;
        final createdUrls = <String, List<String>>{};
        final sessionHistory = <String, List<_FakeSession>>{};
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost(
            'c',
            videoDataSaverUrl: 'https://example.com/c/play_480p.mp4',
          ),
        ];
        final postsById = {for (final post in posts) post.id: post};

        coordinator.dispose();
        coordinator = PostVideoCoordinator(
          sessionFactory: (id) {
            final post = postsById[id]!;
            final url = videoQualityService.resolvePlaybackUrl(
              post.videoPlaybackUrl,
              dataSaverUrl: post.videoDataSaverUrl,
              userPreference: 'auto',
              networkTier: resolverTier,
            );
            createdUrls.putIfAbsent(id, () => <String>[]).add(url);
            final session = _FakeSession(id);
            sessions[id] = session;
            sessionHistory.putIfAbsent(id, () => <_FakeSession>[]).add(session);
            return session;
          },
        );

        await pumpScoped(
          tester,
          posts: posts,
          initialIndex: 1,
          networkTier: NetworkTier.wifi,
          tierChanges: tierChanges.stream,
          onNetworkTierChanged: (tier) {
            expect(coordinator.preloadPostIds, isEmpty,
                reason: 'old-tier preloads must be evicted before callback');
            resolverTier = tier;
          },
        );
        expect(createdUrls['c'], ['https://example.com/c.mp4']);
        final activeSession = coordinator.sessionFor('b');
        final originSession = activeSession;
        final wifiPreload = sessionHistory['c']!.single;

        tierChanges.add(NetworkTier.cellularFast);
        await tester.pump();

        expect(wifiPreload.disposeCount, 1);
        expect(coordinator.sessionFor('b'), same(activeSession),
            reason: 'active/origin playback must not restart on tier change');
        expect(coordinator.preloadPostIds, isEmpty,
            reason: 'cellular preload waits for sufficient active buffer');

        final activeView = tester.widget<FeedVideoPostView>(
          find.byKey(const ValueKey('scoped-fs-b')),
        );
        activeView.onBufferAheadChanged!(
          AdaptiveVideoPreloadPolicy.cellularBufferAheadThreshold,
        );
        await tester.pump();

        expect(createdUrls['c'], [
          'https://example.com/c.mp4',
          'https://example.com/c/play_480p.mp4',
        ]);
        expect(sessionHistory['c'], hasLength(2));
        expect(coordinator.sessionFor('b'), same(originSession));
      },
    );

    testWidgets(
      'swipe A→B: B pakai sesi preload (createCount B tetap 1, tak dibuat ulang)',
      (tester) async {
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
        ];
        await pumpScoped(tester, posts: posts);
        expect(createCount['b'], 1,
            reason: 'B dipreload sekali di aktivasi awal');

        await swipeNext(tester);

        expect(coordinator.activePostId, 'b');
        expect(sessions['b']!.playing, isTrue);
        expect(createCount['b'], 1,
            reason: 'B jadi active pakai sesi preload — TIDAK dibuat ulang');
        // Nol dobel controller: setiap id maksimum 1 sesi dibuat.
        for (final entry in createCount.entries) {
          expect(entry.value, 1,
              reason: 'id ${entry.key} tak boleh dobel sesi');
        }
      },
    );

    testWidgets(
      'steady state respects max 5 live and max 3 adaptive preloads',
      (tester) async {
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
          _fakeVideoPost('d'),
          _fakeVideoPost('e'),
        ];
        await pumpScoped(tester, posts: posts);

        await swipeNext(tester); // a→b
        await swipeNext(tester); // b→c
        await swipeNext(tester); // c→d

        expect(coordinator.livePostIds.length, lessThanOrEqualTo(5),
            reason: 'origin + active + at most three adaptive preloads');
        expect(coordinator.preloadPostIds.length, lessThanOrEqualTo(3));
        // Origin (a) tetap hidup (pinned) untuk kembali ke Postingan.
        expect(coordinator.livePostIds, contains('a'));
        expect(sessions['a']!.disposeCount, 0);
        // Nol dobel controller sepanjang swipe.
        for (final entry in createCount.entries) {
          expect(entry.value, 1,
              reason: 'id ${entry.key} tak boleh dobel sesi');
        }
      },
    );

    testWidgets(
      'data saver: preloadNext DILEWATI — swipe bikin sesi saat itu (1 sesi/id)',
      (tester) async {
        await appSettingsStore.setFeedVideoQuality('data_saver');
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
        ];
        await pumpScoped(tester, posts: posts);

        // Aktivasi awal TIDAK preload B (data saver).
        expect(coordinator.preloadPostId, isNull);
        expect(sessions.containsKey('b'), isFalse,
            reason: 'data saver → tak ada preload sebelum swipe');

        await swipeNext(tester); // a→b: setActive bikin sesi B saat itu

        expect(coordinator.activePostId, 'b');
        expect(createCount['b'], 1,
            reason: 'B dibuat sekali (satu controller)');
        // Masih tak ada preload C.
        expect(coordinator.preloadPostId, isNull);
        expect(sessions.containsKey('c'), isFalse);
      },
    );

    testWidgets(
      'kembali ke Postingan: origin (pinned) TIDAK di-dispose saat viewer tutup',
      (tester) async {
        final posts = [
          _fakeVideoPost('a'),
          _fakeVideoPost('b'),
          _fakeVideoPost('c'),
        ];
        await pumpScoped(tester, posts: posts);
        await swipeNext(tester); // a→b, origin a tetap pinned

        // Tutup viewer (dispose screen) — origin masih pinned via setOrigin.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 30));

        expect(sessions['a']!.disposeCount, 0,
            reason: 'origin hidup → inline lanjut di timestamp saat kembali');
        // Coordinator (milik halaman Postingan) belum dispose di test ini.
        expect(coordinator.sessionFor('a'), same(sessions['a']));
      },
    );
  });
}
