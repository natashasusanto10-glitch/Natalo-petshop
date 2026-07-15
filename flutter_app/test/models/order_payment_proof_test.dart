import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';

void main() {
  test('OrderSummary parses payment proof audit state', () {
    final order = OrderSummary.fromJson({
      'id': 'order-1',
      'orderNumber': 'ORD-1',
      'status': 'PENDING',
      'paymentStatus': 'UNPAID',
      'paymentProofUrl': 'https://cdn.example/proof.jpg',
      'paymentProofStatus': 'PENDING_REVIEW',
      'paymentProofVersion': 2,
      'paymentProofUploadedAt': '2026-07-15T03:30:00.000Z',
      'createdAt': '2026-07-15T03:00:00.000Z',
    });

    expect(order.paymentProofStatus, 'PENDING_REVIEW');
    expect(order.paymentProofVersion, 2);
    expect(order.paymentProofUploadedAt, DateTime.utc(2026, 7, 15, 3, 30));
  });
}
