import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_detail_transition_session.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_back_gesture.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_route.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_transition.dart';
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
        final order = <String>[];
        final session = _OrderRecordingSession(
          initialPost: fakePost('a'),
          source: fake,
          order: order,
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

        fake.onSuppress = (id, suppressed) =>
            order.add('suppress:$id:$suppressed');

        final future = route.requestClose();
        // Freeze happens BEFORE the reverse animation's suppress/restore
        // events — asserted here as actual recorded ordering, not merely by
        // reading the source.
        expect(order, ['freeze', 'suppress:a:true']);
        expect(route.phase, PostPageZoomPhase.closingToTarget);

        await tester.pumpAndSettle();
        await future;

        expect(order, ['freeze', 'suppress:a:true', 'suppress:a:false']);
        expect(route.phase, PostPageZoomPhase.closed);
      },
    );
  });

  group('dispose race during a pending close', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    testWidgets(
      'route disposal while _performClose is still awaiting its reverse '
      'animation does not surface an exception, and ends closed',
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

        // Start the non-interactive close, but don't let its reverse
        // animation finish before disposing the route out from under it.
        var closeCompleted = false;
        final future = route.requestClose()..then((_) => closeCompleted = true);
        expect(route.phase, PostPageZoomPhase.closingToTarget);
        // The first pump after `animateTo` starts is only the ticker's
        // anchor tick (elapsed == 0); a second pump is needed to observe
        // real mid-flight progress.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(route.debugController!.value, greaterThan(0.0));
        expect(route.debugController!.value, lessThan(1.0));

        // Force-remove (and thus dispose) the route while its reverse
        // animation is still in flight, exactly like an app-level teardown
        // interrupting a normal back navigation.
        navigatorKey.currentState!.removeRoute(route);
        await tester.pump();
        expect(route.phase, PostPageZoomPhase.closed);

        // Let the still-pending `_performClose` continuation run its course.
        // Bounded pump loop (not `pumpAndSettle`, and no real-time
        // `Future.timeout` — timers inside the FakeAsync test zone only
        // fire on a `pump`, so a real-time timeout would never trigger here
        // either): if the continuation is truly hung, this loop ends
        // without `closeCompleted` ever flipping, and the assertion below
        // fails cleanly instead of the whole suite hanging.
        for (var i = 0; i < 20 && !closeCompleted; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(closeCompleted, isTrue);
        await future;

        expect(tester.takeException(), isNull);
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
        await tester.pump();
        // Never targets the opening A rect: fallback close never builds the
        // geometry-based transition surface at all (structurally incapable
        // of animating toward any tile rect, opening or otherwise) and
        // instead renders the dedicated fade+scale fallback widget.
        expect(find.byType(PostPageZoomTransition), findsNothing);
        expect(_findsFallbackCloseTransition(), findsOneWidget);

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

        // Ladder case (c) — "nothing": the registered target's proxy has no
        // `imageInfo` (no retained frame, no memory-cached provider), so no
        // `Image` widget is built at all and the deterministic placeholder
        // color is painted via a plain `ColoredBox`.
        expect(find.byType(Image), findsNothing);
        final coloredBoxes = tester.widgetList<ColoredBox>(
          find.byType(ColoredBox),
        );
        expect(
          coloredBoxes.any((box) => box.color == const Color(0xFF123456)),
          isTrue,
        );
      },
    );

    testWidgets(
      'no opening target at all still paints a deterministic placeholder, '
      'never blocking on the missing-target edge',
      (tester) async {
        // No target registered for 'a' at all (deferred item — see
        // task-8-report.md "no-opening-target proxy source" note:
        // `PostDetailTransitionSession` has no public accessor for its
        // private `_openingFallbackProxy`/`_resolveFallbackProxy`, so this
        // route cannot reach the session's own resolved fallback color for
        // this specific edge; it uses its own hardcoded placeholder
        // instead). This test only proves the route stays synchronous and
        // still paints a deterministic color rather than throwing/hanging.
        debugPostPageZoomOnSnapshotAttempt = () {
          fail('route attempted a snapshot/toImage capture');
        };
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
        await tester.pump();

        expect(find.byType(Image), findsNothing);
        final coloredBoxes = tester.widgetList<ColoredBox>(
          find.byType(ColoredBox),
        );
        expect(
          coloredBoxes.any((box) => box.color == const Color(0xFF000000)),
          isTrue,
        );
      },
    );
  });

  group('iOS interactive edge back', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    // The foundation-debug-var invariant check runs at the END of the test
    // body (before any tearDown/addTearDown callback), so a platform override
    // must be reset in-body. Method-driven tests don't need it at all: the
    // default flutter-test platform is Android and the route's public gesture
    // entry points bypass the leading-edge recognizer entirely.

    testWidgets(
      'leading-edge recognizer is absent on Android',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final route = await _openInteractive(tester, navigatorKey);
        expect(find.byKey(postPageBackGestureEdgeKey), findsNothing);
        expect(route.phase, PostPageZoomPhase.open);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'leading-edge recognizer is installed on iOS',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        await _openInteractive(tester, navigatorKey);
        expect(find.byKey(postPageBackGestureEdgeKey), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'gesture is accepted only from phase open (freeze once at first '
      'progress; later reportActivePost/reportLoadedPage do not retarget)',
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

        final route = await _openInteractiveWith(tester, navigatorKey, session);

        // Cannot begin from a non-open phase.
        route.beginInteractiveBack();
        expect(route.phase, PostPageZoomPhase.interactiveBack);
        expect(session.isFrozen, isTrue);
        expect(route.beginInteractiveBack, throwsStateError);

        route.updateInteractiveBack(0.2);
        final frameBefore = route.debugCurrentBackFrame;
        expect(frameBefore, isNotNull);

        final before = session.loadedPosts.length;
        // Pages still merge while frozen, but must not retarget.
        session.reportLoadedPage(
          FeedPage(items: [fakePost('a'), fakePost('b'), fakePost('c')]),
        );
        session.reportActivePost(fakePost('b'));
        expect(session.loadedPosts.length, greaterThan(before));
        expect(session.isFrozen, isTrue);
        expect(route.debugCurrentBackFrame, frameBefore);

        route.cancelInteractiveBack();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('preview progress is LINEAR (no easing): scale/radius/'
        'translation follow injected progress exactly', (tester) async {
      const viewport = Rect.fromLTWH(0, 0, 800, 600);
      final zero = resolvePostPageBackPreview(
        viewportRect: viewport,
        progress: 0,
      );
      expect(zero.rect, viewport);
      expect(zero.radius, 0);

      final half = resolvePostPageBackPreview(
        viewportRect: viewport,
        progress: 0.5,
      );
      // Radius is exactly half of the full-extent value (linear).
      expect(half.radius, closeTo(kPostPageBackPreviewCornerRadius / 2, 1e-9));
      // Scale is exactly the midpoint between 1.0 and the preview minimum.
      const expectedScale = (1.0 + kPostPageBackPreviewMinScale) / 2;
      expect(half.rect.width, closeTo(viewport.width * expectedScale, 1e-6));
      // Horizontal translation follows progress exactly.
      expect(
        half.rect.center.dx,
        closeTo(
          viewport.center.dx +
              0.5 * viewport.width * kPostPageBackPreviewTranslateFraction,
          1e-6,
        ),
      );

      final full = resolvePostPageBackPreview(
        viewportRect: viewport,
        progress: 1,
      );
      expect(full.radius, kPostPageBackPreviewCornerRadius);
      expect(
        full.rect.width,
        closeTo(viewport.width * kPostPageBackPreviewMinScale, 1e-6),
      );
    });

    testWidgets(
      'cancel below threshold springs from the EXACT current transform back '
      'to fullscreen (no restart), settlingOpenAfterCancel -> open, then '
      'resumes tracking',
      (tester) async {
        final session = _RecordingSession(
          initialPost: fakePost('a'),
          source: FakeTransitionSource(),
        );
        addTearDown(session.dispose);
        final route = await _openInteractiveWith(tester, navigatorKey, session);

        route.beginInteractiveBack();
        route.updateInteractiveBack(0.2);
        final atRelease = route.debugCurrentBackFrame;

        expect(session.resumeCalls, 0);
        route.endInteractiveBack(0); // progress .2 < .25, velocity 0 -> cancel
        expect(route.phase, PostPageZoomPhase.settlingOpenAfterCancel);
        // First frame of the settle equals the released transform (no restart).
        expect(route.debugCurrentBackFrame, atRelease);
        expect(session.resumeCalls, 0);

        await tester.pumpAndSettle();
        expect(route.phase, PostPageZoomPhase.open);
        expect(route.debugBackPreviewProgress, 0);
        expect(session.resumeCalls, 1);
      },
    );

    testWidgets(
      'commit at >= .25 continues from the EXACT current transform to B over '
      '180-240 ms; phase closingToTarget',
      (tester) async {
        expect(
          kPostPageBackCommitDuration.inMilliseconds,
          inInclusiveRange(180, 240),
        );
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

        final route = await _openInteractiveWith(tester, navigatorKey, session);
        route.beginInteractiveBack();
        route.updateInteractiveBack(0.3);
        final atRelease = route.debugCurrentBackFrame;

        final future = route.endInteractiveBack(0); // .3 >= .25 -> commit
        expect(route.phase, PostPageZoomPhase.closingToTarget);
        // First frame equals the released transform (no restart).
        expect(route.debugCurrentBackFrame, atRelease);

        await tester.pumpAndSettle();
        await future;
        expect(route.phase, PostPageZoomPhase.closed);
      },
    );

    testWidgets('a fling >= 800 px/s commits even below the progress threshold',
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

      final route = await _openInteractiveWith(tester, navigatorKey, session);
      route.beginInteractiveBack();
      route.updateInteractiveBack(0.1); // below progress threshold
      final future = route.endInteractiveBack(900); // fling -> commit
      expect(route.phase, PostPageZoomPhase.closingToTarget);
      await tester.pumpAndSettle();
      await future;
      expect(route.phase, PostPageZoomPhase.closed);
    });

    testWidgets(
      'B tile is NOT suppressed during preview and only suppressed in the '
      'terminal portion of the commit, restored at completion',
      (tester) async {
        final fake = FakeTransitionSource();
        fake.targets['a'] = fakeTarget('a');
        fake.preparations['a'] = Completer<PostPageSourceTarget?>()
          ..complete(fakeTarget('a'));
        final order = <String>[];
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: fake,
        );
        addTearDown(session.dispose);
        await session.prepareActiveTarget();

        final route = await _openInteractiveWith(tester, navigatorKey, session);
        fake.onSuppress = (id, s) => order.add('suppress:$id:$s');

        route.beginInteractiveBack();
        route.updateInteractiveBack(0.3);
        // No suppression during the preview.
        expect(order, isEmpty);

        final future = route.endInteractiveBack(0);
        await tester.pumpAndSettle();
        await future;
        // Suppress then restore, in that order, during the terminal portion.
        expect(order, ['suppress:a:true', 'suppress:a:false']);
      },
    );

    testWidgets('no haptic channel call across a full drag+commit and '
        'drag+cancel', (tester) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method.startsWith('HapticFeedback')) {
            haptics.add(call.method);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

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

      final route = await _openInteractiveWith(tester, navigatorKey, session);
      // Drag + cancel.
      route.beginInteractiveBack();
      route.updateInteractiveBack(0.1);
      route.endInteractiveBack(0);
      await tester.pumpAndSettle();
      expect(route.phase, PostPageZoomPhase.open);
      // Drag + commit.
      route.beginInteractiveBack();
      route.updateInteractiveBack(0.4);
      final future = route.endInteractiveBack(0);
      await tester.pumpAndSettle();
      await future;
      expect(haptics, isEmpty);
    });

    testWidgets(
      'seam-driven progress begins the gesture and updates the preview; '
      'lifecycle interruption cancels back to open',
      (tester) async {
        // Arm the gesture-progress seam so the route publishes its driver.
        debugPostPageZoomGestureProgress = (_, __) {};
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: FakeTransitionSource(),
        );
        addTearDown(session.dispose);
        final route = await _openInteractiveWith(tester, navigatorKey, session);

        // A single seam call at `open` begins the gesture and updates.
        debugPostPageZoomGestureProgress!(0.15, 0);
        expect(route.phase, PostPageZoomPhase.interactiveBack);
        expect(route.debugBackPreviewProgress, closeTo(0.15, 1e-9));

        // Backgrounding mid-gesture cancels back to fullscreen open.
        route.debugHandleInterruption();
        expect(route.phase, PostPageZoomPhase.settlingOpenAfterCancel);
        await tester.pumpAndSettle();
        expect(route.phase, PostPageZoomPhase.open);
        expect(session.playbackAllowed, isFalse);
      },
    );

    testWidgets('a real leading-edge drag on iOS drives an interactive back',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final session = PostDetailTransitionSession(
        initialPost: fakePost('a'),
        source: FakeTransitionSource(),
      );
      addTearDown(session.dispose);
      final route = await _openInteractiveWith(tester, navigatorKey, session);

      final gesture = await tester.startGesture(const Offset(5, 300));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(route.phase, PostPageZoomPhase.interactiveBack);
      expect(route.debugBackPreviewProgress, greaterThan(0));
      await gesture.up();
      await tester.pumpAndSettle();
      // 60px drag on an 800px viewport is well below the 25% threshold -> cancel.
      expect(route.phase, PostPageZoomPhase.open);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Android Predictive Back', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    testWidgets(
      'no predictive-back handler participates on iOS; the iOS recognizer '
      'participates instead',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final route = await _openInteractive(tester, navigatorKey);
        expect(route.debugPredictiveBackParticipating, isFalse);
        expect(find.byKey(postPageBackGestureEdgeKey), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'the route participates in predictive back on Android and installs no '
      'iOS leading-edge recognizer',
      (tester) async {
        // Default flutter-test platform is Android.
        final route = await _openInteractive(tester, navigatorKey);
        expect(route.debugPredictiveBackParticipating, isTrue);
        expect(find.byKey(postPageBackGestureEdgeKey), findsNothing);
      },
    );

    testWidgets(
      'system predictive progress from the LEFT edge drives the same surface '
      'and state machine (interactiveBack), translating toward the trailing '
      'side',
      (tester) async {
        debugPostPageZoomPredictiveEvents = (kind, {progress, edge}) {};
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: FakeTransitionSource(),
        );
        addTearDown(session.dispose);
        final route = await _openInteractiveWith(tester, navigatorKey, session);

        debugPostPageZoomPredictiveEvents!(
          PostPageZoomPredictiveEventKind.start,
          progress: 0.2,
          edge: SwipeEdge.left,
        );
        expect(route.phase, PostPageZoomPhase.interactiveBack);
        expect(route.debugBackPreviewProgress, closeTo(0.2, 1e-9));
        // Left edge (not mirrored): surface center moves toward the trailing
        // (right) side of the 800px viewport.
        expect(route.debugCurrentBackFrame!.rect.center.dx, greaterThan(400));

        route.cancelInteractiveBack();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'RIGHT-edge predictive progress is respected (mirrored translation)',
      (tester) async {
        debugPostPageZoomPredictiveEvents = (kind, {progress, edge}) {};
        final session = PostDetailTransitionSession(
          initialPost: fakePost('a'),
          source: FakeTransitionSource(),
        );
        addTearDown(session.dispose);
        final route = await _openInteractiveWith(tester, navigatorKey, session);

        debugPostPageZoomPredictiveEvents!(
          PostPageZoomPredictiveEventKind.start,
          progress: 0.2,
          edge: SwipeEdge.right,
        );
        expect(route.phase, PostPageZoomPhase.interactiveBack);
        // Right edge: translation is mirrored, surface center moves toward the
        // leading (left) side.
        expect(route.debugCurrentBackFrame!.rect.center.dx, lessThan(400));

        route.cancelInteractiveBack();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'system cancellation follows the exact current transform back to '
      'fullscreen (no restart), settling open and resuming tracking once',
      (tester) async {
        debugPostPageZoomPredictiveEvents = (kind, {progress, edge}) {};
        final session = _RecordingSession(
          initialPost: fakePost('a'),
          source: FakeTransitionSource(),
        );
        addTearDown(session.dispose);
        final route = await _openInteractiveWith(tester, navigatorKey, session);

        debugPostPageZoomPredictiveEvents!(
          PostPageZoomPredictiveEventKind.start,
          progress: 0.2,
        );
        debugPostPageZoomPredictiveEvents!(
          PostPageZoomPredictiveEventKind.progress,
          progress: 0.18,
        );
        final atRelease = route.debugCurrentBackFrame;

        expect(session.resumeCalls, 0);
        debugPostPageZoomPredictiveEvents!(
          PostPageZoomPredictiveEventKind.cancel,
        );
        expect(route.phase, PostPageZoomPhase.settlingOpenAfterCancel);
        // First frame of the settle equals the released transform (no restart).
        expect(route.debugCurrentBackFrame, atRelease);

        await tester.pumpAndSettle();
        expect(route.phase, PostPageZoomPhase.open);
        expect(route.debugBackPreviewProgress, 0);
        expect(session.resumeCalls, 1);
      },
    );

    testWidgets(
      'system commit continues from the exact current transform to frozen B '
      'without geometry restart, ending closed',
      (tester) async {
        debugPostPageZoomPredictiveEvents = (kind, {progress, edge}) {};
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

        final route = await _openInteractiveWith(tester, navigatorKey, session);

        debugPostPageZoomPredictiveEvents!(
          PostPageZoomPredictiveEventKind.start,
          progress: 0.3,
        );
        final atRelease = route.debugCurrentBackFrame;

        debugPostPageZoomPredictiveEvents!(
          PostPageZoomPredictiveEventKind.commit,
        );
        expect(route.phase, PostPageZoomPhase.closingToTarget);
        // First frame equals the released transform (no restart).
        expect(route.debugCurrentBackFrame, atRelease);

        await tester.pumpAndSettle();
        expect(route.phase, PostPageZoomPhase.closed);
      },
    );

    testWidgets(
      'predictive-unavailable system back (3-button) runs the Task-8 '
      'NON-INTERACTIVE reverse, never the interactive preview',
      (tester) async {
        // No predictive seam armed: on Android the route installs the real
        // predictive observer, but a plain system back arrives via maybePop
        // (not a predictive gesture) and must run the non-interactive reverse.
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

        final route = await _openInteractiveWith(tester, navigatorKey, session);
        expect(route.phase, PostPageZoomPhase.open);

        await tester.binding.handlePopRoute();
        await tester.pump();
        // Non-interactive reverse (closingToTarget), NOT interactiveBack.
        expect(route.phase, PostPageZoomPhase.closingToTarget);
        expect(route.debugBackPreviewProgress, isNull);

        await tester.pumpAndSettle();
        expect(route.phase, PostPageZoomPhase.closed);
      },
    );

    testWidgets(
      'a modal route above Postingan owns the first back; the zoom route '
      'defers (popDisposition != doNotPop while not topmost) and never moves',
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

        final route = await _openInteractiveWith(tester, navigatorKey, session);
        expect(route.phase, PostPageZoomPhase.open);

        // Push a modal route on top of the zoom route.
        navigatorKey.currentState!.push(
          PageRouteBuilder<void>(
            settings: const RouteSettings(name: 'modal-above'),
            pageBuilder: (context, a, b) =>
                const Text('modal', textDirection: TextDirection.ltr),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('modal'), findsOneWidget);
        expect(route.isCurrent, isFalse);
        // While not topmost, the zoom route defers its pop disposition.
        expect(route.popDisposition, isNot(RoutePopDisposition.doNotPop));

        // The first back pops the modal, not the zoom route.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('modal'), findsNothing);
        // The zoom route did not observe/animate the back: still open, and its
        // interactive preview never started.
        expect(route.phase, PostPageZoomPhase.open);
        expect(route.debugBackPreviewProgress, isNull);
      },
    );
  });
}

/// Opens the route and settles to `open` using the ambient platform override.
Future<PostPageZoomRoute> _openInteractive(
  WidgetTester tester,
  GlobalKey<NavigatorState> navigatorKey,
) async {
  final session = PostDetailTransitionSession(
    initialPost: fakePost('a'),
    source: FakeTransitionSource(),
  );
  addTearDown(session.dispose);
  return _openInteractiveWith(tester, navigatorKey, session);
}

Future<PostPageZoomRoute> _openInteractiveWith(
  WidgetTester tester,
  GlobalKey<NavigatorState> navigatorKey,
  PostDetailTransitionSession session,
) async {
  await tester.pumpWidget(_app(navigatorKey));
  final route = _pushDirect(navigatorKey, session);
  await tester.pump();
  session.markDestinationReady(PostDetailDestinationReadiness.geometryReady);
  await tester.pumpAndSettle();
  expect(route.phase, PostPageZoomPhase.open);
  return route;
}

final _observer = _CountingObserver();

class _CountingObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PostPageZoomRoute) pushCount++;
  }
}

/// `_FallbackCloseTransition` is private to `post_page_zoom_route.dart` (a
/// different library), so it cannot be referenced by type here. Match on its
/// `runtimeType` string instead, which still proves the fallback-specific
/// widget (not [PostPageZoomTransition]) is what actually got built.
Finder _findsFallbackCloseTransition() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_FallbackCloseTransition',
);

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

class _OrderRecordingSession extends PostDetailTransitionSession {
  _OrderRecordingSession({
    required super.initialPost,
    required super.source,
    required this.order,
  });

  final List<String> order;

  @override
  PostPageFrozenTarget freeze() {
    order.add('freeze');
    return super.freeze();
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
