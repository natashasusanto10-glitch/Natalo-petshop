import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_back_gesture.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_transition.dart';

/// Golden coverage for the Postingan full-page zoom flight (Task 15).
///
/// These goldens drive the ONE-surface renderer ([PostPageZoomTransition]) and
/// the iOS interactive back surface ([PostPageBackSurface]) at fixed progress
/// with fully deterministic, network-free proxies and destination children.
/// They are deliberately geometry- and color-focused with NO text glyphs, so
/// they carry the minimum possible platform (font/AA) variance — the repo has
/// a history of text-heavy goldens going stale across environments.
///
/// Regenerate with:
/// ```bash
/// flutter test --no-pub --update-goldens \
///   test/features/feed/transition/post_page_zoom_golden_test.dart
/// ```
///
/// NOTE for CI: even geometry-focused goldens can differ subtly between the
/// generating host (Windows here) and a Linux CI raster backend. If CI reports
/// pixel diffs, regenerate on the CI image and commit those PNGs; the geometry
/// assertions in the sibling `*_geometry_test.dart` / `*_route_test.dart`
/// suites remain the source of truth for behavior.
void main() {
  // Small, fixed viewport keeps the PNGs tiny and reduces raster variance.
  const viewportRect = Rect.fromLTWH(0, 0, 200, 400);
  // A non-full-width square tile so scale/clip diverge at intermediate frames.
  const tileRect = Rect.fromLTWH(24, 72, 88, 88);
  const tileCornerRadius = 14.0;

  Future<void> pumpZoom(
    WidgetTester tester, {
    required double progress,
    required Widget destinationChild,
    required Color proxyColor,
    required Color background,
    required Key captureKey,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(200, 400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: captureKey,
          child: SizedBox(
            width: 200,
            height: 400,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: background),
                PostPageZoomTransition(
                  progress: AlwaysStoppedAnimation<double>(progress),
                  tileRect: tileRect,
                  viewportRect: viewportRect,
                  tileCornerRadius: tileCornerRadius,
                  proxyColor: proxyColor,
                  destinationChild: destinationChild,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpBackPreview(
    WidgetTester tester, {
    required double progress,
    required Widget destinationChild,
    required Color background,
    required Key captureKey,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(200, 400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final frame = resolvePostPageBackPreview(
      viewportRect: viewportRect,
      progress: progress,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: captureKey,
          child: SizedBox(
            width: 200,
            height: 400,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: background),
                PostPageBackSurface(
                  frame: frame,
                  viewportRect: viewportRect,
                  child: destinationChild,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // ---- light + dark schemes -------------------------------------------------
  const lightBg = Color(0xFFFFFFFF);
  const darkBg = Color(0xFF000000);
  const lightProxy = Color(0xFFB8C4D0);
  const darkProxy = Color(0xFF20272E);

  group('forward intermediate frame (p=0.5)', () {
    for (final theme in const ['light', 'dark']) {
      final isDark = theme == 'dark';
      final bg = isDark ? darkBg : lightBg;
      final proxy = isDark ? darkProxy : lightProxy;

      testWidgets('photo — $theme', (tester) async {
        final key = Key('golden_photo_$theme');
        await pumpZoom(
          tester,
          progress: 0.5,
          destinationChild: _FakePhoto(dark: isDark),
          proxyColor: proxy,
          background: bg,
          captureKey: key,
        );
        await expectLater(
          find.byKey(key),
          matchesGoldenFile('goldens/post_page_zoom_photo_$theme.png'),
        );
      });

      testWidgets('carousel — $theme', (tester) async {
        final key = Key('golden_carousel_$theme');
        await pumpZoom(
          tester,
          progress: 0.5,
          destinationChild: _FakeCarousel(dark: isDark),
          proxyColor: proxy,
          background: bg,
          captureKey: key,
        );
        await expectLater(
          find.byKey(key),
          matchesGoldenFile('goldens/post_page_zoom_carousel_$theme.png'),
        );
      });

      testWidgets('video poster — $theme', (tester) async {
        final key = Key('golden_video_$theme');
        await pumpZoom(
          tester,
          progress: 0.5,
          destinationChild: _FakeVideoPoster(dark: isDark),
          proxyColor: proxy,
          background: bg,
          captureKey: key,
        );
        await expectLater(
          find.byKey(key),
          matchesGoldenFile('goldens/post_page_zoom_video_$theme.png'),
        );
      });
    }
  });

  testWidgets('iOS interactive preview frame (p=0.5, scaled + rounded)', (
    tester,
  ) async {
    const key = Key('golden_ios_preview');
    await pumpBackPreview(
      tester,
      progress: 0.5,
      destinationChild: const _FakePhoto(dark: false),
      background: lightBg,
      captureKey: key,
    );
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/post_page_zoom_ios_preview.png'),
    );
  });

  testWidgets('reverse terminal frame lands on B tile geometry (p=0)', (
    tester,
  ) async {
    const key = Key('golden_reverse_terminal');
    // progress 0 == exact source/target tile geometry: the surface is the
    // small rounded tile, proxy fully opaque, destination faded out.
    await pumpZoom(
      tester,
      progress: 0.0,
      destinationChild: const _FakePhoto(dark: false),
      proxyColor: lightProxy,
      background: lightBg,
      captureKey: key,
    );
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/post_page_zoom_reverse_terminal.png'),
    );
  });
}

/// Deterministic, font-free photo destination: two diagonal color bands.
class _FakePhoto extends StatelessWidget {
  const _FakePhoto({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BandsPainter(dark: dark),
      size: Size.infinite,
    );
  }
}

/// Photo + a bottom-center row of three page dots (carousel affordance).
class _FakeCarousel extends StatelessWidget {
  const _FakeCarousel({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _FakePhoto(dark: dark),
        Align(
          alignment: const Alignment(0, 0.82),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == 0
                      ? const Color(0xFFFFFFFF)
                      : const Color(0x88FFFFFF),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// Dark poster + a centered play triangle (static — proves no autoplay glyph).
class _FakeVideoPoster extends StatelessWidget {
  const _FakeVideoPoster({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: dark ? const Color(0xFF101418) : const Color(0xFF2B2F36)),
        Center(
          child: CustomPaint(
            size: const Size(48, 48),
            painter: _PlayTrianglePainter(),
          ),
        ),
      ],
    );
  }
}

class _BandsPainter extends CustomPainter {
  const _BandsPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final top = Paint()
      ..color = dark ? const Color(0xFF33506E) : const Color(0xFF7FA8D0);
    final bottom = Paint()
      ..color = dark ? const Color(0xFF1E3346) : const Color(0xFFCFE0F0);
    canvas.drawRect(Offset.zero & size, bottom);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.45)
      ..lineTo(0, size.height * 0.7)
      ..close();
    canvas.drawPath(path, top);
  }

  @override
  bool shouldRepaint(covariant _BandsPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class _PlayTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final circle = Paint()..color = const Color(0x66000000);
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2,
      circle,
    );
    final tri = Paint()..color = const Color(0xFFFFFFFF);
    final path = Path()
      ..moveTo(size.width * 0.40, size.height * 0.32)
      ..lineTo(size.width * 0.40, size.height * 0.68)
      ..lineTo(size.width * 0.70, size.height * 0.50)
      ..close();
    canvas.drawPath(path, tri);
  }

  @override
  bool shouldRepaint(covariant _PlayTrianglePainter oldDelegate) => false;
}
