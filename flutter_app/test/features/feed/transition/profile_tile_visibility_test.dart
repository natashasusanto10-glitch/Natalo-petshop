import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/profile_tile_visibility.dart';

void main() {
  group('ensureProfileTileVisible', () {
    testWidgets('tile already fully visible: offset unchanged', (tester) async {
      final scrollController = ScrollController();
      final tileKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: ListView.builder(
                controller: scrollController,
                itemCount: 20,
                itemBuilder: (context, index) {
                  return SizedBox(
                    key: index == 5 ? tileKey : null,
                    height: 80,
                    child: Text('item $index'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Scroll so item 5 (top at 400, bottom 480) sits mid-viewport,
      // fully visible without needing repositioning.
      scrollController.jumpTo(50);
      await tester.pump();

      final offsetBefore = scrollController.offset;

      await ensureProfileTileVisible(tileKey.currentContext!);
      await tester.pump();

      expect(scrollController.offset, offsetBefore);
    });

    testWidgets('tile below the fold: scrolls minimum distance', (
      tester,
    ) async {
      final scrollController = ScrollController();
      final tileKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: ListView(
                controller: scrollController,
                cacheExtent: 5000,
                children: List.generate(20, (index) {
                  return SizedBox(
                    key: index == 15 ? tileKey : null,
                    height: 80,
                    child: Text('item $index'),
                  );
                }),
              ),
            ),
          ),
        ),
      );

      // Item 15 is far below the fold at scroll 0.
      expect(scrollController.offset, 0);

      await ensureProfileTileVisible(tileKey.currentContext!);
      await tester.pump();

      final renderBox = tileKey.currentContext!.findRenderObject() as RenderBox;
      final topLeft = renderBox.localToGlobal(Offset.zero);
      final bottom = topLeft.dy + renderBox.size.height;

      // The helper moves the tile the MINIMUM distance needed — its bottom
      // lands EXACTLY at (viewportExtent - bottomPadding), here 600 - 0,
      // not merely "somewhere on screen" (a one-sided bound would also pass
      // if the helper overshot, e.g. centered the tile instead).
      expect(bottom, closeTo(600, 0.5));
    });

    testWidgets(
      'tile above the fold: scrolls minimum distance, respects topPadding',
      (tester) async {
        final scrollController = ScrollController();
        final tileKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 600,
                child: ListView(
                  controller: scrollController,
                  cacheExtent: 5000,
                  children: List.generate(20, (index) {
                    return SizedBox(
                      key: index == 2 ? tileKey : null,
                      height: 80,
                      child: Text('item $index'),
                    );
                  }),
                ),
              ),
            ),
          ),
        );

        // Scroll deep so item 2 (top at 160) is above the fold.
        scrollController.jumpTo(1000);
        await tester.pump();

        const topPadding = 50.0;
        await ensureProfileTileVisible(
          tileKey.currentContext!,
          topPadding: topPadding,
        );
        await tester.pump();

        final renderBox =
            tileKey.currentContext!.findRenderObject() as RenderBox;
        final top = renderBox.localToGlobal(Offset.zero).dy;

        // The helper moves the tile the MINIMUM distance needed — its top
        // lands EXACTLY at topPadding, not merely "not above topPadding" (a
        // one-sided bound would also pass if the helper overshot, e.g.
        // centered the tile further down than necessary).
        expect(top, closeTo(topPadding, 0.5));
      },
    );

    testWidgets(
      'nested scrollables: outer scrollable offset unchanged after call',
      (tester) async {
        final outerController = ScrollController();
        final innerController = ScrollController();
        final tileKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                controller: outerController,
                child: Column(
                  children: [
                    const SizedBox(height: 300, child: Text('outer header')),
                    SizedBox(
                      height: 600,
                      child: ListView(
                        controller: innerController,
                        cacheExtent: 5000,
                        children: List.generate(20, (index) {
                          return SizedBox(
                            key: index == 15 ? tileKey : null,
                            height: 80,
                            child: Text('inner item $index'),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final outerOffsetBefore = outerController.offset;

        await ensureProfileTileVisible(tileKey.currentContext!);
        await tester.pump();

        expect(outerController.offset, outerOffsetBefore);
      },
    );
  });
}
