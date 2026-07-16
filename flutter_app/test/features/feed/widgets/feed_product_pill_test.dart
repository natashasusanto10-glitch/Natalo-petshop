import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_pill.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('renders title, count, and discount badge', (tester) async {
    await tester.pumpWidget(_host(FeedProductPill(
      title: 'Happy Cat Sensitive Skin & Coat',
      count: 5,
      maxDiscountPercent: 20,
      onTap: () {},
    )));
    await tester.pump();
    expect(find.text('Happy Cat Sensitive Skin & Coat'), findsOneWidget);
    expect(find.text('·5'), findsOneWidget);
    expect(find.text('Diskon s/d 20%'), findsOneWidget);
  });

  testWidgets('no badge when maxDiscountPercent is 0', (tester) async {
    await tester.pumpWidget(_host(FeedProductPill(
      title: 'Produk', count: 1, maxDiscountPercent: 0, onTap: () {},
    )));
    await tester.pump();
    expect(find.textContaining('Diskon'), findsNothing);
  });

  testWidgets('tap invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(FeedProductPill(
      title: 'Produk', count: 2, onTap: () => tapped = true,
    )));
    await tester.pump();
    await tester.tap(find.text('Produk'));
    expect(tapped, isTrue);
  });
}
