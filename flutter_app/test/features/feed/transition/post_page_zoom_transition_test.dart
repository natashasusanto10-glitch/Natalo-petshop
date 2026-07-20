import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_transition.dart';

Widget _host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

// Same pattern as post_page_zoom_geometry_test.dart's coversTightly: tight
// on all 4 edges (within a sub-pixel tolerance), plus "at least one axis
// matches exactly" to confirm true BoxFit.cover framing rather than an
// arbitrarily larger box that merely contains the target.
bool _coversTightly(Rect content, Rect target) =>
    content.left <= target.left + 0.5 &&
    content.top <= target.top + 0.5 &&
    content.right >= target.right - 0.5 &&
    content.bottom >= target.bottom - 0.5 &&
    ((content.width - target.width).abs() < 0.5 ||
        (content.height - target.height).abs() < 0.5);

void main() {
  const tileRect = Rect.fromLTWH(30, 100, 120, 120);
  const slotRect = Rect.fromLTWH(0, 80, 400, 500);
  const mediaAspect = 4 / 5;

  testWidgets('renders chrome + hero; chrome opacity tracks progress', (
    tester,
  ) async {
    final ctrl = AnimationController(vsync: const TestVSync());
    addTearDown(ctrl.dispose);
    ctrl.value = 0.0;
    await tester.pumpWidget(
      _host(
        PostPageZoomTransition(
          progress: ctrl,
          tileRect: tileRect,
          slotRect: slotRect,
          mediaAspect: mediaAspect,
          tileRadius: 4,
          slotRadius: 0,
          chromeChild: const Text('chrome'),
          heroMediaChild: const ColoredBox(color: Color(0xFF00FF00)),
        ),
      ),
    );
    // chrome present but fully transparent at progress 0
    final op0 = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('chrome'), matching: find.byType(Opacity))
          .first,
    );
    expect(op0.opacity, 0.0);

    ctrl.value = 1.0;
    await tester.pump();
    final op1 = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('chrome'), matching: find.byType(Opacity))
          .first,
    );
    expect(op1.opacity, 1.0);
  });

  // Pins the tile/slot coverage endpoint contract: at progress 0 the hero
  // media surface must tightly cover the source grid tile, and at progress
  // 1 it must tightly cover the destination media slot. This caught a real
  // bug: Stack(fit: StackFit.expand) imposes tight constraints that
  // Opacity/ClipRRect/Transform pass through unchanged, so the inner
  // SizedBox(mediaAspect, 1) intrinsic surface was being forced to the full
  // ambient (viewport) size instead of its own declared size. Fixed by
  // wrapping the SizedBox in an unconstrained OverflowBox so it actually
  // lays out at its intrinsic size before Transform.scale scales it up.
  testWidgets('hero media on-screen rect covers the tile at progress 0 and '
      'the slot at progress 1', (tester) async {
    final ctrl = AnimationController(vsync: const TestVSync());
    addTearDown(ctrl.dispose);
    const heroKey = Key('hero-media');
    Widget build() => _host(
      PostPageZoomTransition(
        progress: ctrl,
        tileRect: tileRect,
        slotRect: slotRect,
        mediaAspect: mediaAspect,
        tileRadius: 4,
        slotRadius: 0,
        chromeChild: const SizedBox.expand(),
        heroMediaChild: const ColoredBox(
          key: heroKey,
          color: Color(0xFF00FF00),
        ),
      ),
    );

    ctrl.value = 0.0;
    await tester.pumpWidget(build());
    final r0 = tester.getRect(find.byKey(heroKey));
    expect(
      _coversTightly(r0, tileRect),
      isTrue,
      reason: 'progress 0: hero rect $r0 should tightly cover tile $tileRect',
    );

    ctrl.value = 1.0;
    await tester.pump();
    final r1 = tester.getRect(find.byKey(heroKey));
    expect(
      _coversTightly(r1, slotRect),
      isTrue,
      reason: 'progress 1: hero rect $r1 should tightly cover slot $slotRect',
    );
  });

  testWidgets(
    'hero opacity flat at 1.0 then linearly fades to 0.0 over the final '
    'crossfade window (reverseHandoff: false)',
    (tester) async {
      final ctrl = AnimationController(vsync: const TestVSync());
      addTearDown(ctrl.dispose);
      const heroKey = Key('hero-media-opacity-forward');
      ctrl.value = 0.0;
      await tester.pumpWidget(
        _host(
          PostPageZoomTransition(
            progress: ctrl,
            tileRect: tileRect,
            slotRect: slotRect,
            mediaAspect: mediaAspect,
            tileRadius: 4,
            slotRadius: 0,
            chromeChild: const SizedBox.expand(),
            heroMediaChild: const ColoredBox(
              key: heroKey,
              color: Color(0xFF00FF00),
            ),
          ),
        ),
      );

      // The hero Opacity is the one that is an ancestor of the hero media
      // child; disambiguated from the chrome Opacity via find.ancestor,
      // which throws if this ever matches more than one widget.
      Opacity heroOpacityWidget() => tester.widget<Opacity>(
        find.ancestor(of: find.byKey(heroKey), matching: find.byType(Opacity)),
      );

      // Derived by hand from _heroOpacity in post_page_zoom_transition.dart:
      // rampStart = 1 - 0.35 = 0.65; fraction =
      // ((t - 0.65) / 0.35).clamp(0, 1); opacity = 1 - fraction.
      for (final sample in <({double progress, double expected})>[
        (progress: 0.0, expected: 1.0),
        (progress: 0.5, expected: 1.0),
        (progress: 0.65, expected: 1.0),
        // fraction = (0.15/0.35) = 3/7; opacity = 1 - 3/7
        (progress: 0.8, expected: 4 / 7),
        (progress: 1.0, expected: 0.0),
      ]) {
        ctrl.value = sample.progress;
        await tester.pump();
        expect(
          heroOpacityWidget().opacity,
          closeTo(sample.expected, 1e-9),
          reason: 'progress=${sample.progress}',
        );
      }
    },
  );

  testWidgets(
    'hero opacity mirrors the crossfade window to the start of the flight '
    '(reverseHandoff: true)',
    (tester) async {
      final ctrl = AnimationController(vsync: const TestVSync());
      addTearDown(ctrl.dispose);
      const heroKey = Key('hero-media-opacity-reverse');
      ctrl.value = 0.0;
      await tester.pumpWidget(
        _host(
          PostPageZoomTransition(
            progress: ctrl,
            tileRect: tileRect,
            slotRect: slotRect,
            mediaAspect: mediaAspect,
            tileRadius: 4,
            slotRadius: 0,
            reverseHandoff: true,
            chromeChild: const SizedBox.expand(),
            heroMediaChild: const ColoredBox(
              key: heroKey,
              color: Color(0xFF00FF00),
            ),
          ),
        ),
      );

      Opacity heroOpacityWidget() => tester.widget<Opacity>(
        find.ancestor(of: find.byKey(heroKey), matching: find.byType(Opacity)),
      );

      // Derived by hand from _heroOpacity with reverseHandoff: true:
      // effective = 1 - t; rampStart = 0.65; fraction =
      // ((effective - 0.65) / 0.35).clamp(0, 1); opacity = 1 - fraction.
      // This mirrors the forward ramp to the START of the flight: 0.0 at
      // t=0, rising linearly to 1.0 by t=0.35, flat at 1.0 afterwards.
      for (final sample in <({double progress, double expected})>[
        (progress: 0.0, expected: 0.0),
        // effective=0.85; fraction=(0.2/0.35)=4/7
        (progress: 0.15, expected: 3 / 7),
        (progress: 0.35, expected: 1.0),
        (progress: 0.7, expected: 1.0),
        (progress: 1.0, expected: 1.0),
      ]) {
        ctrl.value = sample.progress;
        await tester.pump();
        expect(
          heroOpacityWidget().opacity,
          closeTo(sample.expected, 1e-9),
          reason: 'progress=${sample.progress}',
        );
      }
    },
  );
}
