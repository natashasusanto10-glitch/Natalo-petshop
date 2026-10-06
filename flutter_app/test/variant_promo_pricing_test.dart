import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/cart_item.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';

Product product({DateTime? endsAt}) => Product(
      id: 'majes',
      slug: 'majes',
      title: 'Vita Belly / Velvet Fur',
      category: '',
      brand: 'Majes',
      imageUrl: '',
      price: 125000,
      discountPrice: 112500,
      rating: 0,
      reviewCount: 0,
      stock: 20,
      description: '',
      hasVariants: true,
      flashSaleEndsAt: endsAt,
    );

void main() {
  test('variant Promo Toko works without a Flash Sale countdown', () {
    final variant = ProductVariant.fromJson({
      'id': 'vita-belly',
      'price': 125000,
      'discountPrice': 112500,
      'stock': 20,
    });
    final item = CartItem(
        product: product(),
        variant: variant,
        quantity: 2,
        unitPrice: effectiveCartVariantPrice(product(), variant));
    expect(item.unitPrice, 112500);
    expect(item.originalPrice, 125000);
    expect(item.lineTotal, 225000);
    final restored = CartItem.fromJson(item.toJson());
    expect(restored.unitPrice, 112500);
    expect(restored.originalPrice, 125000);
    expect(restored.variant!.discountPrice, 112500);
  });

  test('explicitly undiscounted variant does not inherit another promotion',
      () {
    final variant = ProductVariant.fromJson({
      'id': 'velvet-fur',
      'price': 125000,
      'discountPrice': null,
      'stock': 20,
    });
    final parent = product(endsAt: DateTime.now().add(const Duration(days: 1)));
    expect(effectiveCartVariantPrice(parent, variant), 125000);
    expect(ProductVariant.fromJson(variant.toJson()).hasResolvedPrice, isTrue);
  });
}
