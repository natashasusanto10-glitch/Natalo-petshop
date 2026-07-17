import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';

void main() {
  testWidgets(
      'compact media respects safe area and tracks drawer extent one-to-one',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final extent = ValueNotifier<double>(0.60);
    final mediaKey = GlobalKey();
    addTearDown(extent.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              FeedCommentMediaFrame(
                open: true,
                extentListenable: extent,
                dragOffsetPx: 0,
                keyboardInsetPx: 0,
                compactTopInsetPx: 44,
                screenSize: const Size(400, 900),
                child: ColoredBox(key: mediaKey, color: Colors.orange),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialRect = tester.getRect(find.byKey(mediaKey));
    expect(initialRect.top, closeTo(44, 1));
    expect(initialRect.bottom, closeTo(360, 1));

    extent.value = 0.75;
    await tester.pump();

    final draggedRect = tester.getRect(find.byKey(mediaKey));
    expect(draggedRect.top, closeTo(44, 1));
    expect(draggedRect.bottom, closeTo(225, 1));
  });

  testWidgets('media frame uses easeOutCubic for both open and close',
      (tester) async {
    for (final open in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                FeedCommentMediaFrame(
                  open: open,
                  extentListenable: ValueNotifier<double>(0.60),
                  dragOffsetPx: 0,
                  keyboardInsetPx: 0,
                  screenSize: const Size(400, 900),
                  child: const ColoredBox(color: Colors.orange),
                ),
              ],
            ),
          ),
        ),
      );
      final anim = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>),
      );
      expect(anim.curve, Curves.easeOutCubic,
          reason: 'open=$open harus easeOutCubic');
    }
  });
}
