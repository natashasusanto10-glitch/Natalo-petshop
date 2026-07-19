import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/push_notification_service.dart';

void main() {
  test('push init state starts idle (not latched on construction)', () {
    expect(pushNotificationService.initState, PushInitState.idle);
  });

  group('PushNotificationService.shouldDisplayLocally', () {
    test('foreground notification with category enabled => display', () {
      expect(
        PushNotificationService.shouldDisplayLocally(
          isForeground: true,
          hasNotificationPayload: true,
          categoryEnabled: true,
        ),
        isTrue,
      );
    });

    test('background never re-displays (OS already rendered it)', () {
      expect(
        PushNotificationService.shouldDisplayLocally(
          isForeground: false,
          hasNotificationPayload: true,
          categoryEnabled: true,
        ),
        isFalse,
      );
    });

    test('disabled category suppresses display', () {
      expect(
        PushNotificationService.shouldDisplayLocally(
          isForeground: true,
          hasNotificationPayload: true,
          categoryEnabled: false,
        ),
        isFalse,
      );
    });

    test('foreground data-only (no notification payload) => no display', () {
      expect(
        PushNotificationService.shouldDisplayLocally(
          isForeground: true,
          hasNotificationPayload: false,
          categoryEnabled: true,
        ),
        isFalse,
      );
    });
  });
}
