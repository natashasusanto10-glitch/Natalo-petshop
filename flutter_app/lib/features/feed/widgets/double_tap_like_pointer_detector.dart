import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Deteksi double-tap dari RAW pointer event — di luar gesture arena.
///
/// KENAPA: selama PageView masih ballistic-settle sesudah swipe, pointer-down
/// pertama diklaim scrollable untuk menghentikan animasi, sehingga
/// [DoubleTapGestureRecognizer] di media tidak pernah menang arena → user
/// harus mengetuk berkali-kali sebelum like masuk. [Listener] menerima semua
/// event yang hit-test ke area-nya terlepas siapa pemenang arena, jadi
/// deteksi manual di sini tetap jalan saat arena "macet".
///
/// Kriteria satu KETUKAN bersih: gerakan < [tapSlop] px sejak down, durasi
/// tekan < [maxTapDuration], dan hanya satu pointer aktif (pointer kedua yang
/// turun bersamaan = pinch-zoom → sequence batal). DOUBLE-tap: dua ketukan
/// bersih, down kedua ≤ [window] sejak UP pertama, dan jarak down kedua dari
/// down pertama ≤ [secondTapSlop].
///
/// Kelas ini murni logika (tanpa widget) supaya bisa diuji unit tanpa pump.
class RawDoubleTapTracker {
  RawDoubleTapTracker({
    this.window = const Duration(milliseconds: 300),
    this.tapSlop = 24,
    this.secondTapSlop = kDoubleTapSlop, // 100 — selaras arena Flutter
    this.maxTapDuration = const Duration(milliseconds: 250),
  });

  final Duration window;
  final double tapSlop;
  final double secondTapSlop;
  final Duration maxTapDuration;

  // Ketukan yang sedang berlangsung (down, belum up).
  int? _activePointer;
  Offset? _downPosition;
  Duration? _downTime;
  bool _movedPastSlop = false;
  bool _multiTouch = false;

  // Ketukan pertama yang sudah selesai (menunggu pasangan).
  Offset? _firstTapDown;
  Duration? _firstTapUpTime;

  void onPointerDown(int pointer, Offset position, Duration timeStamp) {
    if (_activePointer != null) {
      // Pointer kedua turun saat pertama masih ditekan → pinch/multi-touch.
      // Batalkan seluruh sequence; JANGAN jadikan salah satunya ketukan.
      _multiTouch = true;
      _firstTapDown = null;
      _firstTapUpTime = null;
      return;
    }
    _activePointer = pointer;
    _downPosition = position;
    _downTime = timeStamp;
    _movedPastSlop = false;
    // Ketukan pertama basi (lewat jendela) → buang sebelum menilai yang baru.
    final firstUp = _firstTapUpTime;
    if (firstUp != null && timeStamp - firstUp > window) {
      _firstTapDown = null;
      _firstTapUpTime = null;
    }
  }

  void onPointerMove(int pointer, Offset position) {
    if (pointer != _activePointer || _movedPastSlop) return;
    final down = _downPosition;
    if (down != null && (position - down).distance > tapSlop) {
      _movedPastSlop = true;
    }
  }

  /// Return posisi (lokal) ketukan kedua bila up ini MELENGKAPI double-tap.
  Offset? onPointerUp(int pointer, Offset position, Duration timeStamp) {
    if (pointer != _activePointer) {
      // Up milik pointer non-aktif (sisa multi-touch). Saat semua terangkat,
      // bersihkan flag supaya tap berikutnya mulai bersih.
      _multiTouch = false;
      return null;
    }
    final down = _downPosition;
    final downTime = _downTime;
    _activePointer = null;
    _downPosition = null;
    _downTime = null;

    final cleanTap = !_multiTouch &&
        !_movedPastSlop &&
        down != null &&
        downTime != null &&
        timeStamp - downTime <= maxTapDuration;
    _multiTouch = false;
    if (!cleanTap) {
      // Ketukan kotor membatalkan pasangan yang menunggu — mencegah
      // "swipe + tap" terbaca sebagai double-tap.
      _firstTapDown = null;
      _firstTapUpTime = null;
      return null;
    }

    final firstDown = _firstTapDown;
    final firstUp = _firstTapUpTime;
    final pairs = firstDown != null &&
        firstUp != null &&
        downTime - firstUp <= window &&
        (down - firstDown).distance <= secondTapSlop;
    if (pairs) {
      _firstTapDown = null;
      _firstTapUpTime = null;
      return down;
    }
    // Bukan pasangan → ketukan ini jadi "pertama" yang baru.
    _firstTapDown = down;
    _firstTapUpTime = timeStamp;
    return null;
  }

  void onPointerCancel(int pointer) {
    if (pointer == _activePointer) {
      _activePointer = null;
      _downPosition = null;
      _downTime = null;
      _movedPastSlop = false;
    }
    _multiTouch = false;
    _firstTapDown = null;
    _firstTapUpTime = null;
  }
}
