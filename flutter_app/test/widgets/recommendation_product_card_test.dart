import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/theme/natalo_colors.dart';
import 'package:natalo_petshop_flutter/utils/formatters.dart';
import 'package:natalo_petshop_flutter/widgets/recommendation_product_card.dart';

void main() {
  testWidgets(
      'discount card renders red price, original price and variant action without overflow',
      (tester) async {
    final product = Product.fromApiJson({
      'id': 'promo',
      'name': 'Produk suplemen untuk kucing dan anjing',
      'price': 125000,
      'discountPrice': 112500,
      'stock': 10,
      'hasVariants': true,
      'soldCount': 20,
    });
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: RecommendationProductCard(
            product: product, onTap: () {}, onAddToCart: () => tapped = true),
      ),
    ))));
    final price =
        tester.widget<Text>(find.text(formatRupiah(product.finalPrice)));
    expect(price.style?.color, NataloColors.danger);
    final original =
        tester.widget<Text>(find.text(formatRupiah(product.price)));
    expect(original.style?.decoration, TextDecoration.lineThrough);
    expect(find.text('-10%'), findsOneWidget);
    await tester.tap(find.text('Pilih Varian'));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });
}
