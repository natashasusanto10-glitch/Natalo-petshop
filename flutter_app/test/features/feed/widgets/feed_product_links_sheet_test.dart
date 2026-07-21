import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_links_sheet.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

FeedProductLink _link(String name) => FeedProductLink(
      id: name, slug: name, name: name, price: 10000, stock: 5);

void main() {
  testWidgets('opens grid, fires onOpened, cards call callbacks',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final products = [_link('A'), _link('B'), _link('C')];
    FeedProductLink? added;
    FeedProductLink? opened;
    var openedFired = false, closedFired = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showFeedProductLinksSheet(
                context,
                products: products,
                onOpenProduct: (l) => opened = l,
                onAddToCart: (l) => added = l,
                onOpened: () => openedFired = true,
                onClosed: () => closedFired = true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pump(); // start sheet route
    await tester.pump(const Duration(milliseconds: 400)); // settle-ish, no shimmer settle
    expect(openedFired, isTrue);
    expect(find.text('Produk'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // count, terpisah dari label
    expect(find.byType(FeedProductRowCard), findsNWidgets(3));

    await tester.tap(find.byIcon(Icons.shopping_cart_outlined).first);
    expect(added?.name, 'A');

    await tester.tap(find.text('A'));
    await tester.pump();
    expect(opened?.name, 'A'); // sheet popped + onOpenProduct invoked
    await tester.pump(const Duration(milliseconds: 400));
    expect(closedFired, isTrue);
  });

  testWidgets('1 produk pakai FeedProductSingleCard, header "Produk di video"',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showFeedProductLinksSheet(
                context,
                products: [_link('Solo')],
                onOpenProduct: (_) {},
                onAddToCart: (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Produk di video'), findsOneWidget);
    expect(find.byType(FeedProductSingleCard), findsOneWidget);
    expect(find.byType(FeedProductRowCard), findsNothing);
  });

  // NB: drag-to-dismiss (tarik turun menutup sheet) mengandalkan `enableDrag`
  // bawaan showModalBottomSheet — perilaku framework, sama seperti sheet lain
  // di app (added_to_cart_sheet dll). Simulasi gesture pembuangan modal +
  // inner-scrollable tidak andal di widget test, jadi tidak diuji unit di sini;
  // WAJIB device-verify.
}
