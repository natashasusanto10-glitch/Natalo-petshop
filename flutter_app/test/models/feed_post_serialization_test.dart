import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

void main() {
  test('FeedProductLink round-trips every field via toJson/fromJson', () {
    const link = FeedProductLink(
      id: 'p1',
      slug: 'happy-cat',
      name: 'Happy Cat',
      imageUrl: 'https://example.com/y.jpg',
      price: 55000,
      discountPrice: 44500,
      promoPrice: 40000,
      discountSource: 'FLASH_SALE',
      stock: 7,
      weightGram: 300,
      hasVariants: true,
      isActive: true,
      avgRating: 4.8,
      reviewCount: 12,
      soldCount: 120,
    );

    final r = FeedProductLink.fromJson(link.toJson());

    expect(r.id, 'p1');
    expect(r.slug, 'happy-cat');
    expect(r.name, 'Happy Cat');
    expect(r.imageUrl, 'https://example.com/y.jpg');
    expect(r.price, 55000);
    expect(r.discountPrice, 44500);
    expect(r.promoPrice, 40000);
    expect(r.discountSource, 'FLASH_SALE');
    expect(r.stock, 7);
    expect(r.weightGram, 300);
    expect(r.hasVariants, true);
    expect(r.isActive, true);
    expect(r.avgRating, 4.8);
    expect(r.reviewCount, 12);
    expect(r.soldCount, 120);
    // derived getters recompute correctly from the round-tripped fields
    expect(r.hasActiveDiscount, true);
    expect(r.isFlashSale, true);
  });

  test('FeedPost.toJson serializes taggedProducts losslessly (cache round-trip)',
      () {
    final post = FeedPost.fromJson({
      'id': 'post-1',
      // taggedProducts distinct from products, carrying discount + rating +
      // variant flags that the old toJson dropped.
      'taggedProducts': [
        {
          'id': 't1',
          'slug': 'a',
          'name': 'Produk A',
          'price': 55000,
          'discountPrice': 44500,
          'hasVariants': true,
          'avgRating': 4.5,
          'soldCount': 80,
        },
      ],
      'products': [
        {'id': 'x', 'slug': 'x', 'name': 'X', 'price': 10000},
      ],
    });

    expect(post.taggedProducts.single.discountPrice, 44500);

    final round = FeedPost.fromJson(post.toJson());
    final t = round.taggedProducts.single;

    // Discount / rating / variant survive the round-trip (previously lost).
    expect(t.id, 't1');
    expect(t.discountPrice, 44500);
    expect(t.hasVariants, true);
    expect(t.avgRating, 4.5);
    expect(t.soldCount, 80);
    // taggedProducts stays its own list, not collapsed onto `products`.
    expect(round.taggedProducts.single.id, 't1');
    expect(round.products.single.id, 'x');
  });
}
