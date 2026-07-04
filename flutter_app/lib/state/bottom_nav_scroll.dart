import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// State global collapse bottom nav saat user scroll konten.
///
/// Kenapa global (bukan per-Scaffold): app ini pakai layar berdiri sendiri
/// (Home, Produk, dst masing-masing Scaffold + BottomNavBar), bukan satu
/// shell IndexedStack. Jadi collapse tidak bisa di-drive per-layar. Satu
/// `NotificationListener<UserScrollNotification>` global di root app
/// (main.dart) meng-update notifier ini dari arah scroll layar mana pun
/// yang aktif; semua `BottomNavBar` membacanya via `ValueListenableBuilder`.
final ValueNotifier<bool> bottomNavCollapsed = ValueNotifier<bool>(false);

/// Update collapse dari arah scroll vertikal.
///  - reverse (jari ke atas / konten turun = scroll ke bawah) → menyempit
///  - forward (scroll balik ke atas) → penuh lagi
void updateBottomNavCollapse(ScrollDirection direction) {
  if (direction == ScrollDirection.reverse) {
    bottomNavCollapsed.value = true;
  } else if (direction == ScrollDirection.forward) {
    bottomNavCollapsed.value = false;
  }
}

/// Reset ke bentuk penuh. Dipanggil saat pindah route (push/pop) supaya
/// layar baru selalu mulai dengan nav penuh, tidak nyangkut menyempit.
void resetBottomNavCollapse() {
  bottomNavCollapsed.value = false;
}

/// NavigatorObserver yang reset collapse tiap kali pindah route — supaya
/// layar baru selalu mulai dengan nav penuh (tidak mewarisi state menyempit
/// dari layar sebelumnya). Dipasang di MaterialApp.navigatorObservers.
class BottomNavScrollObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    resetBottomNavCollapse();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    resetBottomNavCollapse();
  }
}
