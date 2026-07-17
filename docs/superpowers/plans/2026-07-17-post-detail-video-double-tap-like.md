# Double-tap like di halaman Postingan (video) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Di halaman detail postingan (`MemberPostDetailScreen`), video mendukung double-tap-to-like dengan heart yang terbang ke tombol like, dan single tap membuka fullscreen secara ditunda (bukan langsung).

**Architecture:** Satukan single-tap dan double-tap ke SATU `GestureDetector` luar (pembungkus media) sehingga Flutter menunda single-tap sampai window double-tap lewat. Single-tap video memicu scoped feed lewat `onOpenScopedFeed` + anchor key yang diingat dari `onVideoAnchorReady`. Heart burst dipindah ke screen `Overlay` (koordinat global) memakai helper bersama `feedPostBuildFlyingBurstHeart` supaya bisa terbang dari titik jari di media ke tombol like di action row (di bawah media).

**Tech Stack:** Flutter, `flutter_test`. Reuse `feedPostBuildFlyingBurstHeart` + `FeedPostBurstHeart` dari `lib/features/feed/widgets/feed_post_shared_widgets.dart`.

## Global Constraints

- Double-tap = LIKE saja, tidak pernah un-like (Instagram behavior). Kalau sudah liked, burst tetap tampil tapi `onLike` tidak dipanggil lagi.
- Single tap video = buka fullscreen (scoped feed), TIDAK ada play/pause inline. Buka fullscreen boleh tertunda ~300ms (menunggu kepastian bukan double-tap) — ini diterima.
- Foto: perilaku double-tap-like tetap ada; hanya animasi heart di-upgrade ke fly-to agar seragam dengan video.
- Test memakai bounded pump-loop, BUKAN `pumpAndSettle` (repo ini hang di shimmer/network image). Pola sudah ada di `member_post_detail_screen_fullscreen_test.dart`.
- Semua perubahan kode di `lib/screens/member_post_detail_screen.dart`. Widget `_PostFeedItem` privat → test lewat `MemberPostDetailScreen` (pola harness sudah ada).

---

### Task 1: Satukan gesture — single-tap video (fullscreen, ditunda) + double-tap-like video

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart`
  - `_PostFeedItemState` (build media detector ~1400, dan `_PostMediaSurface` wiring ~1406-1418)
  - `_InlineVideoPlayer` (`_openFullscreen` ~2847, GestureDetector ~2869-2872)
  - `_PostMediaSurface` (field `onVideoExpandRequested` ~2222-2233, penerusan ke `_InlineVideoPlayer` ~2263)
- Test: `flutter_app/test/screens/member_post_detail_double_tap_test.dart` (baru)

**Interfaces:**
- Consumes: `widget.onOpenScopedFeed(String postId, GlobalKey anchorKey)` dan `widget.onVideoAnchorReady(String postId, GlobalKey anchorKey)` — sudah ada di `_PostFeedItem`.
- Produces: `_PostFeedItemState._videoAnchorKey` (GlobalKey?), `_PostFeedItemState._handleVideoSingleTap()`.

- [ ] **Step 1: Tulis test yang gagal — double-tap video like + tidak buka fullscreen; single-tap tetap buka fullscreen**

Buat `flutter_app/test/screens/member_post_detail_double_tap_test.dart`. Salin blok fakes + `_fakeVideoPost` + `pumpAndInitialize` + `disposeTree` dari `member_post_detail_screen_fullscreen_test.dart` (file itu memuat `_FakeVideoPlayerPlatform`, `_NoopCacheManager`, `_NoopMetadataStorage`, dan helper pump). Lalu tambahkan test berikut:

```dart
testWidgets('double-tap video likes without opening fullscreen', (tester) async {
  await pumpAndInitialize(tester);
  final center = tester.getCenter(find.byType(VideoPlayer).first);

  // Double tap dalam window kDoubleTapTimeout.
  await tester.tapAt(center);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(center);
  await tester.pump(const Duration(milliseconds: 50));

  // Like count naik jadi 1 (optimistic) → teks '1' muncul di action row.
  expect(find.text('1'), findsWidgets, reason: 'double-tap harus me-like');
  // Double-tap TIDAK membuka scoped feed.
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(ScopedVideoFeedScreen), findsNothing,
      reason: 'double-tap hanya like, bukan fullscreen');

  await disposeTree(tester);
});

testWidgets('single tap video still opens scoped feed (deferred)', (tester) async {
  await pumpAndInitialize(tester);
  await tester.tapAt(tester.getCenter(find.byType(VideoPlayer).first));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(ScopedVideoFeedScreen).evaluate().isNotEmpty) break;
  }
  expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
  await disposeTree(tester);
});

testWidgets('double-tap twice keeps liked (never un-likes)', (tester) async {
  await pumpAndInitialize(tester);
  final center = tester.getCenter(find.byType(VideoPlayer).first);

  // Dua kali double-tap beruntun.
  for (var round = 0; round < 2; round++) {
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 350));
  }

  // Tetap liked (count 1) — double-tap kedua tidak meng-un-like.
  expect(find.text('1'), findsWidgets,
      reason: 'double-tap saat sudah liked tidak boleh un-like');
  expect(find.text('0'), findsNothing);

  await disposeTree(tester);
});
```

**Catatan foto (sengaja tanpa test widget terpisah):** foto memakai JALUR KODE yang SAMA (`_handleDoubleTap` tidak lagi di-gate `post.isVideo`), jadi begitu video lulus, foto ikut benar. Test widget khusus foto dihindari karena `_ImageSurface` menembak network image yang membuat pump hang di lingkungan test (lihat pola semua test detail yang berbasis video + fake platform). Perilaku foto diverifikasi lewat kesamaan jalur kode, bukan test terpisah.

Tambahkan import yang dipakai: `package:natalo_petshop_flutter/screens/scoped_video_feed_screen.dart` (sudah dipakai di file sumber). `ScopedVideoFeedScreen` sudah ter-import di file fullscreen; pastikan ikut disalin.

- [ ] **Step 2: Jalankan test → pastikan GAGAL**

Run: `cd flutter_app && flutter test test/screens/member_post_detail_double_tap_test.dart`
Expected: FAIL — double-tap saat ini membuka fullscreen (dua single-tap ke inner `_openFullscreen`) sehingga `find.text('1')` tidak ada / `ScopedVideoFeedScreen` malah muncul.

- [ ] **Step 3: Ingat anchor key video di `_PostFeedItemState` + tambah handler single-tap**

Di `_PostFeedItemState`, tambah field setelah `Offset? _heartBurstPosition;`:

```dart
  // Anchor key video inline (dilaporkan lewat onVideoAnchorReady) — dipakai
  // outer detector untuk memicu fullscreen saat single tap (menggantikan
  // onTap milik _InlineVideoPlayer, supaya single & double tap satu detector).
  GlobalKey? _videoAnchorKey;
```

Tambah method di dalam `_PostFeedItemState`:

```dart
  void _rememberVideoAnchor(String postId, GlobalKey anchorKey) {
    _videoAnchorKey = anchorKey;
    widget.onVideoAnchorReady?.call(postId, anchorKey);
  }

  void _handleVideoSingleTap() {
    final anchorKey = _videoAnchorKey;
    if (anchorKey == null) return;
    widget.onOpenScopedFeed?.call(widget.post.id, anchorKey);
  }
```

- [ ] **Step 4: Satukan tap+double-tap di outer detector + intercept anchor**

Di `_PostFeedItemState.build`, ubah outer `GestureDetector` (yang membungkus media Stack). Ganti:

```dart
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: post.isVideo ? null : _rememberHeartBurstPosition,
          onDoubleTap: post.isVideo ? null : _handleDoubleTap,
          child: Stack(
```

menjadi:

```dart
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Single tap video → fullscreen (ditunda framework karena onDoubleTap
          // juga terpasang di detector yang SAMA). Foto: single tap no-op.
          onTap: post.isVideo ? _handleVideoSingleTap : null,
          onDoubleTapDown: _rememberHeartBurstPosition,
          onDoubleTap: _handleDoubleTap,
          child: Stack(
```

Lalu di `_PostMediaSurface(...)` yang jadi child Stack, ubah `onVideoAnchorReady: widget.onVideoAnchorReady,` menjadi `onVideoAnchorReady: _rememberVideoAnchor,`.

- [ ] **Step 5: Lepas tap fullscreen dari `_InlineVideoPlayer` + buang plumbing expand yang jadi mati**

Di `_InlineVideoPlayer` build, ubah GestureDetector anchor (sekitar 2869):

```dart
      child: GestureDetector(
        key: _anchorKey,
        behavior: HitTestBehavior.opaque,
        onTap: widget.dormant ? null : _openFullscreen,
        child: Stack(
```

menjadi (hapus `onTap`):

```dart
      child: GestureDetector(
        key: _anchorKey,
        behavior: HitTestBehavior.opaque,
        child: Stack(
```

Hapus method `_openFullscreen` (sekitar 2847-2849):

```dart
  void _openFullscreen() {
    widget.onExpandRequested?.call(widget.postId, _anchorKey);
  }
```

Hapus field `onExpandRequested` dari `_InlineVideoPlayer` (deklarasi + parameter constructor + pemakaian di `_PostMediaSurface`):
- Di `_InlineVideoPlayer`: hapus `final void Function(String sessionId, GlobalKey anchorKey)? onExpandRequested;` dan `this.onExpandRequested,` di constructor.
- Di `_PostMediaSurface.build` pemanggilan `_InlineVideoPlayer(... onExpandRequested: onVideoExpandRequested, ...)`: hapus baris `onExpandRequested: onVideoExpandRequested,`.
- Di `_PostMediaSurface`: hapus field `final void Function(String sessionId, GlobalKey anchorKey)? onVideoExpandRequested;` + `this.onVideoExpandRequested,`.
- Di `_PostFeedItemState.build`, pada `_PostMediaSurface(...)`: hapus blok:

```dart
                onVideoExpandRequested: (sessionId, anchorKey) {
                  widget.onOpenScopedFeed?.call(sessionId, anchorKey);
                },
```

Catatan: `_anchorKey` tetap ada di GestureDetector inner (dipakai transisi morph). `onVideoAnchorReady` sekarang di-intercept oleh `_rememberVideoAnchor` (Step 4).

- [ ] **Step 6: Jalankan test baru → pastikan LULUS**

Run: `cd flutter_app && flutter test test/screens/member_post_detail_double_tap_test.dart`
Expected: PASS kedua test.

- [ ] **Step 7: Jalankan test fullscreen lama → pastikan tidak ada regresi**

Run: `cd flutter_app && flutter test test/screens/member_post_detail_screen_fullscreen_test.dart`
Expected: PASS semua (single-tap masih membuka scoped feed via deferral; mute tetap terisolasi; handoff controller tetap).

- [ ] **Step 8: analyze**

Run: `cd flutter_app && flutter analyze lib/screens/member_post_detail_screen.dart`
Expected: No issues (tidak ada field/method mati tersisa).

- [ ] **Step 9: Commit**

```bash
git add flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/screens/member_post_detail_double_tap_test.dart
git commit -m "feat(postingan): video single-tap (fullscreen ditunda) + double-tap like satu detector"
```

---

### Task 2: Heart fly-to tombol like (video + foto) via screen Overlay

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart`
  - import; `_PostFeedItemState` controller init (~1275-1325), `_rememberHeartBurstPosition`/`_handleDoubleTap` (~1344-1358), burst overlay dalam Stack (~1432-1481), tombol like (~1500-1512), `dispose` (~1329-1333)
- Test: `flutter_app/test/screens/member_post_detail_double_tap_test.dart` (tambah test)

**Interfaces:**
- Consumes: `feedPostBuildFlyingBurstHeart({Offset? tap, Offset? target, double scale, double opacity, double travel, Size screenSize})` dan `FeedPostBurstHeart` dari `feed_post_shared_widgets.dart`.
- Produces: `_PostFeedItemState._likeButtonKey` (GlobalKey), `_burstTravel` (Animation<double>), `_flyingHeartEntry` (OverlayEntry?).

- [ ] **Step 1: Tulis test yang gagal — double-tap memunculkan FeedPostBurstHeart di overlay**

Tambah di `member_post_detail_double_tap_test.dart` (import `feed_post_shared_widgets.dart`):

```dart
testWidgets('double-tap shows a flying burst heart overlay', (tester) async {
  await pumpAndInitialize(tester);
  final center = tester.getCenter(find.byType(VideoPlayer).first);

  await tester.tapAt(center);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(center);
  await tester.pump(const Duration(milliseconds: 30));

  expect(find.byType(FeedPostBurstHeart), findsOneWidget,
      reason: 'burst heart harus dirender di overlay saat double-tap');

  // Setelah animasi selesai, overlay dibersihkan.
  await tester.pump(const Duration(milliseconds: 700));
  expect(find.byType(FeedPostBurstHeart), findsNothing,
      reason: 'burst heart harus hilang setelah animasi');

  await disposeTree(tester);
});
```

Import: `import 'package:natalo_petshop_flutter/features/feed/widgets/feed_post_shared_widgets.dart';`

- [ ] **Step 2: Jalankan test → pastikan GAGAL**

Run: `cd flutter_app && flutter test test/screens/member_post_detail_double_tap_test.dart -n "flying burst heart"`
Expected: FAIL — saat ini burst pakai `Icon(Icons.favorite_rounded)` inline (bukan `FeedPostBurstHeart`) dan di-render di dalam media, bukan overlay.

- [ ] **Step 3: Tambah travel animation + like key + import**

Di atas file, tambah import setelah import screens/features lain:

```dart
import '../features/feed/widgets/feed_post_shared_widgets.dart';
```

Di `_PostFeedItemState`, tambah field:

```dart
  late final Animation<double> _burstTravel;
  final GlobalKey _likeButtonKey = GlobalKey();
  OverlayEntry? _flyingHeartEntry;
```

Di `initState`, setelah `_burstOpacity = ...` selesai, tambah:

```dart
    // Terbang ke tombol like: mulai setelah pop (0.5) lalu melesat easeIn.
    _burstTravel = CurvedAnimation(
      parent: _heartBurstController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInCubic),
    );
```

- [ ] **Step 4: Ubah simpan posisi ke GLOBAL + resolve pusat tombol like**

Ganti `_rememberHeartBurstPosition`:

```dart
  void _rememberHeartBurstPosition(TapDownDetails details) {
    _heartBurstPosition = details.localPosition;
  }
```

menjadi (pakai global position untuk overlay screen-level):

```dart
  void _rememberHeartBurstPosition(TapDownDetails details) {
    _heartBurstPosition = details.globalPosition;
  }

  Offset? _resolveLikeCenter() {
    final box =
        _likeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }
```

- [ ] **Step 5: `_handleDoubleTap` menyisipkan flying-heart overlay; hapus burst in-media**

Ganti `_handleDoubleTap`:

```dart
  void _handleDoubleTap() {
    AppHaptics.impact();
    if (!widget.liked) {
      _handleLikeTap();
    }
    _heartBurstController.forward(from: 0);
  }
```

menjadi:

```dart
  void _handleDoubleTap() {
    AppHaptics.impact();
    if (!widget.liked) {
      _handleLikeTap();
    }
    _showFlyingHeart();
  }

  void _showFlyingHeart() {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _flyingHeartEntry?.remove();
    final tap = _heartBurstPosition;
    final target = _resolveLikeCenter();
    final entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _heartBurstController,
          builder: (context, _) => feedPostBuildFlyingBurstHeart(
            tap: tap,
            target: target,
            scale: _burstScale.value,
            opacity: _burstOpacity.value,
            travel: _burstTravel.value,
            screenSize: MediaQuery.sizeOf(context),
          ),
        ),
      ),
    );
    _flyingHeartEntry = entry;
    overlay.insert(entry);
    _heartBurstController.forward(from: 0).whenComplete(() {
      _flyingHeartEntry?.remove();
      _flyingHeartEntry = null;
    });
  }
```

Hapus seluruh blok burst overlay in-media di dalam Stack (sekarang digantikan overlay). Hapus dari `Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: _heartBurstController, ...)))` yang membangun `Icon(Icons.favorite_rounded ...)` — yaitu blok yang diawali komentar `// Heart burst overlay — posisi mengikuti titik double-tap.` sampai penutup `),` sebelum `],` Stack. Media Stack sekarang hanya berisi `_PostMediaSurface` dan (untuk video) `_VideoPostAuthorOverlay`.

- [ ] **Step 6: Pasang key di tombol like + bersihkan overlay di dispose**

Di action row, tombol like `NataloPostActionButton(type: NataloPostActionIconType.like, ...)` dibungkus `ScaleTransition`. Tambahkan `key: _likeButtonKey` pada `NataloPostActionButton` like tersebut:

```dart
              ScaleTransition(
                scale: _heartScale,
                child: NataloPostActionButton(
                  key: _likeButtonKey,
                  type: NataloPostActionIconType.like,
                  ...
```

Di `dispose`, sebelum `super.dispose()`, bersihkan overlay:

```dart
    _flyingHeartEntry?.remove();
    _flyingHeartEntry = null;
```

- [ ] **Step 7: Jalankan test → pastikan LULUS**

Run: `cd flutter_app && flutter test test/screens/member_post_detail_double_tap_test.dart`
Expected: PASS semua (termasuk test Task 1 yang tetap hijau — like via double-tap sekarang lewat `_showFlyingHeart`).

- [ ] **Step 8: analyze**

Run: `cd flutter_app && flutter analyze lib/screens/member_post_detail_screen.dart`
Expected: No issues (tidak ada `_heartBurstPosition`/tween yang mati; `_burstScale`/`_burstOpacity`/`_burstTravel` semua terpakai di `_showFlyingHeart`).

- [ ] **Step 9: Commit**

```bash
git add flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/screens/member_post_detail_double_tap_test.dart
git commit -m "feat(postingan): heart double-tap terbang ke tombol like (video + foto) via shared overlay"
```

---

### Task 3: Verifikasi menyeluruh

**Files:** tidak ada perubahan kode.

- [ ] **Step 1: Jalankan seluruh test detail postingan**

Run: `cd flutter_app && flutter test test/screens/member_post_detail_screen_fullscreen_test.dart test/screens/member_post_detail_double_tap_test.dart test/screens/member_post_detail_screen_caption_test.dart test/screens/member_post_detail_screen_coordinator_test.dart test/screens/member_post_detail_comment_identity_test.dart`
Expected: PASS semua.

- [ ] **Step 2: Jalankan seluruh suite (tangkap regresi)**

Run: `cd flutter_app && flutter test`
Expected: Hanya kegagalan pre-existing yang sudah dikenal (`origin_expansion_route_test.dart` 2 fail drag-flaky; `feed_comment_drawer_terminal_state_test.dart` bila masih). Tidak ada kegagalan baru terkait `member_post_detail`.

- [ ] **Step 3: Commit (kalau ada penyesuaian)** — kalau semua sudah hijau tanpa perubahan, lewati.
