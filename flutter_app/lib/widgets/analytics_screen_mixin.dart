import 'package:flutter/widgets.dart';

import '../services/app_analytics.dart';
import '../services/app_crashlytics.dart';

/// Mixin untuk auto-log screen view + crashlytics breadcrumb saat screen
/// pertama kali muncul. Pakai di State class supaya tidak perlu manual
/// `initState() { ... AppAnalytics.logScreenView(...) }` di setiap screen.
///
/// Usage:
/// ```dart
/// class _ProductsScreenState extends State<ProductsScreen>
///     with AnalyticsScreenMixin {
///   @override
///   String get screenName => 'products_list';
///   // ... rest of state
/// }
/// ```
///
/// Otomatis fire di initState (post-frame supaya tidak block first render).
/// No-op kalau Firebase belum di-setup.
mixin AnalyticsScreenMixin<T extends StatefulWidget> on State<T> {
  /// Override di subclass — nama screen untuk Analytics + breadcrumb.
  /// Format snake_case, mis. `'product_detail'`, `'cart'`, `'checkout'`.
  String get screenName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppAnalytics.logScreenView(screenName);
      AppCrashlytics.log('Screen view: $screenName');
      AppCrashlytics.setCustomKey('last_screen', screenName);
    });
  }
}
