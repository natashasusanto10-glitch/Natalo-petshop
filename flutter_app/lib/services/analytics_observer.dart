import 'package:flutter/material.dart';

import 'app_analytics.dart';
import 'app_crashlytics.dart';

/// NavigatorObserver yang auto-log screen view + crashlytics breadcrumb
/// setiap push/replace. Pasang di MaterialApp.navigatorObservers supaya
/// cover semua route tanpa per-screen edits.
class NataloAnalyticsObserver extends NavigatorObserver {
  void _track(Route<dynamic>? route, String action) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    AppAnalytics.logScreenView(name);
    AppCrashlytics.log('nav.$action: $name');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route, 'push');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _track(newRoute, 'replace');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _track(previousRoute, 'pop');
  }
}

final NataloAnalyticsObserver nataloAnalyticsObserver = NataloAnalyticsObserver();
