import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_post_shared_widgets.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

FeedProductLink _link(String name, {required int price, int? discountPrice}) =>
    FeedProductLink(
      id: name, slug: name, name: name, price: price,
      discountPrice: discountPrice, stock: 10,
    );

void main() {
  testWidgets('builds pill for featured index with count + max discount',
      (tester) async {
    final products = [
      _link('A', price: 55000, discountPrice: 44500), // 19%
      _link('B', price: 100000, discountPrice: 70000), // 30%
      _link('C', price: 20000),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: feedProductPillFor(products, 1, onTap: () {}),
      ),
    ));
    await tester.pump();
    expect(find.text('B'), findsOneWidget); // featuredIndex 1
    expect(find.text('·3'), findsOneWidget); // count = list length
    expect(find.text('Diskon s/d 30%'), findsOneWidget); // max across list
  });

  testWidgets('index wraps modulo length', (tester) async {
    final products = [_link('A', price: 1000), _link('B', price: 1000)];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: feedProductPillFor(products, 3, onTap: () {})),
    ));
    await tester.pump();
    expect(find.text('B'), findsOneWidget); // 3 % 2 == 1 -> 'B'
  });
}
