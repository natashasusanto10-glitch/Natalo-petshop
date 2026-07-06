# Promo & Voucher Sheet — 4 Tipe Voucher + Estimasi Bertumpuk

Tanggal: 2026-07-06
Status: Disetujui (menunggu review spec)
Area: Flutter app (`flutter_app/`) + backend Next.js API (`app/`, `lib/`)

## Masalah

Sheet "Promo & voucher" di halaman detail produk app (bottom sheet dari
`_PromoVoucherSheet` di `flutter_app/lib/screens/product_detail_screen.dart`)
punya 3 kekurangan yang dilaporkan:

1. **Voucher loyalty tampil merah, bukan ungu.** Voucher "Hemat Rp150rb"
   adalah voucher hasil tukar poin loyalty (`kind = LOYALTY_CLAIM`,
   `type = LOYALTY_POINT_CLAIM`). Backend sudah mengirim `kind`, tapi model
   Flutter `ProductVoucherPreview.fromJson` membuang field itu dan
   meng-collapse loyalty ke voucher diskon biasa → ter-render merah. Sheet
   hanya mengenal 3 gaya: ongkir (hijau), brand-exclusive (amber), sisanya
   merah. Belum ada gaya loyalty, dan tidak ada warna ungu di mana pun di app
   (layar loyalty/member justru biru `0xFF0B7FEA`).

2. **Voucher brand tidak muncul.** `attachPublicProductVoucherPreviews`
   (`lib/product-vouchers.ts`) hanya mengembalikan `previews[0]` — satu
   voucher diskon produk publik dengan penghematan terbesar. Kalau sebuah
   voucher brand dan voucher umum ("Hemat Rp20rb") sama-sama cocok, hanya
   satu (nominal terbesar) yang lolos; voucher brand ter-drop.

3. **Estimasi "harga hemat" tidak menumpuk voucher.** Estimasi memakai
   `bestVoucherDiscount` = satu voucher terbaik saja. Padahal sistem checkout
   punya 4 slot voucher yang bisa dipakai bersamaan (diskon produk + gratis
   ongkir + poin loyalty + manual/private — lihat
   `components/checkout/CheckoutVoucherCard.tsx:456`). Voucher diskon produk
   dan voucher poin loyalty menempati slot berbeda sehingga **digabung** saat
   checkout, tapi estimasi di sheet tidak mencerminkan itu.

## Tujuan

- Voucher loyalty ter-render **ungu** (`#7C3AED`) dengan badge `POIN LOYALTY`,
  ikon koin, dan subtitle yang menyebut **jumlah poin** ("Ditukar dari 200
  poin loyalty • Min. belanja Rp1,5jt").
- Semua voucher yang cocok untuk produk muncul di daftar, termasuk voucher
  brand — tidak lagi dibatasi 1 voucher diskon terbaik.
- Estimasi "harga hemat" **menumpuk** voucher lintas-slot: diskon produk
  terbaik + voucher loyalty terbaik, ditampilkan sebagai baris terpisah.
  Penumpukan cukup terlihat dari baris diskon yang terpisah + taksonomi 4
  warna — tanpa caption/kalimat penjelas tambahan.

## Non-tujuan

- Tidak mengubah logika resolusi/validasi voucher di checkout
  (`/api/checkout/recalculate`) — checkout sudah benar. Sheet hanya
  **preview**; angka final tetap dihitung di checkout.
- Tidak mengubah kartu voucher di listing produk (`voucherPreview` singular
  tetap dipakai untuk kartu di grid produk).
- Tidak menambah tipe/slot voucher baru; hanya memvisualkan 4 tipe yang sudah
  ada.

## Keputusan desain

- **Deskripsi loyalty menampilkan jumlah poin** (bukan generik).
- **Tampilkan semua voucher yang cocok** (bukan sekadar "selalu sertakan
  brand").
- **Estimasi optimis**: menumpuk semua voucher yang cocok walau min. belanja
  belum terpenuhi — konsisten dengan perilaku sekarang (screenshot pun sudah
  menampilkan −Rp150rb pada produk Rp542rb). Disclaimer "Voucher final akan
  dihitung saat checkout" tetap ada.
- **Tanpa** baris catatan "bisa dipakai bareng" maupun caption penjelas di
  kartu estimasi — dihapus atas permintaan; taksonomi 4 warna + baris diskon
  terpisah sudah cukup mengkomunikasikan penumpukan.

## Model slot (dasar kalkulasi)

Checkout punya 4 slot berdasarkan `VoucherKind`:

| Slot            | Kind              | Efek                        |
|-----------------|-------------------|-----------------------------|
| Diskon produk   | `PRODUCT_DISCOUNT`| Kurangi subtotal barang     |
| Gratis ongkir   | `FREE_SHIPPING`   | Kurangi ongkir (bukan barang)|
| Poin loyalty    | `LOYALTY_CLAIM`   | Kurangi subtotal barang     |
| Manual/private  | `MANUAL_PRIVATE`  | Kurangi subtotal barang     |

Voucher brand = voucher `PRODUCT_DISCOUNT` dengan `eligibleBrandIds` terisi —
**menempati slot diskon produk yang sama** dengan voucher umum. Jadi antar
voucher diskon produk saling bersaing (pilih terbaik), tapi diskon produk
**digabung** dengan poin loyalty (slot berbeda). Manual/private tidak di-preview
(voucher tersembunyi, hanya via input kode).

Estimasi harga barang di sheet:

```
diskonProdukTerbaik = max(estimate(v) untuk v di voucher diskon produk yang cocok)
diskonLoyaltyTerbaik = max(estimate(v) untuk v di voucher loyalty yang cocok)
totalDiskonVoucher   = diskonProdukTerbaik + diskonLoyaltyTerbaik
perkiraanHargaHemat  = clamp(product.finalPrice - totalDiskonVoucher, 0, ∞)
```

(Gratis ongkir tidak mengurangi harga barang → tetap ditampilkan sebagai baris
"Gratis ongkir tersedia di checkout", bukan masuk kalkulasi barang.)

## Taksonomi warna (4 tipe)

| Tipe            | Tone teks   | Bg soft    | Border     | Ikon             |
|-----------------|-------------|------------|------------|------------------|
| Diskon produk   | `#E11D48`   | `#FFEEF1`  | `#FFC9D0`  | ticket/%         |
| Gratis ongkir   | `#16A34A`   | `#F0FDF4`  | `#BBF7D0`  | truk             |
| Poin loyalty ✦  | `#7C3AED`   | `#F5F1FE`  | `#E0D4FB`  | koin             |
| Khusus brand    | `#B85C00`   | `#FEF0DC`  | `#FCD9A0`  | rosette/premium  |

✦ = baru. Konstanta ungu tambahan: dark `#6D28D9` (badge/label), fill icon
`#7C3AED`.

Urutan prioritas penentuan gaya di widget: **ongkir → loyalty → brand →
diskon** (voucher loyalty tidak pernah brand-exclusive karena
`eligibleBrandIds` kosong, jadi cek loyalty didahulukan sebelum brand).

## Perubahan

### 1. `lib/loyalty-tiers.ts` (baru) — sumber tunggal tabel tier

Ekstrak tabel `TIERS` yang sekarang terduplikasi di
`app/api/member/claim-voucher/route.ts` dan
`app/account/loyalty/redeem/RedeemPointsClient.tsx` ke satu modul bersama:

```ts
export const LOYALTY_TIERS = [
  { points: 20,  discountAmount: 10000,  minimumOrder: 150000 },
  { points: 50,  discountAmount: 25000,  minimumOrder: 300000 },
  { points: 75,  discountAmount: 40000,  minimumOrder: 500000 },
  { points: 100, discountAmount: 60000,  minimumOrder: 700000 },
  { points: 200, discountAmount: 150000, minimumOrder: 1500000 },
] as const;

// Balikan poin dari nominal diskon voucher loyalty (nominal unik per tier).
export function loyaltyPointsForDiscount(discountAmount: number): number | null;
```

`claim-voucher/route.ts` dan `RedeemPointsClient.tsx` di-refactor memakai
konstanta ini (label tetap dibangun dari field yang sama). Perilaku redeem
tidak berubah.

### 2. `lib/product-vouchers.ts` — loader plural + poin loyalty

- Tambah `loadPublicProductVoucherPreviews(product, options)` (plural) yang
  mengembalikan **semua** preview voucher diskon produk publik yang cocok
  (ter-sort by savingAmount desc), plus **semua** preview ongkir publik yang
  cocok. Versi singular lama tetap ada untuk kartu listing produk.
- Di `loadVisibleProductVouchers`, untuk voucher `kind === "LOYALTY_CLAIM"`,
  tambah field `loyaltyPoints` = `loyaltyPointsForDiscount(discountAmount)`.
  Tambahkan `loyaltyPoints: number | null` ke tipe `ProductVoucherItem`.
- `kind` sudah dikirim; pastikan tetap ada di payload.

### 3. `app/api/products/[slug]/vouchers/route.ts` — pakai loader plural + dedup

- Ganti `loadPublicProductVoucherPreview` (singular) → plural. Hasil: array
  voucher publik (diskon + ongkir).
- Dedup: kumpulkan semua id voucher publik ke `Set`, filter `memberVouchers`
  yang id-nya sudah ada di set itu (voucher brand publik bisa muncul di dua
  jalur). Ganti pengecekan `publicVoucher?.id`/`shippingVoucher?.id` yang
  sekarang berbasis satu id.
- `attachBrandName` tetap: `brandName` diisi hanya bila `isBrandExclusive`.

### 4. `flutter_app/lib/models/product.dart` — `ProductVoucherPreview`

- Tambah field `final String? kind;` dan `final int? loyaltyPoints;`.
- Di `fromJson`: baca `json['kind']` (simpan apa adanya, jangan di-collapse)
  dan `json['loyaltyPoints'] ?? json['loyalty_points']`.
- Getter baru:
  ```dart
  bool get isLoyaltyVoucher {
    final k = (kind ?? '').trim().toUpperCase();
    final t = type.trim().toUpperCase();
    return k == 'LOYALTY_CLAIM' || t == 'LOYALTY_POINT_CLAIM';
  }
  ```
- Sertakan `kind`/`loyaltyPoints` di `toJson`.

### 5. `flutter_app/lib/screens/product_detail_screen.dart` — UI

- Konstanta warna ungu: `_loyaltyPurple = Color(0xFF7C3AED)`,
  `_loyaltyDark = Color(0xFF6D28D9)`, `_loyaltySoftBg = Color(0xFFF5F1FE)`,
  `_loyaltySoftBorder = Color(0xFFE0D4FB)`.
- `_VoucherSheetCard`: tambah cabang loyalty (ungu, badge `POIN LOYALTY` +
  ikon koin, tone/bg/border ungu, ikon kontainer koin putih). Urutan cek:
  shipping → loyalty → brandExclusive → diskon.
- `_VoucherChip` (rail collapsed): tambah cabang loyalty ungu.
- `_voucherSheetSubtitle`: cabang loyalty →
  `"Ditukar dari {loyaltyPoints} poin loyalty • Min. belanja {min}"`; bila
  `loyaltyPoints == null` → `"Hasil tukar poin loyalty • Min. belanja {min}"`;
  bila min = 0 → tanpa klausa min.
- `_PromoVoucherSheet.build`: pisahkan `vouchers` jadi 3 kelompok —
  shipping, loyalty (`isLoyaltyVoucher`), diskon produk (sisanya). Hitung
  `diskonProdukTerbaik` + `diskonLoyaltyTerbaik` (masing-masing `max` via
  `_voucherDiscountEstimate`).
- `_PromoEstimateCard`: ganti parameter tunggal `voucherDiscount` menjadi
  dua — `productVoucherDiscount` + `loyaltyVoucherDiscount`. Baris kartu
  estimasi terurut: "Harga sebelum promo" → "Diskon barang" (diskon bawaan
  produk `price - finalPrice`, dipertahankan, tampil bila > 0) → "Diskon
  voucher produk" (merah, bila > 0) → "Diskon poin loyalty" (ungu, bila > 0)
  → "Perkiraan harga hemat".
  `showEstimate = discountProduct>0 || diskonProdukTerbaik>0 ||
  diskonLoyaltyTerbaik>0`.
- Daftar voucher di-sort: diskon produk (brand-exclusive dulu, lalu by
  savingAmount) → ongkir → loyalty. (Sesuai mockup: brand, umum, ongkir,
  loyalty.)
- Footer disclaimer "Voucher final akan dihitung saat checkout" tetap ada.
  **Tidak** ada baris catatan "bisa dipakai bareng" maupun caption di kartu
  estimasi.

## Aliran data

```
Voucher (Prisma) ──▶ /api/products/[slug]/vouchers
  ├─ loadPublicProductVoucherPreviews  → semua diskon+ongkir publik yg cocok
  ├─ loadVisibleProductVouchers        → voucher member (brand user-owned +
  │                                       loyalty), + loyaltyPoints
  └─ dedup by id, attachBrandName
        │
        ▼ JSON { vouchers: [...] }  (tiap item punya kind, loyaltyPoints?)
  ProductVoucherPreview.fromJson  → simpan kind + loyaltyPoints
        │
        ▼
  _PromoVoucherSheet
    ├─ kelompokkan: shipping / loyalty / diskon-produk
    ├─ estimasi = maxDiskonProduk + maxLoyalty  (optimis)
    └─ render kartu per tipe (4 warna)
```

## Edge cases

- **Belum login**: `loadVisibleProductVouchers` kosong → tidak ada loyalty /
  voucher user-owned. Voucher brand **publik** tetap muncul lewat loader
  plural. Konsisten.
- **Produk tanpa `brandId`**: voucher scoped-brand tidak match
  (`voucherMatchesProduct` false) → tidak muncul. Ini batasan data yang benar
  (voucher brand tak bisa diatribusikan ke produk tanpa brand). Dicatat
  sebagai dependensi data, bukan bug.
- **`loyaltyPoints == null`** (nominal voucher loyalty tak ada di tier —
  seharusnya tak terjadi karena hanya TIERS yang membuat voucher loyalty):
  subtitle fallback ke teks generik.
- **Beberapa voucher loyalty** (user klaim >1): hanya 1 slot loyalty →
  estimasi pakai yang terbaik (`max`), tapi semua tetap tampil di daftar.
- **Duplikasi voucher brand publik** (muncul di jalur publik & member):
  di-dedup by id.

## Testing

Backend (Vitest/Jest sesuai konvensi repo di `__tests__`/`*.test.ts`):
- `loyaltyPointsForDiscount(150000) === 200`; nominal non-tier → `null`.
- `loadPublicProductVoucherPreviews` mengembalikan **dua** voucher (umum +
  brand) saat keduanya cocok untuk produk.
- Route dedup: voucher brand publik tidak terduplikasi oleh jalur member.

Flutter (`flutter_app/test/`):
- `ProductVoucherPreview.fromJson` mempertahankan `kind` + `loyaltyPoints`;
  `isLoyaltyVoucher` true untuk `kind: LOYALTY_CLAIM` dan untuk
  `type: LOYALTY_POINT_CLAIM`.
- Kalkulasi estimasi bertumpuk: produk `finalPrice` Rp542.000 + voucher
  diskon produk Rp50.000 + voucher loyalty Rp150.000 → `estimatedPrice`
  Rp342.000.
- Subtitle loyalty memuat "200 poin".

## Berkas tersentuh

Baru:
- `lib/loyalty-tiers.ts`

Backend:
- `app/api/member/claim-voucher/route.ts` (pakai tabel tier bersama)
- `app/account/loyalty/redeem/RedeemPointsClient.tsx` (pakai tabel tier bersama)
- `lib/product-vouchers.ts` (loader plural + `loyaltyPoints`)
- `app/api/products/[slug]/vouchers/route.ts` (loader plural + dedup)

Flutter:
- `flutter_app/lib/models/product.dart`
- `flutter_app/lib/screens/product_detail_screen.dart`

Tes: berkas tes backend + Flutter sesuai poin di atas.

## Risiko & mitigasi

- **Refactor tabel tier** menyentuh alur redeem poin (berisiko regresi
  ekonomi loyalty). Mitigasi: pertahankan nilai persis sama, refactor murni
  (tanpa ubah logika), jalankan test redeem existing.
- **Daftar voucher jadi lebih ramai** (semua yang cocok tampil). Mitigasi:
  urutan jelas + batas wajar dari sumber (`take` di loader tetap dipakai).
- **Estimasi optimis** bisa dianggap over-promise. Mitigasi: disclaimer
  "final dihitung saat checkout" (sudah ada) + baris diskon terpisah membuat
  asal angka transparan.
