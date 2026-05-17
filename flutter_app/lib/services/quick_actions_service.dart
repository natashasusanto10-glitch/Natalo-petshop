import 'package:flutter/widgets.dart';
import 'package:quick_actions/quick_actions.dart';

/// Wrap native launcher quick actions (Android App Shortcuts / iOS Quick
/// Actions) — long-press app icon di home screen → shortcut langsung ke
/// screen tertentu.
///
/// PWA Natalo tidak bisa punya ini karena tidak punya icon native di
/// launcher. Salah satu capability eksklusif Flutter native.
class AppQuickActions {
  static const _quickActions = QuickActions();

  /// Register 4 shortcut Natalo: Cart, Wishlist, Pesanan, Tukar Poin.
  /// Dipanggil di main() setelah binding ready. Idempotent.
  static Future<void> initialize(
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    try {
      _quickActions.initialize((type) {
        // Resolve type ke route Flutter.
        switch (type) {
          case 'cart':
            navigatorKey.currentState
                ?.pushNamedAndRemoveUntil('/cart', (r) => false);
            break;
          case 'wishlist':
            navigatorKey.currentState
                ?.pushNamedAndRemoveUntil('/wishlist', (r) => false);
            break;
          case 'orders':
            navigatorKey.currentState
                ?.pushNamedAndRemoveUntil('/member/orders', (r) => false);
            break;
          case 'loyalty':
            navigatorKey.currentState
                ?.pushNamedAndRemoveUntil('/member/loyalty', (r) => false);
            break;
        }
      });

      // Set shortcut list — muncul saat user long-press icon launcher.
      await _quickActions.setShortcutItems(<ShortcutItem>[
        const ShortcutItem(
          type: 'cart',
          localizedTitle: 'Keranjang',
          icon: 'ic_shortcut_cart',
        ),
        const ShortcutItem(
          type: 'wishlist',
          localizedTitle: 'Wishlist',
          icon: 'ic_shortcut_wishlist',
        ),
        const ShortcutItem(
          type: 'orders',
          localizedTitle: 'Pesanan Saya',
          icon: 'ic_shortcut_orders',
        ),
        const ShortcutItem(
          type: 'loyalty',
          localizedTitle: 'Tukar Poin',
          icon: 'ic_shortcut_loyalty',
        ),
      ]);
    } catch (_) {
      // Silent fail — quick actions adalah affordance, jangan blokir startup.
    }
  }
}
