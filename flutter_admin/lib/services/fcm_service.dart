import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/api_config.dart';
import 'api_client.dart';
import 'notification_counts.dart';

/// FCM service untuk Natalo Admin — terima push notif untuk:
///   - Order baru masuk
///   - Customer minta cancel
///   - Feed komunitas pending review
///   - Abuse flag HIGH severity
///
/// Setup wajib (lihat PUSH_SETUP.md):
///   1. Buat Firebase project + Android app (applicationId
///      `com.natalo.petshop.admin`)
///   2. Download google-services.json → drop ke
///      `flutter_admin/android/app/google-services.json`
///   3. Edit `android/build.gradle.kts` + `android/app/build.gradle.kts`
///      apply google-services plugin (lihat docs)
///   4. `flutter clean && flutter pub get && flutter run`
///
/// Tanpa google-services.json, `Firebase.initializeApp()` akan throw
/// — service ini gracefully no-op (catch + log), app tetap jalan
/// dengan badge polling sebagai fallback.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  static const _channelId = 'natalo_admin_default';
  static const _channelName = 'Notifikasi Admin';
  static const _channelDesc =
      'Update order, cancel request, feed review, abuse flag.';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _firebaseReady = false;
  String? _currentToken;
  GlobalKey<NavigatorState>? _navigatorKey;

  bool get firebaseReady => _firebaseReady;
  String? get currentToken => _currentToken;

  /// Set navigator key dari main.dart MaterialApp — dipakai untuk
  /// deep-link saat user tap notif (navigate ke order detail, dll).
  void attachNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Init Firebase + register handlers. Idempotent. Aman dipanggil
  /// tanpa google-services.json — try/catch, fallback no-op.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
      if (kDebugMode) debugPrint('[fcm] Firebase initialized');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[fcm] Firebase init skipped: $e — push notif tidak aktif. '
            'Drop google-services.json untuk aktifkan.');
      }
      return;
    }

    await _setupLocalNotifications();
    await _setupMessaging();
  }

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (resp) {
        _handleTapPayload(resp.payload);
      },
    );
    final androidImpl = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
    await androidImpl?.requestNotificationsPermission();
  }

  Future<void> _setupMessaging() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Foreground message — tampilkan via flutter_local_notifications
    // supaya konsisten visual dengan background notif.
    FirebaseMessaging.onMessage.listen((msg) async {
      await _showLocalFromRemote(msg);
      // Refresh badge counter — kemungkinan ada perubahan state.
      NotificationCounts.instance.refresh();
    });

    // Background tap (app di-resume dari background ke foreground).
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _handleNavigateFromData(msg.data);
    });

    // Cold start: app di-launch dari tap notif (state TERMINATED).
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNavigateFromData(initialMessage.data);
    }

    messaging.onTokenRefresh.listen((token) {
      _currentToken = token;
      _registerWithServer(token);
    });

    final token = await messaging.getToken();
    if (token != null) {
      _currentToken = token;
      await _registerWithServer(token);
      if (kDebugMode) {
        debugPrint('[fcm] token registered (len=${token.length})');
      }
    }
  }

  /// Dipanggil setelah login berhasil — supaya token yang sudah ada di
  /// memory di-re-register dgn session admin (kalau sebelumnya register
  /// tanpa session karena belum login).
  Future<void> registerAfterLogin() async {
    if (!_firebaseReady) return;
    final token = _currentToken ?? await FirebaseMessaging.instance.getToken();
    if (token != null) {
      _currentToken = token;
      await _registerWithServer(token);
    }
  }

  /// Logout — hapus token dari backend supaya admin lain tidak terima
  /// notif yang ditujukan ke akun ini di device ini.
  Future<void> unregister() async {
    final token = _currentToken;
    if (token == null) return;
    try {
      await adminApi.deleteJson(
        '/api/admin/push/register-fcm',
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      // Best-effort.
    }
    _currentToken = null;
  }

  Future<void> _registerWithServer(String token) async {
    try {
      await adminApi.postJson(
        '/api/admin/push/register-fcm',
        body: {'token': token},
        timeout: const Duration(seconds: 8),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] register failed: $e');
    }
  }

  Future<void> _showLocalFromRemote(RemoteMessage msg) async {
    final title = msg.notification?.title ?? msg.data['title']?.toString();
    final body = msg.notification?.body ?? msg.data['body']?.toString();
    if (title == null && body == null) return;
    final payload = msg.data['url']?.toString() ?? msg.data['type']?.toString();
    await _local.show(
      msg.hashCode,
      title ?? 'Natalo Admin',
      body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  void _handleTapPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    _navigateTo(payload);
  }

  void _handleNavigateFromData(Map<String, dynamic> data) {
    final url = data['url']?.toString();
    if (url != null && url.isNotEmpty) {
      _navigateTo(url);
    }
  }

  /// Deep-link minimal: trigger refresh + route ke screen yang related.
  /// Saat ini cuma trigger refresh counter — proper deep-link routing
  /// bisa di-extend dgn parse `url` jadi /admin/orders/XYZ → push
  /// OrderDetailScreen. Untuk MVP, refresh + open default tab.
  void _navigateTo(String url) {
    NotificationCounts.instance.refresh();
    // TODO: parse url ke route mobile yang sesuai. Untuk sekarang user
    // navigate manual via badge yang sudah update.
    if (kDebugMode) debugPrint('[fcm] navigate request: $url');
    // Hint dari ApiConfig — bukan URL absolut, ini path web. Mobile
    // mapping: /admin/orders/XYZ → OrdersScreen + open detail.
    // Implementasi nanti — sekarang cukup refresh badge supaya admin
    // tahu ada perubahan.
    // Silence unused-field warning sampai routing impl.
    // ignore: unused_local_variable
    final navKey = _navigatorKey;
    // ignore: unused_local_variable
    final base = ApiConfig.baseUrl;
  }
}
