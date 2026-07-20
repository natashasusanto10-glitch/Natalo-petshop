// ignore_for_file: depend_on_referenced_packages
//
// video_player_platform_interface is used directly by the fake platform
// below (same pattern as post_page_zoom_route_test.dart /
// member_post_detail_double_tap_test.dart) even though it's only a
// transitive dep of this package via video_player.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/layout/postingan_media_aspect_ratio.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_detail_transition_session.dart';
import 'package:natalo_petshop_flutter/features/feed/video/frame_output_heartbeat_service.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  setUp(() {
    debugPostDelete = null;
    debugPostDetailReadinessClock = () => Duration.zero;
    debugPostDetailReadinessFrameFuture = null;
    debugScopedFeedPostFetcher = null;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDown(() {
    debugPostDelete = null;
    debugPostDetailReadinessClock = null;
    debugPostDetailReadinessFrameFuture = null;
    debugScopedFeedPostFetcher = null;
  });

  testWidgets('nonzero initialIndex is aligned before destination readiness', (
    tester,
  ) async {
    useDetailViewport(tester);
    final posts = List.generate(5, (index) => fakePhoto('post-$index'));
    final session = fakeTransitionSession(posts[3]);

    await tester.pumpWidget(
      detailHost(posts: posts, initialIndex: 3, session: session),
    );

    expect(
      session.destinationReadiness,
      PostDetailDestinationReadiness.preparing,
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }

    final target = find.byKey(const ValueKey('post-detail-item-post-3'));
    expect(target, findsOneWidget);
    expect(
      tester.getTopLeft(target).dy,
      closeTo(detailViewportRect(tester).top, 1),
    );
    expect(
      session.destinationReadiness,
      PostDetailDestinationReadiness.geometryReady,
    );
    expect(find.text('post-0-caption'), findsNothing);

    await disposeDetail(tester);
    session.dispose();
  });

  testWidgets(
    'geometry readiness publishes after fallback removal and list rendering',
    (tester) async {
      useDetailViewport(tester);
      final posts = List.generate(5, (index) => fakePhoto('post-$index'));
      final session = fakeTransitionSession(posts[3]);
      var fallbackAbsentAtPublication = false;
      var targetRenderableAtPublication = false;
      session.addListener(() {
        if (session.destinationReadiness !=
            PostDetailDestinationReadiness.geometryReady) {
          return;
        }
        fallbackAbsentAtPublication = find
            .byKey(const ValueKey('post-detail-transition-fallback-post-3'))
            .evaluate()
            .isEmpty;
        final target = find
            .byKey(const ValueKey('post-detail-item-post-3'))
            .evaluate()
            .firstOrNull;
        final box = target?.findRenderObject() as RenderBox?;
        targetRenderableAtPublication =
            box != null && box.attached && box.hasSize && !box.size.isEmpty;
      });

      await tester.pumpWidget(
        detailHost(posts: posts, initialIndex: 3, session: session),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(
        session.destinationReadiness,
        PostDetailDestinationReadiness.geometryReady,
      );
      expect(fallbackAbsentAtPublication, isTrue);
      expect(targetRenderableAtPublication, isTrue);

      await disposeDetail(tester);
      session.dispose();
    },
  );

  testWidgets(
    'an expired post-removal frame never publishes geometry readiness',
    (tester) async {
      useDetailViewport(tester);
      final posts = List.generate(5, (index) => fakePhoto('post-$index'));
      final session = fakeTransitionSession(posts[3]);
      // The budget is exhausted at exactly the post-removal readiness frame:
      // the frame that renders the fallback removal and makes the destination
      // list observable. A false bounded-frame outcome is authoritative and
      // must never resolve to geometry readiness, however observable the
      // destination happens to be at that instant.
      var expired = false;
      debugPostDetailReadinessClock = () =>
          expired ? const Duration(milliseconds: 80) : Duration.zero;
      debugPostDetailReadinessFrameFuture = () async {
        await WidgetsBinding.instance.endOfFrame;
        final removalRendered =
            find
                .byKey(const ValueKey('post-detail-transition-fallback-post-3'))
                .evaluate()
                .isEmpty &&
            find
                .byKey(const ValueKey('post-detail-item-post-3'))
                .evaluate()
                .isNotEmpty;
        if (removalRendered) expired = true;
      };

      await tester.pumpWidget(
        detailHost(posts: posts, initialIndex: 3, session: session),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      expect(
        session.destinationReadiness,
        PostDetailDestinationReadiness.crossfadeFallback,
        reason: 'a false bounded-frame outcome must not become geometryReady',
      );

      await disposeDetail(tester);
      session.dispose();
    },
  );

  testWidgets(
    'an expired post-removal frame recovers a renderable fallback, never '
    'preparing',
    (tester) async {
      useDetailViewport(tester);
      final posts = List.generate(5, (index) => fakePhoto('post-$index'));
      final session = fakeTransitionSession(posts[3]);
      var frameReq = 0;
      var expired = false;
      debugPostDetailReadinessClock = () =>
          expired ? const Duration(milliseconds: 80) : Duration.zero;
      // Alignment frames render normally; the post-removal frame resolves
      // without rendering (an already-complete future) and expires the budget,
      // so the fallback removal never paints and the destination list never
      // becomes observable. Readiness must still reach a terminal, renderable
      // crossfade fallback — never geometry readiness, never `preparing`.
      debugPostDetailReadinessFrameFuture = () {
        frameReq++;
        if (frameReq >= 3) {
          expired = true;
          return Future<void>.value();
        }
        return WidgetsBinding.instance.endOfFrame;
      };

      await tester.pumpWidget(
        detailHost(posts: posts, initialIndex: 3, session: session),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      expect(
        session.destinationReadiness,
        PostDetailDestinationReadiness.crossfadeFallback,
        reason: 'an invalid destination after expiry must never stay preparing',
      );
      expect(
        find.byKey(const ValueKey('post-detail-transition-fallback-post-3')),
        findsOneWidget,
      );

      await disposeDetail(tester);
      session.dispose();
    },
  );

  testWidgets(
    'clamped final post uses fallback instead of geometry readiness',
    (tester) async {
      useDetailViewport(tester);
      final posts = [fakePhoto('a'), fakePhoto('b')];
      final session = fakeTransitionSession(posts.last);

      await tester.pumpWidget(
        detailHost(posts: posts, initialIndex: 1, session: session),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(
        session.destinationReadiness,
        PostDetailDestinationReadiness.crossfadeFallback,
      );
      expect(
        find.byKey(const ValueKey('post-detail-transition-fallback-b')),
        findsOneWidget,
      );

      session.setPlaybackAllowed(true);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('post-detail-transition-fallback-b')),
        findsNothing,
        reason: 'a valid clamped list surface may replace the bounded fallback',
      );

      await disposeDetail(tester);
      session.dispose();
    },
  );

  testWidgets('readiness deadline includes the first awaited frame', (
    tester,
  ) async {
    useDetailViewport(tester);
    var readinessNow = Duration.zero;
    debugPostDetailReadinessClock = () => readinessNow;
    final posts = List.generate(5, (index) => fakePhoto('post-$index'));
    final session = fakeTransitionSession(posts[3]);

    await tester.pumpWidget(
      detailHost(posts: posts, initialIndex: 3, session: session),
    );
    expect(
      session.destinationReadiness,
      PostDetailDestinationReadiness.preparing,
    );

    readinessNow = const Duration(milliseconds: 80);
    await tester.pump();

    expect(
      session.destinationReadiness,
      PostDetailDestinationReadiness.crossfadeFallback,
    );

    await disposeDetail(tester);
    session.dispose();
  });

  testWidgets(
    'expired first awaited frame does not consume another readiness frame',
    (tester) async {
      useDetailViewport(tester);
      var readinessNow = Duration.zero;
      debugPostDetailReadinessClock = () => readinessNow;
      final posts = List.generate(5, (index) => fakePhoto('post-$index'));
      final session = fakeTransitionSession(posts[3]);
      tester.binding.addPostFrameCallback((_) {
        readinessNow = const Duration(milliseconds: 80);
      });

      await tester.pumpWidget(
        detailHost(posts: posts, initialIndex: 3, session: session),
      );

      expect(
        session.destinationReadiness,
        PostDetailDestinationReadiness.crossfadeFallback,
        reason:
            'the expired first frame must be terminal without a second pump',
      );

      await disposeDetail(tester);
      session.dispose();
    },
  );

  testWidgets('a missing readiness frame times out within the same deadline', (
    tester,
  ) async {
    useDetailViewport(tester);
    var readinessNow = Duration.zero;
    var frameWaits = 0;
    debugPostDetailReadinessClock = () => readinessNow;
    debugPostDetailReadinessFrameFuture = () {
      frameWaits++;
      return Completer<void>().future;
    };
    final posts = List.generate(5, (index) => fakePhoto('post-$index'));
    final session = fakeTransitionSession(posts[3]);

    await tester.pumpWidget(
      detailHost(posts: posts, initialIndex: 3, session: session),
    );
    expect(
      session.destinationReadiness,
      PostDetailDestinationReadiness.preparing,
    );

    readinessNow = const Duration(milliseconds: 75);
    await tester.pump(const Duration(milliseconds: 75));

    expect(frameWaits, 1);
    expect(
      session.destinationReadiness,
      PostDetailDestinationReadiness.crossfadeFallback,
    );
    expect(
      find.byKey(const ValueKey('post-detail-transition-fallback-post-3')),
      findsOneWidget,
    );

    await disposeDetail(tester);
    session.dispose();
  });

  testWidgets('fallback readiness is published after its renderable frame', (
    tester,
  ) async {
    useDetailViewport(tester);
    final posts = [fakePhoto('a'), fakePhoto('b')];
    final session = fakeTransitionSession(posts.last);
    var renderableAtPublication = false;
    session.addListener(() {
      if (session.destinationReadiness !=
          PostDetailDestinationReadiness.crossfadeFallback) {
        return;
      }
      final fallback = find
          .byKey(const ValueKey('post-detail-transition-fallback-b'))
          .evaluate()
          .firstOrNull;
      final box = fallback?.findRenderObject() as RenderBox?;
      renderableAtPublication =
          box != null && box.attached && box.hasSize && !box.size.isEmpty;
    });

    await tester.pumpWidget(
      detailHost(posts: posts, initialIndex: 1, session: session),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(
      session.destinationReadiness,
      PostDetailDestinationReadiness.crossfadeFallback,
    );
    expect(
      renderableAtPublication,
      isTrue,
      reason: 'readiness must never expose an absent fallback destination',
    );

    await disposeDetail(tester);
    session.dispose();
  });

  testWidgets(
    'replacement session discards old readiness and reaches a terminal state',
    (tester) async {
      useDetailViewport(tester);
      final posts = [fakePhoto('a'), fakePhoto('b')];
      final firstSession = fakeTransitionSession(posts.last);
      final replacementSession = fakeTransitionSession(posts.first);
      final frameWaits = <Completer<void>>[];
      debugPostDetailReadinessFrameFuture = () {
        final completer = Completer<void>();
        frameWaits.add(completer);
        return completer.future;
      };

      await tester.pumpWidget(
        detailHost(posts: posts, initialIndex: 1, session: firstSession),
      );
      expect(
        firstSession.destinationReadiness,
        PostDetailDestinationReadiness.preparing,
      );
      expect(frameWaits, hasLength(1));
      expect(
        find.byKey(const ValueKey('post-detail-transition-fallback-b')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        detailHost(posts: posts, initialIndex: 1, session: replacementSession),
      );
      expect(frameWaits, hasLength(2));
      expect(
        find.byKey(const ValueKey('post-detail-transition-fallback-b')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('post-detail-transition-fallback-a')),
        findsOneWidget,
      );

      frameWaits.first.complete();
      await tester.pump();
      expect(
        firstSession.destinationReadiness,
        PostDetailDestinationReadiness.preparing,
        reason: 'captured old-session work must stop at identity replacement',
      );
      expect(
        replacementSession.destinationReadiness,
        PostDetailDestinationReadiness.preparing,
      );

      var replacementWait = 1;
      for (
        var pass = 0;
        pass < 3 &&
            replacementSession.destinationReadiness ==
                PostDetailDestinationReadiness.preparing;
        pass++
      ) {
        expect(replacementWait, lessThan(frameWaits.length));
        frameWaits[replacementWait++].complete();
        await tester.pump();
      }

      expect(
        replacementSession.destinationReadiness,
        isNot(PostDetailDestinationReadiness.preparing),
      );
      expect(
        firstSession.destinationReadiness,
        PostDetailDestinationReadiness.preparing,
        reason: 'captured old-session work must not publish into replacement',
      );

      await disposeDetail(tester);
      firstSession.dispose();
      replacementSession.dispose();
    },
  );

  testWidgets('scrolling selects B once and prepares it behind the route', (
    tester,
  ) async {
    useDetailViewport(tester);
    final posts = [fakePhoto('a'), fakePhoto('b'), fakePhoto('c')];
    final source = FakeTransitionSource();
    final session = fakeTransitionSession(posts.first, source: source);

    await tester.pumpWidget(detailHost(posts: posts, session: session));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    source.preparedPostIds.clear();

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    await tester.pump();

    expect(session.activePost.id, 'b');
    expect(source.preparedPostIds.where((id) => id == 'b'), hasLength(1));

    await disposeDetail(tester);
    session.dispose();
  });

  testWidgets(
    'visibility measurement reports the active post media rect/aspect to '
    'the transition session, and re-reports it on scroll (Task 4 route '
    'geometry channel)',
    (tester) async {
      useDetailViewport(tester);
      final posts = [fakePhoto('a'), fakePhoto('b')];
      final session = fakeTransitionSession(posts.first);

      await tester.pumpWidget(detailHost(posts: posts, session: session));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(session.activePost.id, 'a');
      final boxA = mediaSlotRenderBox(tester, 'a');
      final expectedRectA = boxA.localToGlobal(Offset.zero) & boxA.size;
      expect(session.destinationMediaSlotRect, expectedRectA);
      expect(
        session.destinationMediaAspect,
        resolvePostinganMediaAspectRatio(
          width: posts.first.aspectWidthInt,
          height: posts.first.aspectHeightInt,
          type: posts.first.contentType,
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();
      await tester.pump();

      expect(session.activePost.id, 'b');
      final boxB = mediaSlotRenderBox(tester, 'b');
      final expectedRectB = boxB.localToGlobal(Offset.zero) & boxB.size;
      expect(session.destinationMediaSlotRect, expectedRectB);
      expect(
        session.destinationMediaAspect,
        resolvePostinganMediaAspectRatio(
          width: posts.last.aspectWidthInt,
          height: posts.last.aspectHeightInt,
          type: posts.last.contentType,
        ),
      );

      await disposeDetail(tester);
      session.dispose();
    },
  );

  testWidgets(
    'destination clears the reported video controller on its own dispose, '
    'before the coordinator disposes the underlying controller — closing '
    'the window where session.destinationVideoController could still point '
    'at an already-disposed VideoPlayerController (Task 4 hardening)',
    (tester) async {
      final platform = _FakeHeroVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      // The real VideoPlayerSession registers a frame-output heartbeat over
      // a platform EventChannel that has no test implementation — stub it to
      // a no-op "listen" so it doesn't throw a MissingPluginException (which
      // would otherwise fail this test independently of the assertions
      // below; we don't need real frame heartbeats here).
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(frameOutputHeartbeatChannelName),
        (call) async => null,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel(frameOutputHeartbeatChannelName),
          null,
        );
      });
      useDetailViewport(tester);
      final post = fakeHlsVideo('a');
      final session = fakeTransitionSession(post);

      await tester.pumpWidget(detailHost(posts: [post], session: session));
      // Mirrors what PostPageZoomRoute does on the `opening` -> `open` edge —
      // gates the inline player's attach/autoplay (see `_applyVisibility`).
      session.setPlaybackAllowed(true);
      await tester.pump();
      // Real async: the fake platform's `initialized` event needs a real
      // microtask turn to reach `VideoPlayerController.initialize()` —
      // same documented gotcha as post_page_zoom_route_test.dart.
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      final reportedController = session.destinationVideoController;
      expect(
        reportedController,
        isNotNull,
        reason:
            'the coordinator must have attached + initialized a real '
            'controller for the active video post by now',
      );
      expect(reportedController!.value.isInitialized, isTrue);

      // Tear the destination down WITHOUT disposing the session first (the
      // session is source-owned and normally outlives the destination — see
      // PostDetailTransitionSession's ownership contract). This is exactly
      // the window the reviewer flagged: if the destination's dispose() does
      // not clear the channel before the coordinator disposes its
      // controllers, `session.destinationVideoController` would keep
      // pointing at a controller that is now disposed underneath it.
      await disposeDetail(tester);

      expect(
        session.destinationVideoController,
        isNull,
        reason:
            'the destination must clear the reported controller on its '
            'own dispose, before the coordinator disposes it — otherwise a '
            'later read of session.destinationVideoController (e.g. by the '
            'route rebuilding during Task 5/6 teardown) would touch an '
            'already-disposed VideoPlayerController and throw',
      );

      session.dispose();
    },
  );

  testWidgets(
    'idle user-scroll after ScrollEnd keeps settled center fallback',
    (tester) async {
      useDetailViewport(tester);
      final posts = [fakeVideo('a'), fakeVideo('b')];
      final session = fakeTransitionSession(posts.first);
      await tester.pumpWidget(detailHost(posts: posts, session: session));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }

      final list = find.byType(ListView);
      final controller = tester.widget<ListView>(list).controller!;
      controller.jumpTo(475);
      expect(session.activePost.id, 'a');

      final notificationContext = tester.element(list);
      final listener = tester.widget<NotificationListener<ScrollNotification>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is NotificationListener<ScrollNotification> &&
              widget.child is ListView,
        ),
      );
      listener.onNotification!(
        ScrollEndNotification(
          metrics: controller.position,
          context: notificationContext,
        ),
      );
      listener.onNotification!(
        UserScrollNotification(
          metrics: controller.position,
          context: notificationContext,
          direction: ScrollDirection.idle,
        ),
      );
      await tester.pump();

      expect(session.activePost.id, 'b');

      await disposeDetail(tester);
      session.dispose();
    },
  );

  testWidgets('frozen measurements do not suppress the first unfreeze report', (
    tester,
  ) async {
    useDetailViewport(tester);
    final posts = [fakePhoto('a'), fakePhoto('b')];
    final session = fakeTransitionSession(posts.first);
    await tester.pumpWidget(detailHost(posts: posts, session: session));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }

    session.freeze();
    await tester.pump();
    final list = find.byType(ListView);
    final controller = tester.widget<ListView>(list).controller!;
    controller.jumpTo(900);
    await tester.pump();
    final notificationContext = tester.element(list);
    ScrollEndNotification(
      metrics: controller.position,
      context: notificationContext,
    ).dispatch(notificationContext);
    UserScrollNotification(
      metrics: controller.position,
      context: notificationContext,
      direction: ScrollDirection.idle,
    ).dispatch(notificationContext);
    await tester.pump();
    expect(session.activePost.id, 'a');

    session.resumeTrackingAfterCanceledBack();
    await tester.pump();
    await tester.pump();

    expect(session.activePost.id, 'b');

    await disposeDetail(tester);
    session.dispose();
  });

  testWidgets('near-bottom scroll loads once and forwards the exact page', (
    tester,
  ) async {
    useDetailViewport(tester);
    final next = FeedPage(items: [fakePhoto('b')], nextCursor: null);
    var calls = 0;
    final source = FakeTransitionSource();
    final session = fakeTransitionSession(fakePhoto('a'), source: source);

    await tester.pumpWidget(
      detailHost(
        posts: [fakePhoto('a')],
        session: session,
        initialNextCursor: 'cursor-1',
        loader: (_) async {
          calls++;
          return next;
        },
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }

    expect(calls, 1);
    expect(source.pages, [same(next)]);
    expect(session.loadedPosts.map((post) => post.id), ['a', 'b']);
    expect(find.byKey(const ValueKey('post-detail-item-b')), findsOneWidget);

    await disposeDetail(tester);
    session.dispose();
  });

  testWidgets('concurrent pagination consumers join the exact in-flight page', (
    tester,
  ) async {
    useDetailViewport(tester);
    final page = FeedPage(items: [fakePhoto('b')], nextCursor: 'cursor-2');
    final response = Completer<FeedPage>();
    var calls = 0;
    await tester.pumpWidget(
      detailHost(
        posts: [fakePhoto('a')],
        session: fakeTransitionSession(fakePhoto('a')),
        initialNextCursor: 'cursor-1',
        loader: (_) {
          calls++;
          return response.future;
        },
      ),
    );
    final state = tester.state(find.byType(MemberPostDetailScreen)) as dynamic;

    final Future<FeedPage> listRequest = state.debugLoadNextPostPageForTest();
    final Future<FeedPage> videoRequest = state.debugLoadNextPostPageForTest();
    expect(calls, 1);
    expect(identical(listRequest, videoRequest), isTrue);

    response.complete(page);
    expect(await listRequest, same(page));
    expect(await videoRequest, same(page));

    await disposeDetail(tester);
  });

  testWidgets('scroll pagination errors are contained and retain the cursor', (
    tester,
  ) async {
    useDetailViewport(tester);
    var calls = 0;
    final session = fakeTransitionSession(fakePhoto('a'));
    await tester.pumpWidget(
      detailHost(
        posts: [fakePhoto('a')],
        session: session,
        initialNextCursor: 'cursor-1',
        loader: (_) async {
          calls++;
          throw StateError('page failed');
        },
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    final callsAfterScroll = calls;
    expect(callsAfterScroll, greaterThan(0));

    final state = tester.state(find.byType(MemberPostDetailScreen)) as dynamic;
    await expectLater(
      state.debugLoadNextPostPageForTest(),
      throwsA(isA<StateError>()),
    );
    expect(
      calls,
      callsAfterScroll + 1,
      reason: 'the failed page must not clear cursor-1',
    );

    await disposeDetail(tester);
    session.dispose();
  });

  testWidgets('refresh keeps a page appended while its snapshot awaits', (
    tester,
  ) async {
    useDetailViewport(tester);
    final a = fakePhoto('a');
    final b = fakePhoto('b');
    final session = fakeTransitionSession(a);
    final refreshes = <String, Completer<FeedPost?>>{
      'a': Completer<FeedPost?>(),
      'b': Completer<FeedPost?>(),
    };
    final pageResponse = Completer<FeedPage>();
    debugScopedFeedPostFetcher = (id) => refreshes[id]!.future;
    await tester.pumpWidget(
      detailHost(
        posts: [a, b],
        session: session,
        initialNextCursor: 'cursor-1',
        loader: (_) => pageResponse.future,
      ),
    );
    final state = tester.state(find.byType(MemberPostDetailScreen)) as dynamic;

    final Future<void> refresh = state.debugRefreshPostsForTest();
    final Future<FeedPage> pageLoad = state.debugLoadNextPostPageForTest();
    pageResponse.complete(FeedPage(items: [fakePhoto('c')], nextCursor: null));
    await pageLoad;
    await tester.pump();
    refreshes['a']!.complete(fakePhoto('a', caption: 'a-fresh-caption'));
    refreshes['b']!.complete(fakePhoto('b', caption: 'b-fresh-caption'));
    await refresh;
    await tester.pump();
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('post-detail-item-c')), findsOneWidget);
    expect(session.loadedPosts.map((post) => post.id), contains('c'));
    expect(renderedPost(tester, 'c').caption, 'c-caption');

    await disposeDetail(tester);
    session.dispose();
  });

  testWidgets('refresh cannot resurrect a post deleted from its snapshot', (
    tester,
  ) async {
    useDetailViewport(tester);
    final a = fakePhoto('a');
    final b = fakePhoto('b');
    final session = fakeTransitionSession(a);
    final refreshes = <String, Completer<FeedPost?>>{
      'a': Completer<FeedPost?>(),
      'b': Completer<FeedPost?>(),
    };
    debugScopedFeedPostFetcher = (id) => refreshes[id]!.future;
    debugPostDelete = (_) async => true;
    await tester.pumpWidget(detailHost(posts: [a, b], session: session));
    final state = tester.state(find.byType(MemberPostDetailScreen)) as dynamic;

    final Future<void> refresh = state.debugRefreshPostsForTest();
    await deletePost(tester, 'a');
    refreshes['a']!.complete(fakePhoto('a', caption: 'a-fresh-caption'));
    refreshes['b']!.complete(fakePhoto('b', caption: 'b-fresh-caption'));
    await refresh;
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('post-detail-item-a')), findsNothing);
    expect(find.byKey(const ValueKey('post-detail-media-a')), findsNothing);
    expect(find.byKey(const ValueKey('post-detail-item-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('post-detail-media-b')), findsOneWidget);
    expect(renderedPost(tester, 'b').caption, 'b-fresh-caption');

    await disposeDetail(tester);
    session.dispose();
  });

  testWidgets(
    'deleting B advances post/media keys, local list, and invalidation together',
    (tester) async {
      useDetailViewport(tester);
      final posts = [fakePhoto('b'), fakePhoto('c')];
      final source = FakeTransitionSource()..targets['b'] = fakeTarget('b');
      final session = fakeTransitionSession(posts.first, source: source);
      debugPostDelete = (_) async => true;

      await tester.pumpWidget(detailHost(posts: posts, session: session));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }

      final itemB = find.byKey(const ValueKey('post-detail-item-b'));
      final mediaB = find.byKey(const ValueKey('post-detail-media-b'));
      expect(itemB, findsOneWidget);
      expect(mediaB, findsOneWidget);
      expect(session.openingTarget?.postId, 'b');

      // Exact readiness anchors B at y=0, so its owner button intentionally
      // sits behind the transparent header. Invoke the rendered IconButton's
      // real callback, then exercise both modal confirmations normally.
      final menuButton = find.descendant(
        of: itemB,
        matching: find.widgetWithIcon(IconButton, Icons.more_horiz_rounded),
      );
      tester.widget<IconButton>(menuButton).onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final deleteTile = find.ancestor(
        of: find.text('Hapus postingan'),
        matching: find.byType(ListTile),
      );
      tester.widget<ListTile>(deleteTile).onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.widgetWithText(TextButton, 'Hapus'));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }

      expect(find.byKey(const ValueKey('post-detail-item-b')), findsNothing);
      expect(find.byKey(const ValueKey('post-detail-media-b')), findsNothing);
      expect(find.byKey(const ValueKey('post-detail-item-c')), findsOneWidget);
      expect(find.byKey(const ValueKey('post-detail-media-c')), findsOneWidget);
      expect(session.openingTarget, isNull);
      expect(tester.takeException(), isNull);

      await disposeDetail(tester);
      session.dispose();
    },
  );

  testWidgets(
    'destination media suppression hides only the active post media slot',
    (tester) async {
      useDetailViewport(tester);
      final a = fakePhoto('a');
      final b = fakePhoto('b');
      final session = fakeTransitionSession(a);

      await tester.pumpWidget(detailHost(posts: [a, b], session: session));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(mediaOpacity(tester, 'a'), 1);
      expect(mediaOpacity(tester, 'b'), 1);

      session.setDestinationMediaSuppressed(true);
      await tester.pump();

      // Active post (session.activePost.id == 'a') goes fully transparent.
      expect(mediaOpacity(tester, 'a'), 0);
      // Non-active post keeps rendering normally.
      expect(mediaOpacity(tester, 'b'), 1);
      // The suppressed slot's rect stays measurable — the hero geometry
      // resolver still reads its RenderBox while the hero flight is active.
      final box = mediaSlotRenderBox(tester, 'a');
      expect(box.attached, isTrue);
      expect(box.hasSize, isTrue);
      expect(box.size.isEmpty, isFalse);

      session.setDestinationMediaSuppressed(false);
      await tester.pump();

      expect(mediaOpacity(tester, 'a'), 1);
      expect(mediaOpacity(tester, 'b'), 1);

      await disposeDetail(tester);
      session.dispose();
    },
  );
}

Widget detailHost({
  required List<FeedPost> posts,
  int initialIndex = 0,
  required PostDetailTransitionSession session,
  String? initialNextCursor,
  Future<FeedPage> Function(String? cursor)? loader,
}) {
  return MaterialApp(
    home: MemberPostDetailScreen(
      post: posts[initialIndex],
      posts: posts,
      initialIndex: initialIndex,
      transitionSession: session,
      initialNextCursor: initialNextCursor,
      loadMoreScopedPosts: loader,
    ),
  );
}

Rect detailViewportRect(WidgetTester tester) =>
    tester.getRect(find.byType(ListView));

/// Opacity of the dedicated wrapper around a post's `_PostMediaSurface`
/// (keyed distinctly so it can't be confused with unrelated internal
/// `Opacity` widgets a media surface may use for its own purposes, e.g. the
/// pinch-zoom overlay inside `_ImageSurface`).
double mediaOpacity(WidgetTester tester, String postId) => tester
    .widget<Opacity>(find.byKey(ValueKey('post-detail-media-opacity-$postId')))
    .opacity;

/// RenderBox of the mediaKey subtree for a post — same size as the outer
/// `widget.mediaKey` KeyedSubtree, since neither KeyedSubtree nor Opacity
/// alter layout size.
RenderBox mediaSlotRenderBox(WidgetTester tester, String postId) => tester
    .renderObject<RenderBox>(find.byKey(ValueKey('post-detail-media-$postId')));

FeedPost renderedPost(WidgetTester tester, String postId) {
  final item = tester.widget<KeyedSubtree>(
    find.byKey(ValueKey('post-detail-item-$postId')),
  );
  return (item.child as dynamic).post as FeedPost;
}

void useDetailViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> disposeDetail(WidgetTester tester) async {
  // Flush gesture countdowns and AppToast auto-dismiss timers deterministically.
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> deletePost(WidgetTester tester, String postId) async {
  final item = find.byKey(ValueKey('post-detail-item-$postId'));
  final menuButton = find.descendant(
    of: item,
    matching: find.widgetWithIcon(IconButton, Icons.more_horiz_rounded),
  );
  tester.widget<IconButton>(menuButton).onPressed!();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  final deleteTile = find.ancestor(
    of: find.text('Hapus postingan'),
    matching: find.byType(ListTile),
  );
  tester.widget<ListTile>(deleteTile).onTap!();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.widgetWithText(TextButton, 'Hapus'));
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

FeedPost fakePhoto(String id, {String? caption}) => FeedPost.fromJson({
  'id': id,
  'slug': id,
  'kind': 'PHOTO',
  'imageUrl': '',
  'caption': caption ?? '$id-caption',
  'aspectWidth': 9,
  'aspectHeight': 16,
  'author': const {'id': 'author', 'name': 'Author'},
  'likeCount': 0,
  'commentCount': 0,
  'shareCount': 0,
  'createdAt': '2026-07-18T00:00:00.000Z',
});

FeedPost fakeVideo(String id) => FeedPost.fromJson({
  'id': id,
  'slug': id,
  'kind': 'USER_VIDEO',
  'videoUrl': '',
  'thumbnailUrl': '',
  'caption': '$id-caption',
  'aspectWidth': 9,
  'aspectHeight': 16,
  'author': const {'id': 'author', 'name': 'Author'},
  'likeCount': 0,
  'commentCount': 0,
  'shareCount': 0,
  'createdAt': '2026-07-18T00:00:00.000Z',
});

/// HLS URL so `VideoPlayerSession` takes the `VideoPlayerController.networkUrl`
/// branch directly (no `CachedVideoPlayerPlus` wrapper — segments aren't
/// cacheable), matching the fake platform below.
FeedPost fakeHlsVideo(String id) => FeedPost.fromJson({
  'id': id,
  'slug': id,
  'kind': 'USER_VIDEO',
  'videoUrl': 'https://example.com/$id/playlist.m3u8',
  'thumbnailUrl': '',
  'caption': '$id-caption',
  'aspectWidth': 9,
  'aspectHeight': 16,
  'author': const {'id': 'author', 'name': 'Author'},
  'likeCount': 0,
  'commentCount': 0,
  'shareCount': 0,
  'createdAt': '2026-07-18T00:00:00.000Z',
});

/// Minimal fake video platform (trimmed from the same pattern used in
/// `post_page_zoom_route_test.dart`): auto-fires an `initialized` event on
/// `create()` so `VideoPlayerController.initialize()` completes with real
/// `value.isInitialized == true`, without touching a real platform channel.
class _FakeHeroVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _streams = {};
  int _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) => _create();

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) => _create();

  Future<int?> _create() async {
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
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
}

PostDetailTransitionSession fakeTransitionSession(
  FeedPost initialPost, {
  FakeTransitionSource? source,
}) {
  return PostDetailTransitionSession(
    initialPost: initialPost,
    source: source ?? FakeTransitionSource(),
  );
}

PostPageSourceTarget fakeTarget(String postId) => PostPageSourceTarget(
  postId: postId,
  rect: const Rect.fromLTWH(10, 20, 100, 120),
  proxy: PostPageMediaProxy(placeholderColor: const Color(0xFF123456)),
  viewportSize: const Size(400, 800),
  textDirection: TextDirection.ltr,
  layoutGeneration: 1,
);

class FakeTransitionSource implements PostDetailTransitionSourceAdapter {
  @override
  bool mounted = true;

  final Map<String, PostPageSourceTarget> targets = {};
  final List<String> preparedPostIds = [];
  final List<FeedPage> pages = [];

  @override
  void mergePage(FeedPage page) => pages.add(page);

  @override
  Future<PostPageSourceTarget?> prepareTarget(
    FeedPost post, {
    required int generation,
  }) async {
    preparedPostIds.add(post.id);
    return targets[post.id] ?? fakeTarget(post.id);
  }

  @override
  PostPageSourceTarget? resolveTarget(FeedPost post) => targets[post.id];

  @override
  PostPageMediaProxy resolveProxy(FeedPost post) =>
      PostPageMediaProxy(placeholderColor: const Color(0xFF123456));

  @override
  void setPendingReturnPostId(String? postId) {}

  @override
  void setTileSuppressed(String postId, bool suppressed) {}
}
