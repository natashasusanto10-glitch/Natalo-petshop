import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';

/// Launcher quick actions — long-press app icon → shortcut langsung ke
/// screen tertentu (Cart, Wishlist, Pesanan, Tukar Poin).
class AppQuickActions {
  AppQuickActions._();

  // Custom shortcut icons (drawable XMLs) belum tersedia di
  // android/app/src/main/res/drawable/ — pass `icon: null` supaya
  // Android pakai default app icon untuk shortcut. iOS dynamic
  // shortcuts juga support tanpa custom icon (pakai SF Symbols default
  // by type kalau ada, else generic). Drawable XML bisa ditambah
  // belakangan tanpa break call site ini.
  static const _shortcuts = <ShortcutItem>[
    ShortcutItem(type: 'cart', localizedTitle: 'Keranjang'),
    ShortcutItem(type: 'wishlist', localizedTitle: 'Wishlist'),
    ShortcutItem(type: 'orders', localizedTitle: 'Pesanan Saya'),
    ShortcutItem(type: 'loyalty', localizedTitle: 'Tukar Poin'),
  ];

  static bool _initialized = false;

  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    if (_initialized) return;
    _initialized = true;
    try {
      const qa = QuickActions();
      qa.initialize((type) {
        final nav = navigatorKey.currentState;
        if (nav == null) return;
        switch (type) {
          case 'cart':
            nav.pushNamed('/cart');
            break;
          case 'wishlist':
            nav.pushNamed('/wishlist');
            break;
          case 'orders':
            nav.pushNamed('/member/orders');
            break;
          case 'loyalty':
            nav.pushNamed('/member/loyalty');
            break;
        }
      });
      qa.setShortcutItems(_shortcuts);
    } catch (e) {
      if (kDebugMode) debugPrint('[QuickActions] init error: $e');
    }
  }
}
