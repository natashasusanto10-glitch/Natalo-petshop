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

## Non-goals

- Tidak membuat tipe voucher baru (`memberExclusive`, `cashback`, dll).
- Tidak menggarap styling voucher loyalty point.
- Tidak mengubah cart/checkout voucher list screen (`member_vouchers_screen.dart`)
  — di luar permintaan user saat ini, bisa jadi iterasi lanjutan kalau
  diminta.
