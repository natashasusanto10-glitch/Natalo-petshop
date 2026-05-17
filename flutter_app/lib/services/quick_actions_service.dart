import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';

/// Launcher quick actions — long-press app icon → shortcut langsung ke
/// screen tertentu (Cart, Wishlist, Pesanan, Tukar Poin).
class AppQuickActions {
  AppQuickActions._();

  static const _shortcuts = <ShortcutItem>[
    ShortcutItem(
      type: 'cart',
      localizedTitle: 'Keranjang',
      icon: 'ic_shortcut_cart',
    ),
    ShortcutItem(
      type: 'wishlist',
      localizedTitle: 'Wishlist',
      icon: 'ic_shortcut_heart',
    ),
    ShortcutItem(
      type: 'orders',
      localizedTitle: 'Pesanan Saya',
      icon: 'ic_shortcut_orders',
    ),
    ShortcutItem(
      type: 'loyalty',
      localizedTitle: 'Tukar Poin',
      icon: 'ic_shortcut_loyalty',
    ),
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
