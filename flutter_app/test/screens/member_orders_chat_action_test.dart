import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_orders_screen.dart';

void main() {
  testWidgets('openOrderChat routes an old selected order into chat',
      (tester) async {
    final oldCompletedOrder = OrderSummary(
      id: 'old-order',
      orderNumber: 'ORD-OLD-20250101',
      status: 'COMPLETED',
      paymentStatus: 'PAID',
      total: 932000,
      itemCountFromApi: 1,
      createdAt: DateTime(2025, 1, 1),
    );
    RouteSettings? capturedSettings;

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          capturedSettings = settings;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('Chat NLCATTER')),
          );
        },
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => openOrderChat(context, oldCompletedOrder),
            child: const Text('Hubungi admin'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Hubungi admin'));
    await tester.pumpAndSettle();

    expect(find.text('Chat NLCATTER'), findsOneWidget);
    expect(capturedSettings?.name, '/chat');
    final context = capturedSettings!.arguments! as Map<String, dynamic>;
    expect(context['orderNumber'], oldCompletedOrder.orderNumber);
    expect((context['order'] as Map)['status'], 'COMPLETED');
  });
}
