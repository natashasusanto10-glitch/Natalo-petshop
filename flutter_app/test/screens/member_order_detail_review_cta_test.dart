import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_order_detail_screen.dart';

OrderSummary _completedOrder({required bool reviewed}) {
  return OrderSummary(
    id: 'order-1',
    orderNumber: 'ORD-UX-001',
    status: 'DELIVERED',
    paymentStatus: 'PAID',
    createdAt: DateTime(2026, 7, 15, 10),
    total: 125000,
    items: [
      OrderItemSummary(
        id: 'item-1',
        productId: 'product-1',
        name: 'Makanan Kucing Natalo',
        price: 125000,
        quantity: 1,
        reviewed: reviewed,
      ),
    ],
  );
}

Widget _host(OrderSummary order) {
  return MaterialApp(home: MemberOrderDetailScreen(order: order));
}

void main() {
  testWidgets(
      'completed order with pending review shows review and reorder CTA',
      (tester) async {
    await tester.pumpWidget(_host(_completedOrder(reviewed: false)));
    await tester.pump();

    expect(find.byKey(const ValueKey('order-review-cta')), findsOneWidget);
    expect(find.text('Beri Ulasan'), findsOneWidget);
    expect(find.byKey(const ValueKey('order-reorder-cta')), findsOneWidget);
    expect(find.text('Beli Lagi'), findsOneWidget);
  });

  testWidgets('completed fully reviewed order only shows reorder CTA',
      (tester) async {
    await tester.pumpWidget(_host(_completedOrder(reviewed: true)));
    await tester.pump();

    expect(find.byKey(const ValueKey('order-review-cta')), findsNothing);
    expect(find.byKey(const ValueKey('order-reorder-cta')), findsOneWidget);
    expect(find.text('Beli Lagi'), findsOneWidget);
  });
}
