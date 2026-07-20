import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_back_gesture.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_geometry.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_transition.dart';

/// Golden coverage for the Postingan full-page zoom flight (Task 8/T8).
///
/// These goldens drive the TWO-LAYER renderer ([PostPageZoomTransition] =
/// a faded-in chrome layer + a scaled/clipped hero-media layer) and the iOS
/// interactive-back hero surface ([PostPageHeroSurface]) at fixed progress
/// with fully deterministic, network-free content. They are deliberately
/// geometry- and color-focused with NO text glyphs, so they carry the
/// minimum possible platform (font/AA) variance — the repo has a history of
/// text-heavy goldens going stale across environments.
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
  const tileRadius = 14.0;
  const slotRadius = 0.0;
  const mediaAspect = 0.8;

  Future<void> pumpZoom(
    WidgetTester tester, {
    required double progress,
    required Widget heroMediaChild,
    required Widget chromeChild,
    required Color background,
    required Key captureKey,
    bool reverseHandoff = false,
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
                  slotRect: viewportRect,
                  mediaAspect: mediaAspect,
                  tileRadius: tileRadius,
                  slotRadius: slotRadius,
                  chromeChild: chromeChild,
                  heroMediaChild: heroMediaChild,
                  reverseHandoff: reverseHandoff,
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
    required double dragProgress,
    required Widget heroMediaChild,
    required Color background,
    required Key captureKey,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(200, 400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    // Mirrors `PostPageZoomRoute._backHeroFrame`: the preview is driven by
    // (1 - dragProgress) of the same hero-frame resolver used for the
    // forward/close flights, from full-screen (slot) toward the tile.
    final frame = resolveHeroFrame(
      tileRect: tileRect,
      slotRect: viewportRect,
      mediaAspect: mediaAspect,
      tileRadius: tileRadius,
      slotRadius: slotRadius,
      progress: 1 - dragProgress,
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
                PostPageHeroSurface(
                  frame: frame,
                  mediaAspect: mediaAspect,
                  child: heroMediaChild,
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

  Widget chromeFor(bool dark) => ColoredBox(
    color: dark ? const Color(0xFF0B0E11) : const Color(0xFFEFF2F5),
  );

  group('forward intermediate frame (p=0.5)', () {
    for (final theme in const ['light', 'dark']) {
      final isDark = theme == 'dark';
      final bg = isDark ? darkBg : lightBg;

      testWidgets('photo — $theme', (tester) async {
        final key = Key('golden_photo_$theme');
        await pumpZoom(
          tester,
          progress: 0.5,
          heroMediaChild: _FakePhoto(dark: isDark),
          chromeChild: chromeFor(isDark),
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
          heroMediaChild: _FakeCarousel(dark: isDark),
          chromeChild: chromeFor(isDark),
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
          heroMediaChild: _FakeVideoPoster(dark: isDark),
          chromeChild: chromeFor(isDark),
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

  group('forward endpoint frames (p=0 / p=1)', () {
    testWidgets('photo — light — p=0 (tile geometry, chrome hidden)', (
      tester,
    ) async {
      const key = Key('golden_photo_p0');
      await pumpZoom(
        tester,
        progress: 0.0,
        heroMediaChild: const _FakePhoto(dark: false),
        chromeChild: chromeFor(false),
        background: lightBg,
        captureKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/post_page_zoom_photo_p0.png'),
      );
    });

    testWidgets('photo — light — p=1 (slot geometry, chrome fully visible)', (
      tester,
    ) async {
      const key = Key('golden_photo_p1');
      await pumpZoom(
        tester,
        progress: 1.0,
        heroMediaChild: const _FakePhoto(dark: false),
        chromeChild: chromeFor(false),
        background: lightBg,
        captureKey: key,
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/post_page_zoom_photo_p1.png'),
      );
    });
  });

  testWidgets('iOS interactive preview frame (drag=0.5, mid-flight)', (
    tester,
  ) async {
    const key = Key('golden_ios_preview');
    await pumpBackPreview(
      tester,
      dragProgress: 0.5,
      heroMediaChild: const _FakePhoto(dark: false),
      background: lightBg,
      captureKey: key,
    );
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/post_page_zoom_ios_preview.png'),
    );
  });

  testWidgets('reverse terminal frame lands on tile geometry (p=0, hero '
      'reappeared immediately via reverseHandoff)', (tester) async {
    const key = Key('golden_reverse_terminal');
    // progress 0 with reverseHandoff == exact tile geometry, hero fully
    // opaque (the crossfade window is mirrored to the START of the flight
    // for a reverse, so the fake hero is already back at full opacity).
    await pumpZoom(
      tester,
      progress: 0.0,
      heroMediaChild: const _FakePhoto(dark: false),
      chromeChild: chromeFor(false),
      background: lightBg,
      captureKey: key,
      reverseHandoff: true,
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
///
/// Painted entirely via [CustomPaint] (no Row/Container/fixed-pixel-sized
/// widgets): [heroMediaChild] is laid out inside an intrinsic
/// `Size(mediaAspect, 1.0)` surface (`paintPostPageHero`'s `SizedBox`) which
/// is a FRACTION-of-a-logical-pixel box before the hero transform scales it
/// up — any child that assumes real pixel sizes (e.g. a 6px circle in a Row)
/// overflows there. A [CustomPaint] instead draws everything proportional to
/// whatever `size` it's given, which works at any scale.
class _FakeCarousel extends StatelessWidget {
  const _FakeCarousel({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CarouselPainter(dark: dark),
      size: Size.infinite,
    );
  }
}

class _CarouselPainter extends CustomPainter {
  const _CarouselPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    _BandsPainter(dark: dark).paint(canvas, size);
    final dotRadius = size.width * 0.02;
    final dotY = size.height * 0.82;
    final centerX = size.width / 2;
    final spacing = size.width * 0.06;
    for (var i = 0; i < 3; i++) {
      final paint = Paint()
        ..color = i == 0 ? const Color(0xFFFFFFFF) : const Color(0x88FFFFFF);
      canvas.drawCircle(
        Offset(centerX + (i - 1) * spacing, dotY),
        dotRadius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CarouselPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

/// Dark poster + a centered play triangle (static — proves no autoplay glyph).
/// Painted entirely via [CustomPaint] — see [_FakeCarousel] for why.
class _FakeVideoPoster extends StatelessWidget {
  const _FakeVideoPoster({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VideoPosterPainter(dark: dark),
      size: Size.infinite,
    );
  }
}

class _VideoPosterPainter extends CustomPainter {
  const _VideoPosterPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = dark ? const Color(0xFF101418) : const Color(0xFF2B2F36);
    canvas.drawRect(Offset.zero & size, bg);
    final playSize = size.shortestSide * 0.3;
    canvas.save();
    canvas.translate(
      size.width / 2 - playSize / 2,
      size.height / 2 - playSize / 2,
    );
    _PlayTrianglePainter().paint(canvas, Size.square(playSize));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VideoPosterPainter oldDelegate) =>
      oldDelegate.dark != dark;
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
    canvas.drawCircle(size.center(Offset.zero), size.width / 2, circle);
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
