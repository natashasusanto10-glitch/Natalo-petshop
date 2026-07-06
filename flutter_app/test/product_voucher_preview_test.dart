import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';

void main() {
  test('kind LOYALTY_CLAIM -> isLoyaltyVoucher + loyaltyPoints', () {
    final v = ProductVoucherPreview.fromJson({
      'id': 'poin-1',
      'kind': 'LOYALTY_CLAIM',
      'discountAmount': 150000,
      'minPurchase': 1500000,
      'loyaltyPoints': 200,
    });
    expect(v.isLoyaltyVoucher, isTrue);
    expect(v.loyaltyPoints, 200);
    expect(v.isShippingVoucher, isFalse);
  });

  test('type LOYALTY_POINT_CLAIM -> isLoyaltyVoucher', () {
    final v = ProductVoucherPreview.fromJson({
      'id': 'x',
      'type': 'LOYALTY_POINT_CLAIM',
    });
    expect(v.isLoyaltyVoucher, isTrue);
  });

  test('voucher diskon biasa -> bukan loyalty', () {
    final v = ProductVoucherPreview.fromJson({
      'id': 'y',
      'kind': 'PRODUCT_DISCOUNT',
      'discountAmount': 20000,
    });
    expect(v.isLoyaltyVoucher, isFalse);
    expect(v.loyaltyPoints, isNull);
  });
}
