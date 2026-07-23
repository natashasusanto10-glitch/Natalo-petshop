import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/double_tap_like_pointer_detector.dart';

void main() {
  group('RawDoubleTapTracker', () {
    RawDoubleTapTracker tracker() => RawDoubleTapTracker();

    // Helper: satu ketukan bersih (down lalu up di posisi sama).
    ({Offset position, bool firstTapSettling})? tap(
        RawDoubleTapTracker t, int pointer, Offset pos, int downMs,
        {int? upMs, bool settling = false}) {
      t.onPointerDown(pointer, pos, Duration(milliseconds: downMs),
          settling: settling);
      return t.onPointerUp(
          pointer, pos, Duration(milliseconds: upMs ?? downMs + 50));
    }

    test('dua ketukan cepat berdekatan → deteksi pada up kedua', () {
      final t = tracker();
      expect(tap(t, 1, const Offset(100, 100), 0), isNull);
      expect(
        tap(t, 2, const Offset(105, 102), 200)?.position,
        const Offset(105, 102),
      );
    });

    test('ketukan kedua lewat jendela (>300ms dari up pertama) → null, '
        'jadi ketukan-pertama-baru', () {
      final t = tracker();
      expect(tap(t, 1, const Offset(100, 100), 0), isNull); // up di 50ms
      expect(tap(t, 2, const Offset(100, 100), 400), isNull);
      // Ketukan tadi jadi "pertama" → ketukan berikutnya dalam jendela = deteksi.
      expect(tap(t, 3, const Offset(100, 100), 600)?.position,
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
      expect(tap(t, 3, const Offset(305, 300), 300)?.position,
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
      expect(tap(t, 4, const Offset(100, 100), 350)?.position,
          const Offset(100, 100));
    });

    test('onPointerCancel membatalkan ketukan berjalan', () {
      final t = tracker();
      t.onPointerDown(1, const Offset(100, 100), Duration.zero);
      t.onPointerCancel(1);
      expect(tap(t, 2, const Offset(100, 100), 100), isNull);
      expect(tap(t, 3, const Offset(100, 100), 250)?.position,
          const Offset(100, 100));
    });

    test('tiga ketukan: deteksi di kedua, ketiga mulai sequence baru', () {
      final t = tracker();
      expect(tap(t, 1, const Offset(100, 100), 0), isNull);
      expect(tap(t, 2, const Offset(100, 100), 150), isNotNull);
      expect(tap(t, 3, const Offset(100, 100), 300), isNull);
    });

    test('ketukan pertama saat settling → firstTapSettling true '
        '(walau ketukan kedua sudah tidak settling)', () {
      final t = tracker();
      expect(tap(t, 1, const Offset(100, 100), 0, settling: true), isNull);
      final hit = tap(t, 2, const Offset(100, 100), 150);
      expect(hit?.firstTapSettling, isTrue);
    });

    test('ketukan pertama saat diam → firstTapSettling false '
        '(walau ketukan kedua settling)', () {
      final t = tracker();
      expect(tap(t, 1, const Offset(100, 100), 0), isNull);
      final hit = tap(t, 2, const Offset(100, 100), 150, settling: true);
      expect(hit?.firstTapSettling, isFalse);
    });
  });

  group('DoubleTapLikePointerDetector (widget, membungkus PageView)', () {
    Widget host(List<Offset> hits) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: DoubleTapLikePointerDetector(
            onSettleDoubleTapLike: hits.add,
            child: PageView(
              scrollDirection: Axis.vertical,
              physics:
                  const PageScrollPhysics(parent: BouncingScrollPhysics()),
              children: [
                for (var i = 0; i < 3; i++)
                  GestureDetector(
                    // Meniru media view: onTap + onDoubleTap terdaftar.
                    onTap: () {},
                    onDoubleTap: () {},
                    child: ColoredBox(color: Color(0xFF000000 + i)),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets(
        'REGRESI INTI: double-tap saat PageView masih settle → callback '
        'sekali (posisi global ketukan kedua)', (tester) async {
      final hits = <Offset>[];
      await tester.pumpWidget(host(hits));
      // Fling lalu JANGAN pumpAndSettle — ballistic masih jalan, persis
      // momen bug di device. IgnorePointer scrollable aktif di sini.
      await tester.fling(
          find.byType(PageView), const Offset(0, -400), 1200);
      // Pump per-frame (bukan satu lompatan besar): binding test mengevaluasi
      // simulasi ballistic sampai TUNTAS dalam satu pump bila delta waktunya
      // besar, sehingga window "mid-settle" tidak pernah tertangkap. Step
      // kecil ala frame asli (~16ms) menyisakan tick ballistic yang genuin
      // sedang berjalan saat tap mendarat.
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final center = tester.getCenter(find.byType(PageView));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(hits, [center],
          reason: 'detector luar IgnorePointer harus tetap menerima tap');
    });

    testWidgets(
        'KASUS BATAS: tap-1 mid-settle, tap-2 sesudah scroll berhenti '
        '→ tetap menembak (aturan ketukan pertama)', (tester) async {
      final hits = <Offset>[];
      await tester.pumpWidget(host(hits));
      await tester.fling(
          find.byType(PageView), const Offset(0, -400), 1200);
      // Lihat CATATAN KASUS BATAS: step kecil ala frame asli (bukan satu
      // lompatan besar) supaya tap-1 benar-benar mendarat di tengah tick
      // ballistic yang masih berjalan.
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final center = tester.getCenter(find.byType(PageView));
      await tester.tapAt(center); // tap-1 menghentikan ballistic
      // Beri waktu scroll benar-benar selesai (snap + ScrollEnd)…
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(center); // …tap-2 saat sudah diam
      await tester.pumpAndSettle();
      expect(hits, hasLength(1),
          reason: 'ketukan pertama saat settle → luar yang menangani');
    });

    testWidgets('kondisi DIAM: double-tap → TIDAK menembak '
        '(jalur dalam yang menangani)', (tester) async {
      final hits = <Offset>[];
      await tester.pumpWidget(host(hits));
      final center = tester.getCenter(find.byType(PageView));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(hits, isEmpty,
          reason: 'saat diam, like via jalur GestureDetector lama');
    });

    testWidgets('swipe biasa (drag jari) tidak memicu callback',
        (tester) async {
      final hits = <Offset>[];
      await tester.pumpWidget(host(hits));
      await tester.fling(
          find.byType(PageView), const Offset(0, -400), 1200);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.fling(
          find.byType(PageView), const Offset(0, -400), 1200);
      await tester.pumpAndSettle();
      expect(hits, isEmpty);
    });
  });

  group('ExternalDoubleTapLike', () {
    test('fire tanpa handler → false; dengan handler → true + terpanggil',
        () {
      final bridge = ExternalDoubleTapLike();
      expect(bridge.fire(const Offset(1, 2)), isFalse);
      Offset? received;
      void handler(Offset p) => received = p;
      bridge.attach(handler);
      expect(bridge.fire(const Offset(3, 4)), isTrue);
      expect(received, const Offset(3, 4));
    });

    test('detach hanya melepas handler yang sama (guard race attach baru)',
        () {
      final bridge = ExternalDoubleTapLike();
      void oldHandler(Offset p) {}
      Offset? received;
      void newHandler(Offset p) => received = p;
      bridge.attach(oldHandler);
      bridge.attach(newHandler); // view baru attach duluan…
      bridge.detach(oldHandler); // …lalu view lama detach — jangan clobber.
      expect(bridge.fire(const Offset(5, 6)), isTrue);
      expect(received, const Offset(5, 6));
    });
  });
}
