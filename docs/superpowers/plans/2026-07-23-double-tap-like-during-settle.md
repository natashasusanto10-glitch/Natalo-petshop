# Double-Tap Like Saat PageView Settle — Implementation Plan (REVISI 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double-tap-to-like di Feed & fullscreen video langsung merespons pada percobaan pertama, termasuk saat PageView masih dalam animasi settle sesudah swipe (bug: user harus tap ~4x).

**Architecture (REVISI):** Selama ballistic settle, `Scrollable` membungkus SELURUH isinya dengan `IgnorePointer(ignoring: true)` (scrollable.dart:1037-1040 + `BallisticScrollActivity.shouldIgnorePointer == true`, scroll_activity.dart:791) — hit-test tidak pernah mencapai APA PUN di dalam halaman, termasuk raw `Listener`. Ini BUKAN masalah gesture arena (asumsi rencana awal, terbukti salah lewat eksperimen hit-test). Maka detector dipindah MEMBUNGKUS PageView (di luar IgnorePointer scrollable). Gating "Opsi A": detector luar hanya menembak bila KETUKAN PERTAMA terjadi saat settle — kasus yang mustahil dilihat jalur dalam — sehingga jalur double-tap lama di dalam `FeedVideoPostView` tetap utuh untuk kondisi diam (tahu area media, tombol aman) dan keduanya mutually-exclusive tanpa dedup. Like diteruskan ke view aktif via jembatan `ExternalDoubleTapLike`.

**Tech Stack:** Flutter (Dart), `Listener`/`PointerEvent` raw events, `ScrollNotification`, flutter_test.

## Global Constraints

- Semua kerja di branch `claude/double-tap-like-settle`.
- Working dir test/analyze: `flutter_app/` (jalankan `flutter test` / `flutter analyze` dari situ).
- JANGAN mengubah physics PageView (`PageScrollPhysics(parent: BouncingScrollPhysics())`) di `feed_screen.dart` maupun `scoped_video_feed_screen.dart` — rasa scroll tidak boleh berubah.
- JANGAN menyentuh handler gesture existing di `FeedVideoPostView`: `onTap` (`_onTapMedia`), `onDoubleTapDown`/`onDoubleTap` (jalur like lama TETAP jadi pemicu saat kondisi diam), long-press (`_onLongPressStart/End`). Revisi ini HANYA MENAMBAH jalur eksternal, tidak mengubah yang lama.
- Gaya komentar kode: bahasa Indonesia, jelaskan KENAPA (ikuti konvensi file sekitar).
- Test existing yang mencari media detector via predicate `widget is GestureDetector && widget.onDoubleTap != null` (feed_video_post_view_test.dart:924) HARUS tetap lolos — otomatis aman karena handler lama tidak disentuh.
- Setelah semua task: `flutter analyze` bersih pada file yang diubah + seluruh test suite terkait lolos. Perubahan ini WAJIB device-verify (timing sentuhan nyata) sebelum dianggap final — build TestFlight oleh user. PR JANGAN di-merge sebelum device-verify.

## Kenapa desain ini (konteks untuk implementer)

**Akar masalah (dikonfirmasi empiris + source Flutter 3.41.9):** sesudah fling, `PageView` menjalankan `BallisticScrollActivity`. Selama aktivitas itu `shouldIgnorePointer == true`, dan `ScrollableState` menerapkannya lewat `IgnorePointer` yang membungkus viewport (scrollable.dart `setIgnorePointer`). Akibatnya hit-test BERHENTI di level Scrollable — pointer event tidak pernah dikirim ke widget apa pun di dalam halaman (dibuktikan: `renderView.hitTest()` manual saat mid-ballistic hanya berisi listener milik Scrollable; saat idle berisi seluruh subtree halaman). Karena itu solusi apa pun DI DALAM halaman (recognizer arena ATAU raw Listener — percobaan pertama kami) pasti gagal.

**Solusi:** pasang raw `Listener` MEMBUNGKUS PageView — level ini tetap menerima semua pointer event selama settle (dibuktikan sama; `scoped_video_feed_screen.dart:754` bahkan sudah punya Listener serupa untuk gesture dismiss yang berfungsi normal saat scroll).

**Gating Opsi A (disetujui user):** detector luar melihat SEMUA ketukan termasuk di tombol (komentar/share/dll) → tidak boleh selalu aktif, nanti rapid-tap tombol memicu like nyasar. Aturan tembak: **hanya bila ketukan PERTAMA dari pasangan terjadi saat settle**. Logika kelengkapannya:
- Ketukan pertama saat settle → jalur dalam tidak pernah melihat ketukan itu (terblokir IgnorePointer) → jalur dalam mustahil menyelesaikan double-tap → HARUS ditangani luar. Saat settle, semua tombol di dalam halaman juga mati, jadi ketukan saat itu pasti bukan pencetan tombol.
- Ketukan pertama saat diam → jalur dalam melihatnya → jalur dalam yang menangani (perilaku lama, teruji) → luar diam.
- Kasus batas (tap-1 saat settle menghentikan animasi, tap-2 sesudah berhenti) tercakup: aturan mengikat ke ketukan PERTAMA, bukan kondisi saat ketukan kedua.
- Ketukan kedua yang dilihat jalur dalam sendirian → `onTap` (play/pause) akan menyala setelah timeout; ini ditekan karena handler like eksternal memanggil `_onDoubleTapLike()` yang me-register `DoubleTapBurstGuard` (jendela 500ms) SEBELUM `onTap` sempat menyala (like eksternal menembak di pointer-up kedua; `onTap` baru menyala setelah `kDoubleTapTimeout` ± 300ms dari down kedua).

**Deteksi settle:** `NotificationListener<ScrollNotification>` di dalam widget detector (self-contained): `ScrollUpdateNotification` dengan `dragDetails == null` pada `depth == 0` → settling = true; `ScrollEndNotification` depth 0 → false; `ScrollStartNotification` dengan `dragDetails != null` (drag jari asli) → false. `depth == 0` menyaring scroll dari PageView foto horizontal di dalam item (feed_screen ±2161).

**Routing ke video aktif:** `ExternalDoubleTapLike` (jembatan handler tunggal). Layar membuat satu instance, mengoper ke `FeedVideoPostView`; view attach handler saat `isActive == true`, detach saat tidak. Detector luar → `fire(globalPosition)` → handler view aktif → set posisi heart burst + `_onDoubleTapLike()`. Post FOTO di feed utama tidak di-attach (lingkup video sesuai keluhan; foto = follow-up).

**Lingkup:** `feed_screen.dart` (Feed utama) + `scoped_video_feed_screen.dart` (fullscreen) — dua permukaan yang dikeluhkan, dapat perlakuan identik. `_InlineVideoPlayer` halaman Postingan (ListView, bukan PageView snap) TIDAK disentuh.

**Riwayat revisi:** Task 1 (RawDoubleTapTracker murni) tetap valid dan sudah selesai (commit 99c92caa) — revisi ini menambah parameter `settling` padanya. Commit 9bce9cbb (widget per-halaman, desain lama) direvisi di atasnya, bukan rewrite history.

---

### Task 1: `RawDoubleTapTracker` — logika murni + unit test ✅ SELESAI (commit 99c92caa)

Sudah diimplementasikan & lolos review. API yang tersedia (SEBELUM revisi Task 2):
- `RawDoubleTapTracker({Duration window = 300ms, double tapSlop = 24, double secondTapSlop = kDoubleTapSlop, Duration maxTapDuration = 250ms})`
- `void onPointerDown(int pointer, Offset position, Duration timeStamp)`
- `void onPointerMove(int pointer, Offset position)`
- `Offset? onPointerUp(int pointer, Offset position, Duration timeStamp)`
- `void onPointerCancel(int pointer)`

File: `flutter_app/lib/features/feed/widgets/double_tap_like_pointer_detector.dart` + test `flutter_app/test/features/feed/widgets/double_tap_like_pointer_detector_test.dart` (8 unit test).

CATATAN: commit 9bce9cbb sesudahnya menambahkan widget `DoubleTapLikePointerDetector` versi per-halaman + 3 widget test (1 gagal: "REGRESI INTI") dan komentar fallback di `onPointerCancel` yang menonaktifkan reset `_firstTapDown/_firstTapUpTime`. Task 2 revisi MENGGANTI widget itu dan MENGEMBALIKAN reset cancel (fallback itu untuk desain lama yang salah diagnosis; dengan detector di luar IgnorePointer, cancel benar-benar berarti batal).

---

### Task 2 (REVISI): Tracker ber-flag settling + widget detector luar + gating

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/double_tap_like_pointer_detector.dart` (tracker: param `settling`, return record; widget: tulis ulang total; kembalikan reset di `onPointerCancel`)
- Modify: `flutter_app/test/features/feed/widgets/double_tap_like_pointer_detector_test.dart` (sesuaikan 8 unit test ke API baru, +2 unit test flag; ganti 3 widget test lama dengan 4 widget test baru)

**Interfaces:**
- Produces (dipakai Task 3 & 4):
  - `RawDoubleTapTracker.onPointerDown(int pointer, Offset position, Duration timeStamp, {bool settling = false})`
  - `({Offset position, bool firstTapSettling})? onPointerUp(int pointer, Offset position, Duration timeStamp)` — record berisi posisi ketukan kedua + apakah ketukan PERTAMA terjadi saat settling.
  - `class DoubleTapLikePointerDetector extends StatefulWidget` — constructor `({super.key, required this.onSettleDoubleTapLike, required this.child})`, `onSettleDoubleTapLike` bertipe `ValueChanged<Offset>` (posisi GLOBAL ketukan kedua). Dipanggil HANYA bila firstTapSettling.

- [ ] **Step 1: Sesuaikan unit test ke API baru + tambah test flag (failing dulu)**

Di file test, ubah helper `tap` dan SEMUA expectation unit test lama: hasil `onPointerUp` sekarang record — akses `?.position`. Helper baru:

```dart
    // Helper: satu ketukan bersih (down lalu up di posisi sama).
    ({Offset position, bool firstTapSettling})? tap(
        RawDoubleTapTracker t, int pointer, Offset pos, int downMs,
        {int? upMs, bool settling = false}) {
      t.onPointerDown(pointer, pos, Duration(milliseconds: downMs),
          settling: settling);
      return t.onPointerUp(
          pointer, pos, Duration(milliseconds: upMs ?? downMs + 50));
    }
```

Expectation lama pola `expect(tap(...), const Offset(x, y))` menjadi `expect(tap(...)?.position, const Offset(x, y))`; pola `isNull`/`isNotNull` tetap. Tambahkan 2 test baru di group `RawDoubleTapTracker`:

```dart
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
```

- [ ] **Step 2: Ganti group widget test lama dengan 4 test baru (failing dulu)**

Hapus seluruh group `DoubleTapLikePointerDetector (widget)` lama, ganti:

```dart
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
      await tester.pump(const Duration(milliseconds: 80)); // mid-settle
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
      await tester.pump(const Duration(milliseconds: 80));
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
```

CATATAN KASUS BATAS: bila test kedua gagal karena tap-1 saat mid-settle memicu snap-ballistic lanjutan (sehingga 120ms belum ScrollEnd), itu TIDAK masalah — aturan tetap terpenuhi lewat flag ketukan pertama; pastikan expectation `hasLength(1)` terpenuhi, bukan menyoal kapan ScrollEnd. Bila perlu, naikkan pump ke 400ms dan pastikan tap-2 masih ≤ `window` (300ms) dari UP tap-1 — kalau bentrok (window kedaluwarsa), turunkan pump ke 150ms; yang penting satu pasangan sah.

- [ ] **Step 3: Jalankan — pastikan GAGAL compile/behavior**

Run (dari `flutter_app/`): `flutter test test/features/feed/widgets/double_tap_like_pointer_detector_test.dart`
Expected: FAIL — API tracker belum menerima `settling`, widget belum punya `onSettleDoubleTapLike`.

- [ ] **Step 4: Implementasi**

4a. Tracker — tambah state & param (perubahan dari kode existing):

```dart
  // Ketukan yang sedang berlangsung (down, belum up).
  int? _activePointer;
  Offset? _downPosition;
  Duration? _downTime;
  bool _movedPastSlop = false;
  bool _multiTouch = false;
  bool _downSettling = false;

  // Ketukan pertama yang sudah selesai (menunggu pasangan).
  Offset? _firstTapDown;
  Duration? _firstTapUpTime;
  bool _firstTapSettling = false;

  void onPointerDown(int pointer, Offset position, Duration timeStamp,
      {bool settling = false}) {
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
    _downSettling = settling;
    // Ketukan pertama basi (lewat jendela) → buang sebelum menilai yang baru.
    final firstUp = _firstTapUpTime;
    if (firstUp != null && timeStamp - firstUp > window) {
      _firstTapDown = null;
      _firstTapUpTime = null;
    }
  }
```

`onPointerUp` — ganti tipe return & rekam flag:

```dart
  /// Return posisi (global) ketukan kedua + flag "ketukan pertama terjadi
  /// saat scroll settle" bila up ini MELENGKAPI double-tap; selain itu null.
  ({Offset position, bool firstTapSettling})? onPointerUp(
      int pointer, Offset position, Duration timeStamp) {
    if (pointer != _activePointer) {
      // Up milik pointer non-aktif (sisa multi-touch). Saat semua terangkat,
      // bersihkan flag supaya tap berikutnya mulai bersih.
      _multiTouch = false;
      return null;
    }
    final down = _downPosition;
    final downTime = _downTime;
    final downSettling = _downSettling;
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
      final settledFlag = _firstTapSettling;
      _firstTapDown = null;
      _firstTapUpTime = null;
      return (position: down, firstTapSettling: settledFlag);
    }
    // Bukan pasangan → ketukan ini jadi "pertama" yang baru.
    _firstTapDown = down;
    _firstTapUpTime = timeStamp;
    _firstTapSettling = downSettling;
    return null;
  }
```

`onPointerCancel` — KEMBALIKAN reset penuh (hapus komentar fallback desain lama):

```dart
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
```

Perbarui dartdoc kelas: sebutkan bahwa detector ini dipasang MEMBUNGKUS PageView (di luar `IgnorePointer` scrollable yang aktif selama `BallisticScrollActivity`), bukan di dalam halaman — jelaskan KENAPA (IgnorePointer memblokir hit-test ke seluruh isi halaman selama settle; bukan isu arena).

4b. Widget — ganti total `DoubleTapLikePointerDetector`:

```dart
/// Pembungkus PageView yang menembakkan [onSettleDoubleTapLike] HANYA bila
/// ketukan PERTAMA dari pasangan double-tap terjadi saat scroll sedang
/// ballistic-settle.
///
/// KENAPA di luar PageView: selama settle, [ScrollableState] mengaktifkan
/// IgnorePointer atas seluruh viewport (BallisticScrollActivity
/// .shouldIgnorePointer == true) sehingga hit-test tidak pernah mencapai
/// widget APA PUN di dalam halaman — termasuk GestureDetector media dan raw
/// Listener. Level ini (ancestor Scrollable) tetap menerima semua event.
///
/// KENAPA gating "ketukan pertama saat settle": saat diam, jalur double-tap
/// lama di dalam FeedVideoPostView yang menangani (tahu area media, tombol
/// aman). Ketukan pertama saat settle mustahil dilihat jalur dalam → wajib
/// ditangani di sini; saat itu semua tombol di dalam halaman juga mati,
/// jadi ketukan bukan pencetan tombol. Dua jalur mutually-exclusive.
class DoubleTapLikePointerDetector extends StatefulWidget {
  const DoubleTapLikePointerDetector({
    super.key,
    required this.onSettleDoubleTapLike,
    required this.child,
  });

  /// Dipanggil saat double-tap "settle-case" lengkap; argumen = posisi
  /// GLOBAL ketukan kedua (dikonversi lokal oleh penerima utk heart burst).
  final ValueChanged<Offset> onSettleDoubleTapLike;
  final Widget child;

  @override
  State<DoubleTapLikePointerDetector> createState() =>
      _DoubleTapLikePointerDetectorState();
}

class _DoubleTapLikePointerDetectorState
    extends State<DoubleTapLikePointerDetector> {
  final RawDoubleTapTracker _tracker = RawDoubleTapTracker();

  /// True selama scroll depth-0 (PageView yang kami bungkus) bergerak tanpa
  /// jari (ballistic). Bukan state widget — tidak perlu rebuild.
  bool _settling = false;

  bool _onScrollNotification(ScrollNotification notification) {
    // depth 0 = scrollable langsung di bawah kami (PageView vertikal);
    // scroll lain (mis. carousel foto horizontal di dalam item) diabaikan.
    if (notification.depth != 0) return false;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails == null) {
      _settling = true;
    } else if (notification is ScrollEndNotification) {
      _settling = false;
    } else if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      // Drag jari asli — bukan settle; tap saat drag bukan kasus kami.
      _settling = false;
    }
    return false; // jangan telan notifikasi milik listener lain.
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _tracker.onPointerDown(
            event.pointer, event.position, event.timeStamp,
            settling: _settling),
        onPointerMove: (event) =>
            _tracker.onPointerMove(event.pointer, event.position),
        onPointerUp: (event) {
          final hit = _tracker.onPointerUp(
              event.pointer, event.position, event.timeStamp);
          if (hit != null && hit.firstTapSettling) {
            widget.onSettleDoubleTapLike(hit.position);
          }
        },
        onPointerCancel: (event) => _tracker.onPointerCancel(event.pointer),
        child: widget.child,
      ),
    );
  }
}
```

CATATAN: pakai `event.position` (GLOBAL) di semua panggilan tracker — ruang layar konsisten walau konten bergeser selama settle.

- [ ] **Step 5: Jalankan — pastikan LOLOS semua**

Run: `flutter test test/features/feed/widgets/double_tap_like_pointer_detector_test.dart`
Expected: PASS (14 test: 10 unit + 4 widget).

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/double_tap_like_pointer_detector.dart flutter_app/test/features/feed/widgets/double_tap_like_pointer_detector_test.dart
git commit -m "fix(feed): detector double-tap pindah membungkus PageView — IgnorePointer settle blokir jalur dalam"
```

---

### Task 3 (REVISI): Jembatan `ExternalDoubleTapLike` + handler di `FeedVideoPostView`

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/double_tap_like_pointer_detector.dart` (tambah kelas jembatan di akhir file)
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` (param optional + attach/detach + handler)
- Test: `flutter_app/test/features/feed/widgets/double_tap_like_pointer_detector_test.dart` (unit jembatan) dan `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart` (1 widget test)

**Interfaces:**
- Consumes: `_onDoubleTapLike()`, `_heartBurstPosition` (state existing FeedVideoPostView).
- Produces (dipakai Task 4):
  - `class ExternalDoubleTapLike` dengan `void attach(void Function(Offset) handler)`, `void detach(void Function(Offset) handler)`, `bool fire(Offset globalPosition)`.
  - Param baru `FeedVideoPostView({..., ExternalDoubleTapLike? externalDoubleTapLike})`.

- [ ] **Step 1: Unit test jembatan (failing)**

Tambah group di file test detector:

```dart
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
```

- [ ] **Step 2: Implementasi jembatan**

Tambah di akhir `double_tap_like_pointer_detector.dart`:

```dart
/// Jembatan perintah like eksternal: layar (pemilik detector luar) →
/// [FeedVideoPostView] yang sedang aktif. Handler tunggal — hanya view
/// aktif yang attach; view lama wajib detach dengan referensi handler-nya
/// sendiri supaya tidak meng-clobber attach view baru (urutan attach/detach
/// saat pindah halaman tidak dijamin).
class ExternalDoubleTapLike {
  void Function(Offset globalPosition)? _handler;

  void attach(void Function(Offset globalPosition) handler) {
    _handler = handler;
  }

  void detach(void Function(Offset globalPosition) handler) {
    if (identical(_handler, handler)) _handler = null;
  }

  /// True bila ada view aktif yang menangani.
  bool fire(Offset globalPosition) {
    final handler = _handler;
    if (handler == null) return false;
    handler(globalPosition);
    return true;
  }
}
```

Run: `flutter test test/features/feed/widgets/double_tap_like_pointer_detector_test.dart` → PASS (16 test).

- [ ] **Step 3: Widget test FeedVideoPostView (failing)**

Tambah di `feed_video_post_view_test.dart` dekat test double-tap lain. Pakai helper pump yang SUDAH ADA di file itu (cek nama persisnya — mis. `pumpLegacy`; sesuaikan) dan pola observasi like yang dipakai test existing (JANGAN menambah param baru ke widget hanya untuk test; cek bagaimana test lain memverifikasi like — mis. finder ikon heart aktif / heart burst widget):

```dart
  testWidgets(
      'ExternalDoubleTapLike.fire saat isActive → like + heart burst '
      '(jalur settle dari detector luar)', (tester) async {
    final bridge = ExternalDoubleTapLike();
    // Pump FeedVideoPostView dengan externalDoubleTapLike: bridge dan
    // isActive: true memakai helper existing file ini.
    // …
    final center = tester.getCenter(find.byType(FeedVideoPostView));
    expect(bridge.fire(center), isTrue,
        reason: 'view aktif harus attach handler');
    await tester.pump();
    // Verifikasi like/heart-burst memakai pola test existing file ini.
  });
```

CATATAN implementer: kerangka di atas sengaja menyisakan bagian pump & verifikasi — WAJIB diisi mengikuti pola test double-tap yang sudah ada di file yang sama (jangan menciptakan pola baru). Tambahkan juga assertion `bridge.fire(...)` mengembalikan `false` setelah view di-dispose atau `isActive` jadi false (pump ulang dengan isActive: false → fire false).

- [ ] **Step 4: Implementasi di FeedVideoPostView**

4a. Import (blok import relative dekat `double_tap_burst_guard.dart`):

```dart
import 'double_tap_like_pointer_detector.dart';
```

4b. Param widget (letakkan dekat param callback lain):

```dart
  /// Jembatan like eksternal dari detector settle di level layar (lihat
  /// DoubleTapLikePointerDetector). Null = layar tanpa detector luar.
  final ExternalDoubleTapLike? externalDoubleTapLike;
```

(+ tambahkan ke constructor sebagai `this.externalDoubleTapLike,` optional.)

4c. State — attach/detach mengikuti `isActive`:

```dart
  void _syncExternalDoubleTapLike() {
    final bridge = widget.externalDoubleTapLike;
    if (bridge == null) return;
    if (widget.isActive) {
      bridge.attach(_onExternalDoubleTapLike);
    } else {
      bridge.detach(_onExternalDoubleTapLike);
    }
  }

  /// Jalur like dari detector settle di layar (posisi GLOBAL ketukan kedua).
  /// Konversi ke lokal utk titik heart burst; _onDoubleTapLike juga
  /// me-register DoubleTapBurstGuard sehingga single-tap "ekor" yang sempat
  /// dilihat jalur dalam (play/pause) ikut tertekan.
  void _onExternalDoubleTapLike(Offset globalPosition) {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached) {
      _heartBurstPosition = box.globalToLocal(globalPosition);
    } else {
      _heartBurstPosition = null; // fallback: _onDoubleTapLike pakai center.
    }
    _onDoubleTapLike();
  }
```

Panggil `_syncExternalDoubleTapLike()` di `initState` dan `didUpdateWidget` (setelah logika existing; di didUpdateWidget tangani juga pergantian instance bridge: bila `oldWidget.externalDoubleTapLike != widget.externalDoubleTapLike`, detach dari yang lama dulu). Di `dispose`: `widget.externalDoubleTapLike?.detach(_onExternalDoubleTapLike);` SEBELUM super.dispose().

CATATAN implementer: cek bagaimana `_heartBurstPosition` dipakai `_onDoubleTapLike`/render burst — bila null tidak di-handle (tidak ada fallback center), pakai `_resolveLikeCenter()` (±2230) sebagai fallback alih-alih null. Sesuaikan dengan kode nyata, jangan menabrak perilaku existing.

- [ ] **Step 5: Jalankan test**

Run: `flutter test test/features/feed/widgets/feed_video_post_view_test.dart`
Expected: PASS semua (termasuk test predicate `onDoubleTap != null` ±924 — tidak tersentuh).

Run: `flutter test test/features/feed/widgets/double_tap_like_pointer_detector_test.dart`
Expected: PASS (16 test).

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/features/feed/widgets/double_tap_like_pointer_detector.dart flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/test/features/feed/widgets/double_tap_like_pointer_detector_test.dart flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
git commit -m "feat(feed): jembatan ExternalDoubleTapLike — like settle dirutekan ke view aktif"
```

---

### Task 4 (REVISI): Wiring dua layar (Feed utama + fullscreen)

**Files:**
- Modify: `flutter_app/lib/screens/feed_screen.dart` (±800: bungkus PageView.builder; ±828/±844: oper bridge ke FeedVideoPostView)
- Modify: `flutter_app/lib/screens/scoped_video_feed_screen.dart` (±769: bungkus PageView.builder; `_buildItem` ±686/±700: oper bridge ke KEDUA cabang)
- Test: jalankan suite existing kedua layar (regresi); tidak ada test baru wajib (perilaku settle sudah tercakup test detector Task 2; layar terlalu berat utk integrasi penuh — device-verify menutup sisanya).

**Interfaces:**
- Consumes: `DoubleTapLikePointerDetector` + `ExternalDoubleTapLike` (Task 2 & 3).
- Produces: tidak ada API baru.

- [ ] **Step 1: Wiring feed_screen.dart**

1a. Import:

```dart
import '../features/feed/widgets/double_tap_like_pointer_detector.dart';
```

(sesuaikan gaya path import file itu — cek import existing utk widgets feed.)

1b. Field state (dekat field controller lain):

```dart
  /// Jembatan like settle → FeedVideoPostView aktif (lihat
  /// DoubleTapLikePointerDetector utk kenapa detector di level layar).
  final ExternalDoubleTapLike _externalDoubleTapLike = ExternalDoubleTapLike();
```

1c. Bungkus `PageView.builder` (±800) — SEBELUM:

```dart
                    child: PageView.builder(
```

SESUDAH (detector membungkus langsung; jangan pindahkan NotificationListener existing bila ada):

```dart
                    child: DoubleTapLikePointerDetector(
                      onSettleDoubleTapLike: (globalPos) =>
                          _externalDoubleTapLike.fire(globalPos),
                      child: PageView.builder(
```

(+ tutup paren; jaga indentasi & trailing comma gaya file.)

1d. Oper bridge ke SEMUA instansiasi `FeedVideoPostView` di itemBuilder (±828 dan ±844):

```dart
                            externalDoubleTapLike: _externalDoubleTapLike,
```

CATATAN: post FOTO (carousel) TIDAK dioper bridge — lingkup video only; saat post aktif = foto, `fire()` return false dan tidak terjadi apa-apa (sama dengan perilaku sekarang).

- [ ] **Step 2: Wiring scoped_video_feed_screen.dart**

Sama polanya: import + field `_externalDoubleTapLike` + bungkus `PageView.builder` (±769, di dalam `NotificationListener<ScrollNotification>` existing — detector punya NotificationListener sendiri, aman nested) + oper `externalDoubleTapLike: _externalDoubleTapLike` di KEDUA cabang `_buildItem` (coordinator null ±686 dan managed ±700).

- [ ] **Step 3: Analyze + regresi layar**

Run: `flutter analyze lib/screens/feed_screen.dart lib/screens/scoped_video_feed_screen.dart lib/features/feed/widgets/double_tap_like_pointer_detector.dart lib/features/feed/widgets/feed_video_post_view.dart`
Expected: No issues baru (info pre-existing yang tidak menyentuh baris kita boleh).

Run: `flutter test test/screens/scoped_video_feed_screen_test.dart test/features/feed/`
Expected: PASS semua.

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/screens/feed_screen.dart flutter_app/lib/screens/scoped_video_feed_screen.dart
git commit -m "fix(feed): double-tap like responsif saat PageView settle — wiring Feed & fullscreen"
```

---

### Task 5: Sweep regresi penuh + PR (JANGAN merge)

**Files:** tidak ada perubahan kode baru (hanya verifikasi + PR).

- [ ] **Step 1: Suite gesture/feed terkait**

Run: `flutter test test/features/feed/ test/screens/scoped_video_feed_screen_test.dart test/screens/member_post_detail_double_tap_test.dart test/screens/member_post_detail_screen_fullscreen_test.dart`
Expected: PASS semua. Bila ada kegagalan di test yang mem-pin perilaku lama, JANGAN asal sesuaikan — laporkan dulu (perilaku lama seharusnya tidak berubah dalam desain revisi ini).

- [ ] **Step 2: Push + PR (JANGAN merge)**

```bash
git push -u origin claude/double-tap-like-settle
gh pr create --title "fix(feed): double-tap like responsif saat PageView masih settle" --body "..."
```

Isi body PR: akar masalah SEBENARNYA (IgnorePointer scrollable selama BallisticScrollActivity — bukan arena; sebutkan revisi desain), arsitektur detector-luar + gating ketukan-pertama + jembatan, hasil test, dan blok **Device-verify wajib** berisi checklist Step 3. JANGAN merge — tunggu hasil TestFlight user.

- [ ] **Step 3: Checklist device-verify (dikerjakan user di TestFlight)**

1. Swipe ke video berikut lalu SEGERA double-tap → like + burst heart muncul pada percobaan pertama (Feed utama DAN fullscreen).
2. Double-tap saat video sudah diam → tetap 1 like, tidak dobel (jalur lama).
3. Single-tap biasa → play/pause normal, TIDAK ikut ter-trigger saat burst-like (baik kasus diam maupun kasus settle).
4. Long-press kiri (2x speed) & tengah (peek pause) → masih jalan.
5. Pinch zoom media → tidak memicu like.
6. Swipe cepat beruntun antar video → tidak ada like nyasar.
7. Rapid-tap tombol komentar/share/like SAAT VIDEO DIAM → tidak ada like nyasar (gating: detector luar diam saat idle).
8. Bila like terasa terlalu "gampang"/"susah" nyala: laporkan — ambang `window`/`tapSlop` di `RawDoubleTapTracker` yang akan dituning.
