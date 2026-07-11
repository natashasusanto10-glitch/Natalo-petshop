import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_product_anchor_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: SizedBox(width: 260, child: child)),
      ),
    );

void main() {
  testWidgets('judul + harga + harga coret + badge diskon tampil',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedProductAnchorCard(
      title: 'Majes Magic Bites',
      priceText: 'Rp129.000',
      strikePriceText: 'Rp159.000',
      discountBadgeText: 'Diskon 19%',
    )));
    expect(find.text('Majes Magic Bites'), findsOneWidget);
    expect(find.text('Rp129.000'), findsOneWidget);
    expect(find.text('Rp159.000'), findsOneWidget);
    expect(find.text('Diskon 19%'), findsOneWidget);
  });

  testWidgets('tanpa harga coret & badge — tidak render elemen opsional',
      (tester) async {
    await tester.pumpWidget(_wrap(const FeedProductAnchorCard(
      title: 'Wild Call',
      priceText: 'Rp98.000',
    )));
    expect(find.text('Wild Call'), findsOneWidget);
    expect(find.textContaining('Diskon'), findsNothing);
  });
}
