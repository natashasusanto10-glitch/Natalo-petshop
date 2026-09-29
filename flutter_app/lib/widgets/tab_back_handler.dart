library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/android_back_overlays.dart';
import 'app_toast.dart';

/// Android system back handler untuk tab root screens.
///
/// Tab screens (Beranda/Produk/Feed/Transaksi/Akun) dinavigasikan via
/// `pushNamedAndRemoveUntil` sehingga selalu menjadi route TUNGGAL di
/// stack Navigator. Tanpa handler ini, system back gesture/button di tab
/// mana pun langsung terminate app.
///
/// Dipasang terpusat di main.dart onGenerateRoute untuk semua route tab.
/// Priority (port dari MainNavigationScreen yang sudah tidak dipakai):
///   1. Overlay non-modal terbuka (mis. comment drawer Feed) → tutup
///      via consumeAndroidBackOverlay().
///   2. Tab != Beranda → kembali ke Beranda (pushNamedAndRemoveUntil '/').
///   3. Beranda + back pertama → toast "Tekan sekali lagi untuk keluar".
///   4. Beranda + back kedua dalam 2 detik → SystemNavigator.pop() (exit).
///
/// iOS skip — tidak ada system back button; swipe-back per-route
/// ditangani Navigator default (di root stack kosong, gesture no-op).
class TabBackHandler extends StatefulWidget {
  final Widget child;
  final bool isHomeTab;

  const TabBackHandler({super.key, required this.child, this.isHomeTab = false});

  @override
  State<TabBackHandler> createState() => _TabBackHandlerState();
}

class _TabBackHandlerState extends State<TabBackHandler> {
  /// Timestamp back terakhir untuk double-tap-to-exit detection.
  /// Window 2 detik — back ke-2 dalam window = exit app.
  DateTime? _lastBackTap;
  static const _doubleBackWindow = Duration(seconds: 2);

  void _handleAndroidBack() {
    // Priority 1: overlay registry (mis. Feed comment drawer) — tutup
    // dulu, reset exit timer.
    if (consumeAndroidBackOverlay()) {
      _lastBackTap = null;
      return;
    }
    // Priority 2: tab non-Beranda → balik ke Beranda, bukan exit.
    if (!widget.isHomeTab) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      return;
    }
    final now = DateTime.now();
    final last = _lastBackTap;
    if (last != null && now.difference(last) <= _doubleBackWindow) {
      SystemNavigator.pop();
      return;
    }
    _lastBackTap = now;
    if (!mounted) return;
    AppToast.showBanner(
      context,
      'Tekan sekali lagi untuk keluar',
      kind: ToastKind.info,
      duration: _doubleBackWindow,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.android) {
      return widget.child;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleAndroidBack();
      },
      child: widget.child,
    );
  }
}
