# Shoppable Video — TikTok Shop Parity (Design Spec)

**Tanggal:** 2026-07-04
**Status:** Disetujui untuk implementasi (menunggu review spec)
**Scope:** Flutter-only. Tidak ada perubahan backend, model, atau migrasi DB.

## Tujuan

Menyamakan pengalaman shoppable video di feed dengan standar TikTok Shop:
konversi beli yang lebih agresif dan UX yang konsisten. Metrik sukses
kualitatif: elemen commerce di video terasa setara TikTok Shop (kartu
produk, keranjang, dorongan beli), tidak ada elemen membingungkan/mati.

## Kondisi Sekarang (baseline)

Semua kode di `flutter_app/lib/screens/feed_screen.dart`.

- **`_ProductLinkChip`** (`:4751`) — chip teks berputar di kiri-bawah,
  hanya nama produk + badge Flash Sale/Diskon. Selalu tampil.
- **`_EndOfVideoProductCta`** (`:6494`) — kartu produk kaya
  (gambar + rating + terjual + harga + tombol) yang muncul kondisional
  (`showProductCard`) di akhir video, dengan `_ProductCardArrowPointer`.
- **`_ProductCommerceOverlayGroup`** (`:4644`) — pembungkus yang menyusun
  kartu end-of-video (atas) + chip (bawah).
- **`_FeedTaggedProductsSheet`** (`:4891`) — bottom sheet "Lihat Produk (N)".
  Header punya ikon `Icons.shopping_bag_outlined` + badge angka
  (`cartStore.totalQuantity`) yang **BUG**: pakai ikon tas (bukan
  keranjang) dan **tidak tappable** (tidak ada handler; komentar
  "tap → close sheet" basi/menyesatkan).
- **`_FeedTaggedProductCard`** (`:5171`) — kartu produk di sheet:
  thumbnail, badge "Khusus Video", rating+terjual, harga, stepper jumlah,
  tombol keranjang (`_FeedSmallCartButton` → add-to-cart) + "Beli Sekarang"
  (`_FeedPrimaryProductButton` → buy-now).
- **`_KhususVideoBadge`** (`:5146`) — pill outline "Khusus Video" yang
  dirender **tanpa syarat** di setiap produk (3 lokasi) → tidak bermakna.

Data tersedia di `FeedProductLink` (`lib/models/feed_post.dart:76`):
`imageUrl`, `price`, `avgRating`, `soldCount`, `hasActiveDiscount`,
`discountPercent`, `isFlashSale`. Route keranjang: `/cart`
(`lib/main.dart:307`). Handler yang direuse: `_quickAddProduct(featured)`,
`_addFeedLinkToCart`, `_buyFeedLinkNow`, `cartStore.totalQuantity`.

## Keputusan Desain (disepakati user)

1. Elemen yang dimasukkan: **keempat** (kartu anchor, cart-pill di rail,
   fix ikon keranjang sheet, poles kartu sheet).
2. Badge "Khusus Video": **dibuang**.
3. Kartu akhir video: **Opsi B** — kartu kompak permanen SELAMA video main
   + popup ekspansi (`_EndOfVideoProductCta` dipoles) saat video selesai.

## Komponen

### 1. Kartu produk anchor (ganti chip teks berputar)

Ganti `_ProductLinkChip` dengan kartu kompak permanen di kiri-bawah:

- Layout horizontal: `[thumbnail 40px] [nama 1–2 baris + baris harga] [tombol keranjang oranye]`.
- Baris harga: harga aktif merah; jika `hasActiveDiscount`, tampilkan
  harga coret abu di sampingnya. Badge Flash Sale/Diskon tetap di atas
  kartu (seperti sekarang, label by `isFlashSale`).
- **Tap badan kartu** → buka sheet "Lihat Produk" (handler `onTap` yang ada).
- **Tap tombol keranjang oranye** → quick-add produk unggulan
  (`onQuickAdd` / `_quickAddProduct(featuredProduct)`) + haptic + toast.
  Jika `product.hasVariants` → buka product detail (pola existing).
- Multi-produk: index unggulan tetap berputar seperti sekarang (semua N
  tetap terjangkau via sheet). Nama sheet tetap "Lihat Produk (N)".
- Warna tombol: oranye `#FF7A00` (aksen commerce TikTok-Shop-style),
  konsisten dengan cart-pill di rail.

### 2. Cart-pill di action rail

Item rail baru, **hanya muncul di video shoppable** (`products.isNotEmpty`)
supaya video non-commerce tetap bersih:

- Ikon keranjang oranye + badge jumlah (`cartStore.totalQuantity`, cap
  "99+", hanya jika > 0). Dibungkus `AnimatedBuilder(animation: cartStore)`
  untuk live update.
- Urutan rail: like → komentar → share → **keranjang** → more.
- **Tap** → `Navigator.pushNamed(context, '/cart')`.

### 3. Fix ikon keranjang di sheet header

- Ganti `Icons.shopping_bag_outlined` → `Icons.shopping_cart_outlined`.
- Bungkus dengan `InkWell`/`GestureDetector`: tutup sheet dulu
  (`Navigator.pop`) lalu `Navigator.pushNamed('/cart')`.
- Buang komentar basi "tap → close sheet". Badge tetap
  (`cartStore.totalQuantity`).

### 4. Poles kartu sheet + buang "Khusus Video"

- Hapus pemakaian `_KhususVideoBadge` di 3 lokasi
  (`_FeedTaggedProductCard :5283`, `_VideoPromoBanner :5136`, dan kartu
  di `:6616`). Hapus definisi class `_KhususVideoBadge` jika tak terpakai.
- Pastikan kartu konsisten: harga coret saat diskon + baris rating/terjual
  (sudah ada) tetap tampil; rapikan spacing yang longgar setelah badge
  dibuang.

### Popup akhir video (Opsi B — poles, bukan buang)

`_EndOfVideoProductCta` dipertahankan sebagai popup ekspansi saat video
selesai. Poles ringan agar konsisten dengan kartu anchor baru: hapus
badge "Khusus Video" di dalamnya, samakan warna tombol beli ke oranye
`#FF7A00`, pertahankan `_ProductCardArrowPointer`.

## Edge Cases

- **Guest** tap cart/quick-add → ditangani cart screen / flow existing.
- **Produk bervarian** (`hasVariants`) → tombol quick-add/beli membuka
  product detail (pola existing), bukan langsung add.
- **Tanpa `imageUrl`** → placeholder thumbnail (pola existing di kartu sheet).
- **Video non-shoppable** (tanpa tagged products) → kartu anchor, cart-pill,
  dan popup tidak dirender sama sekali.

## Di Luar Scope (YAGNI)

- Harga video-eksklusif nyata (ditolak user — badge dibuang, bukan dibikin nyata).
- In-sheet mini-checkout (bayar tanpa keluar sheet) — tetap pakai alur
  checkout existing.
- Perubahan backend/model apa pun.

## Testing

- `flutter analyze` bersih pada file yang disentuh.
- Verifikasi manual di device: kartu anchor tampil + tap → sheet;
  tombol oranye → add + toast; cart-pill → /cart; ikon sheet → /cart;
  popup akhir video muncul saat selesai; badge "Khusus Video" hilang;
  video non-shoppable bersih.
- Build via Codemagic (Flutter-only; tidak butuh deploy Vercel).
