import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Mirror of lib/feed/notification-center.ts + lib/apns.ts + lib/fcm.ts
// (Wave 4 — push rich content).
//
// Categories from web (web mirror in deriveNotificationCategory):
//   - "feed_review"  → admin moderation: buttons "Lihat" + "Buang"
//   - "feed_result"  → user post approved/rejected: button "Lihat"
//
// On iOS, the Notification Service Extension (Swift) already attaches
// the rich image — this Dart code only handles foreground delivery
// and action button taps. Reuse the NSE from:
//   ios/App/NotificationServiceExtension/  (in natalo-petshop-app/)
//
// On Android, FCM `notification.imageUrl` triggers BigPictureStyle
// automatically — no extra setup needed beyond Firebase config.

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  final _local = FlutterLocalNotificationsPlugin();
  late final FirebaseMessaging _fcm;

  /// Tap handler — wire to your router (e.g. push to /feed/<id> route).
  void Function(String? url, String? actionId)? onNotificationTap;

  Future<void> init() async {
    _fcm = FirebaseMessaging.instance;

    // 1. Permissions (iOS + Android 13+)
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Local notifications init — needed to render foreground messages
    // with action buttons.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          'feed_review',
          actions: [
            DarwinNotificationAction.plain(
              'open',
              'Lihat',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              'reject',
              'Buang',
              options: {DarwinNotificationActionOption.destructive},
            ),
          ],
        ),
        DarwinNotificationCategory(
          'feed_result',
          actions: [
            DarwinNotificationAction.plain(
              'open',
              'Lihat',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    );
    await _local.initialize(
      InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // 3. Android channels (must match category IDs used in payload)
    if (Platform.isAndroid) {
      final android =
          _local.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'feed_review',
        'Moderasi Feed',
        description: 'Notifikasi review post yang menunggu moderasi admin',
        importance: Importance.high,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'feed_result',
        'Hasil Post Feed',
        description: 'Notifikasi hasil approval post yang kamu unggah',
        importance: Importance.high,
      ));
    }

    // 4. Foreground message handler — FCM by default suppresses banner
    // when app is foregrounded; we re-render via flutter_local_notifications.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 5. Background tap handler — when user taps a push that was rendered
    // by the OS while app was suspended.
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final url = msg.data['url'] as String?;
      onNotificationTap?.call(url, null);
    });

    // 6. App launched from terminated state via notification tap.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      final url = initial.data['url'] as String?;
      // Defer to next event loop tick so the router has a chance to mount.
      Future.microtask(() => onNotificationTap?.call(url, null));
    }
  }

  Future<String?> getDeviceToken() async {
    return _fcm.getToken();
  }

  Future<void> _onForegroundMessage(RemoteMessage msg) async {
    final notif = msg.notification;
    if (notif == null) return;

    final category = msg.data['category'] as String?; // feed_review | feed_result
    final url = msg.data['url'] as String?;
    final imageUrl = msg.data['imageUrl'] as String? ??
        notif.android?.imageUrl ??
        notif.apple?.imageUrl;

    final androidDetails = AndroidNotificationDetails(
      category ?? 'feed_default',
      _channelName(category),
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: imageUrl != null
          ? BigPictureStyleInformation(
              FilePathAndroidBitmap(imageUrl), // TODO: download to file first
              contentTitle: notif.title,
              summaryText: notif.body,
            )
          : null,
    );
    final darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: category,
      // Rich image on iOS is handled by NSE — Dart layer doesn't attach it.
    );

    await _local.show(
      msg.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(android: androidDetails, iOS: darwinDetails),
      payload: url,
    );
  }

  void _onLocalTap(NotificationResponse response) {
    onNotificationTap?.call(response.payload, response.actionId);
  }

  String _channelName(String? category) {
    switch (category) {
      case 'feed_review':
        return 'Moderasi Feed';
      case 'feed_result':
        return 'Hasil Post Feed';
      default:
        return 'Feed';
    }
  }
}
