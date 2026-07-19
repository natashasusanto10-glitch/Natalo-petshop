import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_detail_transition_session.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  setUp(() {
    debugPostDelete = null;
    debugScopedFeedPostFetcher = null;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDown(() {
    debugPostDelete = null;
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
    final posts = List.generate(5, (index) => fakePhoto('post-$index'));
    final session = fakeTransitionSession(posts[3]);

    await tester.pumpWidget(
      detailHost(posts: posts, initialIndex: 3, session: session),
    );
    expect(
      session.destinationReadiness,
      PostDetailDestinationReadiness.preparing,
    );

    await tester.pump(const Duration(milliseconds: 80));

    expect(
      session.destinationReadiness,
      PostDetailDestinationReadiness.crossfadeFallback,
    );

    await disposeDetail(tester);
    session.dispose();
  });

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
    final controller = tester.widget<ListView>(find.byType(ListView)).controller!;
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
