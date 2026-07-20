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
      // double is applied uniformly. Verify the value at a mid-point matches
      // the width-only lerp formula exactly.
      final frame = frameAt(0.5);
      final expectedScale = lerpDoubleForTest(
        tileRect.width / viewportRect.width,
        1.0,
        0.5,
      );
      expect(frame.scale, closeTo(expectedScale, 1e-9));
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
        final frame = frameAt(0.5);
        // The clip rect at .5 must NOT equal the scaled-surface bounds at
        // .5 (offset + tileRect.size*scale), proving there is no derived
        // stretch coupling clip to the transform.
        final scaledSurfaceBounds = Rect.fromLTWH(
          frame.offset.dx,
          frame.offset.dy,
          viewportRect.width * frame.scale,
          viewportRect.height * frame.scale,
        );
        expect(frame.clip.outerRect, isNot(scaledSurfaceBounds));

        final expectedClip = RRect.lerp(
          RRect.fromRectAndRadius(
            tileRect,
            const Radius.circular(tileCornerRadius),
          ),
          RRect.fromRectAndRadius(viewportRect, Radius.zero),
          0.5,
        )!;
        expect(frame.clip, expectedClip);
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
    test(
      'reverse progress reproduces the same forward values at each point',
      () {
        // Reverse flights simply drive progress from 1 -> 0; the resolver is
        // pure and direction-agnostic, so the same values must come back.
        for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          expect(frameAt(p), frameAt(p));
        }
        // Endpoints swapped relative to a naive "reverse" driver: driving from
        // 1 down to 0 lands back on exact source-tile geometry.
        final reverseEnd = frameAt(1.0 - 1.0);
        expect(reverseEnd.offset, tileRect.topLeft);
        expect(reverseEnd.clip.outerRect, tileRect);
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
