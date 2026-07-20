import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_transition.dart';

/// Task 15/T8 performance + accessibility verification for the two-layer zoom
/// renderer ([PostPageZoomTransition] = chrome layer + hero-media layer).
/// These are the assertions that are genuinely unit-testable WITHOUT a
/// device; the tap→first-motion (<50ms), 60Hz (<16.7ms) and 120Hz (<8.3ms)
/// raster budgets are DEVICE-VERIFY and documented in the task report, not
/// faked here.
///
/// Complementary coverage already lives in sibling suites and is referenced
/// (not duplicated) here:
/// - `post_page_zoom_geometry_test.dart`: `resolveHeroFrame`/
///   `resolveChromeOpacity` pure-function geometry.
/// - `post_page_zoom_route_test.dart`: `debugPostPageZoomOnSnapshotAttempt`
///   throwing seam proves no `toImage`; synchronous proxy selection (no await
///   before first motion); source semantics/focus lock; reduced-motion path;
///   repeated-push guard; video controller sharing/identity.
void main() {
  const tileRect = Rect.fromLTWH(24, 72, 120, 120);
  const slotRect = Rect.fromLTWH(0, 80, 400, 500);
  const tileRadius = 14.0;
  const slotRadius = 0.0;
  const mediaAspect = 0.8;

  group('performance — compositor-only flight, no per-tick work', () {
    testWidgets('chromeChild (destination) is built exactly once across a full '
        'forward+reverse (open then close) cycle', (tester) async {
      var buildCount = 0;
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 200),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PostPageZoomTransition(
            progress: controller,
            tileRect: tileRect,
            slotRect: slotRect,
            mediaAspect: mediaAspect,
            tileRadius: tileRadius,
            slotRadius: slotRadius,
            chromeChild: Builder(
              builder: (context) {
                buildCount++;
                return const SizedBox.expand();
              },
            ),
            heroMediaChild: const SizedBox.expand(),
          ),
        ),
      );
      expect(buildCount, 1);

      // Forward (opening).
      controller.forward(from: 0);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      // Reverse (closing) from wherever it landed.
      controller.reverse();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      // Not one extra build across the entire open+close flight.
      expect(buildCount, 1);
    });

    testWidgets(
      'heroMediaChild is built exactly once across a full forward+reverse '
      'cycle (passed as the AnimatedBuilder child, never rebuilt per tick)',
      (tester) async {
        var buildCount = 0;
        final controller = AnimationController(
          vsync: tester,
          duration: const Duration(milliseconds: 200),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: PostPageZoomTransition(
              progress: controller,
              tileRect: tileRect,
              slotRect: slotRect,
              mediaAspect: mediaAspect,
              tileRadius: tileRadius,
              slotRadius: slotRadius,
              chromeChild: const SizedBox.expand(),
              heroMediaChild: Builder(
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
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }
        controller.reverse();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }

        expect(buildCount, 1);
      },
    );

    testWidgets(
      'flight uses only compositor-friendly primitives (Transform/Opacity/'
      'ClipRRect) — no BackdropFilter/ImageFiltered/ShaderMask',
      (tester) async {
        final controller = AnimationController(
          vsync: tester,
          duration: const Duration(milliseconds: 200),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: PostPageZoomTransition(
              progress: controller,
              tileRect: tileRect,
              slotRect: slotRect,
              mediaAspect: mediaAspect,
              tileRadius: tileRadius,
              slotRadius: slotRadius,
              chromeChild: const SizedBox.expand(),
              heroMediaChild: const SizedBox.expand(),
            ),
          ),
        );

        controller.forward(from: 0);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          expect(find.byType(Transform), findsWidgets);
          expect(find.byType(Opacity), findsWidgets);
          expect(find.byType(ClipRRect), findsOneWidget);
          expect(find.byType(BackdropFilter), findsNothing);
          expect(find.byType(ImageFiltered), findsNothing);
          expect(find.byType(ShaderMask), findsNothing);
        }
        await tester.pumpAndSettle();
      },
    );
  });

  group('accessibility — foreground surface exposed, deterministic label', () {
    testWidgets(
      'the chromeChild (destination) subtree remains semantically reachable '
      'throughout the flight (foreground route is the focusable surface)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final controller = AnimationController(
          vsync: tester,
          duration: const Duration(milliseconds: 200),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: PostPageZoomTransition(
              progress: controller,
              tileRect: tileRect,
              slotRect: slotRect,
              mediaAspect: mediaAspect,
              tileRadius: tileRadius,
              slotRadius: slotRadius,
              chromeChild: Semantics(
                container: true,
                label: 'destination-content',
                child: const SizedBox.expand(),
              ),
              heroMediaChild: const SizedBox.expand(),
            ),
          ),
        );

        controller.forward(from: 0);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }

        expect(find.bySemanticsLabel('destination-content'), findsOneWidget);
        await tester.pumpAndSettle();
        handle.dispose();
      },
    );
  });
}
