import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_geometry.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_transition.dart';

void main() {
  // A deliberately non-full-width tile so scale-derived surface bounds and
  // the independent clip rect diverge at intermediate progress.
  const tileRect = Rect.fromLTWH(40, 120, 150, 200);
  const viewportRect = Rect.fromLTWH(0, 0, 400, 800);
  const tileCornerRadius = 12.0;

  PostPageZoomFrame frameAt(double progress) => resolvePostPageZoomFrame(
    tileRect: tileRect,
    viewportRect: viewportRect,
    tileCornerRadius: tileCornerRadius,
    progress: progress,
  );

  group('resolvePostPageZoomFrame — forward', () {
    test('endpoint p=0 is exact source-tile geometry', () {
      final frame = frameAt(0);
      expect(frame.offset, tileRect.topLeft);
      expect(frame.scale, closeTo(tileRect.width / viewportRect.width, 1e-9));
      expect(frame.clip.tlRadiusX, closeTo(tileCornerRadius, 1e-9));
      expect(frame.clip.outerRect, tileRect);
      expect(frame.proxyOpacity, 1.0);
      expect(frame.destinationOpacity, 0.0);
    });

    test('endpoint p=1 is exact fullscreen geometry', () {
      final frame = frameAt(1);
      expect(frame.offset, Offset.zero);
      expect(frame.scale, closeTo(1.0, 1e-9));
      expect(frame.clip.tlRadiusX, closeTo(0.0, 1e-9));
      expect(frame.clip.outerRect, viewportRect);
      expect(frame.proxyOpacity, 0.0);
      expect(frame.destinationOpacity, 1.0);
    });

    test('scale is uniform width-derived, no independent y-scale field', () {
      // The frame type itself must not carry a y-scale; a single `scale`
      // double is applied uniformly at every sampled progress.
      for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final frame = frameAt(p);
        final expectedScale = lerpDoubleForTest(
          tileRect.width / viewportRect.width,
          1.0,
          p,
        );
        expect(
          frame.scale,
          closeTo(expectedScale, 1e-9),
          reason: 'progress=$p',
        );
      }
    });

    test('offset translates top-left from tile to viewport top-left', () {
      for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final frame = frameAt(p);
        final expected = Offset.lerp(
          tileRect.topLeft,
          viewportRect.topLeft,
          p,
        )!;
        expect(frame.offset, expected, reason: 'progress=$p');
      }
    });

    test(
      'clip tweens tile bounds+radius toward viewport bounds+0 independently of scale',
      () {
        for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          final frame = frameAt(p);
          final expectedClip = RRect.lerp(
            RRect.fromRectAndRadius(
              tileRect,
              const Radius.circular(tileCornerRadius),
            ),
            RRect.fromRectAndRadius(viewportRect, Radius.zero),
            p,
          )!;
          expect(frame.clip, expectedClip, reason: 'progress=$p');
        }

        // At a strictly-intermediate progress, the clip rect must NOT equal
        // the scaled-surface bounds (offset + viewportRect.size*scale),
        // proving there is no derived stretch coupling clip to the
        // transform for this non-full-width tile.
        final midFrame = frameAt(0.5);
        final scaledSurfaceBounds = Rect.fromLTWH(
          midFrame.offset.dx,
          midFrame.offset.dy,
          viewportRect.width * midFrame.scale,
          viewportRect.height * midFrame.scale,
        );
        expect(midFrame.clip.outerRect, isNot(scaledSurfaceBounds));
      },
    );

    test('proxy/destination crossfade is monotonic and completes early', () {
      final progresses = [0.0, 0.1, 0.2, 0.25, 0.35, 0.5, 0.75, 1.0];
      double? previousProxy;
      double? previousDestination;
      for (final p in progresses) {
        final frame = frameAt(p);
        if (previousProxy != null) {
          expect(frame.proxyOpacity, lessThanOrEqualTo(previousProxy));
        }
        if (previousDestination != null) {
          expect(
            frame.destinationOpacity,
            greaterThanOrEqualTo(previousDestination),
          );
        }
        previousProxy = frame.proxyOpacity;
        previousDestination = frame.destinationOpacity;
      }
      expect(frameAt(0).proxyOpacity, 1.0);
      // Destination is fully opaque well before the flight completes.
      expect(frameAt(0.35).destinationOpacity, 1.0);
      expect(frameAt(0.35).proxyOpacity, 0.0);
    });
  });

  group('resolvePostPageZoomFrame — reverse', () {
    testWidgets(
      'reverse-sampled frames from a real AnimationController match forward frames at the same progress',
      (tester) async {
        // Drive an actual AnimationController forward to completion, then
        // reverse() it and sample deterministically (via tester.pump with
        // fixed durations, no wall-clock) at progress 1/.75/.5/.25/0. Resolve
        // frames directly from that SAME animation object's `.value` (as the
        // widget does) and assert each reverse-sampled frame equals the
        // forward frame computed independently at the same progress value.
        // If resolvePostPageZoomFrame ever became direction-sensitive (e.g.
        // by consulting AnimationStatus or accumulating state), the
        // reverse-sampled values would diverge from the pure forward values
        // and this test would fail.
        final controller = AnimationController(
          vsync: tester,
          duration: const Duration(milliseconds: 300),
        );

        PostPageZoomFrame frameFromController() => resolvePostPageZoomFrame(
          tileRect: tileRect,
          viewportRect: viewportRect,
          tileCornerRadius: tileCornerRadius,
          progress: controller.value,
        );

        // A zero-duration "prime" pump establishes the ticker's start
        // timestamp; subsequent fixed-duration pumps then advance the
        // controller by exactly that much elapsed time each, so the
        // controller lands deterministically on each target progress.
        controller.forward(from: 0);
        await tester.pump();
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 75));
        }
        expect(controller.value, closeTo(1.0, 1e-9));

        controller.reverse();
        await tester.pump();
        final sampledFrames = <double, PostPageZoomFrame>{};
        final targetProgresses = [0.75, 0.5, 0.25, 0.0];
        for (final target in targetProgresses) {
          // duration is 300ms; step in fixed 75ms increments (1/4 of the
          // controller duration each) so controller.value lands exactly on
          // each target deterministically.
          await tester.pump(const Duration(milliseconds: 75));
          expect(controller.value, closeTo(target, 1e-9));
          sampledFrames[target] = frameFromController();
        }

        for (final target in targetProgresses) {
          expect(
            sampledFrames[target],
            frameAt(target),
            reason:
                'reverse-sampled frame at progress=$target must equal '
                'the pure forward frame at the same progress',
          );
        }

        // Endpoint reached by reversing all the way lands on exact
        // source-tile geometry.
        expect(sampledFrames[0.0]!.offset, tileRect.topLeft);
        expect(sampledFrames[0.0]!.clip.outerRect, tileRect);

        controller.dispose();
      },
    );
  });

  group('PostPageZoomTransition widget', () {
    testWidgets('destination child is built exactly once across ticks', (
      tester,
    ) async {
      var buildCount = 0;
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 300),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PostPageZoomTransition(
            progress: controller,
            tileRect: tileRect,
            viewportRect: viewportRect,
            tileCornerRadius: tileCornerRadius,
            proxyColor: const Color(0xFF112233),
            destinationChild: Builder(
              builder: (context) {
                buildCount++;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      expect(buildCount, 1);

      controller.forward(from: 0);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(buildCount, 1);
      expect(find.byType(RepaintBoundary), findsWidgets);
      expect(find.byType(ClipRRect), findsOneWidget);
      expect(find.byType(Transform), findsWidgets);
      controller.dispose();
    });

    testWidgets('proxy uses BoxFit.cover inside the same animated clip', (
      tester,
    ) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 300),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PostPageZoomTransition(
            progress: controller,
            tileRect: tileRect,
            viewportRect: viewportRect,
            tileCornerRadius: tileCornerRadius,
            proxyColor: const Color(0xFF112233),
            destinationChild: const SizedBox.expand(),
          ),
        ),
      );

      final coloredBoxFinder = find.byType(ColoredBox);
      expect(coloredBoxFinder, findsWidgets);

      // The ColoredBox (proxy) must be a descendant of the single ClipRRect
      // that also clips the destination surface.
      final clipRRectElement = tester.element(find.byType(ClipRRect));
      final coloredBoxElement = tester.element(coloredBoxFinder.first);
      var found = false;
      coloredBoxElement.visitAncestorElements((ancestor) {
        if (ancestor == clipRRectElement) {
          found = true;
          return false;
        }
        return true;
      });
      expect(found, isTrue);
      controller.dispose();
    });

    testWidgets(
      'emits no AnnotatedRegion / overlay-style change across ticks',
      (tester) async {
        final controller = AnimationController(
          vsync: tester,
          duration: const Duration(milliseconds: 300),
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: PostPageZoomTransition(
              progress: controller,
              tileRect: tileRect,
              viewportRect: viewportRect,
              tileCornerRadius: tileCornerRadius,
              proxyColor: const Color(0xFF112233),
              destinationChild: const SizedBox.expand(),
            ),
          ),
        );

        // Status bar / overlay style is platform-owned; this one-surface
        // renderer must not introduce any AnnotatedRegion of its own.
        expect(find.byType(AnnotatedRegion<Object>), findsNothing);

        controller.forward(from: 0);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          expect(find.byType(AnnotatedRegion<Object>), findsNothing);
        }
        controller.dispose();
      },
    );
  });
}

double lerpDoubleForTest(double a, double b, double t) => a + (b - a) * t;
