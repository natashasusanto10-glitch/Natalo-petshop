import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_post_shared_widgets.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

FeedProductLink _link({required int price, int? discountPrice}) => FeedProductLink(
      id: 'p$price',
      slug: 'p$price',
      name: 'Produk $price',
      price: price,
      discountPrice: discountPrice,
      stock: 10,
    );

void main() {
  test('empty list -> 0', () {
    expect(feedMaxDiscountPercent(const []), 0);
  });

  test('no promo -> 0', () {
    expect(
      feedMaxDiscountPercent([_link(price: 50000), _link(price: 20000)]),
      0,
    );
  });

  test('mixed -> highest discount percent', () {
    // 55000->44500 = 19%, 100000->70000 = 30%, plus one non-promo
    final products = [
      _link(price: 55000, discountPrice: 44500),
      _link(price: 100000, discountPrice: 70000),
      _link(price: 20000),
    ];
    expect(feedMaxDiscountPercent(products), 30);
  });
}
