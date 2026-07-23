# Double-Tap Like Saat PageView Settle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double-tap-to-like di Feed & fullscreen video langsung merespons pada percobaan pertama, termasuk saat PageView masih dalam animasi settle sesudah swipe (bug: user harus tap ~4x).

**Architecture:** Deteksi double-tap dipindah dari gesture arena (yang tap-nya "ditelan" scroll selama ballistic settle) ke raw pointer `Listener` yang selalu menerima event apa pun status arena. GestureDetector lama tetap memegang `onDoubleTap` sebagai **no-op** murni untuk mempertahankan timing arena (supaya `onTap` play/pause tetap menunggu double-tap timeout dan tidak nyala dua kali saat burst-like). `DoubleTapBurstGuard` yang sudah ada tetap menekan single-tap nyasar.

**Tech Stack:** Flutter (Dart), `Listener`/`PointerEvent` raw events, flutter_test.

## Global Constraints

- Semua kerja di branch `claude/double-tap-like-settle` (sudah dibuat off `origin/main`).
- Working dir test/analyze: `flutter_app/` (jalankan `flutter test` / `flutter analyze` dari situ).
- JANGAN mengubah physics PageView (`PageScrollPhysics(parent: BouncingScrollPhysics())`) di `feed_screen.dart` maupun `scoped_video_feed_screen.dart` — rasa scroll tidak boleh berubah.
- JANGAN menyentuh handler single-tap (`_onTapMedia`) dan long-press (`_onLongPressStart/End`) — di luar lingkup.
- Gaya komentar kode: bahasa Indonesia, jelaskan KENAPA (ikuti konvensi file sekitar).
- Test existing yang mencari media detector via predicate `widget is GestureDetector && widget.onDoubleTap != null` (feed_video_post_view_test.dart:924) HARUS tetap lolos — makanya `onDoubleTap` dipertahankan sebagai no-op, bukan dihapus.
- Setelah semua task: `flutter analyze` bersih pada file yang diubah + seluruh test suite terkait lolos. Perubahan ini WAJIB device-verify (timing sentuhan nyata) sebelum dianggap final — build TestFlight oleh user.

## Kenapa desain ini (konteks untuk implementer)

Bug: sesudah swipe antar-video, PageView masih menjalankan ballistic settle. Selama itu, pointer-down pertama diklaim scrollable untuk menghentikan animasi — tap tidak pernah sampai ke `TapGestureRecognizer`/`DoubleTapGestureRecognizer` di media. Handler like sendiri ([feed_video_post_view.dart:2236] `_onDoubleTapLike`) tanpa syarat, jadi masalah murni di pengenalan gesture.

`Listener` menerima SEMUA pointer event yang hit-test ke area-nya, terlepas siapa yang menang arena — termasuk saat scroll mengklaim tap untuk stop settle. Maka double-tap dideteksi manual dari raw event: dua ketukan bersih (gerakan < slop, durasi < max) dalam jendela waktu, ketukan kedua dekat ketukan pertama.

Kenapa `onDoubleTap` GestureDetector TIDAK dihapus melainkan jadi no-op: tanpa recognizer double-tap terdaftar, setiap tap langsung diputuskan sebagai single-tap → `_onTapMedia` (play/pause) nyala DUA KALI selama burst-like. Dengan no-op terdaftar, arena tetap menunda `onTap` sebesar `kDoubleTapTimeout` dan "menelan" pasangan tap sebagai double — persis perilaku sekarang. Saat arena macet (settle), pasangan tap lolos ke `Listener` kita; single-tap nyasar yang menyusul ditekan `DoubleTapBurstGuard` (jendela 500ms, sudah ada).

Dedup TIDAK diperlukan: satu-satunya pemicu like adalah jalur raw. Arena double-tap = no-op.

Lingkup: `FeedVideoPostView` saja — dipakai oleh Feed utama (`feed_screen.dart`) DAN fullscreen (`scoped_video_feed_screen.dart`), dua permukaan yang dikeluhkan. `_InlineVideoPlayer` di halaman Postingan (ListView, bukan PageView snap) TIDAK disentuh — follow-up terpisah bila ternyata kena juga.

---

### Task 1: `RawDoubleTapTracker` — logika murni + unit test

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/double_tap_like_pointer_detector.dart`
- Test: `flutter_app/test/features/feed/widgets/double_tap_like_pointer_detector_test.dart`

**Interfaces:**
- Produces: `class RawDoubleTapTracker` dengan API:
  - `RawDoubleTapTracker({Duration window, double tapSlop, double secondTapSlop, Duration maxTapDuration})`
  - `void onPointerDown(int pointer, Offset position, Duration timeStamp)`
  - `void onPointerMove(int pointer, Offset position)`
  - `Offset? onPointerUp(int pointer, Offset position, Duration timeStamp)` — return posisi ketukan kedua (lokal) bila double-tap TERDETEKSI pada up ini, selain itu null.
  - `void onPointerCancel(int pointer)`
- Produces (Task 2 memakai): widget `DoubleTapLikePointerDetector`.

- [ ] **Step 1: Tulis failing unit test**

Buat `flutter_app/test/features/feed/widgets/double_tap_like_pointer_detector_test.dart`:

```dart
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
      // Ketukan tadi jadi "pertama" → ketukan berikut dalam jendela = deteksi.
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
      // Karena ketukan pertama batal, ketukan berikut BUKAN pasangan.
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
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run (dari `flutter_app/`): `flutter test test/features/feed/widgets/double_tap_like_pointer_detector_test.dart`
Expected: FAIL — file/kelas belum ada (compile error `Target of URI doesn't exist`).

- [ ] **Step 3: Implementasi minimal `RawDoubleTapTracker`**

Buat `flutter_app/lib/features/feed/widgets/double_tap_like_pointer_detector.dart`:

```dart
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
```

- [ ] **Step 4: Jalankan test — pastikan LOLOS**

Run: `flutter test test/features/feed/widgets/double_tap_like_pointer_detector_test.dart`
Expected: PASS (8 test).

Catatan bila ada yang gagal: periksa test "jendela" — jendela dihitung dari UP ketukan pertama ke DOWN ketukan kedua (`downTime - firstUp <= window`), bukan up-ke-up.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/double_tap_like_pointer_detector.dart flutter_app/test/features/feed/widgets/double_tap_like_pointer_detector_test.dart
git commit -m "feat(feed): RawDoubleTapTracker — deteksi double-tap dari raw pointer"
```

---

### Task 2: Widget `DoubleTapLikePointerDetector` + widget test

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/double_tap_like_pointer_detector.dart` (tambah widget di file yang sama)
- Test: `flutter_app/test/features/feed/widgets/double_tap_like_pointer_detector_test.dart` (tambah group widget)

**Interfaces:**
- Consumes: `RawDoubleTapTracker` (Task 1).
- Produces: `class DoubleTapLikePointerDetector extends StatefulWidget` dengan constructor `({super.key, required this.onDoubleTapDetected, required this.child})` di mana `onDoubleTapDetected` bertipe `void Function(Offset localPosition)`.

- [ ] **Step 1: Tambah widget test yang gagal**

Tambahkan di akhir `main()` file test yang sama:

```dart
  group('DoubleTapLikePointerDetector (widget)', () {
    testWidgets('double-tap normal → callback sekali dengan posisi lokal',
        (tester) async {
      final hits = <Offset>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: DoubleTapLikePointerDetector(
                onDoubleTapDetected: hits.add,
                child: const ColoredBox(color: Color(0xFF000000)),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(
          find.byType(DoubleTapLikePointerDetector));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(center);
      await tester.pump();
      expect(hits, hasLength(1));
      // kDoubleTapTimeout guard: tak ada tembakan kedua menyusul.
      await tester.pump(const Duration(milliseconds: 400));
      expect(hits, hasLength(1));
    });

    testWidgets(
        'REGRESI INTI: double-tap saat PageView masih settle → tetap terdeteksi',
        (tester) async {
      final hits = <Offset>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PageView(
            scrollDirection: Axis.vertical,
            physics:
                const PageScrollPhysics(parent: BouncingScrollPhysics()),
            children: [
              for (var i = 0; i < 3; i++)
                DoubleTapLikePointerDetector(
                  onDoubleTapDetected: hits.add,
                  child: GestureDetector(
                    // Meniru media view: onTap + no-op onDoubleTap terdaftar.
                    onTap: () {},
                    onDoubleTap: () {},
                    child: ColoredBox(color: Color(0xFF000000 + i)),
                  ),
                ),
            ],
          ),
        ),
      );
      // Swipe ke halaman berikut lalu JANGAN pumpAndSettle — biarkan
      // ballistic masih berjalan, persis momen bug di device.
      await tester.fling(
          find.byType(PageView), const Offset(0, -400), 1200);
      await tester.pump(const Duration(milliseconds: 80)); // mid-settle
      final center = tester.getCenter(find.byType(PageView));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(hits, hasLength(1),
          reason: 'double-tap harus terdeteksi walau arena diklaim scroll');
    });

    testWidgets('swipe biasa tidak memicu callback', (tester) async {
      final hits = <Offset>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PageView(
            scrollDirection: Axis.vertical,
            children: [
              for (var i = 0; i < 3; i++)
                DoubleTapLikePointerDetector(
                  onDoubleTapDetected: hits.add,
                  child: ColoredBox(color: Color(0xFF000000 + i)),
                ),
            ],
          ),
        ),
      );
      await tester.fling(
          find.byType(PageView), const Offset(0, -400), 1200);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.fling(
          find.byType(PageView), const Offset(0, -400), 1200);
      await tester.pumpAndSettle();
      expect(hits, isEmpty);
    });
  });
```

Tambahkan import yang dibutuhkan di atas file test (gabung dengan yang ada):

```dart
import 'package:flutter/gestures.dart';
```

(bila analyzer menandai tidak terpakai, hapus lagi — hanya perlu jika referensi konstanta gesture dipakai.)

- [ ] **Step 2: Jalankan — pastikan test widget GAGAL**

Run: `flutter test test/features/feed/widgets/double_tap_like_pointer_detector_test.dart`
Expected: FAIL compile — `DoubleTapLikePointerDetector` belum ada.

- [ ] **Step 3: Implementasi widget**

Tambahkan di akhir `double_tap_like_pointer_detector.dart`:

```dart
/// Pembungkus media yang menembakkan [onDoubleTapDetected] dari raw pointer
/// (lihat [RawDoubleTapTracker] untuk alasan & kriteria). Behavior
/// translucent: TIDAK ikut arena, TIDAK menghalangi GestureDetector anak
/// (single-tap play/pause, long-press) maupun scroll PageView induk.
class DoubleTapLikePointerDetector extends StatefulWidget {
  const DoubleTapLikePointerDetector({
    super.key,
    required this.onDoubleTapDetected,
    required this.child,
  });

  /// Dipanggil TEPAT saat ketukan kedua turun-naik lengkap; argumen = posisi
  /// LOKAL ketukan kedua (untuk titik burst heart).
  final ValueChanged<Offset> onDoubleTapDetected;
  final Widget child;

  @override
  State<DoubleTapLikePointerDetector> createState() =>
      _DoubleTapLikePointerDetectorState();
}

class _DoubleTapLikePointerDetectorState
    extends State<DoubleTapLikePointerDetector> {
  final RawDoubleTapTracker _tracker = RawDoubleTapTracker();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _tracker.onPointerDown(
          event.pointer, event.localPosition, event.timeStamp),
      onPointerMove: (event) =>
          _tracker.onPointerMove(event.pointer, event.localPosition),
      onPointerUp: (event) {
        final hit = _tracker.onPointerUp(
            event.pointer, event.localPosition, event.timeStamp);
        if (hit != null) widget.onDoubleTapDetected(hit);
      },
      onPointerCancel: (event) => _tracker.onPointerCancel(event.pointer),
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Jalankan — pastikan LOLOS semua**

Run: `flutter test test/features/feed/widgets/double_tap_like_pointer_detector_test.dart`
Expected: PASS (11 test: 8 unit + 3 widget).

Catatan bila test REGRESI INTI gagal: cek apakah `tester.tapAt` mengirim `PointerCancelEvent` ke Listener saat scroll menang arena — Listener raw TETAP menerima down/up asli (cancel hanya sinyal arena, `onPointerCancel` Listener hanya menyala bila OS membatalkan pointer). Bila ternyata framework mengirim cancel ke Listener juga pada versi Flutter ini, ubah strategi: catat ketukan di `onPointerDown` + `onPointerUp` TANPA mereset pada `onPointerCancel` yang datang < 50ms sesudah up — dan dokumentasikan alasannya di komentar.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/double_tap_like_pointer_detector.dart flutter_app/test/features/feed/widgets/double_tap_like_pointer_detector_test.dart
git commit -m "feat(feed): DoubleTapLikePointerDetector — widget Listener utk like saat settle"
```

---

### Task 3: Wire ke `FeedVideoPostView` + regresi

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
  - Import baru di blok import features/feed/widgets.
  - Situs gesture media (±baris 3207–3225, `GestureDetector` di dalam `Positioned` ber-key `feed-video-media-viewport`).
  - Method `_onMediaDoubleTapDown` (±2677) dan sekitar `_onDoubleTapLike` (±2236).
- Test: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart` (tambah 1 test; existing HARUS tetap lolos).

**Interfaces:**
- Consumes: `DoubleTapLikePointerDetector` (Task 2), `_onDoubleTapLike()` + `_heartBurstPosition` (state existing).
- Produces: tidak ada API baru keluar file.

- [ ] **Step 1: Tulis failing test regresi**

Tambahkan di `feed_video_post_view_test.dart` (letakkan dekat test gesture lain; pakai helper pump yang sudah ada di file itu — `pumpLegacy` menerima `preloaded`/`managed`):

```dart
  testWidgets(
      'double-tap like saat PageView settle → like tetap masuk (raw listener)',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    var likeChanged = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PageView(
          scrollDirection: Axis.vertical,
          physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
            FeedVideoPostView(
              post: _fakeVideoPost(),
              isActive: true,
              preloadedController: null,
              onOverlayStateChanged: (_) {},
              onMediaZoomChanged: (_) {},
              onLikeChanged: (_) => likeChanged++,
            ),
            FeedVideoPostView(
              post: _fakeVideoPost(id: 'post-2'),
              isActive: false,
              preloadedController: null,
              onOverlayStateChanged: (_) {},
              onMediaZoomChanged: (_) {},
              onLikeChanged: (_) => likeChanged++,
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Fling lalu double-tap SAAT masih settle (tanpa pumpAndSettle dulu).
    await tester.fling(find.byType(PageView), const Offset(0, -300), 900);
    await tester.pump(const Duration(milliseconds: 80));
    final center = tester.getCenter(find.byType(PageView));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    expect(likeChanged, greaterThanOrEqualTo(1),
        reason: 'like harus masuk walau tap terjadi selama ballistic settle');
  });
```

CATATAN implementer: periksa signature `FeedVideoPostView` di file — bila tidak ada param `onLikeChanged`, cari mekanisme observasi like yang dipakai test lain di file yang sama (mis. cek `feedStore`/`_fakeVideoPost` liked state atau finder ikon heart aktif) dan pakai pola itu; JANGAN menambah param baru ke widget hanya untuk test. Sesuaikan helper `_fakeVideoPost(id:)` dengan yang tersedia (bila helper tak menerima `id`, buat dua post dari helper yang ada).

- [ ] **Step 2: Jalankan — pastikan GAGAL**

Run: `flutter test test/features/feed/widgets/feed_video_post_view_test.dart --plain-name "double-tap like saat PageView settle"`
Expected: FAIL — like tidak terdaftar (arena menelan tap saat settle).

- [ ] **Step 3: Implementasi wiring**

3a. Tambah import (blok import relative sekitar `double_tap_burst_guard.dart`):

```dart
import 'double_tap_like_pointer_detector.dart';
```

3b. Di situs GestureDetector media (±3207), bungkus dengan detector baru dan jadikan `onDoubleTap` no-op. SEBELUM:

```dart
                          child: GestureDetector(
                            onTap: () => unawaited(_onTapMedia()),
                            onDoubleTapDown: _onMediaDoubleTapDown,
                            onDoubleTap: _onDoubleTapLike,
                            // Sprint 4 #1 — Long-press signature gesture.
                            onLongPressStart: _onLongPressStart,
                            onLongPressEnd: _onLongPressEnd,
                            child: FeedPostSnapBackZoomMedia(
```

SESUDAH:

```dart
                          // Like via RAW listener (bukan arena) supaya tetap
                          // responsif saat PageView masih settle sesudah
                          // swipe — arena menelan tap pertama utk stop
                          // ballistic (bug "harus tap 4x baru like").
                          child: DoubleTapLikePointerDetector(
                            onDoubleTapDetected: _onRawDoubleTapLike,
                            child: GestureDetector(
                              onTap: () => unawaited(_onTapMedia()),
                              // Sengaja NO-OP, bukan dihapus: recognizer
                              // double-tap harus tetap terdaftar supaya
                              // onTap menunggu kDoubleTapTimeout & pasangan
                              // tap "ditelan" arena (play/pause tidak
                              // toggle 2x saat burst-like). Like nyata
                              // ditembakkan _onRawDoubleTapLike di atas.
                              onDoubleTap: _keepDoubleTapArenaSlot,
                              // Sprint 4 #1 — Long-press signature gesture.
                              onLongPressStart: _onLongPressStart,
                              onLongPressEnd: _onLongPressEnd,
                              child: FeedPostSnapBackZoomMedia(
```

(dan tutup satu paren tambahan di akhir blok child — sesuaikan indentasi).

3c. Ganti `_onMediaDoubleTapDown` (±2677) dengan dua method:

```dart
  /// Jalur like dari raw listener (satu-satunya pemicu like double-tap).
  void _onRawDoubleTapLike(Offset localPosition) {
    _heartBurstPosition = localPosition;
    _onDoubleTapLike();
  }

  /// No-op — lihat komentar di situs GestureDetector media.
  void _keepDoubleTapArenaSlot() {}
```

`_onMediaDoubleTapDown` DIHAPUS (tidak ada pemakai lain — verifikasi dengan grep sebelum hapus; bila masih dirujuk tempat lain di file, biarkan dan cukup lepas dari GestureDetector ini).

- [ ] **Step 4: Jalankan test — regresi baru + seluruh file**

Run: `flutter test test/features/feed/widgets/feed_video_post_view_test.dart`
Expected: PASS semua, termasuk test baru dan test lama di ±baris 920 (predicate `onDoubleTap != null` masih match karena no-op terdaftar).

Run juga: `flutter test test/features/feed/widgets/double_tap_burst_guard_test.dart`
Expected: PASS (guard tidak berubah).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/features/feed/widgets/feed_video_post_view.dart lib/features/feed/widgets/double_tap_like_pointer_detector.dart`
Expected: No issues (selain info pre-existing yang tidak menyentuh baris kita).

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
git commit -m "fix(feed): double-tap like responsif saat PageView settle via raw listener"
```

---

### Task 4: Sweep regresi penuh + PR

**Files:** tidak ada perubahan kode baru (hanya verifikasi + PR).

- [ ] **Step 1: Suite gesture/feed terkait**

Run: `flutter test test/features/feed/ test/screens/scoped_video_feed_screen_test.dart test/screens/member_post_detail_double_tap_test.dart test/screens/member_post_detail_screen_fullscreen_test.dart`
Expected: PASS semua. Bila ada kegagalan di test yang mem-pin perilaku lama `onDoubleTapDown` di FeedVideoPostView, sesuaikan test itu ke jalur baru (raw listener) dengan menyebut alasan di komentar test.

- [ ] **Step 2: Push + PR (JANGAN merge)**

```bash
git push -u origin claude/double-tap-like-settle
gh pr create --title "fix(feed): double-tap like responsif saat PageView masih settle" --body "..."
```

Isi body PR: ringkasan akar masalah (arena vs ballistic settle), desain raw-listener + no-op arena slot, hasil test, dan blok **Device-verify wajib** berisi checklist di bawah. JANGAN merge — tunggu hasil TestFlight user.

- [ ] **Step 3: Checklist device-verify (dikerjakan user di TestFlight)**

1. Swipe ke video berikut lalu SEGERA double-tap → like + burst heart muncul pada percobaan pertama (Feed utama DAN fullscreen).
2. Double-tap saat video sudah diam → tetap 1 like, tidak dobel.
3. Single-tap biasa → play/pause normal, TIDAK ikut ter-trigger saat burst-like.
4. Long-press kiri (2x speed) & tengah (peek pause) → masih jalan.
5. Pinch zoom media → tidak memicu like.
6. Swipe cepat beruntun antar video → tidak ada like nyasar.
7. Bila like terasa terlalu "gampang"/"susah" nyala: laporkan — ambang `window`/`tapSlop` di `RawDoubleTapTracker` yang akan dituning.
