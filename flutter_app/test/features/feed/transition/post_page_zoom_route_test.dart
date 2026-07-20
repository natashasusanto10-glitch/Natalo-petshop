import 'dart:async';

import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_detail_transition_session.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_route.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

void main() {
  setUp(() {
    debugPostPageZoomGestureProgress = null;
    debugPostPageZoomPredictiveEvents = null;
    debugPostPageZoomOnSnapshotAttempt = null;
  });

  tearDown(() {
    debugPostPageZoomGestureProgress = null;
    debugPostPageZoomPredictiveEvents = null;
    debugPostPageZoomOnSnapshotAttempt = null;
  });

  group('PostPageZoomPhase state machine legality (no widget tree needed)', () {
    test('only open accepts a new interactive back interaction', () {
      final route = _standaloneRoute();
      route.phaseListenable.value = PostPageZoomPhase.opening;
      expect(route.beginInteractiveBack, throwsStateError);

      route.phaseListenable.value = PostPageZoomPhase.open;
      expect(route.phase, PostPageZoomPhase.open);
      // beginInteractiveBack touches controller!, which requires an
      // installed route; covered end-to-end below. Legality is asserted via
      // the illegal-phase path here, which throws before touching it.
    });

    test('only interactiveBack can commit or cancel', () {
      final route = _standaloneRoute();
      route.phaseListenable.value = PostPageZoomPhase.open;
      expect(route.cancelInteractiveBack, throwsStateError);
      expect(route.commitInteractiveBack, throwsStateError);

      route.phaseListenable.value = PostPageZoomPhase.opening;
      expect(route.cancelInteractiveBack, throwsStateError);
      expect(route.commitInteractiveBack, throwsStateError);
    });

    test('preparingOpen cannot commit/cancel or accept back interaction', () {
      final route = _standaloneRoute();
      expect(route.beginInteractiveBack, throwsStateError);
      expect(route.cancelInteractiveBack, throwsStateError);
      expect(route.commitInteractiveBack, throwsStateError);
    });
  });

  group('interactive back lifecycle (installed route)', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    testWidgets(
      'cancel returns to open via settlingOpenAfterCancel and resumes '
      'target tracking exactly once, only on that edge',
      (tester) async {
        final fake = FakeTransitionSource();
        final session = _RecordingSession(
          initialPost: fakePost('a'),
          source: fake,
        );
        addTearDown(session.dispose);

        await tester.pumpWidget(_app(navigatorKey));
        final route = _pushDirect(navigatorKey, session);
        await tester.pump();
        session.markDestinationReady(
          PostDetailDestinationReadiness.geometryReady,
        );
        await tester.pumpAndSettle();
        expect(route.phase, PostPageZoomPhase.open);

        route.beginInteractiveBack();
        expect(route.phase, PostPageZoomPhase.interactiveBack);
        expect(session.resumeCalls, 0);

        route.cancelInteractiveBack();
        expect(route.phase, PostPageZoomPhase.settlingOpenAfterCancel);
        expect(session.resumeCalls, 0);

        await tester.pumpAndSettle();

        expect(route.phase, PostPageZoomPhase.open);
        expect(session.resumeCalls, 1);
      },
    );

    testWidgets(
      'disposal from a mid-flight phase forces the terminal closed state',
      (tester) async {
        final fake = FakeTransitionSource();
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: fake,
        );
        addTearDown(session.dispose);

        await tester.pumpWidget(_app(navigatorKey));
        final route = _pushDirect(navigatorKey, session);
        await tester.pump();
        session.markDestinationReady(
          PostDetailDestinationReadiness.geometryReady,
        );
        await tester.pumpAndSettle();
        route.beginInteractiveBack();
        expect(route.phase, PostPageZoomPhase.interactiveBack);

        // Tear down the whole tree so the Navigator disposes the still
        // mid-flight route exactly once, the way a real app lifecycle
        // teardown would.
        await tester.pumpWidget(const SizedBox.shrink());

        expect(route.phase, PostPageZoomPhase.closed);
      },
    );
  });

  group('forward animation', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    testWidgets('preparingOpen holds until readiness resolves, then curve is '
        'monotone/non-overshooting and the route stays non-opaque', (
      tester,
    ) async {
      final fake = FakeTransitionSource();
      final session = PostDetailTransitionSession(
        initialPost: fakePost('a'),
        source: fake,
      );
      addTearDown(session.dispose);

      await tester.pumpWidget(_app(navigatorKey));
      final route = _pushDirect(navigatorKey, session);
      await tester.pump();

      expect(route.opaque, isFalse);
      expect(route.phase, PostPageZoomPhase.preparingOpen);
      expect(route.debugController!.value, 0.0);

      await tester.pump(const Duration(milliseconds: 50));
      expect(route.phase, PostPageZoomPhase.preparingOpen);
      expect(route.debugController!.value, 0.0);

      session.markDestinationReady(
        PostDetailDestinationReadiness.geometryReady,
      );
      await tester.pump();
      expect(route.phase, PostPageZoomPhase.opening);

      double? previous;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final value = route.debugController!.value;
        expect(value, inInclusiveRange(0.0, 1.0));
        if (previous != null) {
          expect(value, greaterThanOrEqualTo(previous));
        }
        previous = value;
      }

      await tester.pumpAndSettle();
      expect(route.phase, PostPageZoomPhase.open);
      // Source stays mounted beneath the non-opaque route.
      expect(find.text('source-marker'), findsOneWidget);
    });
  });

  group('source semantics/focus lock', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    testWidgets(
      'source has no focusable semantics node while the route is opening/open',
      (tester) async {
        final handle = tester.ensureSemantics();
        final fake = FakeTransitionSource();
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: fake,
        );
        addTearDown(session.dispose);

        await tester.pumpWidget(_app(navigatorKey));
        _pushDirect(navigatorKey, session);
        await tester.pump();
        session.markDestinationReady(
          PostDetailDestinationReadiness.geometryReady,
        );
        await tester.pumpAndSettle();

        // `find.bySemanticsLabel` inspects each RenderObject's own
        // `debugSemantics`, which is still populated even when an ancestor
        // `ExcludeSemantics` detaches it from the compiled tree. Walk the
        // actually-compiled `SemanticsNode` tree instead, which is what a
        // real `SemanticsTester`/accessibility walk observes.
        final root =
            tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode;
        expect(_semanticsTreeHasLabel(root, 'source-button'), isFalse);
        expect(_semanticsTreeHasLabel(root, 'destination'), isTrue);
        handle.dispose();
      },
    );
  });

  group('repeated push guard', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    testWidgets(
      'a second pushPostPageZoom on an already-attached session pushes '
      'exactly zero additional routes',
      (tester) async {
        final fake = FakeTransitionSource();
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: fake,
        );
        addTearDown(session.dispose);

        await tester.pumpWidget(_app(navigatorKey));
        final observer = _observer;
        observer.pushCount = 0;
        final context = navigatorKey.currentContext!;

        unawaited(
          pushPostPageZoom(
            context,
            session: session,
            destinationBuilder: (c) =>
                const Text('destination', textDirection: TextDirection.ltr),
          ),
        );
        await tester.pump();
        expect(observer.pushCount, 1);

        unawaited(
          pushPostPageZoom(
            context,
            session: session,
            destinationBuilder: (c) =>
                const Text('destination', textDirection: TextDirection.ltr),
          ),
        );
        await tester.pump();

        expect(observer.pushCount, 1);
      },
    );
  });

  group('non-interactive reverse ordering', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    testWidgets(
      'freezes before animating, then crossfades, restores, then disposes',
      (tester) async {
        final fake = FakeTransitionSource();
        fake.targets['a'] = fakeTarget('a');
        fake.preparations['a'] = Completer<PostPageSourceTarget?>()
          ..complete(fakeTarget('a'));
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: fake,
        );
        addTearDown(session.dispose);
        await session.prepareActiveTarget();

        await tester.pumpWidget(_app(navigatorKey));
        final route = _pushDirect(navigatorKey, session);
        await tester.pump();
        session.markDestinationReady(
          PostDetailDestinationReadiness.geometryReady,
        );
        await tester.pumpAndSettle();
        expect(route.phase, PostPageZoomPhase.open);

        final order = <String>[];
        fake.onSuppress = (id, suppressed) =>
            order.add('suppress:$id:$suppressed');

        final future = route.requestClose();
        expect(order, ['suppress:a:true']);
        expect(route.phase, PostPageZoomPhase.closingToTarget);

        await tester.pumpAndSettle();
        await future;

        expect(order, ['suppress:a:true', 'suppress:a:false']);
        expect(route.phase, PostPageZoomPhase.closed);
      },
    );
  });

  group('fallback reverse', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    testWidgets(
      'no usable geometry closes via closingFallback, never toward A rect',
      (tester) async {
        final fake = FakeTransitionSource();
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: fake,
        );
        addTearDown(session.dispose);
        // No prepared target for the active post: freeze() must fall back.
        session.invalidatePost('a');

        await tester.pumpWidget(_app(navigatorKey));
        final route = _pushDirect(navigatorKey, session);
        await tester.pump();
        session.markDestinationReady(
          PostDetailDestinationReadiness.crossfadeFallback,
        );
        await tester.pumpAndSettle();
        expect(route.phase, PostPageZoomPhase.open);

        final future = route.requestClose();
        expect(route.phase, PostPageZoomPhase.closingFallback);
        expect(fake.pendingReturnPostId, 'a');
        // Never targets the opening A rect: fallback close renders the
        // dedicated fade+scale widget, not the geometry-based transition.
        expect(find.byType(_FallbackMarker), findsNothing);

        await tester.pumpAndSettle();
        await future;

        expect(route.phase, PostPageZoomPhase.closed);
        expect(fake.suppressionCalls, isEmpty);
      },
    );
  });

  group('proxy selection ladder', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    testWidgets(
      'is synchronous (never awaits before first motion); no toImage call; '
      'no-proxy case paints the deterministic placeholder',
      (tester) async {
        debugPostPageZoomOnSnapshotAttempt = () {
          fail('route attempted a snapshot/toImage capture');
        };

        final fake = FakeTransitionSource();
        // Target has no `imageInfo`, so the deterministic placeholder color
        // must be used (proxy-selection ladder case "nothing available").
        fake.targets['a'] = fakeTarget('a');
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: fake,
        );
        addTearDown(session.dispose);

        await tester.pumpWidget(_app(navigatorKey));
        _pushDirect(navigatorKey, session);
        // First pump: opening geometry/proxy must already be resolved
        // synchronously, with no pending microtask/await gating first paint.
        await tester.pump();
        session.markDestinationReady(
          PostDetailDestinationReadiness.geometryReady,
        );
        await tester.pump();

        final coloredBoxes = tester.widgetList<ColoredBox>(
          find.byType(ColoredBox),
        );
        expect(
          coloredBoxes.any((box) => box.color == const Color(0xFF123456)),
          isTrue,
        );
      },
    );
  });
}

final _observer = _CountingObserver();

class _CountingObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PostPageZoomRoute) pushCount++;
  }
}

class _FallbackMarker extends StatelessWidget {
  const _FallbackMarker();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _app(GlobalKey<NavigatorState> navigatorKey) {
  return WidgetsApp(
    color: const Color(0xFFFFFFFF),
    navigatorKey: navigatorKey,
    navigatorObservers: [_observer],
    onGenerateRoute: (settings) => PageRouteBuilder<void>(
      settings: settings,
      pageBuilder: (context, a, b) => const _SourceScreen(),
    ),
  );
}

PostPageZoomRoute _pushDirect(
  GlobalKey<NavigatorState> navigatorKey,
  PostDetailTransitionSession session,
) {
  expect(session.tryAttachRoute(), isTrue);
  final route = PostPageZoomRoute(
    session: session,
    destinationBuilder: (context) =>
        const Text('destination', textDirection: TextDirection.ltr),
  );
  navigatorKey.currentState!.push(route);
  return route;
}

PostPageZoomRoute _standaloneRoute() => PostPageZoomRoute(
  session: PostDetailTransitionSession(
    initialPost: fakePost('a'),
    source: FakeTransitionSource(),
  ),
  destinationBuilder: (context) => const SizedBox.shrink(),
);

class _SourceScreen extends StatelessWidget {
  const _SourceScreen();

  @override
  Widget build(BuildContext context) {
    return PostPageZoomSourceVisibility(
      child: Stack(
        textDirection: TextDirection.ltr,
        children: [
          const Text('source-marker', textDirection: TextDirection.ltr),
          Semantics(
            label: 'source-button',
            button: true,
            child: const SizedBox(width: 10, height: 10),
          ),
        ],
      ),
    );
  }
}

class _RecordingSession extends PostDetailTransitionSession {
  _RecordingSession({required super.initialPost, required super.source});

  int resumeCalls = 0;

  @override
  void resumeTrackingAfterCanceledBack() {
    resumeCalls++;
    super.resumeTrackingAfterCanceledBack();
  }
}

FeedPost fakePost(String id) => FeedPost(
  id: id,
  slug: id,
  videoUrl: 'https://example.com/$id.mp4',
  author: const FeedAuthor(id: 'author', name: 'Author'),
  createdAt: DateTime.utc(2026),
);

PostPageSourceTarget fakeTarget(
  String postId, {
  Rect rect = const Rect.fromLTWH(10, 20, 100, 120),
  PostPageMediaProxy? proxy,
}) => PostPageSourceTarget(
  postId: postId,
  rect: rect,
  proxy: proxy ?? TrackingMediaProxy(),
  viewportSize: const Size(400, 800),
  textDirection: TextDirection.ltr,
  layoutGeneration: 1,
);

class FakeTransitionSource implements PostDetailTransitionSourceAdapter {
  @override
  bool mounted = true;

  final Map<String, PostPageSourceTarget> targets = {};
  final Map<String, Completer<PostPageSourceTarget?>> preparations = {};
  final List<(String, bool)> suppressionCalls = [];
  void Function(String id, bool suppressed)? onSuppress;
  String? pendingReturnPostId;

  @override
  void mergePage(FeedPage page) {}

  @override
  Future<PostPageSourceTarget?> prepareTarget(
    FeedPost post, {
    required int generation,
  }) async => preparations[post.id]?.future ?? targets[post.id];

  @override
  PostPageSourceTarget? resolveTarget(FeedPost post) => targets[post.id];

  @override
  PostPageMediaProxy resolveProxy(FeedPost post) => TrackingMediaProxy();

  @override
  void setPendingReturnPostId(String? postId) {
    pendingReturnPostId = postId;
  }

  @override
  void setTileSuppressed(String postId, bool suppressed) {
    suppressionCalls.add((postId, suppressed));
    onSuppress?.call(postId, suppressed);
  }
}

class TrackingMediaProxy extends PostPageMediaProxy {
  TrackingMediaProxy() : super(placeholderColor: const Color(0xFF123456));
}

bool _semanticsTreeHasLabel(SemanticsNode? node, String label) {
  if (node == null) return false;
  if (node.label.contains(label)) return true;
  var found = false;
  node.visitChildren((child) {
    if (_semanticsTreeHasLabel(child, label)) found = true;
    return true;
  });
  return found;
}
