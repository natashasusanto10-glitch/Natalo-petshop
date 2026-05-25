/// Coordinator minimal untuk Android system back priority.
///
/// Problem: MainNavigationScreen.PopScope dan FeedPostView (yang
/// nge-host comment drawer non-modal) hidup di route yang SAMA. Flutter
/// PopScope yang multiple di route sama → semua handler fire bareng,
/// gak ada "consumed by inner". Jadi kita pakai shared state minimal:
/// FeedPostView push/pop closer ke list ini, MainNavigationScreen
/// handler cek list dulu sebelum tab nav.
///
/// Pattern: pure module-level mutable variable. Tidak butuh Provider /
/// InheritedWidget / ChangeNotifier — gak ada widget yang perlu rebuild
/// saat state ini berubah (cuma di-baca on-demand di back handler).
///
/// **Rules:**
/// - Pakai HANYA untuk Android system back. iOS skip.
/// - Pakai HANYA untuk overlay yang BUKAN modal route (showModalBottomSheet,
///   showDialog, Navigator.push — semua udah auto-handled).
/// - LIFO order: terakhir push = terakhir muncul = pertama close.
/// - Setiap widget yang push WAJIB pop saat dispose atau saat overlay
///   close, supaya gak ghost-callback ke widget yang udah unmounted.
library;

import 'package:flutter/foundation.dart';

/// LIFO stack of overlay closers. Terakhir di-push = terakhir muncul di
/// UI = pertama yang close saat user tap back.
final List<VoidCallback> _closerStack = <VoidCallback>[];

/// Register closer untuk overlay yang baru saja terbuka. Caller WAJIB
/// pop dengan `popAndroidBackOverlayCloser` saat overlay close atau
/// widget dispose, supaya gak ghost.
void pushAndroidBackOverlayCloser(VoidCallback closer) {
  _closerStack.add(closer);
}

/// Pop closer specific (by reference). Tidak nge-call closer-nya —
/// caller responsible close UI-nya sendiri. Function ini cuma cleanup
/// dari registry.
void popAndroidBackOverlayCloser(VoidCallback closer) {
  // Remove last occurrence — handle edge case kalau widget sama push
  // 2× tanpa pop di antara (shouldn't happen, defensive).
  for (var i = _closerStack.length - 1; i >= 0; i--) {
    if (identical(_closerStack[i], closer)) {
      _closerStack.removeAt(i);
      return;
    }
  }
}

/// Dipanggil oleh MainNavigationScreen PopScope handler. Kalau ada
/// overlay di stack, ambil top, call closer-nya, return true (consumed).
/// Closer responsible untuk cleanup state UI-nya + call popAndroidBackOverlayCloser.
///
/// Return true = back press consumed, jangan lanjut ke tab nav / exit.
/// Return false = stack kosong, lanjut handler default (tab nav atau exit).
bool consumeAndroidBackOverlay() {
  if (_closerStack.isEmpty) return false;
  final closer = _closerStack.last;
  // Pop SEBELUM call closer — supaya kalau closer langsung re-open
  // (rare), state stack udah clean.
  _closerStack.removeLast();
  try {
    closer();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[android-back-overlay] closer threw: $e');
    }
  }
  return true;
}

/// Defensive helper — clear semua closer. Pakai kalau ada catastrophic
/// state desync (mis. hot reload bikin orphan closer). Normal flow gak
/// boleh pakai ini.
void resetAndroidBackOverlays() {
  _closerStack.clear();
}
