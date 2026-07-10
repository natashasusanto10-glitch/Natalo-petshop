# Video Produk — Plan 2: Tampilan App Flutter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Tampilkan video produk di app Flutter — grid Beranda autoplay bisu visible-only, dan galeri detail dengan video sebagai slide #1 (play manual).

**Architecture:** Data-only + UI. API sudah mengekspos `videoUrl` (HLS `.m3u8`), `videoThumbnailUrl`, `videoDurationSec` (hanya saat "ready"). Flutter `video_player` memutar HLS Bunny **langsung** (native AVPlayer/ExoPlayer) — TANPA derive MP4 (beda dari web). Grid: widget video per-kartu bergaya `_InlineVideoPlayer` (VisibilityDetector, bisu+loop, controller dibuat **lazy saat pertama terlihat**, dispose saat lewat) + registry Dart yang membatasi jumlah controller grid aktif. Detail: video slide #1 di `_ProductHero` PageView.

**Tech Stack:** Flutter 3.41.9, `video_player: ^2.10.0`, `visibility_detector: ^0.4.0+2`, `cached_network_image: ^3.4.1` (semua sudah dep — tak ada perubahan pubspec).

## Global Constraints

- TANPA perubahan API/DB. Konsumsi field video dari JSON produk yang sudah ada (`videoUrl`/`videoThumbnailUrl`/`videoDurationSec`, camelCase, non-null hanya saat "ready").
- Flutter putar **HLS `videoUrl` langsung** (`VideoPlayerController.networkUrl`). JANGAN derive MP4, JANGAN pakai `cached_video_player_plus` untuk `.m3u8` (segmen tak ke-cache — ikuti pola feed `feed_screen.dart:469-498`).
- **Grid autoplay**: bisu (`setVolume(0)`), loop (`setLooping(true)`), **visible-only** (VisibilityDetector, main saat `visibleFraction >= 0.6`, pause saat < 0.6), **controller dibuat lazy saat pertama terlihat** (BUKAN di `initState`/`build` — `_RecommendationGrid` build semua kartu sekaligus, akan spawn banyak stream kalau eager). **Batas jumlah controller grid aktif via registry** (maks 3). **Dispose controller saat scroll-away/unmount + lepas slot registry**. **Fallback foto** (`CachedNetworkImage` cover) selalu tampil sebelum siap / saat gagal — TAK PERNAH kotak hitam. Grid TIDAK ada tombol unmute (selalu bisu).
- **Detail**: video slide #1, thumbnail (`videoThumbnailUrl`) + tombol play, **play manual in-place** (bukan buka `ImageViewerScreen`), dengan suara + kontrol; pause saat pindah slide. Foto-foto menyusul slide 2+; `ImageViewerScreen` tetap foto-saja.
- Verifikasi: `flutter analyze` 0 issue baru (subagent jalankan `flutter pub get` dulu). Widget test opsional — GOTCHA [[flutter-widget-test-shimmer-hang]]: `pumpAndSettle` hang saat gambar/shimmer; pakai bounded pump-loop kalau bikin test. TIDAK bisa jalan di device/emulator di sini → device-verify = gate manual.
- Kerja di worktree `.claude/worktrees/product-video-flutter`, branch `claude/product-video-flutter-display`. Commit tiap task. JANGAN commit di main tree.
- Gotcha [[grid-shopee-redesign]]: `_HomeProductCard` dipakai juga oleh rail (`_MiniProductCard` `squareImage:false`) — video HANYA untuk kartu `squareImage:true` (grid Beranda), jangan aktif di rail.

## File Structure

**Modify:**
- `flutter_app/lib/models/product.dart` — 3 field video + parse di `fromApiJson` + `toJson` round-trip + getter `hasVideo`.
- `flutter_app/lib/screens/home_screen.dart` — `_HomeProductCard` image `Stack` (ternary ~3014-3021): saat `product.hasVideo && squareImage` render widget video, else `_HomeProductImageSquare` existing.
- `flutter_app/lib/screens/product_detail_screen.dart` — `_ProductHero`/`_ProductHeroState`: prepend video slide #0 saat `hasVideo`.

**Create:**
- `flutter_app/lib/widgets/product_grid_video_registry.dart` — singleton pembatas jumlah controller video grid aktif (maks 3).
- `flutter_app/lib/widgets/product_grid_video.dart` — widget video per-kartu grid (VisibilityDetector + lazy controller + bisu/loop + fallback foto + registry).
- `flutter_app/lib/widgets/product_detail_video_slide.dart` — widget slide video detail (thumbnail+play → play manual in-place).

---

## Task 1: Field video di model Product

**Files:** Modify `flutter_app/lib/models/product.dart`.

**Interfaces:** Produces `Product.videoUrl`/`videoThumbnailUrl`/`videoDurationSec` + `bool get hasVideo`.

- [ ] **Step 1: Tambah field + getter**

Di `class Product` (mulai ~line 353), dekat `imageUrl` (line 359), tambah:
```dart
  final String? videoUrl;
  final String? videoThumbnailUrl;
  final int? videoDurationSec;
```
Di getter area (~584-628) tambah:
```dart
  /// True kalau produk punya video "ready" (server hanya kirim videoUrl saat ready).
  bool get hasVideo => (videoUrl ?? '').isNotEmpty;
```

- [ ] **Step 2: Constructor params**

Di constructor `Product({...})` (~409-437) tambah param opsional named:
```dart
    this.videoUrl,
    this.videoThumbnailUrl,
    this.videoDurationSec,
```

- [ ] **Step 3: Parse di `fromApiJson`**

Di `factory Product.fromApiJson` (~451-555), setelah parsing `imageUrl` (~496), tambah ke objek yang di-return:
```dart
      videoUrl: _stringOrNull(json['videoUrl']),
      videoThumbnailUrl: _stringOrNull(json['videoThumbnailUrl']),
      videoDurationSec: _asIntOrNull(json['videoDurationSec']),
```
(`_stringOrNull` ~692, `_asIntOrNull` ~716 sudah ada — konfirmasi signature-nya saat implement.)

- [ ] **Step 4: `toJson` round-trip**

Di `Map<String,dynamic> toJson()` (~559-582) tambah supaya produk dari cache lokal (recently-viewed/cart) tak kehilangan video:
```dart
      'videoUrl': videoUrl,
      'videoThumbnailUrl': videoThumbnailUrl,
      'videoDurationSec': videoDurationSec,
```

- [ ] **Step 5: Analyze + commit**

Run: `cd flutter_app && flutter pub get && flutter analyze lib/models/product.dart` → 0 issue baru.
```bash
git add flutter_app/lib/models/product.dart
git commit -m "feat(flutter/product-video): field video di model Product"
```

---

## Task 2: Registry pembatas controller video grid

**Files:** Create `flutter_app/lib/widgets/product_grid_video_registry.dart`.

**Interfaces:** Produces singleton `ProductGridVideoRegistry` dengan `bool tryAcquire(Object owner)`, `void release(Object owner)`, dan callback saat slot bebas (`void Function() addListener(...)` / `removeListener`).

- [ ] **Step 1: Implementasi**

```dart
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
```

- [ ] **Step 2: Analyze + commit**

Run: `cd flutter_app && flutter analyze lib/widgets/product_grid_video_registry.dart` → 0 issue.
```bash
git add flutter_app/lib/widgets/product_grid_video_registry.dart
git commit -m "feat(flutter/product-video): registry pembatas controller video grid"
```

---

## Task 3: Widget video per-kartu grid (autoplay visible-only)

**Files:** Create `flutter_app/lib/widgets/product_grid_video.dart`.

**Interfaces:** Produces `ProductGridVideo({ required String videoUrl, required String? imageUrl })` — StatefulWidget 1:1 yang menampilkan foto sebagai dasar + video autoplay bisu saat terlihat.

**Reference:** model pada `_InlineVideoPlayer` (`flutter_app/lib/screens/member_post_detail_screen.dart:1825-1948`) — VisibilityDetector + bisu+loop. TAPI: (a) buat controller **lazy saat pertama terlihat** (bukan `initState`), (b) gate via registry, (c) dispose + release saat scroll-away.

- [ ] **Step 1: Implementasi**

Poin wajib:
- `AspectRatio(aspectRatio: 1)` (cover) supaya konsisten dengan `_HomeProductImageSquare`.
- Dasar SELALU `CachedNetworkImage(imageUrl, fit: BoxFit.cover)` (fallback). Video di atasnya, opacity 0 → fade in saat sudah `value.isInitialized && isPlaying`.
- `VisibilityDetector(key: ValueKey(videoUrl))` → `onVisibilityChanged`: simpan `visibleFraction`. Kalau `>= 0.6` → `_ensureAndPlay()`; else → `_stopAndRelease()`.
- `_ensureAndPlay()`: kalau controller belum ada → cek `ProductGridVideoRegistry.instance.tryAcquire(this)`; kalau gagal → tetap foto, daftar `addSlotFreeListener(_onSlotFree)` (retry saat slot bebas). Kalau dapat slot → buat `VideoPlayerController.networkUrl(Uri.parse(videoUrl))`, `initialize()` → `setLooping(true)`, `setVolume(0)`, `play()`, `setState` (fade in). (Pola HLS langsung, seperti feed.)
- `_stopAndRelease()`: `controller?.pause()`, dispose controller, null-kan, `registry.release(this)`, `removeSlotFreeListener`.
- `_onSlotFree()`: kalau masih `visibleFraction >= 0.6` dan belum ada controller → `_ensureAndPlay()`.
- `onError`/initialize gagal → tetap tampil foto (jangan kotak hitam), release slot.
- `dispose()` widget: `_stopAndRelease()` + `removeSlotFreeListener`.
- Chip kecil ikon video/🔇 opsional pojok (subtle) — boleh, kecil.

Gunakan `VideoPlayerController.networkUrl` (bukan cached wrapper) untuk `.m3u8`. Tirukan penanganan init/looping/volume dari `_InlineVideoPlayer` `_initialize()` (member_post_detail_screen.dart:1867-1907), tapi lazy + registry-gated.

- [ ] **Step 2: Analyze + commit**

Run: `cd flutter_app && flutter analyze lib/widgets/product_grid_video.dart` → 0 issue baru.
```bash
git add flutter_app/lib/widgets/product_grid_video.dart
git commit -m "feat(flutter/product-video): widget grid autoplay visible-only + fallback foto"
```

---

## Task 4: Pasang video ke grid Beranda (`_HomeProductCard`)

**Files:** Modify `flutter_app/lib/screens/home_screen.dart`.

**Interfaces:** Consumes `ProductGridVideo` (Task 3), `Product.hasVideo` (Task 1).

- [ ] **Step 1: Swap image square → video saat hasVideo**

Di `_HomeProductCard` build, `imageStack` (~3012-3052), ternary square (~3014-3021):
```dart
child: squareImage
    ? (product.hasVideo
        ? ProductGridVideo(videoUrl: product.videoUrl!, imageUrl: product.imageUrl)
        : _HomeProductImageSquare(imageUrl: product.imageUrl))
    : _HomeProductImage(imageUrl: product.imageUrl, height: 132),
```
Import `ProductGridVideo`. JANGAN ubah badge (diskon/rank/brand) yang overlay di atas Stack — mereka tetap. Video HANYA di path `squareImage` (rail `squareImage:false` tetap foto).

- [ ] **Step 2: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/home_screen.dart` → 0 issue baru. (Both Beranda call sites — infinite grid 835 + `_RecommendationGrid` 4306/4315 — otomatis kena karena keduanya render `_HomeProductCard(squareImage:true)`. `_RecommendationGrid` build eager tapi controller lazy di Task 3 → aman.)

- [ ] **Step 3: Commit**
```bash
git add flutter_app/lib/screens/home_screen.dart
git commit -m "feat(flutter/product-video): grid Beranda autoplay video saat ada"
```

---

## Task 5: Widget slide video detail (manual play)

**Files:** Create `flutter_app/lib/widgets/product_detail_video_slide.dart`.

**Interfaces:** Produces `ProductDetailVideoSlide({ required String videoUrl, required String? thumbnailUrl, int? durationSec })` — StatefulWidget: thumbnail + tombol play → play manual in-place; expose cara pause dari parent saat swipe (via `GlobalKey` state method atau controller callback).

- [ ] **Step 1: Implementasi**

- Sebelum play: `CachedNetworkImage(thumbnailUrl, fit: BoxFit.cover)` + tombol ▶ besar di tengah + badge durasi (`durationSec` → mm:ss, sembunyi kalau null) + tag "Video".
- Tap ▶: buat `VideoPlayerController.networkUrl(Uri.parse(videoUrl))`, `initialize()` → `setLooping(false)`, **suara ON** (volume default), `play()`, `setState` (tampilkan `VideoPlayer` + kontrol dasar: tap toggle play/pause, mungkin `VideoProgressIndicator`). Play dipicu langsung oleh gesture (native gesture, aman).
- `onError`/init gagal → balik ke thumbnail + tombol ▶ (retry).
- Expose `void pauseIfPlaying()` (via `GlobalKey<State>` atau callback) supaya `_ProductHero` bisa pause saat user swipe ke slide lain.
- `dispose()`: dispose controller.

- [ ] **Step 2: Analyze + commit**

Run: `cd flutter_app && flutter analyze lib/widgets/product_detail_video_slide.dart` → 0 issue baru.
```bash
git add flutter_app/lib/widgets/product_detail_video_slide.dart
git commit -m "feat(flutter/product-video): widget slide video detail (manual play)"
```

---

## Task 6: Pasang video slide #1 di galeri detail (`_ProductHero`)

**Files:** Modify `flutter_app/lib/screens/product_detail_screen.dart`.

**Interfaces:** Consumes `ProductDetailVideoSlide` (Task 5), `Product.hasVideo`.

- [ ] **Step 1: Tambah video slide #0**

Di `_ProductHeroState` (~685-857):
- Definisikan `bool get _hasVideo => widget.product.hasVideo;` dan `int get _slideCount => _images.length + (_hasVideo ? 1 : 0);`.
- `PageView.builder` (~736-799): `itemCount: _slideCount`. Di `itemBuilder(context, index)`:
  - Kalau `_hasVideo && index == 0` → `ProductDetailVideoSlide(videoUrl: widget.product.videoUrl!, thumbnailUrl: widget.product.videoThumbnailUrl, durationSec: widget.product.videoDurationSec)` (simpan `GlobalKey` untuk pause). JANGAN bungkus dengan GestureDetector→ImageViewerScreen.
  - Else → hitung `final imageIndex = index - (_hasVideo ? 1 : 0);` lalu render slide foto existing (`AppProductImage(imageUrl: _images[imageIndex], fit: BoxFit.contain)` + GestureDetector→`ImageViewerScreen(images: _images, initialIndex: imageIndex)`). `ImageViewerScreen` tetap terima `_images` (foto saja).
- Dot indicators (~801-824) + counter `x/y` (~825-847): pakai `_slideCount` (bukan `_images.length`), dan active index apa adanya dari PageController.
- `onPageChanged`: kalau pindah dari slide 0 (video) → panggil `videoSlideKey.currentState?.pauseIfPlaying()`.

- [ ] **Step 2: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/product_detail_screen.dart` → 0 issue baru. Cek index mapping: buka foto ke-N buka `_images[N-1]` saat ada video; video tak pernah buka `ImageViewerScreen`.

- [ ] **Step 3: Commit**
```bash
git add flutter_app/lib/screens/product_detail_screen.dart
git commit -m "feat(flutter/product-video): video slide #1 di galeri detail produk"
```

---

## Task 7: Verifikasi akhir

- [ ] **Step 1: Analyze menyeluruh**

Run: `cd flutter_app && flutter pub get && flutter analyze 2>&1 | tail -20` → 0 issue baru (bandingkan dengan baseline analyze sebelum perubahan; warning pre-existing boleh).

- [ ] **Step 2: Widget test (opsional, kalau praktis)**

Kalau menulis test untuk `ProductGridVideo`/registry: pakai bounded pump-loop bukan `pumpAndSettle` ([[flutter-widget-test-shimmer-hang]]); mock/hindari network video di test. Kalau ragu, lewati — analyze + device-verify cukup.

> **DEVICE-VERIFY (gate manual — tak bisa di sandbox):**
> Rilis app (APK/TestFlight) → Beranda: kartu produk bervideo autoplay bisu saat terlihat, foto saat lainnya, tak ada kotak hitam, scroll mulus, maks ~3 main bersamaan (cek HP low-end tak lag). Detail produk bervideo: slide #1 = thumbnail + ▶, tap → main dengan suara + kontrol, swipe → pause. **iOS + Android**. Kalau MP4/HLS gagal load → tetap foto/thumbnail (tak rusak).

## Self-Review
- Grid autoplay visible-only + registry + fallback foto → Task 2/3/4. Detail slide #1 manual → Task 5/6. HLS langsung (no MP4) → Task 3/5. Data field → Task 1. Rail tak kena (squareImage guard) → Task 4. ✓
- Gotcha `_RecommendationGrid` eager-build → controller lazy di Task 3 (dibuat saat pertama terlihat) → aman. ✓
- Placeholder: tidak ada. Nama/tipe konsisten: `ProductGridVideo`/`ProductDetailVideoSlide`/`ProductGridVideoRegistry`/`hasVideo` dipakai konsisten lintas task.

## Catatan
- **Kualitas adaptif opsional (fast-follow)**: `videoQualityService.resolvePlaybackUrl()` (`flutter_app/lib/services/video_quality_service.dart:142-195`) bisa dipakai untuk pilih HLS/MP4 per tier jaringan — TIDAK dipakai di v1 (pakai `videoUrl` langsung); tambah nanti kalau perlu hemat data di grid.
- Deploy: fitur baru tampil setelah **rilis app Flutter** (beda dari web yang auto-deploy). API sudah live.
