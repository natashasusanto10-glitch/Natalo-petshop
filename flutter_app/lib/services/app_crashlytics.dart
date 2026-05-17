import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Wrapper di sekitar `FirebaseCrashlytics` — graceful no-op kalau Firebase
/// belum di-initialize (dev build tanpa google-services.json).
///
/// Capture pattern:
/// - **Flutter framework errors**: `FlutterError.onError`
/// - **Async errors (PlatformDispatcher)**: `PlatformDispatcher.instance.onError`
/// - **Manual exceptions**: panggil `recordError()` di catch block
///
/// Plus custom keys + breadcrumbs untuk debug context (mis. last screen,
/// last API endpoint, user ID).
class AppCrashlytics {
  static FirebaseCrashlytics? _instance;

  static bool get isAvailable {
    if (kIsWeb) return false;
    if (Firebase.apps.isEmpty) return false;
    return _instance != null;
  }

  /// Initialize di main() setelah Firebase.initializeApp(). Idempotent.
  /// Disable di debug — crash di dev tidak relevant untuk production funnel.
  static Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) return;
      _instance = FirebaseCrashlytics.instance;
      // Disable di debug; release otomatis enable.
      await _instance!.setCrashlyticsCollectionEnabled(!kDebugMode);

      // Hook 1: Flutter framework errors (widget build, render, etc).
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        _instance!.recordFlutterError(details);
      };

      // Hook 2: Async errors yang lolos zone — PlatformDispatcher onError
      // hanya available di Flutter 3.3+ (kita di 3.41 jadi OK).
      PlatformDispatcher.instance.onError = (error, stack) {
        _instance!.recordError(error, stack, fatal: true);
        return true; // mark as handled supaya tidak crash app
      };
    } catch (_) {
      // Silent — crash reporter tidak boleh sendiri jadi penyebab crash.
    }
  }

  /// Set user ID (member ID) supaya crash di-attribute ke user yang affected.
  /// null saat logout.
  static Future<void> setUserId(String? userId) async {
    if (!isAvailable) return;
    try {
      await _instance!.setUserIdentifier(userId ?? '');
    } catch (_) {}
  }

  /// Tambah custom key — searchable di Crashlytics dashboard.
  /// Mis: `setCustomKey('last_screen', 'checkout')`.
  static Future<void> setCustomKey(String key, Object value) async {
    if (!isAvailable) return;
    try {
      await _instance!.setCustomKey(key, value);
    } catch (_) {}
  }

  /// Breadcrumb log — muncul di crash report sebagai timeline event sebelum
  /// crash. Mis: `log('Tapped Beli Sekarang on product XYZ')`.
  static Future<void> log(String message) async {
    if (!isAvailable) return;
    try {
      await _instance!.log(message);
    } catch (_) {}
  }

  /// Manual error report dari try/catch — non-fatal (app tetap jalan).
  /// Mis: API call gagal yang sudah di-handle gracefully tapi kita mau
  /// tahu seberapa sering kejadian.
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!isAvailable) return;
    try {
      await _instance!.recordError(error, stack, reason: reason, fatal: fatal);
    } catch (_) {}
  }
}
