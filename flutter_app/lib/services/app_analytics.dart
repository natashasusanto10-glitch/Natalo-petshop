import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Wrapper Firebase Analytics — log standard recommended events
/// (view_item, add_to_cart, begin_checkout, purchase) untuk funnel.
/// Auto-disable di debug supaya dashboard tidak polluted dev data.
class AppAnalytics {
  AppAnalytics._();

  static bool _ready = false;
  static FirebaseAnalytics? _instance;

  static Future<void> initialize() async {
    try {
      Firebase.app(); // throws kalau Firebase belum init.
      _instance = FirebaseAnalytics.instance;
      _ready = true;
      await _instance!.setAnalyticsCollectionEnabled(!kDebugMode);
      if (kDebugMode) debugPrint('[AppAnalytics] ready (collection disabled in debug)');
    } catch (e) {
      _ready = false;
      if (kDebugMode) {
        debugPrint('[AppAnalytics] init skipped — Firebase not ready: $e');
      }
    }
  }

  static Future<void> logEvent(
    String name, [
    Map<String, Object>? params,
  ]) async {
    if (!_ready || _instance == null) {
      if (kDebugMode) debugPrint('[Analytics:$name] ${params ?? {}}');
      return;
    }
    await _instance!.logEvent(name: name, parameters: params);
  }

  static Future<void> logViewProduct({
    required String productId,
    required String productName,
    required int price,
    String? category,
  }) =>
      logEvent('view_item', {
        'item_id': productId,
        'item_name': productName,
        'price': price,
        if (category != null) 'item_category': category,
        'currency': 'IDR',
      });

  static Future<void> logAddToCart({
    required String productId,
    required String productName,
    required int price,
    int quantity = 1,
  }) =>
      logEvent('add_to_cart', {
        'item_id': productId,
        'item_name': productName,
        'price': price,
        'quantity': quantity,
        'currency': 'IDR',
      });

  static Future<void> logBeginCheckout({required int value}) =>
      logEvent('begin_checkout', {'value': value, 'currency': 'IDR'});

  static Future<void> logPurchase({
    required String transactionId,
    required int value,
  }) =>
      logEvent('purchase', {
        'transaction_id': transactionId,
        'value': value,
        'currency': 'IDR',
      });

  static Future<void> logScreenView(String screenName) =>
      logEvent('screen_view', {'screen_name': screenName});

  static Future<void> logShareSheetOpened({
    required String contentType,
    required String contentId,
  }) =>
      _logShareEvent(
        'share_sheet_opened',
        contentType: contentType,
        contentId: contentId,
        result: 'opened',
      );

  static Future<void> logShareCompleted({
    required String contentType,
    required String contentId,
  }) =>
      _logShareEvent(
        'share_completed',
        contentType: contentType,
        contentId: contentId,
        result: 'success',
      );

  static Future<void> logShareDismissed({
    required String contentType,
    required String contentId,
    required String result,
  }) =>
      _logShareEvent(
        'share_dismissed',
        contentType: contentType,
        contentId: contentId,
        result: result,
      );

  static Future<void> _logShareEvent(
    String eventName, {
    required String contentType,
    required String contentId,
    required String result,
  }) =>
      logEvent(eventName, {
        'content_type': contentType,
        'content_id': contentId,
        'os': _sharePlatform,
        'result': result,
      });

  static String get _sharePlatform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static Future<void> setUserId(String? userId) async {
    if (!_ready || _instance == null) return;
    await _instance!.setUserId(id: userId);
  }
}
