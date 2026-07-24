import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/push_notification_service.dart';

void main() {
  group('shouldRenderDataMessage', () {
    test('data-only sosial → render', () {
      expect(PushNotificationService.shouldRenderDataMessage(
        hasNotificationPayload: false, hasDataTitle: true), isTrue);
    });
    test('notification-message (order/promo) → JANGAN render (OS gambar)', () {
      expect(PushNotificationService.shouldRenderDataMessage(
        hasNotificationPayload: true, hasDataTitle: true), isFalse);
    });
    test('data tanpa title (silent/data lain) → jangan render', () {
      expect(PushNotificationService.shouldRenderDataMessage(
        hasNotificationPayload: false, hasDataTitle: false), isFalse);
    });
  });
  group('notificationIdFromTag', () {
    test('deterministik + non-negatif', () {
      final a = PushNotificationService.notificationIdFromTag('feed-tagged-p1-u1', 7);
      final b = PushNotificationService.notificationIdFromTag('feed-tagged-p1-u1', 9);
      expect(a, b);
      expect(a >= 0, isTrue);
    });
    test('null tag → fallback', () {
      expect(PushNotificationService.notificationIdFromTag(null, 42), 42);
    });
  });
}
