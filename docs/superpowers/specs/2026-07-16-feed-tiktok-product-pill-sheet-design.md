# Feed TikTok-style Product Pill + Links Sheet — Design

Tanggal: 2026-07-16
Branch: `claude/tiktok-flow-discussion-341a86`
Status: disetujui untuk masuk rencana implementasi (menunggu review spec)

## 1. Tujuan

Ganti **kartu produk anchor** yang lebar & menutup bagian bawah video feed dengan
**pill produk mungil ala TikTok** yang ringan dan tak mengganggu isi video, plus
**sheet "Links"** (grid produk) yang naik saat pill ditap. Selaras dengan referensi
TikTok (2 screenshot): tag produk = pill kecil di atas video; tap → sheet grid produk;
video jeda selagi sheet terbuka.

Prinsip yang ditekankan user: **jangan pernah memaksa produk keluar menutupi video**
— produk hanya muncul kalau user sendiri membuka sheet.

## 2. Keputusan yang sudah dikunci

| # | Keputusan | Nilai |
|---|-----------|-------|
| D1 | Bentuk pill | Glass netral ramping (~25px), transparan + blur, garis tipis putih |
| D2 | Ikon di pill | Kotak keranjang biru brand `NataloColors.primary` (#1E5FBF), **bukan** kuning TikTok |
| D3 | Isi pill | Judul produk **bergilir** (crossfade) + `·N ⌄` (N = jumlah produk tag) |
| D4 | Diskon | Badge merah **compact terpisah** di atas pill: `Diskon s/d {maks}%` |
| D5 | Aturan angka diskon | Persen **tertinggi** di antara produk tag yang promo; badge hilang jika tak ada promo |
| D6 | Tap pill | Buka **sheet grid** yang naik ala TikTok Links |
| D7 | Sheet PAUSE video | Ya — video jeda saat sheet terbuka, lanjut saat ditutup |
| D8 | Layout sheet | **Grid rapat 2 kolom** (Opsi A) |
| D9 | Kartu grid | **Opsi 2** — meniru token kartu Katalog, tapi diisi `FeedProductLink` langsung |
| D10 | Cakupan | **Video + foto** — ganti widget bersama sekali (foto ikut berubah) |
| D11 | Kartu akhir video | **Hapus** `_EndOfVideoProductCta` (bertentangan dgn prinsip "jangan tutup video") |
| D12 | Tap kartu di sheet | Langsung ke **halaman detail produk** (fetch by slug) |
| D13 | Aksi kartu | **Keranjang saja**; produk varian diarahkan ke detail utk pilih varian |

## 3. Temuan kode (grounded — hasil recon)

- **Rotasi judul sudah ada**: `Timer.periodic(2500ms)` di
  [feed_video_post_view.dart:2126](../../../flutter_app/lib/features/feed/widgets/feed_video_post_view.dart)
  (`_syncProductRotation`), gated `widget.isActive && products.length > 1`, di-dispose bersih.
  Duplikat di [feed_screen.dart:1847](../../../flutter_app/lib/screens/feed_screen.dart)
  (`_PhotoCarouselPostView`). → "judul bergilir" tinggal restyle, bukan bikin baru; hanya
  Duration 2500→3000ms jika ingin ~3s.
- **Tanpa backend baru**: `FeedProductLink`
  ([feed_post.dart:89](../../../flutter_app/lib/models/feed_post.dart)) sudah bawa
  `imageUrl, name, slug, price, discountPrice, promoPrice, discountSource, stock,
  hasVariants, isActive, avgRating, reviewCount, soldCount`, plus getter
  `hasActiveDiscount`, `discountPercent` (round+clamp 1..99), `isFlashSale`, `isAvailable`.
- **Sumber list**: gunakan `post.taggedProducts` (bukan `productsInVideo` yang tak pernah
  di-populate). List di-cap oleh `_rotatingProductsForPost` = admin 5 / non-admin 3
  ([feed_video_post_view.dart:2115](../../../flutter_app/lib/features/feed/widgets/feed_video_post_view.dart)).
- **Diskon**: pakai getter `FeedProductLink.discountPercent` (round+clamp), **jangan**
  `productDiscountPercent` di product_card.dart (floor → beda 1%). Rumus maks:
  `products.map((p) => p.discountPercent).fold<int>(0, (m, v) => v > m ? v : m)`.
  `discountPercent` mengembalikan 0 bila tak promo, jadi fold otomatis mengabaikannya.
- **Pill = widget BERSAMA**: builder
  [`feedPostProductAnchorCardFor`](../../../flutter_app/lib/features/feed/widgets/feed_post_shared_widgets.dart)
  (feed_post_shared_widgets.dart:1487) memberi `FeedProductAnchorCard` ke video
  (`_ProductCommerceOverlayGroup`, feed_video_post_view.dart:3974) **dan** foto
  (feed_screen.dart:2343). Surface ke-3: `scoped_video_feed_screen.dart` me-reuse
  `FeedVideoPostView`. Juga dipakai post-preview & fullscreen member-post-detail.
- **Sheet yang PAUSE = perilaku baru**: sheet produk yang ada (`_onProductsTap` →
  `FeedPostTaggedProductsSheet`) sengaja `backgroundColor: transparent` & **tidak** pause.
  Satu-satunya yang pause = comment sheet, via extent →
  `shouldPauseForCommentExtent` → `CoverPauseReason.commentSheetFull`, dgn split
  **managed vs legacy** dan flag sekali-transisi `_pausedByCommentSheet`
  (feed_video_post_view.dart:2064). Wajib ditiru; kalau salah → regresi audio-hantu/desync
  (lihat MEMORY PostVideoCoordinator).
- **Cart-add**: reuse `_addFeedLinkToCart` (feed_video_post_view.dart:2693) — sudah tangani
  availability, reroute varian, konversi `feedPostProductFromFeedLink`, `cartStore.addProduct`,
  `AppToast.showCartAdded`. **Tak ada fly-to-cart** di feed (tak ada `AppCartButton` target).
- **Tes terdampak** (3): `feed_product_anchor_card_test.dart`,
  `feed_post_preview_screen_test.dart`, `member_post_detail_screen_fullscreen_test.dart`.
  Idiom tes video: fake `VideoPlayerPlatform` + noop cache manager + **bounded pump loop**
  (jangan `pumpAndSettle` — shimmer tak pernah settle) + `SharedPreferences.setMockInitialValues`
  + `cartStore.clear()`. Tak ada golden yang menyentuh overlay.

## 4. Arsitektur

Tiga unit baru + beberapa titik jahitan diubah. Setiap unit punya satu tujuan jelas.

### 4.1 `FeedProductPill` (widget baru, presentational)

File baru: `flutter_app/lib/features/feed/widgets/feed_product_pill.dart`

Menggantikan `FeedProductAnchorCard` secara visual. **Stateless**, API primitif (tak
terikat model) supaya bisa dipakai video, foto, preview, fullscreen.

Parameter:
- `String title` — judul produk yang sedang tampil (rotasi dikendalikan pemanggil)
- `int count` — jumlah produk tag (untuk `·N`)
- `int maxDiscountPercent` — 0 = tak ada badge
- `VoidCallback onTap` — buka sheet

Struktur:
- Column(min, start):
  - jika `maxDiscountPercent > 0`: badge compact `Diskon s/d {maks}%` + SizedBox(5)
  - pill: `Material(transparent) > InkWell(onTap) > ClipRRect(999) > BackdropFilter(blur ~6) >`
    Container(bg `Colors.black.withValues(alpha:0.40)`, border `Colors.white.withValues(alpha:0.14)` 1px,
    radius 999, padding L3/R9/V3) > Row(min):
    - kotak ikon 19×19 radius 6 bg `NataloColors.primary`, `Icons.shopping_bag`/`shopping_cart` putih ~12
    - SizedBox(6)
    - window judul: tinggi tetap ~14, `AnimatedSwitcher(260ms, Fade)` keyed by `title`,
      `maxWidth ~150`, ellipsis, putih 11.5 w500
    - SizedBox(6)
    - `·N` + `Icons.keyboard_arrow_down` 11, putih opacity .8

Badge compact: Container bg `0xFFFF4D4F` (konvensi merah feed anchor), padding H6 V3, radius 4,
Text putih 9.5 w500, opsional ikon `Icons.local_offer`/`discount` 10. Teks netral `Diskon s/d {n}%`
(jangan warisi label "Flash Sale" — `isFlashSale` per-produk, ambigu untuk agregat).

Tinggi target pill ~25px (vs anchor lama ~36px).

### 4.2 `FeedProductLinksSheet` + `FeedProductGridCard` (widget baru)

File baru: `flutter_app/lib/features/feed/widgets/feed_product_links_sheet.dart`

**Sheet** (meniru idiom comment sheet / post_likers, BUKAN sheet produk transparan lama):
- Dibuka via `showModalBottomSheet(isScrollControlled: true, backgroundColor: transparent,
  barrierColor: black.withOpacity(~0.4), enableDrag: false)` — `enableDrag:false` supaya
  `DraggableScrollableSheet` yang pegang gesture (hindari stuck-drawer).
- Isi: `DraggableScrollableSheet(initial ~0.66, min ~0.45, max ~0.92)` →
  Container(bg `commerceGridSurfaceTint(context)` = `0xFFEEF1F5` light / `surfaceContainerLow`
  dark, radius atas 18) → `SafeArea(top:false)`:
  - `SheetDragHandle` (widget bersama)
  - Header: "Produk (N)" + tombol X
  - `Expanded(GridView.builder(crossAxisCount: 2, gap ~10, controller: sheet scrollController))`
    berisi `FeedProductGridCard`
- Callback keluar: `onOpenProduct(FeedProductLink)`, `onAddToCart(FeedProductLink)`.

**`FeedProductGridCard`** (Opsi 2 — token Katalog, diisi `FeedProductLink`):
- Shell: `Material(transparent) > InkWell(onTap → onOpenProduct, radius 8) >`
  Container(bg `cs.surface`, border `cs.outlineVariant` 1, radius 8,
  boxShadow black@0.045 blur18 offset(0,8), padding **zero**, clip antiAlias)
- Foto: `AspectRatio(1) > Stack`:
  - `Positioned.fill(AppProductImage(imageUrl, fit: BoxFit.cover, borderRadius: BorderRadius.zero))`
    — **`borderRadius.zero` WAJIB** (default 12 memasang ClipRRect internal → double-round).
  - jika `discountPercent > 0`: `Positioned(top0,right0, _NBadge)` = Container padding H10V7
    bg `0xFFE11D48` radius `only(topRight16, bottomLeft14)`, Text `-N%` putih 15 w900
- Konten: `Padding(fromLTRB(10,8,10,10)) > Column(min,start)`:
  - Title 13.5 w800 h1.22 `cs.onSurface`, 2 baris ellipsis
  - jika `avgRating>0 || soldCount>0`: SizedBox(7) + baris rating•terjual
    (star `0xFFF59E0B` 15, rating `toStringAsFixed(1)` 11.8 w800, `•`, `{n} terjual` 11.8 w700)
    — **sembunyikan kalau dua-duanya 0** (jangan render "0.0 / 0 terjual")
  - SizedBox(10)
  - Row(end): `Expanded(price block)` + SizedBox(8) + cart button 42
- Price block (pakai `feedPostProductPricing(product)`):
  - tanpa promo: Text `formatRupiah(displayPrice)` 20 w900 `cs.onSurface` ls-0.25
  - promo: strike `formatRupiah(originalPrice)` 12.5 w700 `cs.onSurfaceVariant` +
    SizedBox(3) + Text `formatRupiah(displayPrice)` 20 w900 `0xFFE11D48` ls-0.25
- Cart button: 42×42 radius 14, border `0xFFBFD5FF` 1.2, `Icons.shopping_cart_outlined` 22
  warna `NataloColors.primary`; `stock<=0` → `Icons.block_rounded` + disabled; `ActionThrottle(650ms)`.
  Tap → `onAddToCart`.

> Catatan token: `_discountRed(0xFFE11D48)`, `_starAmber(0xFFF59E0B)`, cart border
> `0xFFBFD5FF` adalah literal lokal di compact_commerce_product_card.dart (private) → **redeklarasi**
> di file baru. Jangan pakai `NataloColors.discountRed` (0xFFEF4444 — merah berbeda).

### 4.3 Jahitan yang diubah

**Builder bersama** (`feed_post_shared_widgets.dart`):
- Tambah `Widget feedProductPillFor(List<FeedProductLink> products, int featuredIndex,
  {required VoidCallback onTap})` — hitung `featured = products[i % len]`, `count = products.length`,
  `maxDiscount = fold(...)`, kembalikan `FeedProductPill`.
- Tambah helper murni `int feedMaxDiscountPercent(List<FeedProductLink>)` (bisa diuji lepas).
- `feedPostProductAnchorCardFor` + `FeedProductAnchorCard` → **kandidat hapus** setelah semua
  pemanggil pindah (verifikasi tak ada sisa). `feedPostProductPricing` **tetap** (dipakai kartu grid).

**Video** (`feed_video_post_view.dart`):
- `_ProductCommerceOverlayGroup`: ganti pemanggilan `feedPostProductAnchorCardFor(featuredProduct,…)`
  → `feedProductPillFor(products, _featuredProductIndex, onTap: …)`. Teruskan **list + index**
  (kini hanya `featuredProduct` yang lewat, feed_video_post_view.dart:3450).
- **Hapus** `_EndOfVideoProductCta` + `_ProductCardArrowPointer` + state `_endOfVideoCtaVisible`
  dan pemicunya saat video selesai (feed_video_post_view.dart:1289, 4415). (D11)
- Hapus jahitan `onQuickAdd`/`_quickAddProduct` ke overlay (pill tak punya tombol add).
- Tap pill → handler baru `_onProductLinksTap(products)` yang: (a) `onOverlayStateChanged(true)`,
  (b) **pause**: managed → `onRequestPause(CoverPauseReason.productSheet)`, legacy → `ctrl.pause()`
  dgn flag `_pausedByProductSheet`, (c) `showModalBottomSheet(FeedProductLinksSheet(...))`,
  (d) `.whenComplete`: `onOverlayStateChanged(false)` + resume (managed → `onRequestPlay()`,
  legacy → `_playLegacy(ctrl,'product-sheet-close')` di-gate `_canAutoplayNow()`), reset flag.
- Kartu sheet: `onAddToCart` → `_addFeedLinkToCart(link)` (reuse apa adanya).
  `onOpenProduct` → fetch `productService.fetchProductBySlug(link.slug)` lalu
  `_openProductDetail(product)` (D12). Varian: `_addFeedLinkToCart` sudah reroute; sesuaikan
  target reroute ke `_openProductDetail` agar konsisten pilih-varian di detail (D13).

**Foto** (`feed_screen.dart` `_PhotoCarouselPostView`):
- Cerminan perubahan pill + tap-links sheet yang sama (duplikat helper). Foto tak punya video →
  pause no-op wajar; sheet tetap buka.

**Enum pause** (`feed_video_post_view.dart:67`):
- Tambah `CoverPauseReason.productSheet`; petakan ke `pauseAll` di PostVideoCoordinator
  (cari mapping `CoverPauseReason` → `pauseAll`; recon tak meng-anchor file coordinator — **temukan
  saat implementasi**, ini prasyarat).

**Sumber list konsisten**: pill rotasi, `·N`, `maxDiscount`, dan grid sheet **semua** dari
`_rotatingProductsForPost(post)` (list ter-cap) supaya count == isi sheet == rotasi (hindari
mismatch yang ditandai kritikus).

## 5. Alur data

```
FeedPost.taggedProducts
  └─ _rotatingProductsForPost(post)  (cap admin 5 / non-admin 3)  →  List<FeedProductLink> products
        ├─ pill:  featured = products[_featuredProductIndex]   → judul (AnimatedSwitcher)
        │         count = products.length                      → ·N
        │         maxDiscount = fold(discountPercent)           → badge "Diskon s/d {maks}%"
        │         (rotasi: Timer 2500/3000ms, gated isActive & len>1 — SUDAH ADA)
        └─ tap → FeedProductLinksSheet(products)
                  ├─ pause video (managed/legacy, CoverPauseReason.productSheet)
                  ├─ grid FeedProductGridCard(link)
                  │     ├─ foto/harga/-N%/rating•terjual  ← feedPostProductPricing + getter
                  │     ├─ cart → _addFeedLinkToCart(link) (varian → detail)
                  │     └─ tap kartu → fetchProductBySlug → _openProductDetail
                  └─ close → resume video
```

## 6. Edge case & guard

- **taggedProducts kosong**: pill tak dirender (pertahankan gate `if(products.isNotEmpty)`).
- **1 produk**: rotasi tak arm (static), `·N` = 1, chevron tetap (tap tetap buka sheet 1 kartu).
- **Index basi**: `products[_featuredProductIndex % len]` (guard modulo sudah ada).
- **Tak ada promo**: badge pill hilang; kartu tanpa `-N%`.
- **Diskon >100% teoretis**: clamp 1..99 (sudah di getter).
- **Varian (`hasVariants`)**: cart & tap → detail (picker varian di detail); jangan add langsung
  (`cartStore.addProduct` tolak varian tanpa pilihan).
- **stock<=0 / !isActive**: kartu tampil tapi cart disabled (`Icons.block_rounded`);
  `_addFeedLinkToCart` sudah `_showProductUnavailable`.
- **Managed vs legacy playback**: WAJIB hormati `widget.playbackManagedExternally` persis seperti
  `_syncCommentSheetProgress`; flag sekali-transisi `_pausedByProductSheet`.
- **Rotasi saat sheet terbuka**: pill tertutup sheet; boleh biarkan berputar (tak terlihat) atau
  suspend via `onOverlayStateChanged` (polish opsional).
- **VisibilityDetector timer di tes**: set `updateInterval = Duration.zero` di setUp.

## 7. Rencana testing

Update:
1. `feed_product_anchor_card_test.dart` → jadi unit test `FeedProductPill`: judul, `·N`,
   badge `Diskon s/d {maks}%` (termasuk clamp 99 & kasus 0% = tak ada badge).
2. `feed_post_preview_screen_test.dart:45` → `find.byType(FeedProductPill)`.
3. `member_post_detail_screen_fullscreen_test.dart` → assert pill hadir, atau tap pill lalu
   assert nama produk muncul di dalam sheet.

Baru:
4. **Pill rotasi**: post 2+ produk, bounded pump loop, assert tiap judul muncul bergilir.
5. **Badge maks%**: unit `feedMaxDiscountPercent` + render badge; kasus campuran promo/non-promo.
6. **Kartu grid**: render `FeedProductGridCard` dari `FeedProductLink` — foto, harga coret+merah,
   `-N%`, rating•terjual sembunyi saat 0.
7. **Sheet open/pause**: fake platform + hls post + `playbackManagedExternally:true`, tap pill,
   assert sheet muncul + `onRequestPause(productSheet)` terpanggil; close → `onRequestPlay`.
8. **Add-to-cart dari sheet**: idiom `added_to_cart_sheet_test` (`setMockInitialValues` +
   `cartStore.clear()` + bounded settle), tap cart di kartu, assert cartStore berisi produk.

Idiom wajib: **jangan `pumpAndSettle`**; fake `VideoPlayerPlatform` + noop cache manager;
hls fixture (.m3u8) untuk paksa init controller.

## 8. Verifikasi

`flutter analyze` bersih + `flutter test` (unit + widget hijau). Device-verify iOS+Android
(pill di latar terang/gelap, rotasi, badge, sheet naik + pause/resume, add-to-cart, tap→detail,
varian→detail) — dilakukan setelah implementasi, dicatat sebagai pending rilis app.

## 9. Di luar cakupan (deferred)

- Backend baru / field baru (tak perlu).
- Fly-to-cart animasi dari sheet (tak ada target `AppCartButton` di feed → no-op).
- Tombol "Beli langsung" di kartu (D13: keranjang saja).
- Ekstrak mixin untuk hilangkan duplikasi rotasi video/foto (nice-to-have; boleh saat menyentuh
  kedua file, tapi bukan syarat).
- Badge "Brand Eksklusif" di kartu grid (butuh `brandId` yang tak ada di `FeedProductLink`).

## 10. Risiko utama

1. **Duplikasi 2 file** (video + foto): tiap perubahan pill/cart/rotasi harus di **kedua** tempat
   atau drift. Surface ke-3 `scoped_video_feed_screen.dart` otomatis ikut (reuse `FeedVideoPostView`).
2. **Pause split managed/legacy**: sumber bug audio-hantu berulang; tiru comment sheet tepat.
3. **Coordinator mapping** `CoverPauseReason.productSheet → pauseAll` belum ter-anchor — temukan dulu.
4. **Widget bersama 4 surface** (feed video, feed foto, post-preview, fullscreen detail): pill
   presentational aman berubah semua; wiring sheet-pause hanya perlu di host video/foto interaktif.
