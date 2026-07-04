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

/// Jarak scroll minimal (px) satu arah sebelum nav toggle. Tanpa ambang ini
/// nav flip seketika pada getaran scroll terkecil (kesan "terlalu sensitif" —
/// scroll sedikit sudah membesar/mengecil). 64px ≈ gerakan sengaja, bukan
/// getaran jari.
const double _collapseThreshold = 64.0;

/// Akumulator jarak scroll searah. Di-reset tiap kali arah berbalik supaya
/// dibutuhkan gerakan berkelanjutan (bukan bolak-balik kecil) untuk toggle.
double _scrollAccum = 0.0;

/// Update collapse dari notifikasi scroll dengan HYSTERESIS.
///
/// Beda dari versi lama (yang flip seketika pada perubahan arah): di sini
/// jarak scroll searah diakumulasi, dan nav baru toggle setelah melewati
/// [_collapseThreshold]. Efeknya nav tidak lagi "gemetar" membesar-mengecil
/// saat scroll sedikit.
void updateBottomNavScroll(ScrollUpdateNotification notification) {
  if (notification.metrics.axis != Axis.vertical) return;
  final delta = notification.scrollDelta ?? 0.0;
  if (delta == 0.0) return;

  // Dekat puncak → selalu penuh (jangan biarkan nav nyangkut menyempit di
  // atas halaman).
  if (notification.metrics.pixels <= 16) {
    _scrollAccum = 0.0;
    bottomNavCollapsed.value = false;
    return;
  }

  if (delta > 0) {
    // Scroll ke bawah. Reset akumulator jika sebelumnya arah naik.
    if (_scrollAccum < 0) _scrollAccum = 0.0;
    _scrollAccum += delta;
    if (_scrollAccum >= _collapseThreshold) {
      bottomNavCollapsed.value = true;
      _scrollAccum = 0.0;
    }
  } else {
    // Scroll ke atas. Reset akumulator jika sebelumnya arah turun.
    if (_scrollAccum > 0) _scrollAccum = 0.0;
    _scrollAccum += delta;
    if (_scrollAccum <= -_collapseThreshold) {
      bottomNavCollapsed.value = false;
      _scrollAccum = 0.0;
    }
  }
}

/// Reset ke bentuk penuh. Dipanggil saat pindah route (push/pop) supaya
/// layar baru selalu mulai dengan nav penuh, tidak nyangkut menyempit.
void resetBottomNavCollapse() {
  _scrollAccum = 0.0;
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
