# Brand Exclusive Voucher — Visual Design

## Latar belakang

Fitur Target Brand voucher (`eligibleBrandIds` di model `Voucher`, lihat commit
`6b7fee1`/`6db5259`) sudah berfungsi penuh di backend: admin bisa scope voucher
ke satu atau lebih brand, dan API sudah memfilter voucher yang tampil sesuai
brand produk yang sedang dilihat. Yang belum ada: **penanda visual** di app
Flutter supaya user paham voucher yang mereka lihat itu scoped ke brand
tertentu (bukan voucher umum).

Sistem voucher yang sudah berjalan di app (rail `_VoucherAndTrust` dan sheet
`_PromoVoucherSheet` di
[product_detail_screen.dart](../../../flutter_app/lib/screens/product_detail_screen.dart))
punya 4 tipe voucher (`VoucherTypeCode` di
[lib/voucher-helpers.ts](../../../lib/voucher-helpers.ts)):
`PUBLIC_FREE_SHIPPING` (hijau soft), `PUBLIC_PRODUCT_DISCOUNT` (merah solid),
`LOYALTY_POINT_CLAIM` (ungu, styling belum ada mockup — di luar scope), dan
`PRIVATE_MANUAL_CODE`. "Brand exclusive" BUKAN tipe voucher baru — dia adalah
atribut scope (`eligibleBrandIds` non-kosong) yang menempel di voucher
`PUBLIC_PRODUCT_DISCOUNT` yang sudah ada.

## Scope

Hanya styling untuk voucher `PUBLIC_PRODUCT_DISCOUNT` yang memiliki
`eligibleBrandIds` non-kosong. Tidak membuat tipe/enum voucher baru, tidak
menyentuh logic eligibility (sudah selesai di sesi sebelumnya), tidak
menggarap voucher loyalty point atau tipe lain.

## Desain visual (disetujui)

Palet: oranye/emas **solid cerah** `#F7A100` — satu keluarga saturasi dengan
merah (`#E24B4A`, voucher diskon biasa) dan hijau (`#0F6E56`/`#EFFAF4`,
voucher ongkir) yang sudah ada, supaya menyatu dengan mood flat-cerah app,
bukan menonjol asing.

### 1. Rail chip (`_VoucherChip` di product detail)

Saat `voucher.isBrandExclusive == true`:
- Background fill solid `#F7A100`, tanpa border (sama treatment dengan hero
  chip merah saat ini).
- Ikon `Icons.workspace_premium_rounded` (atau ikon award serupa yang sudah
  tersedia di Material set), warna putih.
- Teks: `Khusus {brandName}` (bukan generic "Khusus Brand"), warna putih,
  weight w900 — pola sama dengan `_voucherChipText` existing.
- Truncation: `maxLines: 1` + `ellipsis` (sudah ada di `_VoucherChip`, tetap
  dipakai) — nama brand panjang akan terpotong dengan "...".

### 2. Card di sheet (`_VoucherSheetCard` di `_PromoVoucherSheet`)

Saat `voucher.isBrandExclusive == true`:
- Background `#FEF0DC`, border `#FCD9A0` (soft oranye, pola sama dengan
  soft-bg voucher lain).
- Badge kecil di atas judul: teks "KHUSUS BRAND" uppercase, ukuran 11,
  weight w900, letter-spacing renggang (~0.06em), warna `#B85C00` (tone gelap
  dari oranye, untuk kontras cukup di atas bg terang — sesuai prinsip
  teks-di-atas-warna).
- Judul (`_voucherChipText`, mis. "Diskon 15%") warna `#B85C00`.
- Subtitle (`_voucherSheetSubtitle`) ditambah klausa `Berlaku untuk
  {brandName}` di depan subtitle existing (mis. "Berlaku untuk Wolly+ • Min.
  belanja Rp150rb").
- Icon container kanan (pengganti `_DiscountVoucherIcon`): bg `#F7A100` solid,
  ikon award putih — analog dengan `_DiscountVoucherIcon` yang sudah ada,
  tapi ikon beda supaya sekilas beda dari voucher diskon biasa.

### Kondisi non-scoped brand lain

Tidak berubah dari behavior yang sudah di-fix: voucher brand-exclusive tidak
muncul sama sekali di produk brand lain (difilter oleh
`loadVisibleProductVouchers` + `voucherMatchesProduct`, lihat commit
`6db5259`). Spec ini murni styling untuk kasus voucher tersebut memang tampil
(di produk brand yang cocok).

## Perubahan data yang dibutuhkan

Backend `app/api/products/[slug]/vouchers/route.ts` dan
`lib/product-vouchers.ts` saat ini mengembalikan `eligibleBrandIds` (array of
ID) tapi TIDAK mengembalikan nama brand yang bisa langsung ditampilkan.
Perlu ditambahkan:

- Query tambahan (atau join) untuk resolve `eligibleBrandIds` → nama brand
  pertama yang cocok dengan brand produk yang sedang dilihat (karena voucher
  bisa multi-brand, tapi yang relevan untuk ditampilkan di context produk ini
  cuma brand produk itu sendiri).
- Field baru `brandName: string | null` di payload voucher (baik shape
  `PublicProductVoucherRow` maupun member voucher row) yang dikirim ke
  endpoint `/api/products/{slug}/vouchers`.

## Perubahan Flutter

- `ProductVoucherPreview` (di
  [flutter_app/lib/models/product.dart](../../../flutter_app/lib/models/product.dart)):
  tambah field `brandName` (nullable String), getter `isBrandExclusive =>
  brandName != null && brandName!.trim().isNotEmpty`. Parse dari JSON key
  `brandName` di `fromJson` (opsional/nullable, tidak mengubah shape lain).
- `_VoucherChip`, `_VoucherSheetCard`, `_voucherChipText`,
  `_voucherSheetSubtitle` di `product_detail_screen.dart`: tambah branch
  `isBrandExclusive` sesuai desain di atas. Warna oranye (`#F7A100`,
  `#FEF0DC`, `#FCD9A0`, `#B85C00`) didefinisikan sebagai const baru di file
  yang sama, mengikuti pola `_discountRed`/`_successGreen` yang sudah ada.

## Halaman lain yang menampilkan voucher (ditemukan saat review scope)

Voucher tampil di 3 tempat berbeda di app. Investigasi menemukan salah
satunya punya bug logic (bukan cuma kurang styling), jadi masuk scope
perbaikan bareng fitur visual ini:

1. **Detail produk** (`product_detail_screen.dart`) — sudah difilter benar
   per-brand (fix commit `6db5259`). Ini fokus utama styling di atas.
2. **Voucher Saya** (`member_vouchers_screen.dart`, widget `_VoucherCard`,
   model `MemberVoucher`) — daftar semua voucher user tanpa konteks produk
   spesifik. Voucher brand-exclusive **tetap wajar tampil** di sini (ini
   halaman "semua voucher saya"), tapi butuh badge kecil "Khusus {brand}"
   (pola sama seperti card di sheet promo, disesuaikan ke card style
   `_VoucherCard` yang sudah ada — badge di dekat `voucher.title`, warna
   `#B85C00` di atas `#FEF0DC`) supaya user paham voucher ini tidak berlaku
   umum sebelum mencoba pakai.
   - `MemberVoucher` model saat ini tidak punya field brand sama sekali —
     perlu tambah `brandName` (nullable) dan `hasProductScope` (bool),
     di-parse dari field baru di response `/api/cart/vouchers` (lihat poin
     3 di bawah, endpoint yang sama dipakai `memberService.fetchVouchers`).
   - Kalau `eligibleBrandIds` berisi >1 brand, tampilkan `brandName` sebagai
     nama brand pertama + suffix count, mis. `"Wolly+ & 2 brand lain"` —
     cukup untuk transparansi, tidak perlu list lengkap di card kecil.
3. **Cart / Checkout voucher picker** (`cart_screen.dart` →
   `memberService.fetchCartVouchers` → `GET /api/cart/vouchers`) — **bug
   ditemukan**: endpoint ini hanya menerima `subtotal` sebagai parameter
   ([app/api/cart/vouchers/route.ts](../../../app/api/cart/vouchers/route.ts)),
   lalu `buildVoucherListItems` di
   [lib/voucher-list.ts:222-223](../../../lib/voucher-list.ts) menghitung
   `applicable` murni dari `calcVoucherDiscount(subtotal, voucher)` — TIDAK
   pernah mengecek apakah isi cart benar-benar match `eligibleBrandIds`/
   `eligibleProductIds`/`eligibleCategoryIds`. Akibatnya voucher
   brand-exclusive bisa muncul di kolom **"available"** di keranjang
   walau keranjang tidak berisi produk brand tersebut sama sekali — baru
   ketahuan gagal saat checkout benar-benar recalculate (yang sudah
   difilter dengan benar). Ini root cause yang sama persis dengan bug
   sebelumnya, cuma di titik masuk yang berbeda.

   **Perbaikan**: `cart_screen.dart` sudah tahu isi keranjang (`CartItem`
   dengan `productId`); kirim daftar `productIds` (atau
   `{productId, brandId, categoryId}[]` kalau sudah tersedia di cart store
   tanpa fetch tambahan) sebagai query/body baru ke `/api/cart/vouchers`.
   Endpoint fetch produk terkait (id, categoryId, brandId) dan, untuk
   voucher yang `hasProductScope === true`, tandai `applicable = false`
   dengan `disabledReason` baru (mis. "Voucher hanya berlaku untuk produk
   {brand} — tidak ada di keranjang") kalau **tidak ada satupun** item cart
   yang match lewat `voucherMatchesProduct` (helper yang sudah ada di
   `lib/voucher-eligibility.ts`, dipakai ulang, bukan re-implementasi).
   Voucher yang match sebagian (misal 1 dari 3 item cart) tetap
   `applicable: true`, karena `calcVoucherDiscount` saat ini menghitung dari
   subtotal keseluruhan — perhitungan diskon presisi per-item tetap
   tanggung jawab `checkout/recalculate` seperti sekarang, endpoint ini
   cuma memperbaiki flag *availability*-nya.

## Non-goals

- Tidak membuat tipe voucher baru (`memberExclusive`, `cashback`, dll).
- Tidak menggarap styling voucher loyalty point.
- Tidak mengubah perhitungan diskon per-item di `checkout/recalculate` —
  sudah benar, di luar scope perbaikan ini (yang diperbaiki cuma flag
  `applicable` di listing `/api/cart/vouchers`).
- Tidak menambah UI baru untuk menampilkan daftar lengkap semua brand
  saat voucher scoped ke banyak brand sekaligus (cukup ringkasan
  "{brand} & N brand lain").
