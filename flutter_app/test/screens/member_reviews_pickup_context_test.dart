import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/review.dart';
import 'package:natalo_petshop_flutter/screens/member_reviews_screen.dart';

const _pickupItem = ReviewableItem(
  orderItemId: 'item-1',
  productId: 'product-1',
  productName: 'Magic Bites',
  quantity: 1,
  orderNumber: 'ORD-PICKUP-1',
);

void main() {
  test('manual review selection inherits pickup context from scoped order', () {
    final result = resolveReviewPickupContext(
      item: _pickupItem,
      scopedOrderNumber: 'ORD-PICKUP-1',
      scopedIsSelfPickup: true,
    );

    expect(result, isTrue);
  });

  test('pickup context is not leaked to an item from another order', () {
    final result = resolveReviewPickupContext(
      item: _pickupItem,
      scopedOrderNumber: 'ORD-OTHER',
      scopedIsSelfPickup: true,
    );

    expect(result, isNull);
  });

  test('explicit fulfillment context wins over inherited context', () {
    final result = resolveReviewPickupContext(
      item: _pickupItem,
      scopedOrderNumber: 'ORD-PICKUP-1',
      scopedIsSelfPickup: true,
      explicitIsSelfPickup: false,
    );

    expect(result, isFalse);
  });
}
