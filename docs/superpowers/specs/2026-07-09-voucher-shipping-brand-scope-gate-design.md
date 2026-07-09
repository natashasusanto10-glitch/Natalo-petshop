# Spec: Gate scope voucher untuk SEMUA discountScope (tutup bypass voucher ongkir brand-eksklusif)

- **Tanggal:** 2026-07-09
- **Status:** Design — disetujui untuk lanjut ke plan
- **Area:** Backend Next.js (`lib/`, `app/api/`) + client (Flutter `flutter_app/`, web `components/cart/`)

---

## 1. Masalah

Voucher **gratis ongkir** yang di-*lock* ke sebuah brand (mis. `FREEOKSHPI` = "Gratis Ongkir Brand HPI", `discountScope = "SHIPPING"` + `eligibleBrandIds` berisi brand Happy Cat/HPI) **tetap ke-apply dan memotong ongkir** walaupun tidak ada satu pun produk brand tersebut di keranjang.

Gejala nyata (dari laporan user):

- Di daftar voucher (sheet keranjang + halaman Voucher Member) voucher itu **benar** muncul "Belum bisa dipakai — Voucher tidak berlaku untuk produk di keranjang".
- Tapi di **checkout** dia jadi "Terpakai otomatis", dan di **Detail Pesanan** tercatat `Voucher Gratis Ongkir: FREEOKSHPI −Rp15.000` (ongkir Rp17.000 → Rp2.000).

Akibat: **potongan ongkir diberikan tanpa hak → kebocoran uang tiap transaksi.**

> Catatan: selisih angka "−Rp9.000" (sheet) vs "−Rp15.000" (order) **bukan** bug — voucher ongkir ini berbasis persen, jadi nominalnya ikut nilai ongkir yang berbeda antar tahap. Di luar scope.

---

## 2. Akar masalah

Cek scope-eligibility ("apakah ada produk cocok di keranjang?") **hanya dijalankan untuk voucher dengan `discountScope === "PRODUCT"`**. Voucher gratis ongkir punya `discountScope === "SHIPPING"` ([`voucherScopeOf`](../../../lib/voucher-helpers.ts) line 108-113), sehingga **melewati** cek brand/kategori/produk sepenuhnya. `voucherMatchesProduct` sudah benar dan `brandId` sudah di-forward — yang salah adalah **kondisi kapan gate dipanggil**.

Ini instance ke sekian dari anti-pattern yang justru ditulis di header [`lib/voucher-eligibility.ts`](../../../lib/voucher-eligibility.ts) ("logika terduplikasi di 4 tempat… pola sama dengan bug 3-search-engine"): `voucherMatchesProduct` sudah dikonsolidasi, tapi tiap caller memutuskan sendiri **kapan** memanggilnya — sebagian salah kondisi.

### Hasil audit surface (14 agen, cross-checked + completeness critic)

| Surface | Peran | Status | Aksi |
|---|---|---|---|
| [`app/api/orders/route.ts:393`](../../../app/api/orders/route.ts) | **Charge order (uang)** | ❌ gate `=== "PRODUCT"` saja | **FIX** (kritikal) |
| [`app/api/checkout/recalculate/route.ts:442`](../../../app/api/checkout/recalculate/route.ts) | Preview + auto-apply (loop member) | ❌ gate `=== "PRODUCT"` saja | **FIX** |
| [`app/api/checkout/recalculate/route.ts:554-558`](../../../app/api/checkout/recalculate/route.ts) | Preview (cabang voucher manual/private) | ❌ gate `=== "PRODUCT"` saja, **path terpisah** | **FIX** |
| [`app/api/vouchers/validate/route.ts`](../../../app/api/vouchers/validate/route.ts) | Preview kode publik | ❌ **tanpa gate scope sama sekali**, body `{code, subtotal}` | **FIX** (+ plumbing) |
| [`app/api/cart/vouchers/validate-private/route.ts`](../../../app/api/cart/vouchers/validate-private/route.ts) | Preview kode private | ❌ **tanpa gate scope sama sekali**, body `{code, subtotal}` | **FIX** (+ plumbing) |
| [`lib/voucher-list.ts:244-254`](../../../lib/voucher-list.ts) | Listing (cart sheet + member page) | ✅ **benar** (gate semua scope via `scopeUnmatched`) | Dedup ke helper bersama |
| `lib/product-vouchers.ts` | Preview product page | ✅ scope-agnostic, benar | — |
| `lib/refund-wallet.ts` | Alokasi refund | ✅ SHIPPING di-nol-kan (kebalikan bocor) | — |
| `app/api/products/[slug]/vouchers`, `app/api/cart/recommendations`, `app/api/recommendations/personalized`, `lib/chat/catalog-card.ts`, `lib/cart-recommendation-products.ts`, `lib/order-detail.ts` | Display / data-provider / read-only | ✅ tidak ada gate keliru | — |

**Money leak = 3 charging gate.** Dua endpoint `validate` **tidak** memotong total order (backstop = `orders`), jadi murni **display-only** (bikin voucher tampak "applied" padahal nanti ditolak) — tapi ikut diperbaiki demi konsistensi total (keputusan user).

---

## 3. Desain fix (konsolidasi — satu predikat, semua surface)

### 3.1 Helper baru di `lib/voucher-eligibility.ts`

```ts
// True kalau voucher di-scope ke produk/kategori/brand tertentu.
export function voucherHasScope(voucher: VoucherEligibilityScope): boolean {
  return (
    (voucher.eligibleProductIds?.length ?? 0) > 0 ||
    (voucher.eligibleCategoryIds?.length ?? 0) > 0 ||
    (voucher.eligibleBrandIds?.length ?? 0) > 0
  );
}

// True kalau voucher TIDAK di-scope, ATAU minimal SATU produk keranjang cocok.
// Berbasis EKSISTENSI produk cocok — BUKAN subtotal — supaya produk cocok
// berharga 0 (hadiah / diskon 100%) tetap dianggap memenuhi scope.
export function cartMatchesVoucherScope(
  voucher: VoucherEligibilityScope,
  products: EligibilityProductInput[],
): boolean {
  if (!voucherHasScope(voucher)) return true;
  return products.some((p) => voucherMatchesProduct(voucher, p));
}
```

**Kritikal (dari audit):**
- Gate **berbasis eksistensi** (`products.some(match)`), **bukan** `eligibleProductSubtotal <= 0`. Kalau pakai subtotal, produk cocok berharga 0 akan salah-tolak.
- Voucher tak-berscope (`eligible...Ids` semua kosong) → `voucherMatchesProduct` return `true` → `voucherHasScope` false → gate di-skip → **gratis ongkir global tetap berlaku** (jangan regres).
- `eligibleProductSubtotal` **tetap dipertahankan** sebagai basis **nominal** voucher PRODUCT. Predikat baru hanya untuk **kelayakan** (boolean). Jangan tukar keduanya (kalau ditukar, voucher produk mendiskon seluruh subtotal → over-discount).

### 3.2 Charging surface — `app/api/orders/route.ts`

- Bangun `cartProductInputs: EligibilityProductInput[]` dari `checkoutItems` + `productById` — bentuk sama dengan yang sudah dipakai `eligibleProductSubtotal` (`{id, categoryId, categorySlug, brandId}`).
- Ganti gate di `validateAndCalcVoucher` (line 393-400):

```ts
// SEBELUM:
if (voucherScopeOf(voucher) === "PRODUCT" && eligibleProductSubtotal(voucher) <= 0) { ... }
// SESUDAH:
if (!cartMatchesVoucherScope(voucher, cartProductInputs)) {
  throw new VoucherValidationError("Voucher tidak berlaku untuk produk ini");
}
```

- **Satu perubahan ini menutup semua path**: `validateAndCalcVoucher` dipakai ulang untuk `freeShippingCode`, `productCode`, `loyaltyCode`, dan `privateCode` (line 432-459), lalu hasilnya dirutekan ke `shippingDiscount`/`productDiscount`. Verified.
- **THROW, bukan silent-drop.** Alasan: (a) konsisten dgn semua kegagalan lain di validator; (b) gate jalan **sebelum** transaksi Serializable & sebelum `usedCount`/`voucherUsage` di-tulis → tidak ada state setengah-apply; (c) hindari overcharge diam-diam (user tap Bayar lihat gratis ongkir, lalu dicharge penuh). Client meng-handle 400 dgn re-run recalculate (sudah pola untuk voucher PRODUCT).

### 3.3 Charging surface — `app/api/checkout/recalculate/route.ts`

- Bangun `cartProductInputs` sekali (dari `checkoutItems` + `productById`).
- **DUA gate** harus diganti (jangan lupa yang kedua):
  - Line 442 (loop voucher member): `if (!cartMatchesVoucherScope(voucher, cartProductInputs)) → unavailable("Voucher tidak berlaku untuk produk di keranjang")`.
  - Line 554-558 (cabang voucher manual/private): idem untuk `manualVoucher`.
- Cek `scope === "SHIPPING" && shippingFee <= 0` (line 436) **tetap**; gate scope baru ditaruh di posisi gate PRODUCT lama (setelah cek shipping-fee). Urutan lain tak berubah.
- Pakai wording pesan yang sama dgn `voucher-list.ts` ("Voucher tidak berlaku untuk produk di keranjang") demi konsistensi UI.

### 3.4 Listing — `lib/voucher-list.ts` (dedup, perilaku tetap)

- `hasProductScope` → `voucherHasScope(v)`.
- `scopeUnmatched` → `cartProducts !== undefined && !cartMatchesVoucherScope(v, cartProducts)`.
- **Guard `cartProducts !== undefined` tetap DI LUAR helper** — client lama yang tak kirim isi cart tetap permisif (jangan regres listing jadi semua "unavailable").

### 3.5 Validate endpoints (preview) — plumbing cart items lintas-client

Kedua endpoint sekarang cuma terima `{code, subtotal}` → secara struktur belum bisa nge-gate. Tambahkan **daftar produk keranjang** ke body, lalu gate seperti pola [`app/api/cart/vouchers/route.ts`](../../../app/api/cart/vouchers/route.ts) (fetch produk → `EligibilityProductInput[]` → `cartMatchesVoucherScope`).

Kontrak baru (backward-compatible): field cart items **opsional**. Kalau tidak dikirim (client lama) → **skip gate** (permisif), persis `cart/vouchers` GET.

**a. Public — `app/api/vouchers/validate/route.ts`**
- Terima `productIds` (opsional). Kalau ada → fetch `{id, categoryId, brandId, category.slug}` → kalau `voucherHasScope(voucher) && !cartMatchesVoucherScope(...)` → `{ valid: false, error: "Voucher tidak berlaku untuk produk di keranjang" }`.
- Client: Flutter [`voucher_service.dart:67-73`](../../../flutter_app/lib/services/voucher_service.dart) — tambah `productIds` ke body `validate()`; teruskan dari pemanggil UI.

**b. Private — `app/api/cart/vouchers/validate-private/route.ts`**
- `bodySchema` (line 22-25): tambah `productIds: z.array(z.string()).optional()` (atau CSV, samakan dgn cart/vouchers).
- Setelah cek `minimumOrder` (line 124-129), sebelum hitung `discount`: kalau scoped & tak cocok → `{ ok: false, message: "Voucher tidak berlaku untuk produk di keranjang" }`.
- Client Flutter: [`cart_service.dart:120-128`](../../../flutter_app/lib/services/cart_service.dart) `validatePrivateVoucher` — kirim `productIds`.
- Client web: [`components/cart/CartVoucherSheet.tsx`](../../../components/cart/CartVoucherSheet.tsx) — sertakan product ids saat POST validate-private.

### 3.6 Parity `categorySlug` (item tambahan)

Charging surface saat ini hanya forward `categoryId` (recalculate ~396-400, orders ~326-329), **bukan** `categorySlug` — padahal `voucherMatchesProduct` line 42-43 mendukung `eligibleCategoryIds` berbasis slug (data legacy/admin). Akibat: voucher kategori berbasis-slug **cocok di listing tapi gagal di checkout**.

Fix: pada product fetch di `orders` + `recalculate`, `select` `category: { select: { slug: true } }`, dan forward `categorySlug` ke `cartProductInputs`. Menyamakan perilaku listing == checkout.

---

## 4. Edge cases (dikonfirmasi via workflow)

| Kasus | Perilaku setelah fix |
|---|---|
| Voucher tak-berscope (SHIPPING/PRODUCT) | Gate di-skip → berlaku seperti sekarang (whole cart). **Tidak berubah.** |
| SHIPPING scoped kategori / produk | Ikut ter-gate (bonus, bukan cuma brand). |
| Multi-brand (`eligibleBrandIds` banyak) | Cocok kalau keranjang punya produk dari **salah satu** brand (OR). |
| Self-pickup `shippingFee = 0` + SHIPPING scoped | Tetap ter-blok/nol; tak ada ongkir untuk digratiskan → tak ada bocor. Cek `shippingFee<=0` (436) bisa muncul lebih dulu (beda pesan, hasil sama). |
| Keranjang kosong | recalculate early-return; orders: voucher scoped → `products.some` false → ter-blok; unscoped → lolos gate, di-handle min-order/discount. |
| Manual/private SHIPPING voucher | Ter-gate di orders (jalur `validateAndCalcVoucher`) **dan** recalculate cabang manual (554-558) — dua-duanya wajib diubah. |
| Produk cocok berharga 0 | Lolos gate (eksistensi), lalu di-handle cek `discount<=0` (bukan salah-tolak scope). |
| Nominal voucher PRODUCT | Tetap dari `eligibleProductSubtotal` (partial-cart tetak benar). |

---

## 5. Testing (TDD — tulis dulu)

Unit (pure, `tests/voucher-eligibility.test.ts`):
- `voucherHasScope`: brand/kategori/produk non-empty → true; semua kosong → false.
- `cartMatchesVoucherScope`: brand-scoped + keranjang tanpa brand → false; ada brand → true; unscoped → true; produk cocok berharga 0 → true; multi-brand OR.

Listing (`tests/voucher-list.test.ts`):
- Voucher **ongkir** brand-scoped (bukan cuma produk) + keranjang tanpa brand → `applicable: false`.
- `cartProducts === undefined` → tetap permisif.

Charge-layer (tambah, sesuai kelayakan harness — cek apakah route handler bisa dites; kalau tidak, andalkan predikat pure + code-review kedua route memanggilnya):
- recalculate menolak SHIPPING brand-scoped member voucher tanpa produk cocok (loop **dan** cabang manual).
- orders `validateAndCalcVoucher` menolak (400) untuk `freeShippingCode` dan `privateCode`.
- **Positif:** gratis ongkir global + brand-scoped-DENGAN-produk-cocok tetap ter-apply.
- Parity: voucher kategori berbasis slug cocok di checkout (bukan cuma listing).

Validate endpoints:
- `validate` / `validate-private` menolak voucher scoped tanpa produk cocok begitu `productIds` dikirim; tanpa `productIds` tetap permisif (backward-compat).

---

## 6. Risiko & mitigasi

| Risiko | Mitigasi |
|---|---|
| **`brandId`/`categorySlug` tak ter-forward** di `cartProductInputs` → voucher brand valid malah ter-blok (over-block). TS tak menangkap (field opsional). Ini gotcha yang sudah tercatat di memory. | Review eksplisit: `cartProductInputs` harus forward `{id, categoryId, categorySlug, brandId}`. Test positif brand-scoped-cocok. |
| Lupa gate kedua di recalculate (554-558) | Checklist plan; test cabang manual. |
| `eligibleProductSubtotal` di-repurpose | Larangan eksplisit: tetap sbg basis nominal PRODUCT. |
| Preview ≠ commit (hanya satu surface diubah) | recalculate & orders **wajib** pakai helper yang sama. |
| Client tak handle 400 dari orders | Pastikan client re-run recalculate saat 400 (pola voucher PRODUCT sudah ada). |
| Endpoint publik `validate` tanpa login | Gate scope tetap aman (permisif jika `productIds` absen); tak mengubah kontrak lama. |

---

## 7. Ringkasan file tersentuh

**Backend (inti):**
- `lib/voucher-eligibility.ts` — helper baru
- `lib/voucher-list.ts` — dedup ke helper
- `app/api/orders/route.ts` — gate + cartProductInputs + categorySlug select
- `app/api/checkout/recalculate/route.ts` — 2 gate + cartProductInputs + categorySlug select
- `app/api/vouchers/validate/route.ts` — terima productIds + gate
- `app/api/cart/vouchers/validate-private/route.ts` — terima productIds + gate

**Client:**
- `flutter_app/lib/services/voucher_service.dart` — kirim productIds ke `validate`
- `flutter_app/lib/services/cart_service.dart` — kirim productIds ke `validatePrivateVoucher`
- `components/cart/CartVoucherSheet.tsx` — kirim product ids ke validate-private
- (pemanggil UI yang meneruskan isi keranjang ke service di atas)

**Test:** `tests/voucher-eligibility.test.ts`, `tests/voucher-list.test.ts` (+ charge-layer bila memungkinkan)

---

## 8. Out of scope

- Selisih nominal "9k vs 15k" (perilaku persen ongkir yang benar).
- **Order lama yang sudah terlanjur bocor — TIDAK ditangani sama sekali** (tidak dihitung, tidak dikoreksi, tidak ditagih). Fix hanya menutup kebocoran ke depan.
- Guard di sisi admin/creation voucher (semantik "SHIPPING + brand butuh produk cocok") — bisa follow-up.
