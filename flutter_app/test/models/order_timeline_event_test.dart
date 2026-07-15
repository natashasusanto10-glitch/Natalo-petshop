import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';

void main() {
  group('OrderSummary timeline parsing', () {
    test('normalizes pickup aliases and sorts valid timeline events', () {
      final order = OrderSummary.fromJson({
        'id': 'order-1',
        'orderNumber': 'ORD-1',
        'status': 'picked-up',
        'paymentStatus': 'PAID',
        'createdAt': '2026-07-14T01:00:00.000Z',
        'ready_for_pickup_at': '2026-07-14T03:00:00.000Z',
        'pickedUpAt': '2026-07-14T04:00:00.000Z',
        'timelineEvents': [
          {
            'event': 'READY_TO_PICKUP',
            'occurredAt': '2026-07-14T03:00:00.000Z',
            'actorType': 'ADMIN',
            'metadata': {'location': 'Natalo Medan'},
          },
          {'status': 'processing', 'occurred_at': '2026-07-14T02:00:00.000Z'},
          {'status': 'DELIVERED'},
        ],
      });

      expect(order.status, 'DELIVERED');
      expect(order.readyForPickupAt, DateTime.utc(2026, 7, 14, 3));
      expect(order.pickedUpAt, DateTime.utc(2026, 7, 14, 4));
      expect(order.timelineEvents, hasLength(2));
      expect(order.timelineEvents.first.status, 'PROCESSING');
      expect(order.timelineEvents.last.status, 'READY_FOR_PICKUP');
      expect(order.timelineEvents.last.actorType, 'ADMIN');
      expect(order.timelineEvents.last.metadata['location'], 'Natalo Medan');
    });

    test('normalizes legacy order statuses', () {
      expect(normalizeOrderStatus('waiting payment'), 'PENDING');
      expect(normalizeOrderStatus('READY_TO_PICKUP'), 'READY_FOR_PICKUP');
      expect(normalizeOrderStatus('COMPLETED'), 'DELIVERED');
      expect(normalizeOrderStatus('shipped'), 'SHIPPED');
    });
  });
}
