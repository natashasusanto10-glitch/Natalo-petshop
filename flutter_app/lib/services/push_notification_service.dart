import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../state/account_scope.dart';
import '../utils/owner_scope.dart';
import 'api_client.dart';
import 'deep_link_service.dart';

/// Lifecycle state of [PushNotificationService.initialize]. Replaces the old
/// single `_initialized` bool that latched `true` even on failure — a
/// transient error (mis. Firebase belum boot) used to kill push sampai proses
/// restart. Sekarang gagal → kembali ke [idle] supaya bisa retry.
enum PushInitState { idle, initializing, ready, permissionDenied }

/// Top-level background message handler. WAJIB top-level + `vm:entry-point`
/// karena FCM memanggilnya di isolate terpisah saat app di background/
/// terminated — closure/instance method tidak bisa di-dispatch ke sana.
///
/// Sengaja TIDAK menampilkan ulang notifikasi: pesan dengan payload
/// `notification` sudah dirender OS di tray. Menampilkan lokal lagi =
/// duplikat. Handler ini hanya untuk kerja data-only (kalau ada nanti).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Firebase belum bisa boot di background isolate — no-op aman.
  }
}

class PushSubscriptionStatus {
  final bool authenticated;
  final bool subscribed;
  final int tokenCount;

  const PushSubscriptionStatus({
    required this.authenticated,
    required this.subscribed,
    required this.tokenCount,
  });

  factory PushSubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final mine = json['mine'];
    final aggregate = json['aggregate'];
    final count = mine is Map<String, dynamic>
        ? (mine['total'] as num?)?.toInt() ?? 0
        : aggregate is Map<String, dynamic>
            ? ((aggregate['web'] as num?)?.toInt() ?? 0) +
                ((aggregate['apns'] as num?)?.toInt() ?? 0) +
                ((aggregate['fcm'] as num?)?.toInt() ?? 0)
            : 0;

    return PushSubscriptionStatus(
      authenticated: json['authenticated'] == true,
      subscribed: count > 0,
      tokenCount: count,
    );
  }
}

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

  /// Lightweight signal untuk UI badge notification center. Saat push masuk
  /// foreground, bell di header bisa fetch ulang unread count tanpa polling.
  final ValueNotifier<int> notificationRefreshTick = ValueNotifier<int>(0);

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  PushInitState _initState = PushInitState.idle;
  PushInitState get initState => _initState;

  String? _currentToken;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _registrationInFlight = false;
  bool _registrationQueued = false;
  Timer? _registrationRetryTimer;
  int _registrationRetryAttempt = 0;

  // Init-retry (bounded) — transient failure kembali ke idle lalu dicoba lagi.
  Timer? _initRetryTimer;
  int _initRetryAttempt = 0;
  static const _maxInitRetries = 3;

  // Stream subscriptions disimpan supaya retry init tidak menumpuk listener
  // ganda (yang bikin notif ter-handle N kali).
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  /// Pure decision: apakah pesan ini harus ditampilkan lokal via
  /// flutter_local_notifications. OS sudah auto-render pesan berpayload
  /// `notification` saat app di background — jadi hanya path foreground yang
  /// perlu render sendiri, dan hanya kalau kategori-nya enabled.
  @visibleForTesting
  static bool shouldDisplayLocally({
    required bool isForeground,
    required bool hasNotificationPayload,
    required bool categoryEnabled,
  }) {
    if (!categoryEnabled) return false;
    if (!isForeground) return false; // OS already displayed it — jangan dobel
    return hasNotificationPayload;
  }

  /// True bila app cold-start dipicu tap notifikasi (app tadinya terminated).
  /// Dibaca LaunchPromoGate untuk skip popup agar tidak menutupi tujuan notif.
  bool launchedFromColdPush = false;

  /// Initialize Firebase + register token handlers. Idempotent.
  /// Call ini di main() setelah memberStore + cartStore di-init.
  ///
  /// `isLoggedIn` callback (optional) di-evaluate AFTER Firebase init
  /// success — kalau return true, langsung fire registerWithServer().
  /// Catches auto-login case: user reinstall app, session persist dari
  /// disk, gak ada explicit login event → tanpa callback ini token
  /// gak akan ke-register sampai user logout-login. Dengan callback,
  /// cold start dengan saved session auto-trigger registration.
  Future<void> initialize(
    GlobalKey<NavigatorState> navigatorKey, {
    bool Function()? isLoggedIn,
  }) async {
    // Single-flight: kalau lagi initializing atau sudah ready, no-op.
    if (_initState == PushInitState.initializing ||
        _initState == PushInitState.ready) {
      return;
    }
    _navigatorKey = navigatorKey;
    _initState = PushInitState.initializing;
    try {
      // 1) Initialize Firebase pakai DefaultFirebaseOptions (konsisten dengan
      //    main.dart). Idempotent kalau app sudah di-init di main().
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Daftarkan background handler (top-level + vm:entry-point) untuk pesan
      // saat app background/terminated. OS render notif di tray; handler tidak
      // menampilkan ulang supaya tidak dobel.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

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
        _initState = PushInitState.permissionDenied;
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
      //
      // iOS-specific: messaging.getToken() requires APNs token ready dulu.
      // Kalau dipanggil terlalu cepat setelah requestPermission(), bisa
      // return null karena iOS belum kasih APNs token (timing race async
      // dengan Apple's server). Plugin v15 supposedly handle internally
      // tapi ada edge case di fresh install dimana token return null silent.
      //
      // Fix: explicitly await getAPNSToken() FIRST di iOS — itu blocking
      // sampai APNs token tersedia (atau timeout). Setelah APNs ready,
      // getToken() return FCM token yang properly bound.
      if (Platform.isIOS) {
        // Retry up to 5x dengan exponential backoff total max ~7.75 detik.
        // iOS APNs registration biasanya complete <2 detik tapi network jelek
        // bisa sampai 5-10 detik.
        for (var attempt = 0; attempt < 5; attempt++) {
          final apnsToken = await messaging.getAPNSToken();
          if (apnsToken != null && apnsToken.isNotEmpty) {
            if (kDebugMode) {
              debugPrint(
                  '[push] iOS APNs token ready (attempt ${attempt + 1})');
            }
            break;
          }
          if (kDebugMode) {
            debugPrint(
                '[push] iOS APNs token null, retry in ${250 << attempt}ms');
          }
          await Future.delayed(Duration(milliseconds: 250 << attempt));
        }
      }

      // Retry getToken() juga — kalau APNs wait di atas timeout-out tanpa
      // resolve, getToken() bisa masih return null. Defensive retry.
      for (var attempt = 0; attempt < 3; attempt++) {
        _currentToken = await messaging.getToken();
        if (_currentToken != null && _currentToken!.isNotEmpty) break;
        if (kDebugMode) {
          debugPrint(
              '[push] FCM getToken() null, retry attempt ${attempt + 1}');
        }
        await Future.delayed(Duration(milliseconds: 500 << attempt));
      }
      if (kDebugMode && _currentToken != null) {
        debugPrint('[push] FCM token: ${_currentToken!.substring(0, 20)}...');
      }

      // Cold start: notification tap saat app terminated. Warm handling
      // dipasang bareng listener lain di _attachListeners.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        launchedFromColdPush = true;
        // Delay supaya navigator ready setelah app launch.
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleMessage(initial);
        });
      }

      // Pasang SEMUA stream listener SETELAH semua operasi fallible di atas
      // selesai — supaya kalau init gagal sebelum titik ini, tidak ada
      // listener setengah-pasang, dan retry tidak menumpuk listener ganda.
      _attachListeners(messaging);

      _initState = PushInitState.ready;
      _initRetryAttempt = 0;

      // Cold start auto-registration. Saat user reinstall app dengan
      // session persist (auto-login dari saved cookie), gak ada explicit
      // login event yang fire registerWithServer. Tanpa hook ini, token
      // gak akan ke-register ke backend sampai user logout-login manual.
      //
      // Check isLoggedIn callback (passed dari main.dart) — kalau true,
      // langsung register. Fire-and-forget supaya gak block init.
      if (isLoggedIn?.call() == true) {
        registerWithServer();
      }
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint(
          '[push] Init failed (kemungkinan google-services.json belum ada): $error',
        );
      }
      // Surface ke Crashlytics — sebelumnya silent swallow, jadi kalau
      // Firebase init gagal di production (mis. FirebaseApp.configure()
      // belum di-call di AppDelegate.swift), kita tidak punya visibility.
      // Now: every init failure recorded di Crashlytics dashboard dengan
      // stack trace lengkap untuk diagnose.
      try {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          reason: 'pushNotificationService.initialize() failed',
          fatal: false,
        );
      } catch (_) {
        // Crashlytics belum init (kalau Firebase iOS SDK gak boot sama
        // sekali) — fallback silent. Init di main.dart panggil
        // AppCrashlytics.initialize() AFTER pushNotificationService, jadi
        // mungkin race condition di first launch.
      }
      // Kembali ke idle (BUKAN latch ready) — kegagalan transient bisa
      // di-retry tanpa perlu restart proses.
      _initState = PushInitState.idle;
      _scheduleInitRetry(navigatorKey, isLoggedIn: isLoggedIn);
    }
  }

  void _attachListeners(FirebaseMessaging messaging) {
    // Cancel dulu supaya idempotent — retry init tidak menumpuk listener.
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen(_onTokenRefresh);
    _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _openedAppSub?.cancel();
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
  }

  void _scheduleInitRetry(
    GlobalKey<NavigatorState> navigatorKey, {
    bool Function()? isLoggedIn,
  }) {
    if (_initRetryAttempt >= _maxInitRetries) return;
    _initRetryTimer?.cancel();
    final delay = Duration(seconds: 5 << _initRetryAttempt); // 5s,10s,20s
    _initRetryAttempt++;
    if (kDebugMode) {
      debugPrint('[push] Schedule init retry in ${delay.inSeconds}s');
    }
    _initRetryTimer = Timer(
      delay,
      () => initialize(navigatorKey, isLoggedIn: isLoggedIn),
    );
  }

  /// Register FCM token ke server (PWA `/api/push/subscribe-fcm`).
  /// Call setelah user login sukses.
  ///
  /// iOS tambahan: juga register raw APNs token (bukan FCM-wrapped) ke
  /// `/api/push/subscribe-apns` supaya backend bisa direct-send ke APNs
  /// Apple bypass Firebase. Diagnostic only — push reguler tetap via FCM.
  /// `messaging.getAPNSToken()` return raw 64-char hex APNs device token.
  /// Android: getAPNSToken() return null (no-op silently).
  Future<void> registerWithServer() async {
    if (_registrationInFlight) {
      _registrationQueued = true;
      return;
    }
    _registrationInFlight = true;
    var shouldRetry = false;

    try {
      // FCM token registration — retry inline kalau _currentToken null.
      // Bisa terjadi kalau registerWithServer dipanggil sebelum initialize()
      // selesai retry getToken di iOS.
      String? fcmToken = _currentToken;
      if (fcmToken == null || fcmToken.isEmpty) {
        // Inline retry sekali — kalau initialize() retry udah ngambil,
        // _currentToken seharusnya udah set. Kalau masih null, attempt
        // fresh getToken() dengan retry.
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            fcmToken = await FirebaseMessaging.instance.getToken();
            if (fcmToken != null && fcmToken.isNotEmpty) {
              _currentToken = fcmToken;
              break;
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[push] getToken retry $attempt failed: $e');
            }
          }
          await Future.delayed(Duration(milliseconds: 500 << attempt));
        }
      }

      if (fcmToken != null && fcmToken.isNotEmpty) {
        try {
          await apiClient.postJson(
            '/api/push/subscribe-fcm',
            body: {'token': fcmToken},
          );
          if (kDebugMode) {
            debugPrint(
              '[push] FCM token registered: ${fcmToken.substring(0, 16)}...',
            );
          }
        } catch (error) {
          shouldRetry = true;
          if (kDebugMode) {
            debugPrint('[push] Register FCM token failed: $error');
          }
        }
      } else {
        // Log explicit visibility kalau FCM token bener-bener gak tersedia.
        // Crashlytics akan capture supaya kita lihat di dashboard.
        shouldRetry = true;
        if (kDebugMode) {
          debugPrint(
            '[push] FCM token unavailable after retry — skip subscribe-fcm',
          );
        }
        try {
          await FirebaseCrashlytics.instance.recordError(
            Exception(
                'FCM token null after retry — getToken() persistent fail'),
            StackTrace.current,
            reason: 'registerWithServer() FCM token unavailable',
            fatal: false,
          );
        } catch (_) {}
      }

      if (Platform.isIOS) {
        // iOS — register raw APNs token sebagai diagnostic backup channel.
        // ALWAYS attempt — independent dari FCM token availability. Retry up
        // to 5× dengan exponential backoff. Kalau APNs masih telat, scheduled
        // retry di bawah akan coba lagi tanpa perlu user logout/login.
        try {
          String? apnsToken;
          for (var attempt = 0; attempt < 5; attempt++) {
            apnsToken = await FirebaseMessaging.instance.getAPNSToken();
            if (apnsToken != null && apnsToken.isNotEmpty) break;
            await Future.delayed(Duration(milliseconds: 500 << attempt));
          }
          if (apnsToken != null && apnsToken.isNotEmpty) {
            await apiClient.postJson(
              '/api/push/subscribe-apns',
              body: {'token': apnsToken},
            );
            if (kDebugMode) {
              debugPrint(
                '[push] APNs token registered: ${apnsToken.substring(0, 16)}...',
              );
            }
          } else {
            shouldRetry = true;
            if (kDebugMode) {
              debugPrint('[push] APNs token unavailable after retry');
            }
            try {
              await FirebaseCrashlytics.instance.recordError(
                Exception('APNs token null after retry on iOS'),
                StackTrace.current,
                reason: 'registerWithServer() APNs token unavailable iOS',
                fatal: false,
              );
            } catch (_) {}
          }
        } catch (error) {
          shouldRetry = true;
          if (kDebugMode) {
            debugPrint('[push] Register APNs token failed: $error');
          }
        }
      }
    } finally {
      _registrationInFlight = false;
      if (_registrationQueued) {
        _registrationQueued = false;
        unawaited(registerWithServer());
      } else if (shouldRetry) {
        _scheduleRegistrationRetry();
      } else {
        _clearRegistrationRetry();
      }
    }
  }

  /// Unregister token dari server saat logout. Idempotent.
  Future<void> unregisterFromServer() async {
    _clearRegistrationRetry();
    final token = _currentToken;
    if (token != null && token.isNotEmpty) {
      try {
        await apiClient.deleteJson(
          '/api/push/subscribe-fcm',
          body: {'token': token},
        );
      } catch (_) {}
    }

    // Cleanup APNs token registration juga (iOS only).
    if (Platform.isIOS) {
      try {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) {
          await apiClient.deleteJson(
            '/api/push/subscribe-apns',
            body: {'token': apnsToken},
          );
        }
      } catch (_) {}
    }
  }

  Future<PushSubscriptionStatus> fetchSubscriptionStatus() async {
    try {
      final data = await apiClient.getJson('/api/push/me/status');
      return PushSubscriptionStatus.fromJson(data);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[push] Fetch subscription status failed: $error');
      }
      return const PushSubscriptionStatus(
        authenticated: false,
        subscribed: false,
        tokenCount: 0,
      );
    }
  }

  Future<bool> sendTestPush({
    required String title,
    required String body,
  }) async {
    try {
      final data = await apiClient.postJson(
        '/api/push/me/test',
        body: {
          'title': title,
          'body': body,
        },
      );
      return data['ok'] == true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[push] Send test push failed: $error');
      }
      return false;
    }
  }

  void _onTokenRefresh(String token) {
    _currentToken = token;
    // Auto re-register dengan server (server akan upsert).
    _clearRegistrationRetry();
    registerWithServer();
  }

  void _scheduleRegistrationRetry() {
    if (_registrationRetryAttempt >= 8) return;
    _registrationRetryTimer?.cancel();
    final delay = _registrationRetryDelay(_registrationRetryAttempt);
    _registrationRetryAttempt++;
    if (kDebugMode) {
      debugPrint('[push] Schedule registration retry in ${delay.inSeconds}s');
    }
    _registrationRetryTimer = Timer(delay, registerWithServer);
  }

  Duration _registrationRetryDelay(int attempt) {
    const delays = <Duration>[
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 10),
      Duration(minutes: 15),
    ];
    return delays[attempt.clamp(0, delays.length - 1)];
  }

  void _clearRegistrationRetry() {
    _registrationRetryTimer?.cancel();
    _registrationRetryTimer = null;
    _registrationRetryAttempt = 0;
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null) return; // no payload → tidak ada yang dirender lokal
    // Filter berdasar user notification preferences. Backend bisa kirim
    // `data.category` (order|promo|voucher|newsletter) — kalau category
    // off di settings, skip display. Notif keamanan account selalu lewat.
    final category = message.data['category']?.toString();
    final categoryEnabled =
        category == null ? true : await _isCategoryEnabled(category);
    // Foreground: FCM tidak auto-display, jadi kita render sendiri (kalau
    // kategori enabled). Background TIDAK lewat sini — OS sudah render, tidak
    // dobel.
    if (!shouldDisplayLocally(
      isForeground: true,
      hasNotificationPayload: true,
      categoryEnabled: categoryEnabled,
    )) {
      if (kDebugMode && category != null && !categoryEnabled) {
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
    notificationRefreshTick.value++;
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
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
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
      // Owner-scoped key — must match NotificationPreferencesScreen._prefKey so
      // account A's toggles don't gate account B's notifications.
      return prefs.getBool(OwnerScope.key(
              'natalo_notif_pref_$category', accountOwnerId())) ??
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
