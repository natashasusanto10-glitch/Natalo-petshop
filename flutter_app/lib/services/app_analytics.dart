import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper di sekitar `FirebaseAnalytics` — graceful no-op kalau
/// Firebase belum di-initialize (mis. dev build tanpa google-services.json).
///
/// Strategi log event:
/// - **Standard events**: pakai metode dedicated (`logViewProduct`, dll)
///   supaya nama event + parameter schema konsisten di seluruh app.
/// - **Custom events**: panggil `log(name: ..., parameters: ...)` direct.
///
/// Schema event mengikuti convention Firebase recommended events
/// (snake_case, max 40 chars). Lihat:
/// https://firebase.google.com/docs/reference/cpp/group/event-names
class AppAnalytics {
  static FirebaseAnalytics? _instance;

  /// True kalau Firebase + Analytics aktif (semua log() bakal kirim).
  static bool get isAvailable {
    if (kIsWeb) return false;
    if (Firebase.apps.isEmpty) return false;
    return _instance != null;
  }

  /// Initialize — panggil di main() setelah `Firebase.initializeApp()`.
  /// Idempotent.
  static Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) return;
      _instance = FirebaseAnalytics.instance;
      // Default settings: enable di release, disable di debug supaya tidak
      // pollute dashboard dengan event dari dev session.
      await _instance!.setAnalyticsCollectionEnabled(!kDebugMode);
    } catch (_) {
      // Silent fail — analytics tidak boleh blokir app startup.
    }
  }

  /// Set user ID (member ID) saat login. null saat logout.
  static Future<void> setUserId(String? userId) async {
    if (!isAvailable) return;
    try {
      await _instance!.setUserId(id: userId);
    } catch (_) {}
  }

  /// Log custom event. Pakai standard events kalau ada (mis. logAddToCart).
  static Future<void> log({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    if (!isAvailable) return;
    try {
      await _instance!.logEvent(name: name, parameters: parameters);
    } catch (_) {}
  }

  /// Log screen view — panggil di `didChangeDependencies` atau initState
  /// supaya tau funnel berapa user lihat screen X.
  static Future<void> logScreenView(String screenName) async {
    if (!isAvailable) return;
    try {
      await _instance!.logScreenView(screenName: screenName);
    } catch (_) {}
  }

  // ── Recommended e-commerce events ─────────────────────────────────────

  /// User lihat detail produk. Drive product discovery funnel.
  static Future<void> logViewProduct({
    required String productId,
    required String productName,
    required num price,
    String? category,
  }) async {
    if (!isAvailable) return;
    try {
      await _instance!.logViewItem(
        currency: 'IDR',
        value: price.toDouble(),
        items: [
          AnalyticsEventItem(
            itemId: productId,
            itemName: productName,
            itemCategory: category,
            price: price.toDouble(),
          ),
        ],
      );
    } catch (_) {}
  }

  /// User tambah produk ke cart.
  static Future<void> logAddToCart({
    required String productId,
    required String productName,
    required num price,
    int quantity = 1,
  }) async {
    if (!isAvailable) return;
    try {
      await _instance!.logAddToCart(
        currency: 'IDR',
        value: price.toDouble() * quantity,
        items: [
          AnalyticsEventItem(
            itemId: productId,
            itemName: productName,
            price: price.toDouble(),
            quantity: quantity,
          ),
        ],
      );
    } catch (_) {}
  }

  /// User berhasil checkout / order. Conversion paling penting.
  static Future<void> logPurchase({
    required String orderNumber,
    required num value,
    required int itemCount,
  }) async {
    if (!isAvailable) return;
    try {
      await _instance!.logPurchase(
        currency: 'IDR',
        transactionId: orderNumber,
        value: value.toDouble(),
        parameters: {'item_count': itemCount},
      );
    } catch (_) {}
  }

  /// User login sukses.
  static Future<void> logLogin(String method) async {
    if (!isAvailable) return;
    try {
      await _instance!.logLogin(loginMethod: method);
    } catch (_) {}
  }

  /// User register sukses.
  static Future<void> logSignUp(String method) async {
    if (!isAvailable) return;
    try {
      await _instance!.logSignUp(signUpMethod: method);
    } catch (_) {}
  }

  /// User pakai search.
  static Future<void> logSearch(String query) async {
    if (!isAvailable) return;
    try {
      await _instance!.logSearch(searchTerm: query);
    } catch (_) {}
  }
}
