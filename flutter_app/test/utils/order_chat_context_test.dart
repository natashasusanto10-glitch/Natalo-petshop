import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/utils/order_chat_context.dart';

void main() {
  test('buildOrderChatContext retains the selected old order', () {
    final oldOrder = OrderSummary(
      id: 'old-order',
      orderNumber: 'ORD-OLD-20250101',
      status: 'COMPLETED',
      paymentStatus: 'PAID',
      total: 932000,
      itemCountFromApi: 1,
      createdAt: DateTime(2025, 1, 1),
    );
    final latestOrder = OrderSummary(
      id: 'latest-order',
      orderNumber: 'ORD-LATEST-20260716',
      status: 'PROCESSING',
      paymentStatus: 'PAID',
      total: 150000,
      itemCountFromApi: 2,
      createdAt: DateTime(2026, 7, 16),
    );

    final context = buildOrderChatContext(oldOrder);
    final order = context['order'] as Map<String, dynamic>;

    expect(context['type'], 'order');
    expect(context['orderNumber'], oldOrder.orderNumber);
    expect(order['orderNumber'], oldOrder.orderNumber);
    expect(order['orderNumber'], isNot(latestOrder.orderNumber));
    expect(order['status'], 'COMPLETED');
    expect(order['total'], 932000);
    expect(order['itemCount'], 1);
    expect(order['createdAt'], oldOrder.createdAt.millisecondsSinceEpoch);
  });
}
