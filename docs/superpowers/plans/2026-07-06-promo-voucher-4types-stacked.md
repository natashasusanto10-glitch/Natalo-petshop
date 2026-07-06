# Promo & Voucher 4 Tipe + Estimasi Bertumpuk — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sheet "Promo & voucher" di detail produk app menampilkan 4 tipe voucher dengan warna berbeda (loyalty ungu baru), memunculkan semua voucher yang cocok termasuk brand, dan mengestimasi hemat dengan menumpuk diskon produk + poin loyalty.

**Architecture:** Backend Next.js (`lib/`, `app/api/`) mengirim `kind` + `loyaltyPoints` dan semua voucher publik yang cocok (loader plural). App Flutter menyimpan field baru di `ProductVoucherPreview`, memindah logika estimasi/teks ke util murni yang bisa diuji, lalu me-render 4 taksonomi warna + kartu estimasi dua-baris.

**Tech Stack:** TypeScript/Next.js/Prisma (backend), Dart/Flutter (app). Test backend: `node:test` via `npm test`. Test Flutter: `flutter_test` via `flutter test`.

## Global Constraints

- Warna (hex verbatim): diskon produk `#E11D48` (bg `#FFEEF1`, border `#FFC9D0`); ongkir `#16A34A` (bg `#F0FDF4`, border `#BBF7D0`); loyalty `#7C3AED` (dark `#6D28D9`, bg `#F5F1FE`, border `#E0D4FB`); brand `#B85C00` (amber `#F7A100`, bg `#FEF0DC`, border `#FCD9A0`).
- Presedensi penentuan gaya: **ongkir → loyalty → brand → diskon**.
- Urutan daftar voucher: brand-exclusive → diskon umum → ongkir → loyalty.
- Copy loyalty: `"Ditukar dari {N} poin loyalty • Min. belanja {min}"`; fallback bila poin null: `"Hasil tukar poin loyalty • Min. belanja {min}"`.
- Estimasi **optimis**: menumpuk semua voucher cocok tanpa gating min. belanja. Disclaimer "Voucher final akan dihitung saat checkout" tetap ada.
- **Tanpa** caption di kartu estimasi dan **tanpa** baris "bisa dipakai bareng".
- Refactor tabel tier loyalty **tidak boleh** mengubah perilaku redeem (string `label` byte-identical).
- Verifikasi backend: `npm test` + `npx tsc --noEmit`. Verifikasi Flutter: `flutter test` + `flutter analyze` (jalankan dari dalam `flutter_app/`).

---

### Task 1: Ekstrak tabel tier loyalty ke modul bersama

**Files:**
- Create: `lib/loyalty-tiers.ts`
- Test: `tests/loyalty-tiers.test.ts`
- Modify: `app/api/member/claim-voucher/route.ts` (ganti `TIERS` lokal → import)
- Modify: `app/account/loyalty/redeem/RedeemPointsClient.tsx` (ganti `LOYALTY_TIERS` lokal → import)

**Interfaces:**
- Produces: `LOYALTY_TIERS: readonly LoyaltyTier[]`, `loyaltyPointsForDiscount(discountAmount: number): number | null`, `type LoyaltyTier = { points: number; discountAmount: number; minimumOrder: number; label: string }`.

- [ ] **Step 1: Tulis test yang gagal**

Create `tests/loyalty-tiers.test.ts`:

```ts
import assert from "node:assert/strict";
import test from "node:test";
import { LOYALTY_TIERS, loyaltyPointsForDiscount } from "@/lib/loyalty-tiers";

test("loyaltyPointsForDiscount: Rp150.000 -> 200 poin", () => {
  assert.equal(loyaltyPointsForDiscount(150000), 200);
});

test("loyaltyPointsForDiscount: Rp10.000 -> 20 poin", () => {
  assert.equal(loyaltyPointsForDiscount(10000), 20);
});

test("loyaltyPointsForDiscount: nominal non-tier -> null", () => {
  assert.equal(loyaltyPointsForDiscount(12345), null);
});

test("LOYALTY_TIERS: 5 tier dengan discountAmount unik", () => {
  const amounts = LOYALTY_TIERS.map((t) => t.discountAmount);
  assert.equal(amounts.length, 5);
  assert.equal(new Set(amounts).size, 5);
});
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run: `npm test`
Expected: FAIL — `Cannot find module '@/lib/loyalty-tiers'`.

- [ ] **Step 3: Buat modul**

Create `lib/loyalty-tiers.ts` (label byte-identical dengan `TIERS` lama di claim-voucher):

```ts
export type LoyaltyTier = {
  points: number;
  discountAmount: number;
  minimumOrder: number;
  label: string;
};

// Sumber tunggal tabel tier tukar poin loyalty. Sebelumnya terduplikasi di
// app/api/member/claim-voucher/route.ts dan RedeemPointsClient.tsx.
// Earn rate: 1 poin per Rp20.000 belanja.
export const LOYALTY_TIERS: readonly LoyaltyTier[] = [
  { points: 20, discountAmount: 10000, minimumOrder: 150000, label: "20 poin -> voucher Rp10.000 (min belanja Rp150.000)" },
  { points: 50, discountAmount: 25000, minimumOrder: 300000, label: "50 poin -> voucher Rp25.000 (min belanja Rp300.000)" },
  { points: 75, discountAmount: 40000, minimumOrder: 500000, label: "75 poin -> voucher Rp40.000 (min belanja Rp500.000)" },
  { points: 100, discountAmount: 60000, minimumOrder: 700000, label: "100 poin -> voucher Rp60.000 (min belanja Rp700.000)" },
  { points: 200, discountAmount: 150000, minimumOrder: 1500000, label: "200 poin -> voucher Rp150.000 (min belanja Rp1.500.000)" },
] as const;

// Balikan jumlah poin dari nominal diskon voucher loyalty. Nominal unik per
// tier, jadi cukup match discountAmount. null bila bukan nominal tier.
export function loyaltyPointsForDiscount(discountAmount: number): number | null {
  const tier = LOYALTY_TIERS.find((t) => t.discountAmount === discountAmount);
  return tier ? tier.points : null;
}
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

Run: `npm test`
Expected: PASS untuk 4 test loyalty-tiers.

- [ ] **Step 5: Refactor `claim-voucher/route.ts`**

Di `app/api/member/claim-voucher/route.ts`: hapus deklarasi `const TIERS = [ ... ] as const;` (blok baris ~15-52) beserta komentarnya, tambah import di atas:

```ts
import { LOYALTY_TIERS } from "@/lib/loyalty-tiers";
```

Ganti dua referensi `TIERS` menjadi `LOYALTY_TIERS`:
- `export async function GET() { return NextResponse.json({ tiers: LOYALTY_TIERS }); }`
- `const tier = LOYALTY_TIERS.find((t) => t.points === requestedPoints);`

Sisa logika (termasuk `tier.label`, `tier.discountAmount`, `tier.minimumOrder`) tidak berubah.

- [ ] **Step 6: Refactor `RedeemPointsClient.tsx`**

Di `app/account/loyalty/redeem/RedeemPointsClient.tsx`: hapus deklarasi array tier lokal (`const LOYALTY_TIERS = [ { points: 20, ... }, ... ];`, baris ~11-18) beserta komentar `// Earn rate` di atasnya, tambah import:

```ts
import { LOYALTY_TIERS } from "@/lib/loyalty-tiers";
```

Semua penggunaan `LOYALTY_TIERS`, `tier.points`, `tier.discountAmount`, `tier.minimumOrder` tetap valid (field sama). `tier.label` yang baru tidak dipakai di sini — aman.

- [ ] **Step 7: Verifikasi tipe + test**

Run: `npx tsc --noEmit`
Expected: tidak ada error.
Run: `npm test`
Expected: PASS semua (termasuk test lama).

- [ ] **Step 8: Commit**

```bash
git add lib/loyalty-tiers.ts tests/loyalty-tiers.test.ts app/api/member/claim-voucher/route.ts app/account/loyalty/redeem/RedeemPointsClient.tsx
git commit -m "refactor(loyalty): tabel tier ke lib/loyalty-tiers.ts + loyaltyPointsForDiscount"
```

---

### Task 2: Loader voucher publik plural + poin loyalty di payload member

**Files:**
- Modify: `lib/product-vouchers.ts`
- Test: `tests/product-vouchers.test.ts`

**Interfaces:**
- Consumes: `loyaltyPointsForDiscount` (Task 1).
- Produces: `buildMatchingVoucherPreviews(vouchers: PublicProductVoucherRow[], product: ProductVoucherProductInput): ProductVoucherPreview[]`; `loadPublicProductVoucherPreviews(product, options): Promise<{ product: ProductVoucherPreview[]; shipping: ProductVoucherPreview[] }>`; export `type PublicProductVoucherRow`; `ProductVoucherItem` bertambah `loyaltyPoints: number | null`.

- [ ] **Step 1: Tulis test yang gagal**

Create `tests/product-vouchers.test.ts`:

```ts
import assert from "node:assert/strict";
import test from "node:test";
import {
  buildMatchingVoucherPreviews,
  type PublicProductVoucherRow,
} from "@/lib/product-vouchers";

function makeRow(overrides: Partial<PublicProductVoucherRow> = {}): PublicProductVoucherRow {
  return {
    id: "v-general",
    name: null,
    code: "GEN",
    description: null,
    discountPercent: null,
    discountAmount: 20000,
    maxDiscountAmount: null,
    minimumOrder: 200000,
    maxUsage: null,
    usedCount: 0,
    expiresAt: null,
    discountScope: "PRODUCT",
    targetUser: "ALL_MEMBERS",
    newMemberMaxAccountAgeDays: null,
    newMemberRequireNoSuccessfulOrder: false,
    usageLimitPeriod: "LIFETIME",
    usageLimitPerUser: null,
    eligibleUserIds: [],
    eligibleProductIds: [],
    eligibleCategoryIds: [],
    eligibleBrandIds: [],
    ...overrides,
  };
}

const product = {
  id: "p1",
  price: 542000,
  categoryId: null,
  categorySlug: null,
  brandId: "brand-happydog",
};

test("buildMatchingVoucherPreviews: voucher umum + brand sama-sama muncul", () => {
  const general = makeRow({ id: "v-general", discountAmount: 20000, eligibleBrandIds: [] });
  const brand = makeRow({
    id: "v-brand",
    discountAmount: null,
    discountPercent: 10,
    maxDiscountAmount: 50000,
    minimumOrder: 300000,
    eligibleBrandIds: ["brand-happydog"],
  });
  const previews = buildMatchingVoucherPreviews([general, brand], product);
  const ids = previews.map((p) => p.id);
  assert.equal(previews.length, 2);
  assert.ok(ids.includes("v-general"));
  assert.ok(ids.includes("v-brand"));
});

test("buildMatchingVoucherPreviews: voucher brand lain tidak muncul", () => {
  const otherBrand = makeRow({ id: "v-other", eligibleBrandIds: ["brand-lain"] });
  const previews = buildMatchingVoucherPreviews([otherBrand], product);
  assert.equal(previews.length, 0);
});

test("buildMatchingVoucherPreviews: preview brand ditandai isBrandExclusive", () => {
  const brand = makeRow({ id: "v-brand", eligibleBrandIds: ["brand-happydog"] });
  const [preview] = buildMatchingVoucherPreviews([brand], product);
  assert.equal(preview.isBrandExclusive, true);
});
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run: `npm test`
Expected: FAIL — `buildMatchingVoucherPreviews` / `PublicProductVoucherRow` belum di-export.

- [ ] **Step 3: Export tipe + ekstrak fungsi murni**

Di `lib/product-vouchers.ts`:

Tambah import di atas:

```ts
import { loyaltyPointsForDiscount } from "@/lib/loyalty-tiers";
```

Ubah `type PublicProductVoucherRow = {` menjadi `export type PublicProductVoucherRow = {` (tanpa mengubah isinya).

Tambah komparator + fungsi murni (letakkan tepat sebelum `export async function attachPublicProductVoucherPreviews`):

```ts
function byBestSavingDesc(
  a: ProductVoucherPreview,
  b: ProductVoucherPreview
): number {
  const amountDelta = (b.savingAmount ?? 0) - (a.savingAmount ?? 0);
  if (amountDelta !== 0) return amountDelta;
  return (b.discountPercent ?? 0) - (a.discountPercent ?? 0);
}

// Semua preview voucher yang cocok untuk produk (bukan cuma yang terbaik).
// Murni — tanpa DB — supaya bisa diuji.
export function buildMatchingVoucherPreviews(
  vouchers: PublicProductVoucherRow[],
  product: ProductVoucherProductInput
): ProductVoucherPreview[] {
  return vouchers
    .filter((voucher) => voucherAppliesToProduct(voucher, product))
    .map((voucher) => buildProductVoucherPreview(voucher, product))
    .filter((preview): preview is ProductVoucherPreview => Boolean(preview))
    .sort(byBestSavingDesc);
}
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

Run: `npm test`
Expected: PASS untuk 3 test product-vouchers.

- [ ] **Step 5: Refactor `attachPublicProductVoucherPreviews` agar DRY**

Di dalam `products.map((product) => { ... })` pada `attachPublicProductVoucherPreviews`, ganti blok `const previews = productVouchers.filter(...).map(...).filter(...).sort(...)` dan `const shippingPreviews = ...` menjadi:

```ts
      const previews = buildMatchingVoucherPreviews(productVouchers, product);
      const shippingPreviews = buildMatchingVoucherPreviews(shippingVouchers, product);
```

(sisa: `voucherPreview: previews[0] ?? null, shippingVoucherPreview: shippingPreviews[0] ?? null` tetap.)

- [ ] **Step 6: Tambah loader plural**

Tambahkan setelah `loadPublicShippingVoucherPreview`:

```ts
// Versi plural untuk endpoint 1-produk (/api/products/[slug]/vouchers):
// balikan SEMUA voucher publik yang cocok, bukan cuma terbaik — supaya
// voucher brand tidak ter-drop kalah nominal dari voucher umum.
export async function loadPublicProductVoucherPreviews(
  product: ProductVoucherProductInput,
  options: ProductVoucherPreviewOptions = {}
): Promise<{ product: ProductVoucherPreview[]; shipping: ProductVoucherPreview[] }> {
  try {
    const userContext = await loadProductVoucherPreviewUserContext(options.userId);
    const [productVouchers, shippingVouchers] = await Promise.all([
      loadPublicProductDiscountVouchers("PRODUCT", userContext),
      loadPublicProductDiscountVouchers("SHIPPING", userContext),
    ]);
    return {
      product: buildMatchingVoucherPreviews(productVouchers, product),
      shipping: buildMatchingVoucherPreviews(shippingVouchers, product),
    };
  } catch {
    return { product: [], shipping: [] };
  }
}
```

- [ ] **Step 7: Tambah `loyaltyPoints` ke item member**

Di `type ProductVoucherItem`, tambah field:

```ts
  loyaltyPoints: number | null;
```

Di `loadVisibleProductVouchers`, dalam `.map((voucher) => ({ ... }))`, tambah properti (setelah `isBrandExclusive: ...`):

```ts
      loyaltyPoints:
        voucher.kind === "LOYALTY_CLAIM"
          ? loyaltyPointsForDiscount(voucher.discountAmount ?? 0)
          : null,
```

- [ ] **Step 8: Verifikasi tipe + test**

Run: `npx tsc --noEmit`
Expected: tidak ada error.
Run: `npm test`
Expected: PASS semua.

- [ ] **Step 9: Commit**

```bash
git add lib/product-vouchers.ts tests/product-vouchers.test.ts
git commit -m "feat(voucher): loader publik plural (semua voucher cocok) + loyaltyPoints"
```

---

### Task 3: Endpoint kirim semua voucher + dedup by id

**Files:**
- Modify: `lib/product-vouchers.ts` (tambah `dedupeVouchersById`)
- Modify: `app/api/products/[slug]/vouchers/route.ts`
- Test: `tests/product-vouchers.test.ts` (tambah kasus dedup)

**Interfaces:**
- Consumes: `loadPublicProductVoucherPreviews` (Task 2).
- Produces: `dedupeVouchersById<T extends { id: string }>(lists: T[][]): T[]`.

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan di `tests/product-vouchers.test.ts`:

```ts
import { dedupeVouchersById } from "@/lib/product-vouchers";

test("dedupeVouchersById: buang id duplikat lintas-list, jaga urutan + instance pertama", () => {
  const a = { id: "a" };
  const b = { id: "b" };
  const b2 = { id: "b" };
  const c = { id: "c" };
  const out = dedupeVouchersById([[a, b], [b2, c]]);
  assert.deepEqual(out.map((v) => v.id), ["a", "b", "c"]);
  assert.equal(out[1], b);
});
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run: `npm test`
Expected: FAIL — `dedupeVouchersById` belum di-export.

- [ ] **Step 3: Tambah `dedupeVouchersById`**

Di `lib/product-vouchers.ts` (dekat `buildMatchingVoucherPreviews`):

```ts
// Gabung beberapa list voucher, buang id duplikat (instance pertama menang,
// urutan dipertahankan). Voucher brand publik bisa muncul di jalur publik &
// member sekaligus.
export function dedupeVouchersById<T extends { id: string }>(
  lists: T[][]
): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const list of lists) {
    for (const voucher of list) {
      if (seen.has(voucher.id)) continue;
      seen.add(voucher.id);
      out.push(voucher);
    }
  }
  return out;
}
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

Run: `npm test`
Expected: PASS.

- [ ] **Step 5: Rewire route**

Ganti isi `app/api/products/[slug]/vouchers/route.ts` bagian setelah `attachBrandName` didefinisikan. Ganti import loader:

```ts
import {
  loadPublicProductVoucherPreviews,
  loadVisibleProductVouchers,
  dedupeVouchersById,
} from "@/lib/product-vouchers";
```

(hapus import `loadPublicProductVoucherPreview` dan `loadPublicShippingVoucherPreview` yang lama.)

Ganti blok `Promise.all([...])` + konstruksi `vouchers` menjadi:

```ts
  const [publicPreviews, memberVouchers] = await Promise.all([
    loadPublicProductVoucherPreviews(previewInput, {
      userId: session?.sub ?? null,
    }),
    session
      ? loadVisibleProductVouchers(session.sub, previewInput)
      : Promise.resolve([]),
  ]);

  const deduped = dedupeVouchersById<{ id: string; isBrandExclusive?: boolean }>([
    publicPreviews.product,
    publicPreviews.shipping,
    memberVouchers,
  ]);
  const vouchers = deduped.map(attachBrandName);

  return NextResponse.json({ vouchers });
```

- [ ] **Step 6: Verifikasi tipe + lint + test**

Run: `npx tsc --noEmit`
Expected: tidak ada error.
Run: `npm run lint`
Expected: tidak ada error baru.
Run: `npm test`
Expected: PASS semua.

- [ ] **Step 7: Commit**

```bash
git add lib/product-vouchers.ts app/api/products/[slug]/vouchers/route.ts tests/product-vouchers.test.ts
git commit -m "feat(voucher): endpoint produk kirim semua voucher cocok + dedup by id"
```

---

### Task 4: Model Flutter — `kind`, `loyaltyPoints`, `isLoyaltyVoucher`

**Files:**
- Modify: `flutter_app/lib/models/product.dart` (class `ProductVoucherPreview`)
- Test: `flutter_app/test/product_voucher_preview_test.dart`

**Interfaces:**
- Produces: `ProductVoucherPreview.kind: String?`, `.loyaltyPoints: int?`, getter `.isLoyaltyVoucher: bool`.

- [ ] **Step 1: Tulis test yang gagal**

Create `flutter_app/test/product_voucher_preview_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';

void main() {
  test('kind LOYALTY_CLAIM -> isLoyaltyVoucher + loyaltyPoints', () {
    final v = ProductVoucherPreview.fromJson({
      'id': 'poin-1',
      'kind': 'LOYALTY_CLAIM',
      'discountAmount': 150000,
      'minPurchase': 1500000,
      'loyaltyPoints': 200,
    });
    expect(v.isLoyaltyVoucher, isTrue);
    expect(v.loyaltyPoints, 200);
    expect(v.isShippingVoucher, isFalse);
  });

  test('type LOYALTY_POINT_CLAIM -> isLoyaltyVoucher', () {
    final v = ProductVoucherPreview.fromJson({
      'id': 'x',
      'type': 'LOYALTY_POINT_CLAIM',
    });
    expect(v.isLoyaltyVoucher, isTrue);
  });

  test('voucher diskon biasa -> bukan loyalty', () {
    final v = ProductVoucherPreview.fromJson({
      'id': 'y',
      'kind': 'PRODUCT_DISCOUNT',
      'discountAmount': 20000,
    });
    expect(v.isLoyaltyVoucher, isFalse);
    expect(v.loyaltyPoints, isNull);
  });
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run: `cd flutter_app && flutter test test/product_voucher_preview_test.dart`
Expected: FAIL — getter `isLoyaltyVoucher` / field `loyaltyPoints` belum ada.

- [ ] **Step 3: Tambah field + getter**

Di `flutter_app/lib/models/product.dart`, class `ProductVoucherPreview`:

Tambah dua field (setelah `final String? brandName;`):

```dart
  final String? kind;
  final int? loyaltyPoints;
```

Tambah dua parameter constructor (setelah `this.brandName,`):

```dart
    this.kind,
    this.loyaltyPoints,
```

Tambah getter (setelah `isBrandExclusive`):

```dart
  bool get isLoyaltyVoucher {
    final k = (kind ?? '').trim().toUpperCase();
    final t = type.trim().toUpperCase();
    return k == 'LOYALTY_CLAIM' || t == 'LOYALTY_POINT_CLAIM';
  }
```

Di `factory ProductVoucherPreview.fromJson`, tambah dalam pemanggilan constructor (setelah `brandName: _stringOrNull(json['brandName']),`):

```dart
      kind: _stringOrNull(json['kind']),
      loyaltyPoints:
          _nullableDouble(json['loyaltyPoints'] ?? json['loyalty_points'])
              ?.toInt(),
```

Di `Map<String, dynamic> toJson()`, tambah dua entri:

```dart
        'kind': kind,
        'loyaltyPoints': loyaltyPoints,
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

Run: `cd flutter_app && flutter test test/product_voucher_preview_test.dart`
Expected: PASS 3 test.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/product.dart flutter_app/test/product_voucher_preview_test.dart
git commit -m "feat(app): ProductVoucherPreview simpan kind + loyaltyPoints + isLoyaltyVoucher"
```

---

### Task 5: Util murni Flutter — estimasi bertumpuk + teks voucher

**Files:**
- Create: `flutter_app/lib/utils/voucher_promo.dart`
- Test: `flutter_app/test/voucher_promo_test.dart`

**Interfaces:**
- Consumes: `ProductVoucherPreview` (Task 4), `formatRupiahCompact` (`lib/utils/formatters.dart`).
- Produces: `voucherDiscountEstimate(double productFinalPrice, ProductVoucherPreview)`; `class PromoEstimate { double productVoucherDiscount; double loyaltyVoucherDiscount; double get totalVoucherDiscount; }`; `computePromoEstimate(double productFinalPrice, List<ProductVoucherPreview>): PromoEstimate`; `voucherDiscountText(ProductVoucherPreview): String`; `voucherSheetSubtitle(ProductVoucherPreview): String`; `voucherChipText(ProductVoucherPreview): String`.

- [ ] **Step 1: Tulis test yang gagal**

Create `flutter_app/test/voucher_promo_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/product.dart';
import 'package:natalo_petshop_flutter/utils/voucher_promo.dart';

ProductVoucherPreview vp(Map<String, dynamic> j) =>
    ProductVoucherPreview.fromJson(j);

void main() {
  test('computePromoEstimate: diskon produk terbaik + loyalty digabung', () {
    final vouchers = [
      vp({'id': 'brand', 'kind': 'PRODUCT_DISCOUNT', 'discountPercent': 10, 'maxDiscountAmount': 50000, 'minPurchase': 300000, 'brandName': 'Happy Dog'}),
      vp({'id': 'general', 'kind': 'PRODUCT_DISCOUNT', 'discountAmount': 20000, 'minPurchase': 200000}),
      vp({'id': 'loyalty', 'kind': 'LOYALTY_CLAIM', 'discountAmount': 150000, 'minPurchase': 1500000, 'loyaltyPoints': 200}),
      vp({'id': 'ongkir', 'kind': 'FREE_SHIPPING'}),
    ];
    final est = computePromoEstimate(542000, vouchers);
    expect(est.productVoucherDiscount, 50000);
    expect(est.loyaltyVoucherDiscount, 150000);
    expect(est.totalVoucherDiscount, 200000);
  });

  test('voucherSheetSubtitle: loyalty menyebut jumlah poin', () {
    final v = vp({'id': 'l', 'kind': 'LOYALTY_CLAIM', 'discountAmount': 150000, 'minPurchase': 1500000, 'loyaltyPoints': 200});
    final s = voucherSheetSubtitle(v);
    expect(s.contains('200 poin'), isTrue);
    expect(s.contains('Min. belanja'), isTrue);
  });

  test('voucherSheetSubtitle: loyalty tanpa poin -> fallback generik', () {
    final v = vp({'id': 'l', 'kind': 'LOYALTY_CLAIM', 'discountAmount': 150000, 'minPurchase': 1500000});
    expect(voucherSheetSubtitle(v).startsWith('Hasil tukar poin loyalty'), isTrue);
  });
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run: `cd flutter_app && flutter test test/voucher_promo_test.dart`
Expected: FAIL — `package:.../utils/voucher_promo.dart` belum ada.

- [ ] **Step 3: Buat util**

Create `flutter_app/lib/utils/voucher_promo.dart`:

```dart
import '../models/product.dart';
import 'formatters.dart';

// Estimasi diskon 1 voucher terhadap harga produk. Dipindah dari
// product_detail_screen.dart supaya bisa diuji tanpa widget.
double voucherDiscountEstimate(
  double productFinalPrice,
  ProductVoucherPreview voucher,
) {
  if (voucher.isShippingVoucher) return 0;
  final direct = voucher.savingAmount ?? voucher.discountAmount;
  if (direct != null && direct > 0) return direct;
  final percent = voucher.discountPercent;
  if (percent == null || percent <= 0) return 0;
  final raw = productFinalPrice * (percent / 100);
  final cap = voucher.maxDiscountAmount;
  if (cap != null && cap > 0) return raw > cap ? cap : raw;
  return raw;
}

// Estimasi bertumpuk lintas-slot: 1 voucher diskon produk terbaik + 1
// voucher loyalty terbaik (slot berbeda -> digabung). Ongkir tidak
// mengurangi harga barang.
class PromoEstimate {
  final double productVoucherDiscount;
  final double loyaltyVoucherDiscount;

  const PromoEstimate({
    required this.productVoucherDiscount,
    required this.loyaltyVoucherDiscount,
  });

  double get totalVoucherDiscount =>
      productVoucherDiscount + loyaltyVoucherDiscount;
}

PromoEstimate computePromoEstimate(
  double productFinalPrice,
  List<ProductVoucherPreview> vouchers,
) {
  double bestProduct = 0;
  double bestLoyalty = 0;
  for (final v in vouchers) {
    if (v.isShippingVoucher) continue;
    final d = voucherDiscountEstimate(productFinalPrice, v);
    if (v.isLoyaltyVoucher) {
      if (d > bestLoyalty) bestLoyalty = d;
    } else {
      if (d > bestProduct) bestProduct = d;
    }
  }
  return PromoEstimate(
    productVoucherDiscount: bestProduct,
    loyaltyVoucherDiscount: bestLoyalty,
  );
}

// Teks nominal diskon ("Hemat RpX" / "Diskon N%").
String voucherDiscountText(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) return 'Gratis Ongkir';
  final amount = voucher.discountAmount ?? voucher.savingAmount;
  if (amount != null && amount > 0) {
    return 'Hemat ${formatRupiahCompact(amount)}';
  }
  final percent = voucher.discountPercent;
  if (percent != null && percent > 0) {
    final cap =
        voucher.maxDiscountAmount != null && voucher.maxDiscountAmount! > 0
            ? ' s.d. ${formatRupiahCompact(voucher.maxDiscountAmount!)}'
            : '';
    return 'Diskon ${percent.toStringAsFixed(0)}%$cap';
  }
  final label = voucher.badgeLabel.trim();
  return label.isEmpty ? 'Voucher hemat' : label;
}

// Subtitle kartu voucher di sheet. Loyalty -> sebut jumlah poin.
String voucherSheetSubtitle(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) {
    return 'Bisa digunakan saat checkout';
  }
  final minimum = voucher.minimumOrder;
  if (voucher.isLoyaltyVoucher) {
    final points = voucher.loyaltyPoints;
    final base = points != null && points > 0
        ? 'Ditukar dari $points poin loyalty'
        : 'Hasil tukar poin loyalty';
    return minimum > 0
        ? '$base • Min. belanja ${formatRupiahCompact(minimum)}'
        : base;
  }
  final brandClause =
      voucher.isBrandExclusive ? 'Berlaku untuk ${voucher.brandName}' : null;
  if (brandClause != null && minimum > 0) {
    return '$brandClause • Min. belanja ${formatRupiahCompact(minimum)}';
  }
  if (brandClause != null) return brandClause;
  if (minimum > 0) {
    return 'Potongan belanja saat checkout • Min. belanja ${formatRupiahCompact(minimum)}';
  }
  return 'Potongan belanja saat checkout';
}

// Teks compact untuk rail chip.
String voucherChipText(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) return 'Gratis Ongkir';
  if (voucher.isBrandExclusive) return 'Khusus ${voucher.brandName}';
  return voucherDiscountText(voucher);
}
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

Run: `cd flutter_app && flutter test test/voucher_promo_test.dart`
Expected: PASS 3 test.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/utils/voucher_promo.dart flutter_app/test/voucher_promo_test.dart
git commit -m "feat(app): util voucher_promo (estimasi bertumpuk + teks) yang teruji"
```

---

### Task 6: UI sheet — 4 warna, loyalty ungu, estimasi dua-baris

**Files:**
- Modify: `flutter_app/lib/screens/product_detail_screen.dart`

**Interfaces:**
- Consumes: `voucher_promo.dart` (Task 5), `ProductVoucherPreview.isLoyaltyVoucher/loyaltyPoints` (Task 4).

- [ ] **Step 1: Import util + konstanta warna ungu**

Tambah import (dekat `import '../utils/formatters.dart';`):

```dart
import '../utils/voucher_promo.dart';
```

Tambah konstanta warna (setelah `const _brandExclusiveDark = Color(0xFFB85C00);`):

```dart
const _loyaltyPurple = Color(0xFF7C3AED);
const _loyaltyDark = Color(0xFF6D28D9);
const _loyaltySoftBg = Color(0xFFF5F1FE);
const _loyaltySoftBorder = Color(0xFFE0D4FB);
```

- [ ] **Step 2: Hapus helper privat yang pindah ke util, alihkan pemanggil**

Hapus definisi fungsi privat berikut dari `product_detail_screen.dart` (sudah ada versi publiknya di `voucher_promo.dart`): `_voucherChipText`, `_voucherDiscountText`, `_voucherSheetSubtitle`, `_voucherDiscountEstimate`.

Alihkan seluruh pemanggilan:
- `_voucherChipText(voucher)` → `voucherChipText(voucher)`
- `_voucherDiscountText(voucher)` → `voucherDiscountText(voucher)`
- `_voucherSheetSubtitle(voucher)` → `voucherSheetSubtitle(voucher)`
- `_voucherDiscountEstimate(product, voucher)` → `voucherDiscountEstimate(product.finalPrice, voucher)`

Verifikasi tidak ada sisa: `cd flutter_app && grep -n "_voucherChipText\|_voucherDiscountText\|_voucherSheetSubtitle\|_voucherDiscountEstimate" lib/screens/product_detail_screen.dart` harus kosong.

- [ ] **Step 3: Cabang loyalty di `_VoucherChip.build`**

Ganti awal `_VoucherChip.build` (bagian penentuan `shipping`/`brandExclusive`/`tone`/`icon`/`fill`/`bg`/`fg`) menjadi:

```dart
    final shipping = voucher.isShippingVoucher;
    final loyalty = voucher.isLoyaltyVoucher;
    final brandExclusive = voucher.isBrandExclusive;
    final tone = shipping
        ? _successGreen
        : loyalty
            ? _loyaltyDark
            : brandExclusive
                ? _brandExclusiveDark
                : _discountRed;
    final icon = shipping
        ? Icons.local_shipping_rounded
        : loyalty
            ? Icons.loyalty_rounded
            : brandExclusive
                ? Icons.workspace_premium_rounded
                : Icons.confirmation_number_rounded;
    final fill = loyalty || brandExclusive || (hero && !shipping);
    final bg = loyalty
        ? _loyaltyPurple
        : brandExclusive
            ? _brandExclusiveAmber
            : fill
                ? _discountRed
                : (shipping ? const Color(0xFFEFFAF4) : _softDiscountBg);
    final fg = fill ? Colors.white : tone;
```

(Sisa build `_VoucherChip` — border, teks `voucherChipText(voucher)` — tetap.)

- [ ] **Step 4: Cabang loyalty di `_VoucherSheetCard.build`**

Ganti penentuan `tone`/`bg`/`border` menjadi:

```dart
    final shipping = voucher.isShippingVoucher;
    final loyalty = voucher.isLoyaltyVoucher;
    final brandExclusive = voucher.isBrandExclusive;
    final tone = shipping
        ? _successGreen
        : loyalty
            ? _loyaltyDark
            : brandExclusive
                ? _brandExclusiveDark
                : _discountRed;
    final bg = shipping
        ? const Color(0xFFF0FDF4)
        : loyalty
            ? _loyaltySoftBg
            : brandExclusive
                ? _brandExclusiveSoftBg
                : _softDiscountBg;
    final border = shipping
        ? const Color(0xFFBBF7D0)
        : loyalty
            ? _loyaltySoftBorder
            : brandExclusive
                ? _brandExclusiveSoftBorder
                : const Color(0xFFFFC9D0);
    final subtitle = voucherSheetSubtitle(voucher);
```

Ganti blok badge `if (brandExclusive) ...[ ... ]` menjadi loyalty-dulu:

```dart
                if (loyalty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.loyalty_rounded, size: 13, color: tone),
                      const SizedBox(width: 5),
                      Text(
                        'POIN LOYALTY',
                        style: TextStyle(
                          color: tone,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ] else if (brandExclusive) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium_rounded,
                          size: 13, color: tone),
                      const SizedBox(width: 5),
                      Text(
                        'KHUSUS BRAND',
                        style: TextStyle(
                          color: tone,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
```

Ganti judul menjadi `voucherDiscountText(voucher)` (jika masih `_voucherDiscountText`).

Ganti trailing icon (blok `shipping ? Icon(truck) : brandExclusive ? Container(...) : _DiscountVoucherIcon()`) menjadi:

```dart
          shipping
              ? Icon(
                  Icons.local_shipping_rounded,
                  color: tone,
                  size: 24,
                )
              : loyalty
                  ? Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _loyaltyPurple,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.loyalty_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    )
                  : brandExclusive
                      ? Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _brandExclusiveAmber,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.workspace_premium_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        )
                      : const _DiscountVoucherIcon(),
```

- [ ] **Step 5: Urutan daftar + estimasi bertumpuk di `_PromoVoucherSheet.build`**

Tambah helper top-level (dekat fungsi util lain di file, mis. sebelum `_SectionShell`):

```dart
int _voucherSortRank(ProductVoucherPreview v) {
  if (v.isShippingVoucher) return 2;
  if (v.isLoyaltyVoucher) return 3;
  if (v.isBrandExclusive) return 0;
  return 1;
}
```

Di awal `_PromoVoucherSheet.build`, ganti perhitungan lama (`shippingVouchers`, `discountVouchers`, `bestVoucherDiscount`, `showEstimate`, `estimatedPrice`) menjadi:

```dart
    final sorted = [...vouchers]
      ..sort((a, b) => _voucherSortRank(a).compareTo(_voucherSortRank(b)));
    final shippingVouchers =
        sorted.where((v) => v.isShippingVoucher).toList();
    final estimate = computePromoEstimate(product.finalPrice, sorted);
    final discountProduct = product.price - product.finalPrice;
    final showEstimate =
        discountProduct > 0 || estimate.totalVoucherDiscount > 0;
    final estimatedPrice = (product.finalPrice - estimate.totalVoucherDiscount)
        .clamp(0, double.infinity);
```

Ganti pemakaian `_PromoEstimateCard(...)` menjadi:

```dart
                _PromoEstimateCard(
                  priceBeforePromo: product.price,
                  productDiscount: discountProduct,
                  productVoucherDiscount: estimate.productVoucherDiscount,
                  loyaltyVoucherDiscount: estimate.loyaltyVoucherDiscount,
                  estimatedPrice: estimatedPrice.toDouble(),
                ),
```

Ganti loop `for (final voucher in vouchers) ...` menjadi `for (final voucher in sorted) ...`.

- [ ] **Step 6: Dua baris diskon di `_PromoEstimateCard`**

Ganti field kelas:

```dart
  final double priceBeforePromo;
  final double productDiscount;
  final double productVoucherDiscount;
  final double loyaltyVoucherDiscount;
  final double estimatedPrice;
```

Ganti constructor:

```dart
  const _PromoEstimateCard({
    required this.priceBeforePromo,
    required this.productDiscount,
    required this.productVoucherDiscount,
    required this.loyaltyVoucherDiscount,
    required this.estimatedPrice,
  });
```

Ganti baris `if (voucherDiscount > 0) _PromoEstimateRow(...)` menjadi dua baris:

```dart
          if (productVoucherDiscount > 0)
            _PromoEstimateRow(
              label: 'Diskon voucher produk',
              value: '-${formatRupiah(productVoucherDiscount)}',
              valueColor: _discountRed,
            ),
          if (loyaltyVoucherDiscount > 0)
            _PromoEstimateRow(
              label: 'Diskon poin loyalty',
              value: '-${formatRupiah(loyaltyVoucherDiscount)}',
              valueColor: _loyaltyPurple,
            ),
```

- [ ] **Step 7: Analyze + test penuh**

Run: `cd flutter_app && flutter analyze`
Expected: "No issues found!" (atau tidak ada error baru pada file yang disentuh).
Run: `cd flutter_app && flutter test`
Expected: PASS semua (termasuk Task 4 & 5).

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/screens/product_detail_screen.dart
git commit -m "feat(app): sheet promo 4 warna voucher (loyalty ungu) + estimasi bertumpuk"
```

---

### Task 7: Verifikasi end-to-end

**Files:** (tidak ada perubahan kode — gerbang verifikasi)

- [ ] **Step 1: Sweep backend**

Run: `npm test && npx tsc --noEmit && npm run lint`
Expected: semua PASS / tanpa error.

- [ ] **Step 2: Sweep Flutter**

Run: `cd flutter_app && flutter analyze && flutter test`
Expected: "No issues found!" + semua test PASS.

- [ ] **Step 3: Verifikasi visual (manual)**

Jalankan app (mis. `cd flutter_app && flutter run`), buka detail produk yang punya voucher brand + login akun yang punya voucher loyalty, buka sheet "Promo & voucher". Konfirmasi:
- Kartu loyalty ungu dengan badge `POIN LOYALTY` + "Ditukar dari N poin loyalty".
- Voucher brand muncul (amber `KHUSUS BRAND`).
- Kartu estimasi menampilkan baris "Diskon voucher produk" + "Diskon poin loyalty" terpisah, "Perkiraan harga hemat" = harga − keduanya.
- Tidak ada caption/baris "bisa dipakai bareng".

- [ ] **Step 4: Commit (bila ada penyesuaian kecil dari verifikasi)**

```bash
git add -A && git commit -m "fix(app): penyesuaian sheet promo setelah verifikasi visual"
```

---

## Self-Review

**Spec coverage:**
- Loyalty ungu + badge + poin → Task 4 (model), Task 5 (copy), Task 6 (warna/badge). ✓
- Voucher brand selalu tampil → Task 2 (loader plural), Task 3 (route + dedup). ✓
- Estimasi bertumpuk → Task 5 (`computePromoEstimate`), Task 6 (kartu dua-baris). ✓
- Refactor tier ke `lib/loyalty-tiers.ts` + hapus duplikasi → Task 1. ✓
- Estimasi optimis (tanpa gating min) → `computePromoEstimate` tidak cek min. ✓
- Tanpa caption / baris gabung → tidak ada di Task 6. ✓
- Taksonomi 4 warna + presedensi ongkir→loyalty→brand→diskon → Task 6 Step 3/4. ✓
- Urutan daftar brand→umum→ongkir→loyalty → Task 6 Step 5 (`_voucherSortRank`). ✓
- Edge: belum login (member kosong, brand publik tetap tampil) → Task 3 (memberVouchers `[]`). ✓
- Edge: loyaltyPoints null → fallback generik → Task 5 test 3. ✓
- Edge: dedup voucher brand publik → Task 3. ✓

**Placeholder scan:** Tidak ada TBD/TODO; semua step berisi kode nyata. ✓

**Type consistency:** `buildMatchingVoucherPreviews`, `loadPublicProductVoucherPreviews`, `dedupeVouchersById`, `PromoEstimate`, `computePromoEstimate`, `voucherDiscountEstimate`, `voucherSheetSubtitle`, `voucherChipText`, `voucherDiscountText`, `isLoyaltyVoucher`, `loyaltyPoints`, `kind` — nama & tanda tangan konsisten antar-task. ✓
