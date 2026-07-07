import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/deep_link_service.dart';
import 'package:natalo_petshop_flutter/services/push_notification_service.dart';

void main() {
  test('flag deep-link default false sebelum ada launch link', () {
    expect(deepLinkService.launchedFromDeepLink, isFalse);
  });
  test('flag cold push default false sebelum ada launch notif', () {
    expect(pushNotificationService.launchedFromColdPush, isFalse);
  });
}
