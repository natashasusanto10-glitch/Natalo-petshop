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

    await tester.pump(const Duration(milliseconds: 240));
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
    expect(_snapshotPositioned(tester).width, lessThan(400));

    await gesture.up(timeStamp: const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Destination'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsOneWidget);
    expect(_snapshotPositioned(tester).width, 400);
  });

  testWidgets('edge swipe pops at 25 percent width', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(_buildSource(key));
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
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsNothing);
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
    await tester.pumpWidget(_buildSource(key));
    await _openSnapshotRoute(tester, key);

    final gesture = await tester.startGesture(const Offset(40, 300));
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();

    expect(_snapshotPositioned(tester).width, 400);

    await gesture.up();
    await tester.pumpAndSettle();
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
    await tester.pump(const Duration(milliseconds: 241));

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
  await tester.pump(const Duration(milliseconds: 240));
  await tester.pump(const Duration(milliseconds: 1));
  expect(find.text('Destination'), findsOneWidget);
  expect(
    find.byKey(const ValueKey('origin-expansion-edge-back')),
    findsOneWidget,
  );
}

Positioned _snapshotPositioned(WidgetTester tester) {
  return tester.widget<Positioned>(
    find.ancestor(
      of: find.byKey(const ValueKey('origin-expansion-snapshot')),
      matching: find.byType(Positioned),
    ),
  );
}

Widget _buildSource(GlobalKey key) {
  return MaterialApp(
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
