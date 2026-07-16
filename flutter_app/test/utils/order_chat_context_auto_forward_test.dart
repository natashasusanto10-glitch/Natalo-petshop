import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/order_chat_context.dart';

void main() {
  test('order contexts are automatically forwarded when still pending', () {
    expect(
      shouldAutoForwardOrderContext(
        context: const {'type': 'order', 'orderNumber': 'ORD-OLD'},
        contextAlreadySent: false,
      ),
      isTrue,
    );
  });

  test('product and already forwarded contexts are not auto-forwarded', () {
    expect(
      shouldAutoForwardOrderContext(
        context: const {'type': 'product', 'id': 'product-1'},
        contextAlreadySent: false,
      ),
      isFalse,
    );
    expect(
      shouldAutoForwardOrderContext(
        context: const {'type': 'order', 'orderNumber': 'ORD-OLD'},
        contextAlreadySent: true,
      ),
      isFalse,
    );
  });
}
