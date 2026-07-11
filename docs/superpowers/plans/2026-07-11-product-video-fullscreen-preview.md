# Video Produk — Preview Fullscreen (video di ImageViewerScreen) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Niru alur Tokopedia/Shopee: di detail produk, tombol **⛶** di pojok video → buka **preview fullscreen** (`ImageViewerScreen`) di mana **video jadi slide 1 dan AUTOPLAY (dengan suara)**, foto jadi slide 2+. ▶ inline di detail TETAP (tak diubah).

**Architecture:** UI-only, TANPA API/DB. `ImageViewerScreen` (sekarang foto-saja, `image_viewer_screen.dart`) diperluas menerima video opsional dan menampilkannya sebagai slide #0 (autoplay-saat-aktif, contain di latar hitam, suara + kontrol). `ProductDetailVideoSlide` dapat tombol ⛶ + callback `onOpenFullscreen`. `_ProductHero` (`product_detail_screen.dart`) mengirim video ke viewer di kedua jalur (tap ⛶ → slide 0; tap foto → slide foto), dengan `initialIndex` berbasis **slide index** (video+foto), bukan foto index.

**Tech Stack:** `video_player` (HLS `.m3u8` langsung), `cached_network_image`, sudah dep. Base: main `6e342c44`. Branch `claude/product-video-fullscreen-preview`, worktree `.claude/worktrees/product-video-flutter` (pub get sudah).

## Global Constraints
- TANPA API/DB. Video pakai field yang sudah ada di `Product`: `videoUrl` (HLS), `videoThumbnailUrl`, `videoDurationSec`, + `imageUrl` (poster fallback).
- Flutter putar HLS `videoUrl` LANGSUNG (`VideoPlayerController.networkUrl`) — JANGAN derive MP4, JANGAN cached wrapper utk `.m3u8`.
- **Preview fullscreen video** = **autoplay saat jadi slide aktif**, **DENGAN suara** (default options), **tap toggle play/pause**, **tombol mute** (toggle `setVolume`), **progress bar** (scrub), contain di latar hitam. Pause otomatis saat di-swipe ke slide lain (controller tetap hidup, main lagi saat balik). Dispose saat viewer ditutup.
- **Race dispose-saat-initialize**: setelah tiap `await`, guard `if (!mounted || !identical(_controller, controller)) { dispose; return; }` sebelum play/setState.
- **Render tanpa distorsi**: `Center + FittedBox(BoxFit.contain, SizedBox(size = controller.value.size, VideoPlayer))` di latar hitam (pola feed feed_screen.dart:4022-4035; sama dgn `ProductDetailVideoSlide` playing state).
- **Index mapping**: viewer sekarang berbasis SLIDE (video+foto). `initialIndex` = slide index. Tap foto ke-N di hero (hero slide `index`) → viewer slide `index` (struktur hero & viewer identik: video 0 + foto 1+). Tap ⛶ → viewer slide 0.
- **Gesture**: slide video BUKAN `_ZoomableImage` (tak ada pinch-zoom); tap = play/pause SAJA (jangan makan horizontal drag → PageView tetap swipe). `_zoomed`/`_multiTouch` lock tetap hanya utk foto.
- ▶ inline `ProductDetailVideoSlide` TIDAK diubah. Saat ⛶ ditekan: `pauseIfPlaying()` dulu (cegah dobel suara) baru buka viewer.
- Verifikasi: `flutter analyze` 0 issue baru + `flutter test` file terdampak (cart_store, product_voucher_preview, added_to_cart_sheet, cart_screen_anchor) hijau. Device-verify iOS+Android = gate manual.
- Commit tiap task. JANGAN commit di main tree.

## File Structure
**Modify:**
- `flutter_app/lib/screens/image_viewer_screen.dart` — param video opsional + slide video #0 + widget video internal + thumbnail video-first + counter/index berbasis slide.
- `flutter_app/lib/widgets/product_detail_video_slide.dart` — tombol ⛶ + `onOpenFullscreen` callback.
- `flutter_app/lib/screens/product_detail_screen.dart` — `_ProductHero`: kirim video ke `ImageViewerScreen` (tap ⛶ & tap foto) + `initialIndex` berbasis slide.

---

## Task 1: Widget video preview fullscreen (autoplay-saat-aktif)

**Files:** Modify `flutter_app/lib/screens/image_viewer_screen.dart` (tambah private widget `_PreviewVideoSlide`; BELUM diwire di Task 2).

**Interfaces:** Produces private `_PreviewVideoSlide({ required String videoUrl, required String? thumbnailUrl, String? posterImageUrl, required bool active })` — StatefulWidget fullscreen: autoplay saat `active`, pause saat tidak.

- [ ] **Step 1: Implementasi**
- Field: `VideoPlayerController? _controller`, `bool _initializing`, `bool _failed`, `bool _muted = false`, `bool _ready = false`.
- `initState`: kalau `widget.active` → `_ensure()`.
- `didUpdateWidget`: kalau `active` berubah true→false → `_controller?.pause()`; false→true → kalau controller ada `_controller!.play()`, else `_ensure()`.
- `_ensure()`: kalau controller sudah ada → `play()`; else buat `VideoPlayerController.networkUrl(Uri.parse(videoUrl))` (DEFAULT options — bersuara), `_controller = c`, `_initializing = true`, `await c.initialize()` → **guard race** `if (!mounted || !identical(_controller, c)) { unawaited(c.dispose()); return; }` → `setLooping(false)`, `setVolume(_muted ? 0 : 1)`, kalau `widget.active` `play()`, `setState(_ready=true, _initializing=false)`. Bungkus try/catch → `_failed=true`, tetap tampil poster (JANGAN kotak hitam).
- Render:
  - Belum ready / failed → poster: `CachedNetworkImage(thumbnailUrl ?? posterImageUrl, fit: BoxFit.contain)` di latar hitam + spinner kecil (kalau initializing) atau ▶ (kalau failed, tap = retry `_ensure`).
  - Ready → `Center + FittedBox(BoxFit.contain, SizedBox(size = _controller.value.size, VideoPlayer(_controller)))` di `ColoredBox(Colors.black)`.
  - `GestureDetector(onTap: toggle play/pause)` — **onTap SAJA** (jangan drag). Tampilkan ikon ⏸/▶ sekejap saat toggle.
  - `VideoProgressIndicator(_controller, allowScrubbing: true, colors: VideoProgressColors(playedColor: <brand blue>))` tipis di bawah area video (di atas ruang bar produk — posisikan aman, mis. bottom padding + ~180 supaya tak ketiban `_ProductMediaBar`; koordinasikan di Task 2 kalau perlu). Untuk Task 1 taruh progress + tombol mute di dalam widget, posisi pojok/atas yang tak bentrok.
  - Tombol **mute** (pojok, kapsul hitam `Colors.black.withValues(alpha:0.55)` radius 999, ikon `Icons.volume_off_rounded`/`Icons.volume_up_rounded`) → toggle `_muted` + `_controller?.setVolume(_muted?0:1)`.
- `dispose()`: `_controller?.dispose()`.
- `_brandBlue`: pakai `NataloColors.nataloBlue` (import natalo colors; JANGAN private dari file lain).

- [ ] **Step 2: Analyze + commit**
`cd flutter_app && flutter analyze lib/screens/image_viewer_screen.dart` → 0 issue baru.
```bash
git add flutter_app/lib/screens/image_viewer_screen.dart
git commit -m "feat(flutter/product-video): widget video preview fullscreen (autoplay-saat-aktif + suara + mute)"
```

---

## Task 2: Wire video ke ImageViewerScreen (slide #0 + thumbnail + counter)

**Files:** Modify `flutter_app/lib/screens/image_viewer_screen.dart`.

**Interfaces:** `ImageViewerScreen` dapat param opsional `videoUrl`/`videoThumbnailUrl`/`videoDurationSec` + `posterImageUrl`. Consumes `_PreviewVideoSlide` (Task 1).

- [ ] **Step 1: Param + slide model**
- Tambah field: `final String? videoUrl; final String? videoThumbnailUrl; final int? videoDurationSec;` di constructor (opsional). `bool get hasVideo => (videoUrl ?? '').isNotEmpty;`.
- Total slide = `hasVideo ? list.length + 1 : list.length` (`list` = foto). Video = slide 0.

- [ ] **Step 2: PageView itemBuilder + index mapping**
- `itemCount` = total slide. `itemBuilder(context, i)`:
  - `hasVideo && i == 0` → `_PreviewVideoSlide(videoUrl: widget.videoUrl!, thumbnailUrl: widget.videoThumbnailUrl, posterImageUrl: widget.posterImageUrl, active: _index == 0)`. (Video slide BUKAN `_ZoomableImage`; tak ada zoom.)
  - else → `final imgI = i - (hasVideo ? 1 : 0);` → `_ZoomableImage(imageUrl: images[imgI], ...)` (existing).
- `_index` init: `widget.initialIndex.clamp(0, totalSlide-1)`.
- `onPageChanged`: set `_index`. (Video pause-saat-tak-aktif otomatis via `active` prop yang re-evaluasi tiap build; pastikan build pakai `_index`.)
- **Empty guard** (line ~119 `images.isEmpty`): jadi `images.isEmpty && !hasVideo` (video-only tetap tampil video).
- Zoom lock `_zoomed`/`_multiTouch` tetap hanya dari foto — slide video tak set `_zoomed` (tak ada InteractiveViewer). Aman.

- [ ] **Step 3: Counter + thumbnail strip video-first**
- `_ProductMediaCounter` total = total slide; current = `_index + 1`.
- `_ProductMediaThumbnails`: tambah param opsional `videoThumbnailUrl` + `videoDurationSec`. Kalau ada, item pertama = thumbnail video (`CachedNetworkImage(videoThumbnailUrl)` fallback poster) dengan overlay ▶ kecil + badge durasi `mm:ss` (unpadded menit, samakan `ProductDetailVideoSlide._formatDuration` — `0:32`). Sisanya foto. `onTap(index)` → `animateToPage(index)` berbasis slide index (video=0). `activeIndex` = `_index`.
- Border aktif thumbnail tetap gaya existing.

- [ ] **Step 4: Analyze + commit**
`flutter analyze lib/screens/image_viewer_screen.dart` → 0 issue baru. Cek: video-only tampil video; tap thumbnail foto ke-k buka slide yang benar; counter hitung video+foto.
```bash
git add flutter_app/lib/screens/image_viewer_screen.dart
git commit -m "feat(flutter/product-video): video jadi slide #0 di ImageViewerScreen + thumbnail/counter"
```

---

## Task 3: Tombol ⛶ + callback di ProductDetailVideoSlide

**Files:** Modify `flutter_app/lib/widgets/product_detail_video_slide.dart`.

**Interfaces:** `ProductDetailVideoSlide` dapat param `VoidCallback? onOpenFullscreen`. State expose tetap `pauseIfPlaying()`.

- [ ] **Step 1: Tombol ⛶**
- Tambah param `final VoidCallback? onOpenFullscreen;`.
- Tampilkan tombol **⛶** (`Icons.fullscreen_rounded`, kapsul hitam `Colors.black.withValues(alpha:0.55)` radius 999, ikon putih ~20) di **pojok kanan-bawah** area video (jangan bentrok badge "Video" kiri-atas / durasi kanan-atas / progress bar). Tampil di state poster DAN state playing.
- `onTap` ⛶: `pauseIfPlaying()` (pause inline supaya tak dobel suara) → `widget.onOpenFullscreen?.call()`. `onTap` ⛶ TIDAK memicu play inline (stopPropagation — pakai GestureDetector/InkWell terpisah di atas).

- [ ] **Step 2: Analyze + commit**
`flutter analyze lib/widgets/product_detail_video_slide.dart` → 0 issue baru.
```bash
git add flutter_app/lib/widgets/product_detail_video_slide.dart
git commit -m "feat(flutter/product-video): tombol fullscreen di slide video detail"
```

---

## Task 4: Wire _ProductHero → buka viewer dengan video

**Files:** Modify `flutter_app/lib/screens/product_detail_screen.dart`.

**Interfaces:** Consumes `ImageViewerScreen` video params (Task 2) + `ProductDetailVideoSlide.onOpenFullscreen` (Task 3).

- [ ] **Step 1: Helper buka viewer**
Di `_ProductHeroState`, tambah method yang push `ImageViewerScreen` dengan video (kalau ada) + `initialIndex` berbasis SLIDE:
```dart
void _openMediaViewer(BuildContext context, int initialSlide, List<String> images) {
  AppHaptics.tap();
  Navigator.push<void>(context, PageRouteBuilder<void>(
    opaque: true, barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => ImageViewerScreen(
      images: images,
      videoUrl: _hasVideo ? widget.product.videoUrl : null,
      videoThumbnailUrl: _hasVideo ? widget.product.videoThumbnailUrl : null,
      videoDurationSec: _hasVideo ? widget.product.videoDurationSec : null,
      posterImageUrl: widget.product.imageUrl,
      initialIndex: initialSlide,
      productMediaViewer: true,
      product: widget.product,
      selectedVariant: widget.selectedVariant,
      needsVariantSelection: widget.needsVariantSelection,
      onSelectVariant: widget.onSelectVariant,
      onAddToCart: widget.onAddToCart,
    ),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}
```

- [ ] **Step 2: Wire ⛶ + tap foto**
- Video slide (`ProductDetailVideoSlide`, ~772): tambah `onOpenFullscreen: () => _openMediaViewer(context, 0, images)` (buka di slide video 0).
- Tap foto (~789 `onTap`): ganti push inline yang ada dengan `_openMediaViewer(context, index, images)` — **`index`** (slide index hero, sudah termasuk offset video) BUKAN `imageIndex`, karena viewer kini berbasis slide (video 0 + foto). Rendered image tetap `images[imageIndex]`.
- Hapus duplikasi push lama (yang `initialIndex: imageIndex`), ganti panggil helper.

- [ ] **Step 3: Analyze + commit**
`flutter analyze lib/screens/product_detail_screen.dart` → 0 issue baru. Cek: ⛶ buka slide 0 (video autoplay+suara); tap foto ke-N buka foto yang sama di viewer (bukan geser 1); tanpa video, `index==imageIndex` → tetap benar.
```bash
git add flutter_app/lib/screens/product_detail_screen.dart
git commit -m "feat(flutter/product-video): buka preview fullscreen dgn video dari detail (tombol fullscreen + tap foto)"
```

---

## Task 5: Verifikasi akhir + whole-branch review

- [ ] **Step 1:** `cd flutter_app && flutter analyze lib 2>&1 | tail -5` → 0 issue baru (baseline 1 info pre-existing tak-relevan).
- [ ] **Step 2:** `flutter test test/cart_store_test.dart test/product_voucher_preview_test.dart test/added_to_cart_sheet_test.dart test/cart_screen_anchor_test.dart` → hijau.
- [ ] **Step 3:** Whole-branch review (opus, adversarial) fokus: index mapping slide↔foto (off-by-one buka foto salah / ⛶ buka video), autoplay-saat-aktif + pause-saat-swipe, dobel-suara (inline vs fullscreen), gesture (tap video ≠ makan swipe; pinch foto tetap jalan), dispose/leak, video-only guard, thumbnail video-first + durasi.

> **DEVICE-VERIFY (gate manual — WAJIB, tak bisa di sandbox):** iOS + Android. Detail → tombol ⛶ → preview fullscreen: video slide 1 autoplay + SUARA, tap pause, tombol mute jalan, progress scrub; swipe ke foto → video pause + suara berhenti; filmstrip video di depan (▶+durasi); counter benar; tap foto di detail buka foto yang sama (tak geser); pinch-zoom foto tetap mulus; tutup viewer → balik detail, video inline tetap pause. Tanpa video → viewer sama seperti sebelumnya.

## Self-Review
- ⛶ → viewer slide 0 autoplay+suara (Task 1/2/3/4). Video slide #0 + foto (Task 2). Index slide-based, tap foto tak off-by-one (Task 4). Inline ▶ tak diubah + pause saat ⛶ (Task 3). Gesture video onTap-only, foto zoom tetap (Task 1/2). Suara: default options + mute toggle (Task 1). ✓
- Placeholder: tidak ada. Nama konsisten: `_PreviewVideoSlide`, `onOpenFullscreen`, `videoUrl/videoThumbnailUrl/videoDurationSec/posterImageUrl`.

## Catatan
- Deploy: tampil ke pelanggan hanya setelah **rilis app Flutter** (API sudah live). Ini follow-up dari Plan 2 (video display) yang sudah MERGED (6e342c44).
