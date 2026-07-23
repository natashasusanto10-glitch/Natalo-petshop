import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/double_tap_like_pointer_detector.dart';

void main() {
  group('RawDoubleTapTracker', () {
    RawDoubleTapTracker tracker() => RawDoubleTapTracker();

    // Helper: satu ketukan bersih (down lalu up di posisi sama).
    Offset? tap(RawDoubleTapTracker t, int pointer, Offset pos, int downMs,
        {int? upMs}) {
      t.onPointerDown(pointer, pos, Duration(milliseconds: downMs));
      return t.onPointerUp(
          pointer, pos, Duration(milliseconds: upMs ?? downMs + 50));
    }

    test('dua ketukan cepat berdekatan → deteksi pada up kedua', () {
      final t = tracker();
      expect(tap(t, 1, const Offset(100, 100), 0), isNull);
      expect(
        tap(t, 2, const Offset(105, 102), 200),
        const Offset(105, 102),
      );
    });

    test('ketukan kedua lewat jendela (>300ms dari up pertama) → null, '
        'jadi ketukan-pertama-baru', () {
      final t = tracker();
      expect(tap(t, 1, const Offset(100, 100), 0), isNull); // up di 50ms
      expect(tap(t, 2, const Offset(100, 100), 400), isNull);
      // Ketukan tadi jadi "pertama" → ketukan berikutnya dalam jendela = deteksi.
      expect(tap(t, 3, const Offset(100, 100), 600),
          const Offset(100, 100));
    });

    test('jari bergeser > tapSlop saat ketukan → sequence reset', () {
      final t = tracker();
      t.onPointerDown(1, const Offset(100, 100), Duration.zero);
      t.onPointerMove(1, const Offset(100, 140)); // 40px > slop 24
      expect(
          t.onPointerUp(
              1, const Offset(100, 140), const Duration(milliseconds: 50)),
          isNull);
      // Karena ketukan pertama batal, ketukan berikutnya BUKAN pasangan.
      expect(tap(t, 2, const Offset(100, 100), 100), isNull);
    });

    test('durasi tekan > maxTapDuration (long-press) → bukan ketukan', () {
      final t = tracker();
      expect(
        tap(t, 1, const Offset(100, 100), 0, upMs: 400), // 400ms > 250ms
        isNull,
      );
      expect(tap(t, 2, const Offset(100, 100), 450), isNull);
    });

    test('ketukan kedua terlalu jauh (> secondTapSlop) → jadi ketukan '
        'pertama baru', () {
      final t = tracker();
      expect(tap(t, 1, const Offset(50, 50), 0), isNull);
      expect(tap(t, 2, const Offset(300, 300), 150), isNull);
      // Pasangan dari posisi baru dalam jendela → deteksi.
      expect(tap(t, 3, const Offset(305, 300), 300),
          const Offset(305, 300));
    });

    test('dua pointer bersamaan (pinch) → sequence dibatalkan', () {
      final t = tracker();
      t.onPointerDown(1, const Offset(100, 100), Duration.zero);
      t.onPointerDown(2, const Offset(200, 100),
          const Duration(milliseconds: 20)); // pointer kedua saat pertama down
      expect(
          t.onPointerUp(
              1, const Offset(100, 100), const Duration(milliseconds: 60)),
          isNull);
      expect(
          t.onPointerUp(
              2, const Offset(200, 100), const Duration(milliseconds: 70)),
          isNull);
      // Sesudah pinch, tap normal harus mulai bersih dari nol.
      expect(tap(t, 3, const Offset(100, 100), 200), isNull);
      expect(tap(t, 4, const Offset(100, 100), 350),
          const Offset(100, 100));
    });

    test('onPointerCancel membatalkan ketukan berjalan', () {
      final t = tracker();
      t.onPointerDown(1, const Offset(100, 100), Duration.zero);
      t.onPointerCancel(1);
      expect(tap(t, 2, const Offset(100, 100), 100), isNull);
      expect(tap(t, 3, const Offset(100, 100), 250),
          const Offset(100, 100));
    });

    test('tiga ketukan: deteksi di kedua, ketiga mulai sequence baru', () {
      final t = tracker();
      expect(tap(t, 1, const Offset(100, 100), 0), isNull);
      expect(tap(t, 2, const Offset(100, 100), 150), isNotNull);
      expect(tap(t, 3, const Offset(100, 100), 300), isNull);
    });
  });
}
