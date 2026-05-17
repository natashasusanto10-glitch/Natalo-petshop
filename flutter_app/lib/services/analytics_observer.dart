import 'package:flutter/widgets.dart';

import 'app_analytics.dart';
import 'app_crashlytics.dart';

/// NavigatorObserver yang auto-log screen view + crashlytics breadcrumb
/// setiap push/replace/pop. Pasang di `MaterialApp.navigatorObservers`
/// supaya cover seluruh navigation hierarchy tanpa per-screen edits.
///
/// Resolve screen name dari `RouteSettings.name` (route table di main.dart).
/// Untuk anonymous routes (mis. dialog/sheet), skip — bukan screen view.
class NataloAnalyticsObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _logRoute(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _logRoute(newRoute);
  }

  void _logRoute(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    // Normalize path -> snake_case event name (Firebase Analytics convention).
    // Mis. '/member/order-detail' → 'member_order_detail'.
    final normalized = name
        .replaceAll('/', '_')
        .replaceAll('-', '_')
        .replaceAll(RegExp(r'^_+'), '')
        .toLowerCase();
    final eventName = normalized.isEmpty ? 'home' : normalized;

    AppAnalytics.logScreenView(eventName);
    AppCrashlytics.log('Screen: $eventName');
    AppCrashlytics.setCustomKey('last_screen', eventName);
  }
}

/// Singleton instance — pasang di MaterialApp.navigatorObservers.
final nataloAnalyticsObserver = NataloAnalyticsObserver();
