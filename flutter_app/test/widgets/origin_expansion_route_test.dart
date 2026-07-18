import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/origin_expansion_route.dart';

void main() {
  testWidgets('snapshot sources suppress their Hero without disabling siblings',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              OriginSnapshotSource(
                child: Hero(
                  tag: 'post-thumb-photo-1',
                  child: Container(
                    key: const ValueKey('origin-hero'),
                    width: 40,
                    height: 40,
                    color: Colors.red,
                  ),
                ),
              ),
              Hero(
                tag: 'later-fullscreen-photo-1',
                child: Container(
                  key: const ValueKey('later-hero'),
                  width: 40,
                  height: 40,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final sourceMode = tester.widget<HeroMode>(
      find.ancestor(
        of: find.byKey(const ValueKey('origin-hero')),
        matching: find.byType(HeroMode),
      ),
    );
    expect(sourceMode.enabled, isFalse);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('later-hero')),
        matching: find.byType(HeroMode),
      ),
      findsNothing,
    );
  });

  testWidgets('shows a captured static snapshot when the source is a boundary',
      (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(_buildSource(key));

    unawaited(
      pushOriginExpansion<void>(
        tester.element(find.byKey(const ValueKey('route-context'))),
        originKey: key,
        snapshotImageUrl: 'https://example.com/never-fetched.jpg',
        destinationBuilder: (_) => const Placeholder(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsOneWidget,
    );
    expect(find.byType(RawImage), findsOneWidget);
    final firstImage = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(firstImage, isNotNull);

    await tester.pump(const Duration(milliseconds: 40));

    expect(
      tester.widget<RawImage>(find.byType(RawImage)).image,
      same(firstImage),
    );
  });

  testWidgets('uses a reversible fade when the source boundary is unavailable',
      (
    tester,
  ) async {
    await tester.pumpWidget(_buildSource(GlobalKey()));

    unawaited(
      pushOriginExpansion<void>(
        tester.element(find.byKey(const ValueKey('route-context'))),
        originKey: GlobalKey(),
        destinationBuilder: (_) => const Text('Composer'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Composer'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('origin-expansion-fade')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 300));
    Navigator.of(tester.element(find.byKey(const ValueKey('route-context'))))
        .pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));

    expect(
      find.byKey(const ValueKey('origin-expansion-fade')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('origin-expansion-fade')),
          )
          .opacity,
      lessThan(1),
    );
  });

  testWidgets('owns only one animation status listener and releases it',
      (tester) async {
    final animation = _TrackingAnimation(
      value: 0.8,
      status: AnimationStatus.forward,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OriginExpansionTransition(
          animation: animation,
          origin: null,
          snapshot: null,
          snapshotFallbackColor: Colors.white,
          child: const Text('Destination'),
        ),
      ),
    );

    expect(animation.statusListenerCount, 1);
    expect(find.byType(Opacity), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(animation.statusListenerCount, 0);
    expect(animation.listenerCount, 0);
  });

  testWidgets('transparent route retains Material route semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_buildSource(GlobalKey()));

    unawaited(
      pushOriginExpansion<void>(
        tester.element(find.byKey(const ValueKey('route-context'))),
        originKey: GlobalKey(),
        destinationBuilder: (_) => const Text('Scoped destination'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey('origin-expansion-route-semantics'),
              skipOffstage: false,
            ),
          )
          .properties
          .scopesRoute,
      isTrue,
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey('origin-expansion-route-semantics'),
              skipOffstage: false,
            ),
          )
          .explicitChildNodes,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('edge swipe follows drag and springs back below 25 percent',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(_buildSource(key));
    await _openSnapshotRoute(tester, key);

    final route = ModalRoute.of(tester.element(find.text('Destination')))!;

    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(
      const Offset(20, 0),
      timeStamp: const Duration(milliseconds: 100),
    );
    await gesture.moveBy(
      const Offset(60, 0),
      timeStamp: const Duration(milliseconds: 500),
    );
    await tester.pump();

    expect(
      Navigator.of(tester.element(find.text('Destination')))
          .userGestureInProgress,
      isTrue,
    );
    // The route follows the finger: its view animation drops below the
    // fully-open value of 1.0 as the edge gesture drives it back.
    expect(route.animation!.value, lessThan(1));

    await gesture.up(timeStamp: const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Destination'), findsOneWidget);

    await tester.pumpAndSettle();
    // Released below the 25% completion fraction (and under the fling
    // velocity), so the route springs back to fully open rather than popping:
    // the destination stays mounted, the user gesture ends, and the view
    // animation settles back to the fully-open value of 1.0.
    expect(find.text('Destination'), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.text('Destination')))
          .userGestureInProgress,
      isFalse,
    );
    expect(route.animation!.value, 1.0);
  });

  testWidgets('edge swipe pops at 25 percent width', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final observer = _GestureObserver();
    await tester.pumpWidget(_buildSource(key, navigatorObservers: [observer]));
    await _openSnapshotRoute(tester, key);

    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(
      const Offset(20, 0),
      timeStamp: const Duration(milliseconds: 100),
    );
    await gesture.moveBy(
      const Offset(110, 0),
      timeStamp: const Duration(milliseconds: 600),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 700));

    expect(
      Navigator.of(tester.element(find.byKey(const ValueKey('route-context'))))
          .userGestureInProgress,
      isTrue,
    );
    expect(observer.starts, 1);
    expect(observer.stops, 0);
    await tester.pump(const Duration(milliseconds: 110));
    expect(observer.stops, 0);
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsNothing);
    expect(
      Navigator.of(tester.element(find.byKey(const ValueKey('route-context'))))
          .userGestureInProgress,
      isFalse,
    );
    expect(observer.stops, 1);
  });

  testWidgets('interrupted cancellation stops once without restoring dismissal',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final observer = _GestureObserver();
    final statuses = <AnimationStatus>[];
    debugOriginExpansionStatusObserver = (status, _) => statuses.add(status);
    addTearDown(() => debugOriginExpansionStatusObserver = null);
    await tester.pumpWidget(_buildSource(key, navigatorObservers: [observer]));
    await _openSnapshotRoute(tester, key);
    statuses.clear();

    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(
      const Offset(20, 0),
      timeStamp: const Duration(milliseconds: 100),
    );
    await gesture.moveBy(
      const Offset(60, 0),
      timeStamp: const Duration(milliseconds: 500),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 600));
    await tester.pump();

    Navigator.of(tester.element(find.text('Destination'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsNothing);
    expect(
      Navigator.of(tester.element(find.byKey(const ValueKey('route-context'))))
          .userGestureInProgress,
      isFalse,
    );
    expect(observer.starts, 1);
    expect(observer.stops, 1);
    final dismissedIndex = statuses.lastIndexOf(AnimationStatus.dismissed);
    expect(dismissedIndex, isNonNegative);
    expect(
      statuses.skip(dismissedIndex + 1),
      isNot(contains(AnimationStatus.completed)),
    );
  });

  testWidgets('removing a route during spring cleanup stops the gesture once',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final observer = _GestureObserver();
    await tester.pumpWidget(_buildSource(key, navigatorObservers: [observer]));
    await _openSnapshotRoute(tester, key);

    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(
      const Offset(20, 0),
      timeStamp: const Duration(milliseconds: 100),
    );
    await gesture.moveBy(
      const Offset(60, 0),
      timeStamp: const Duration(milliseconds: 500),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 600));
    await tester.pump();

    final route = ModalRoute.of(tester.element(find.text('Destination')))!;
    Navigator.of(tester.element(find.text('Destination'))).removeRoute(route);
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsNothing);
    expect(observer.starts, 1);
    expect(observer.stops, 1);
    expect(
      Navigator.of(tester.element(find.byKey(const ValueKey('route-context'))))
          .userGestureInProgress,
      isFalse,
    );
  });

  testWidgets('drag end aborts when the route was removed during the drag',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final observer = _GestureObserver();
    final statuses = <AnimationStatus>[];
    debugOriginExpansionStatusObserver = (status, _) => statuses.add(status);
    addTearDown(() => debugOriginExpansionStatusObserver = null);
    await tester.pumpWidget(_buildSource(key, navigatorObservers: [observer]));
    await _openSnapshotRoute(tester, key);
    statuses.clear();

    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(
      const Offset(20, 0),
      timeStamp: const Duration(milliseconds: 100),
    );
    await gesture.moveBy(
      const Offset(60, 0),
      timeStamp: const Duration(milliseconds: 500),
    );

    final navigator = Navigator.of(
      tester.element(find.text('Destination')),
    );
    final route = ModalRoute.of(tester.element(find.text('Destination')))!;
    navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => const Text('Covering route')),
    );
    await tester.pump();
    navigator.removeRoute(route);
    await gesture.up(timeStamp: const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsNothing);
    expect(find.text('Covering route'), findsOneWidget);
    expect(observer.starts, 1);
    expect(observer.stops, 1);
    expect(navigator.userGestureInProgress, isFalse);
    expect(statuses, isNot(contains(AnimationStatus.completed)));
  });

  testWidgets('fast edge fling pops below the distance threshold',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(_buildSource(key));
    await _openSnapshotRoute(tester, key);

    await tester.flingFrom(
      const Offset(1, 300),
      const Offset(70, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsNothing);
  });

  testWidgets('horizontal drag outside the left edge does not drive the route',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final observer = _GestureObserver();
    await tester.pumpWidget(_buildSource(key, navigatorObservers: [observer]));
    await _openSnapshotRoute(tester, key);

    final route = ModalRoute.of(tester.element(find.text('Destination')))!;

    final gesture = await tester.startGesture(const Offset(40, 300));
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();

    // x=40 is past the 28px edge zone, so the back-gesture recognizer is never
    // armed: no user gesture starts and the route is not driven — its view
    // animation stays pinned at the fully-open value of 1.0.
    expect(observer.starts, 0);
    expect(
      Navigator.of(tester.element(find.text('Destination')))
          .userGestureInProgress,
      isFalse,
    );
    expect(route.animation!.value, 1.0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(observer.starts, 0);
    expect(find.text('Destination'), findsOneWidget);
  });

  testWidgets('vertical drag from the left edge remains a child gesture',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    var verticalUpdates = 0;
    await tester.pumpWidget(_buildSource(key));

    unawaited(
      pushOriginExpansion<void>(
        tester.element(find.byKey(const ValueKey('route-context'))),
        originKey: key,
        destinationBuilder: (_) => Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (_) => verticalUpdates++,
            child: const SizedBox.expand(child: Text('Vertical destination')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));

    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(const Offset(0, 80));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.up();
    await tester.pump();

    expect(verticalUpdates, greaterThan(0));
    expect(find.text('Vertical destination'), findsOneWidget);
  });
}

Future<void> _openSnapshotRoute(WidgetTester tester, GlobalKey key) async {
  unawaited(
    pushOriginExpansion<void>(
      tester.element(find.byKey(const ValueKey('route-context'))),
      originKey: key,
      destinationBuilder: (_) => const Scaffold(
        body: Center(child: Text('Destination')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 1));
  expect(find.text('Destination'), findsOneWidget);
  expect(
    find.byKey(const ValueKey('origin-expansion-edge-back')),
    findsOneWidget,
  );
}

Widget _buildSource(
  GlobalKey key, {
  List<NavigatorObserver> navigatorObservers = const [],
}) {
  return MaterialApp(
    navigatorObservers: navigatorObservers,
    home: Scaffold(
      body: Builder(
        builder: (context) => SizedBox(
          key: const ValueKey('route-context'),
          width: 80,
          height: 80,
          child: RepaintBoundary(
            key: key,
            child: const ColoredBox(color: Colors.red),
          ),
        ),
      ),
    ),
  );
}

class _TrackingAnimation extends Animation<double> {
  _TrackingAnimation({required this.value, required this.status});

  @override
  double value;

  @override
  AnimationStatus status;

  final List<VoidCallback> _listeners = [];
  final List<AnimationStatusListener> _statusListeners = [];

  int get listenerCount => _listeners.length;
  int get statusListenerCount => _statusListeners.length;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) {
    _statusListeners.add(listener);
  }

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    _statusListeners.remove(listener);
  }
}

class _GestureObserver extends NavigatorObserver {
  int starts = 0;
  int stops = 0;

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    starts++;
  }

  @override
  void didStopUserGesture() {
    stops++;
  }
}
