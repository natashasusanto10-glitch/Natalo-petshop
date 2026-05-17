import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Wrapper Firebase Crashlytics. Hook FlutterError.onError +
/// PlatformDispatcher.onError di [initialize] supaya semua uncaught error
/// auto-report ke Crashlytics console. Graceful no-op kalau Firebase belum
/// ter-init (mis. config file hilang di platform tertentu).
class AppCrashlytics {
  AppCrashlytics._();

  static bool _ready = false;

  static Future<void> initialize() async {
    try {
      // Cek apakah Firebase.initializeApp sudah jalan di main(). Kalau belum,
      // setiap akses FirebaseCrashlytics.instance akan throw.
      Firebase.app();
      _ready = true;

      // Disable di debug — supaya stacktrace debug tidak polluting prod
      // dashboard. Auto-enable di release / profile build.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);

      // Hook semua Flutter framework error.
      FlutterError.onError = (errorDetails) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      };

      // Hook async error yang lolos dari zone (mis. dari Future.then yang
      // tidak punya catchError). PlatformDispatcher.onError return true
      // = handled, supaya error tidak crash app.
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      _ready = false;
      if (kDebugMode) {
        debugPrint('[AppCrashlytics] init skipped — Firebase not ready: $e');
      }
    }
  }

  static void log(String message) {
    if (!_ready) {
      if (kDebugMode) debugPrint('[Crashlytics:log] $message');
      return;
    }
    FirebaseCrashlytics.instance.log(message);
  }

  static Future<void> setUserId(String? userId) async {
    if (!_ready) return;
    await FirebaseCrashlytics.instance.setUserIdentifier(userId ?? '');
  }

  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!_ready) {
      if (kDebugMode) {
        debugPrint('[Crashlytics:error] $error ($reason)\n$stack');
      }
      return;
    }
    await FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: reason,
      fatal: fatal,
    );
  }
}
