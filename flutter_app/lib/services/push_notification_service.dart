import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'deep_link_service.dart';

/// Push notification service via Firebase Cloud Messaging (FCM).
///
/// PWA Natalo punya Web Push subscription, tapi WebView Capacitor tidak
/// bisa register sebagai Web Push receiver dengan reliable. Flutter native
/// register via FCM (Android) / APNs (iOS) — push lebih reliable, hemat
/// battery, dan punya quick-action butons di notification tray.
///
/// **SETUP REQUIRED**: lihat `FIREBASE_SETUP.md` di root project untuk
/// langkah konfigurasi Firebase project + download `google-services.json`.
/// Tanpa file itu, service ini gracefully no-op (try/catch around init).
class PushNotificationService {
  static const _channelId = 'natalo_default';
  static const _channelName = 'Notifikasi Natalo';
  static const _channelDescription =
      'Update pesanan, promo, dan pengumuman dari Natalo Petshop.';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _currentToken;
  GlobalKey<NavigatorState>? _navigatorKey;

  /// Initialize Firebase + register token handlers. Idempotent.
  /// Call ini di main() setelah memberStore + cartStore di-init.
  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    _navigatorKey = navigatorKey;
    try {
      // 1) Initialize Firebase. Akan auto-load google-services.json di
      //    Android, GoogleService-Info.plist di iOS. Throw kalau missing.
      await Firebase.initializeApp();

      // 2) Request notification permission (iOS + Android 13+).
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (kDebugMode) {
          debugPrint('[push] Notification permission denied.');
        }
        _initialized = true;
        return;
      }

      // 3) Setup local notifications untuk display foreground messages.
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            _handleDeepLink(payload);
          }
        },
      );

      // Buat notification channel Android (wajib untuk Android 8+).
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: _channelDescription,
              importance: Importance.high,
            ),
          );

      // 4) Get FCM token & listen to refresh.
      _currentToken = await messaging.getToken();
      if (kDebugMode && _currentToken != null) {
        debugPrint('[push] FCM token: ${_currentToken!.substring(0, 20)}...');
      }
      messaging.onTokenRefresh.listen(_onTokenRefresh);

      // 5) Foreground handler — saat app terbuka, FCM tidak auto-display.
      //    Kita render lewat flutter_local_notifications.
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // 6) Notification tap saat app background → terminated/swiped-away.
      //    Cold start: getInitialMessage. Warm: onMessageOpenedApp.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        // Delay supaya navigator ready setelah app launch.
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleMessage(initial);
        });
      }
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

      _initialized = true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[push] Init failed (kemungkinan google-services.json belum ada): $error',
        );
      }
      _initialized = true;
      // Silent fail — push notif tidak available, tapi app tetap jalan.
    }
  }

  /// Register FCM token ke server (PWA `/api/push/subscribe-fcm`).
  /// Call setelah user login sukses.
  Future<void> registerWithServer() async {
    final token = _currentToken;
    if (token == null || token.isEmpty) return;
    try {
      await apiClient.postJson(
        '/api/push/subscribe-fcm',
        body: {'token': token},
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[push] Register token failed: $error');
      }
    }
  }

  /// Unregister token dari server saat logout. Idempotent.
  Future<void> unregisterFromServer() async {
    final token = _currentToken;
    if (token == null || token.isEmpty) return;
    try {
      await apiClient.deleteJson(
        '/api/push/subscribe-fcm',
        body: {'token': token},
      );
    } catch (_) {}
  }

  void _onTokenRefresh(String token) {
    _currentToken = token;
    // Auto re-register dengan server (server akan upsert).
    registerWithServer();
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null) return;
    // Filter berdasar user notification preferences. Backend bisa kirim
    // `data.category` (order|promo|voucher|newsletter) — kalau category
    // off di settings, skip display. Notif keamanan account selalu lewat.
    final category = message.data['category']?.toString();
    if (category != null && !await _isCategoryEnabled(category)) {
      if (kDebugMode) {
        debugPrint('[push] Notif skipped (category $category disabled)');
      }
      return;
    }
    final deepLink = message.data['deepLink'] ?? message.data['url'];

    // Sprint 2 #4 — Rich notification dengan image attachment.
    //
    // Server (lib/feed/notification-center.ts di PWA) inject imageUrl ke
    // notification payload — biasanya thumbnail post yang baru di-approve,
    // promo product image, dll. FCM RemoteMessage expose ini via 2 jalur:
    //   - Android: message.notification?.android?.imageUrl
    //   - iOS:     message.notification?.apple?.imageUrl
    //
    // Plus fallback ke message.data['imageUrl'] kalau server kirim via
    // data-only payload (rare, tapi defensive).
    final imageUrl = notif.android?.imageUrl ??
        notif.apple?.imageUrl ??
        message.data['imageUrl']?.toString();

    // Build Android style berdasarkan imageUrl ketersediaan. BigPicture
    // = preview gambar besar di expanded notification tray; iOS pakai
    // attachment via flutter_local_notifications via Notification Service
    // Extension yang Apple handle (FCM otomatis attach kalau imageUrl
    // ada di payload + notification permission granted).
    final androidStyle = (imageUrl != null && imageUrl.isNotEmpty)
        ? await _buildBigPictureStyle(imageUrl: imageUrl, body: notif.body)
        : null;

    await _localNotifications.show(
      message.hashCode,
      notif.title ?? 'Natalo Petshop',
      notif.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          styleInformation: androidStyle,
          // Large icon di samping kiri title — kalau imageUrl ada, pakai
          // sebagai icon thumbnail. FCM Android default render seperti ini.
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // iOS attachment handled by FCM automatically saat
          // mutable-content=1 + Notification Service Extension setup.
          // Tanpa NSE, text-only — degradasi graceful.
        ),
      ),
      payload: deepLink?.toString(),
    );
  }

  /// Build BigPictureStyle Android notification — download image dari URL
  /// lalu attach sebagai preview gambar besar. Fallback ke text-only style
  /// kalau download gagal (network timeout, invalid URL, dll).
  Future<StyleInformation?> _buildBigPictureStyle({
    required String imageUrl,
    String? body,
  }) async {
    try {
      // flutter_local_notifications support ByteArrayAndroidBitmap untuk
      // image dari URL via http fetch. Tapi simpler pakai DrawableResource
      // atau FilePath. Untuk URL, package menyediakan ByteArrayAndroidBitmap
      // yang accept Uint8List.
      //
      // Strategy: fetch raw bytes pakai dart:io HttpClient (no extra dep),
      // convert ke ByteArrayAndroidBitmap. Total budget ~5 detik supaya
      // notif tidak hang.
      final uri = Uri.parse(imageUrl);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        client.close();
        return null;
      }
      final builder = BytesBuilder();
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      client.close();
      final bytes = builder.takeBytes();
      return BigPictureStyleInformation(
        ByteArrayAndroidBitmap(bytes),
        contentTitle: null, // pakai title default dari show()
        summaryText: body,
        hideExpandedLargeIcon: false,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[push] BigPicture build failed: $e');
      }
      return null;
    }
  }

  void _handleMessage(RemoteMessage message) {
    final deepLink = message.data['deepLink'] ?? message.data['url'];
    if (deepLink != null) {
      _handleDeepLink(deepLink.toString());
    }
  }

  /// Cek apakah kategori notifikasi enabled di preferences.
  /// Default semua kategori = true kecuali newsletter (false).
  Future<bool> _isCategoryEnabled(String category) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('natalo_notif_pref_$category') ??
          (category != 'newsletter');
    } catch (_) {
      return true;
    }
  }

  void _handleDeepLink(String url) {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;
    // Reuse deep link service untuk parse path.
    try {
      final uri = Uri.parse(url);
      // Forward ke deep link service yang sudah ada — pattern yang sama
      // dengan tap dari WhatsApp share / native intent.
      deepLinkService.handleExternalUri(uri);
    } catch (_) {}
  }
}

final pushNotificationService = PushNotificationService();
