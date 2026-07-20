import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_transition.dart';

Widget _host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
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
          tileRect: const Rect.fromLTWH(30, 100, 120, 120),
          slotRect: const Rect.fromLTWH(0, 80, 400, 500),
          mediaAspect: 4 / 5,
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

  testWidgets('hero media on-screen rect covers the tile at progress 0 and '
      'the slot at progress 1', (tester) async {
    final ctrl = AnimationController(vsync: const TestVSync());
    addTearDown(ctrl.dispose);
    const heroKey = Key('hero-media');
    Widget build() => _host(
      PostPageZoomTransition(
        progress: ctrl,
        tileRect: const Rect.fromLTWH(30, 100, 120, 120),
        slotRect: const Rect.fromLTWH(0, 80, 400, 500),
        mediaAspect: 4 / 5,
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
    // The clipped hero fully covers the tile (its visible rect contains it).
    final r0 = tester.getRect(find.byKey(heroKey));
    expect(r0.left, lessThanOrEqualTo(30.5));
    expect(r0.right, greaterThanOrEqualTo(149.5));
  });
}
