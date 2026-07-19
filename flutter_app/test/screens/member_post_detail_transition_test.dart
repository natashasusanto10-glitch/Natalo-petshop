import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_detail_transition_session.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';

void main() {
  setUp(() {
    debugPostDelete = null;
  });

  tearDown(() {
    debugPostDelete = null;
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

FeedPost fakePhoto(String id) => FeedPost.fromJson({
  'id': id,
  'slug': id,
  'kind': 'PHOTO',
  'imageUrl': '',
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
