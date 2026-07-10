import 'package:flutter/foundation.dart';

/// Membatasi jumlah controller video grid produk yang aktif bersamaan supaya
/// decoder HP tidak kehabisan (banyak HLS stream sekaligus = janky/crash).
/// Mirror konsep registry web (video-autoplay-registry.ts). Singleton sederhana.
class ProductGridVideoRegistry {
  ProductGridVideoRegistry._();
  static final ProductGridVideoRegistry instance = ProductGridVideoRegistry._();

  static const int maxConcurrent = 3;
  final Set<Object> _active = <Object>{};
  final Set<VoidCallback> _waiters = <VoidCallback>{};

  bool tryAcquire(Object owner) {
    if (_active.contains(owner)) return true;
    if (_active.length >= maxConcurrent) return false;
    _active.add(owner);
    return true;
  }

  void release(Object owner) {
    if (_active.remove(owner)) {
      // Beri tahu kartu yang menunggu slot supaya coba lagi (cegah kartu
      // yang terlihat saat load nyangkut di foto walau slot sudah kosong).
      for (final cb in _waiters.toList()) {
        cb();
      }
    }
  }

  void addSlotFreeListener(VoidCallback cb) => _waiters.add(cb);
  void removeSlotFreeListener(VoidCallback cb) => _waiters.remove(cb);
}
