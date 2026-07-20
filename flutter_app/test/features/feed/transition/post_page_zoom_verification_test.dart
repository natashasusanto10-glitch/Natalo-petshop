import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_transition.dart';

/// Task 15 performance + accessibility verification for the ONE-surface zoom
/// renderer. These are the assertions that are genuinely unit-testable WITHOUT
/// a device; the tap→first-motion (<50ms), 60Hz (<16.7ms) and 120Hz (<8.3ms)
/// raster budgets are DEVICE-VERIFY and documented in the task report, not
/// faked here.
///
/// Complementary coverage already lives in sibling suites and is referenced
/// (not duplicated) here:
/// - `post_page_zoom_geometry_test.dart`: destination built once across ticks;
///   proxy under the single animated clip; no `AnnotatedRegion` churn.
/// - `post_page_zoom_route_test.dart`: `debugPostPageZoomOnSnapshotAttempt`
///   throwing seam proves no `toImage`; synchronous proxy selection (no await
///   before first motion); source semantics/focus lock; reduced-motion path;
///   repeated-push guard.
void main() {
  const tileRect = Rect.fromLTWH(24, 72, 120, 120);
  const viewportRect = Rect.fromLTWH(0, 0, 200, 400);
  const tileCornerRadius = 14.0;

  // Decoded outside the fake-async test zone: `createTestImage` needs real
  // async and would otherwise trip the test framework's guard.
  late ui.Image proxyImage;
  setUp(() async {
    proxyImage = await createTestImage(width: 4, height: 4);
  });

  group('performance — compositor-only flight, no per-tick work', () {
    testWidgets(
      'destination child is built exactly once across a full '
      'forward+reverse (open then close) cycle',
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
              viewportRect: viewportRect,
              tileCornerRadius: tileCornerRadius,
              proxyColor: const Color(0xFF112233),
              destinationChild: const SizedBox.expand(),
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

  group('performance — no network image / per-frame decode during opening', () {
    testWidgets(
      'a proxy ImageProvider is resolved at most once and never re-decoded '
      'per animation tick; no Image.network is constructed',
      (tester) async {
        final spy = _CountingImageProvider(proxyImage);

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
              viewportRect: viewportRect,
              tileCornerRadius: tileCornerRadius,
              proxyImageProvider: spy,
              destinationChild: const SizedBox.expand(),
            ),
          ),
        );

        controller.forward(from: 0);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }

        // Decoded exactly once for the whole flight (proxy is a warm, already
        // resolved provider — no per-tick decode, no network round-trip).
        expect(spy.loadCount, 1);
        // No network image widget anywhere in the flight subtree.
        final networkImages = find.byWidgetPredicate(
          (w) => w is Image && w.image is NetworkImage,
        );
        expect(networkImages, findsNothing);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'the deterministic proxyColor path constructs zero Image widgets',
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
              viewportRect: viewportRect,
              tileCornerRadius: tileCornerRadius,
              proxyColor: const Color(0xFF112233),
              destinationChild: const SizedBox.expand(),
            ),
          ),
        );

        controller.forward(from: 0);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          expect(find.byType(Image), findsNothing);
        }
        await tester.pumpAndSettle();
      },
    );
  });

  group('accessibility — foreground surface exposed, deterministic label', () {
    testWidgets(
      'the destination subtree remains semantically reachable throughout the '
      'flight (foreground route is the focusable surface)',
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
              viewportRect: viewportRect,
              tileCornerRadius: tileCornerRadius,
              proxyColor: const Color(0xFF112233),
              destinationChild: Semantics(
                container: true,
                label: 'destination-content',
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );

        controller.forward(from: 0);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }

        expect(
          find.bySemanticsLabel('destination-content'),
          findsOneWidget,
        );
        await tester.pumpAndSettle();
        handle.dispose();
      },
    );
  });
}

/// A synchronous, resolve-counting [ImageProvider]. Proves the proxy layer
/// decodes exactly once for the whole flight — no per-tick / per-frame decode.
class _CountingImageProvider extends ImageProvider<_CountingImageProvider> {
  _CountingImageProvider(this._image);

  final ui.Image _image;
  int loadCount = 0;

  @override
  Future<_CountingImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_CountingImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CountingImageProvider key,
    ImageDecoderCallback decode,
  ) {
    loadCount++;
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: _image.clone())),
    );
  }

  @override
  bool operator ==(Object other) => other is _CountingImageProvider;

  @override
  int get hashCode => runtimeType.hashCode;
}
