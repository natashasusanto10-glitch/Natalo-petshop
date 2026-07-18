import 'dart:async';

/// Menekan single-tap yang "nyasar" dari burst double-tap-like.
///
/// Masalah: pada satu `GestureDetector` yang punya `onTap` DAN `onDoubleTap`,
/// saat user like beruntun cepat (burst), jumlah tap ganjil menyisakan satu
/// tap tak berpasangan. Gesture arena Flutter menunggu `kDoubleTapTimeout`
/// (~300ms), tak ada tap kedua, lalu memutuskan tap itu sebagai SINGLE-tap →
/// memicu aksi single-tap (di Feed/fullscreen: toggle pause; di Postingan
/// inline: buka fullscreen) padahal user cuma mau like.
///
/// Guard ini: begitu double-tap terjadi, tandai jendela singkat di mana
/// single-tap berikutnya dianggap noise burst dan diabaikan. Jendela default
/// [defaultWindow] cukup untuk menutup gap `kDoubleTapTimeout` + spasi antar-
/// tap pada burst cepat, tapi tetap pendek sehingga single-tap yang benar-
/// benar disengaja beberapa ratus milidetik setelah like tetap lolos.
class DoubleTapBurstGuard {
  DoubleTapBurstGuard({this.window = defaultWindow});

  static const Duration defaultWindow = Duration(milliseconds: 500);

  final Duration window;
  Timer? _timer;
  bool _suppress = false;

  /// True bila single-tap saat ini harus diabaikan (masih dalam jendela
  /// sesudah double-tap terakhir).
  bool get shouldSuppressSingleTap => _suppress;

  /// Panggil TIAP double-tap terdeteksi (mis. dari `onDoubleTap`). Membuka
  /// jendela penekan selama [window]; double-tap beruntun me-reset jendela.
  void registerDoubleTap() {
    _suppress = true;
    _timer?.cancel();
    _timer = Timer(window, () => _suppress = false);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
