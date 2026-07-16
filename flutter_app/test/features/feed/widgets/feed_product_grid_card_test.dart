import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_links_sheet.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 180, child: child)));

void main() {
  testWidgets('promo product: strike + red price + -N% badge', (tester) async {
    final p = FeedProductLink(
      id: '1', slug: 'happy-cat', name: 'Happy Cat Sensitive',
      price: 55000, discountPrice: 44500, stock: 10,
      avgRating: 4.8, soldCount: 120,
    );
    await tester.pumpWidget(_host(
      FeedProductGridCard(product: p, onTap: () {}, onAddToCart: () {}),
    ));
    await tester.pump();
    expect(find.text('-19%'), findsOneWidget);
    expect(find.text('Rp44.500'), findsOneWidget);
    expect(find.text('Rp55.000'), findsOneWidget); // strike original
    expect(find.textContaining('terjual'), findsOneWidget);
  });

  testWidgets('non-promo product: plain price, no badge, no rating row',
      (tester) async {
    final p = FeedProductLink(
      id: '2', slug: 'plain', name: 'Plain Product', price: 30000, stock: 5,
    );
    await tester.pumpWidget(_host(
      FeedProductGridCard(product: p, onTap: () {}, onAddToCart: () {}),
    ));
    await tester.pump();
    expect(find.text('Rp30.000'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('terjual'), findsNothing);
  });

  testWidgets('cart button invokes onAddToCart; card invokes onTap',
      (tester) async {
    var added = false, opened = false;
    final p = FeedProductLink(
      id: '3', slug: 'x', name: 'X', price: 10000, stock: 5,
    );
    await tester.pumpWidget(_host(
      FeedProductGridCard(
        product: p, onTap: () => opened = true, onAddToCart: () => added = true),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.shopping_cart_outlined));
    expect(added, isTrue);
    await tester.tap(find.text('X'));
    expect(opened, isTrue);
  });
}
