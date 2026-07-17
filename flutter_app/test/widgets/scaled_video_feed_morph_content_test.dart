import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/scaled_video_feed_route.dart';

void main() {
  const screen = Size(400, 900);
  final childKey = GlobalKey();

  Widget harness({required Size window}) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: window.width,
              height: window.height,
              child: ScaledVideoFeedMorphContent(
                screenSize: screen,
                imageUrl: 'x',
                borderRadius: 8,
                opacity: 1,
                imageBuilder: (_, __) =>
                    SizedBox(key: childKey, width: screen.width, height: screen.height),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('media child stays screen-sized in a small window (no stretch)',
      (tester) async {
    await tester.pumpWidget(harness(window: const Size(120, 150)));
    // OverflowBox memaksa child ke ukuran layar penuh walau jendela kecil.
    expect(tester.getSize(find.byKey(childKey)), screen);
  });

  testWidgets('media child stays screen-sized in a large window (no stretch)',
      (tester) async {
    await tester.pumpWidget(harness(window: const Size(400, 900)));
    expect(tester.getSize(find.byKey(childKey)), screen);
  });

  testWidgets('opacity is applied to the morph content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: 120,
                height: 150,
                child: ScaledVideoFeedMorphContent(
                  screenSize: screen,
                  imageUrl: 'x',
                  borderRadius: 8,
                  opacity: 0.3,
                  imageBuilder: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(ScaledVideoFeedMorphContent),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 0.3);
  });
}
