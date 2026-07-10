# Voucher Shipping Brand Scope-Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tutup bypass voucher gratis-ongkir brand-eksklusif dengan menerapkan cek scope keranjang untuk SEMUA `discountScope` (bukan hanya `PRODUCT`) di setiap surface, lewat satu predikat bersama.

**Architecture:** Tambah satu predikat `cartMatchesVoucherScope` di `lib/voucher-eligibility.ts` (berbasis eksistensi produk cocok), lalu semua surface listing/preview/charge memanggilnya. Charging surface (`orders`, `recalculate`) sudah punya cart items; dua endpoint `validate` (dormant) di-harden defense-in-depth; klien Flutter dapat param opsional aditif; listing web disamakan dengan Flutter.

**Tech Stack:** Next.js (route handlers + `lib/`), Prisma, Zod, TypeScript; test `tsx --test` (`node:test` + `node:assert/strict`); Flutter/Dart (`flutter_app/`).

**Spec:** `docs/superpowers/specs/2026-07-09-voucher-shipping-brand-scope-gate-design.md`

## Global Constraints

- Gate kelayakan HARUS berbasis eksistensi produk cocok — `cartMatchesVoucherScope(...)` — **JANGAN** pernah pakai `eligibleProductSubtotal(voucher) <= 0` sebagai penentu kelayakan (produk cocok berharga 0 akan salah-tolak).
- `eligibleProductSubtotal` TETAP dipertahankan sebagai basis **nominal** voucher PRODUCT. Jangan hapus / jangan tukar dengan boolean.
- Setiap `cartProductInputs`/`EligibilityProductInput` HARUS meneruskan `brandId` **dan** `categorySlug` (selain `id`, `categoryId`) — field opsional, TS tak menangkap kalau lupa (gotcha memory: brandId pernah drop 4×).
- Voucher tak-berscope (semua `eligible*Ids` kosong) harus tetap berlaku (mis. gratis ongkir global) — `cartMatchesVoucherScope` mengembalikan `true` untuk voucher tak-berscope.
- Di `orders`, voucher tak layak WAJIB `throw VoucherValidationError` (400), BUKAN silent-drop.
- Guard `cartProducts !== undefined` di `voucher-list.ts` tetap DI LUAR helper (client lama tanpa cart items tetap permisif).
- Test runner: `npx tsx --test <file>`. Typecheck: `npx tsc --noEmit`. Dart: `cd flutter_app && flutter analyze`.
- Pesan UI: surface listing/preview (`recalculate`, `validate`, `validate-private`, `voucher-list`) pakai `"Voucher tidak berlaku untuk produk di keranjang"`; `orders` throw pakai `"Voucher tidak berlaku untuk produk ini"` (tak diubah dari string lama).

---

## File Structure

- **Create/extend:** `lib/voucher-eligibility.ts` — helper `voucherHasScope`, `cartMatchesVoucherScope` (satu sumber aturan scope).
- **Modify:** `lib/voucher-list.ts` — dedup ke helper (behavior-preserving).
- **Modify:** `app/api/orders/route.ts` — gate scope-agnostic + `categorySlug` + `cartProductInputs`.
- **Modify:** `app/api/checkout/recalculate/route.ts` — 2 gate (member loop + manual) + `categorySlug` + `cartProductInputs`.
- **Modify:** `app/api/vouchers/validate/route.ts` — terima `productIds` + gate.
- **Modify:** `app/api/cart/vouchers/validate-private/route.ts` — terima `productIds` + gate.
- **Modify:** `flutter_app/lib/services/voucher_service.dart`, `flutter_app/lib/services/cart_service.dart` — param opsional `productIds` (aditif).
- **Modify:** `components/cart/CartVoucherSheet.tsx` + `app/cart/page.tsx` — kirim `productIds` ke `GET /api/cart/vouchers` (parity listing web).
- **Test:** `tests/voucher-eligibility.test.ts`, `tests/voucher-list.test.ts`.

---

## Task 1: Predikat scope bersama + unit test

**Files:**
- Modify: `lib/voucher-eligibility.ts` (setelah `voucherMatchesProduct`, ~line 46)
- Test: `tests/voucher-eligibility.test.ts`

**Interfaces:**
- Consumes: `VoucherEligibilityScope`, `EligibilityProductInput`, `voucherMatchesProduct` (sudah ada di file yang sama).
- Produces:
  - `voucherHasScope(voucher: VoucherEligibilityScope): boolean`
  - `cartMatchesVoucherScope(voucher: VoucherEligibilityScope, products: EligibilityProductInput[]): boolean`

- [ ] **Step 1: Tambah unit test yang gagal**

Tambahkan di akhir `tests/voucher-eligibility.test.ts`:

```ts
import {
  voucherHasScope,
  cartMatchesVoucherScope,
} from "@/lib/voucher-eligibility";

function scope(overrides: Partial<{
  eligibleProductIds: string[];
  eligibleCategoryIds: string[];
  eligibleBrandIds: string[];
}> = {}) {
  return {
    eligibleProductIds: [],
    eligibleCategoryIds: [],
    eligibleBrandIds: [],
    ...overrides,
  };
}

test("voucherHasScope: semua eligible*Ids kosong -> false", () => {
  assert.equal(voucherHasScope(scope()), false);
});

test("voucherHasScope: eligibleBrandIds terisi -> true", () => {
  assert.equal(voucherHasScope(scope({ eligibleBrandIds: ["brand-hpi"] })), true);
});

test("cartMatchesVoucherScope: voucher tanpa scope -> true (berlaku semua produk)", () => {
  assert.equal(
    cartMatchesVoucherScope(scope(), [{ id: "p1", brandId: "b1" }]),
    true,
  );
});

test("cartMatchesVoucherScope: brand-scoped, keranjang tanpa brand cocok -> false", () => {
  assert.equal(
    cartMatchesVoucherScope(scope({ eligibleBrandIds: ["brand-hpi"] }), [
      { id: "p1", brandId: "brand-lain" },
    ]),
    false,
  );
});

test("cartMatchesVoucherScope: brand-scoped, ada produk brand cocok -> true", () => {
  assert.equal(
    cartMatchesVoucherScope(scope({ eligibleBrandIds: ["brand-hpi"] }), [
      { id: "p1", brandId: "brand-lain" },
      { id: "p2", brandId: "brand-hpi" },
    ]),
    true,
  );
});

test("cartMatchesVoucherScope: kategori-scoped cocok via categorySlug -> true", () => {
  assert.equal(
    cartMatchesVoucherScope(scope({ eligibleCategoryIds: ["kucing"] }), [
      { id: "p1", categoryId: null, categorySlug: "kucing" },
    ]),
    true,
  );
});

test("cartMatchesVoucherScope: keranjang kosong + voucher scoped -> false", () => {
  assert.equal(
    cartMatchesVoucherScope(scope({ eligibleBrandIds: ["brand-hpi"] }), []),
    false,
  );
});
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `npx tsx --test tests/voucher-eligibility.test.ts`
Expected: FAIL — `voucherHasScope`/`cartMatchesVoucherScope` belum ada (error import / "is not a function").

- [ ] **Step 3: Implement helper**

Tambahkan di `lib/voucher-eligibility.ts` tepat setelah fungsi `voucherMatchesProduct` (setelah baris `return false;` + `}` di ~line 46):

```ts
/**
 * True kalau voucher di-scope ke produk/kategori/brand tertentu (salah satu
 * eligible*Ids non-empty). Voucher tanpa scope berlaku untuk semua produk.
 */
export function voucherHasScope(voucher: VoucherEligibilityScope): boolean {
  return (
    (voucher.eligibleProductIds ?? []).length > 0 ||
    (voucher.eligibleCategoryIds ?? []).length > 0 ||
    (voucher.eligibleBrandIds ?? []).length > 0
  );
}

/**
 * True kalau voucher boleh dipakai untuk isi keranjang: TIDAK di-scope, ATAU
 * minimal SATU produk keranjang cocok ke scope-nya.
 *
 * Berbasis EKSISTENSI produk cocok (products.some) — BUKAN jumlah subtotal —
 * supaya produk cocok berharga 0 (hadiah / diskon 100%) tetap memenuhi scope.
 * Dipakai SEMUA surface (listing, checkout preview, order) supaya aturan scope
 * seragam untuk semua discountScope (termasuk gratis ongkir / SHIPPING).
 */
export function cartMatchesVoucherScope(
  voucher: VoucherEligibilityScope,
  products: EligibilityProductInput[],
): boolean {
  if (!voucherHasScope(voucher)) return true;
  return products.some((product) => voucherMatchesProduct(voucher, product));
}
```

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run: `npx tsx --test tests/voucher-eligibility.test.ts`
Expected: PASS (semua test lama + 7 test baru hijau).

- [ ] **Step 5: Commit**

```bash
git add lib/voucher-eligibility.ts tests/voucher-eligibility.test.ts
git commit -m "feat(voucher): predikat scope bersama cartMatchesVoucherScope + tests"
```

---

## Task 2: Dedup `voucher-list.ts` ke helper (behavior-preserving)

**Files:**
- Modify: `lib/voucher-list.ts:49-54` (import), `:232-235` (`hasProductScope`), `:244-247` (`scopeUnmatched`)
- Test: `tests/voucher-list.test.ts`

**Interfaces:**
- Consumes: `voucherHasScope`, `cartMatchesVoucherScope` (Task 1).

- [ ] **Step 1: Tambah regression test voucher SHIPPING brand-scoped**

Tambahkan di akhir `tests/voucher-list.test.ts` (fixture `voucher()` + `userCtx()` sudah ada di file):

```ts
test("voucher SHIPPING brand-scoped + cartProducts tanpa brand cocok -> unavailable", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-oks-hpi",
        code: "FREEOKSHPI",
        kind: "FREE_SHIPPING",
        type: "PUBLIC_FREE_SHIPPING",
        discountScope: "SHIPPING",
        discountAmount: 0,
        discountPercent: 0,
        eligibleBrandIds: ["brand-hpi"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [
      { id: "p1", categoryId: null, categorySlug: null, brandId: "brand-lain" },
    ],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, false);
  assert.ok(
    items[0].disabledReason?.includes("tidak berlaku"),
    `expected scope-mismatch reason, got: ${items[0].disabledReason}`,
  );
});

test("voucher SHIPPING brand-scoped + cartProducts ADA brand cocok -> applicable", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-oks-hpi",
        code: "FREEOKSHPI",
        kind: "FREE_SHIPPING",
        type: "PUBLIC_FREE_SHIPPING",
        discountScope: "SHIPPING",
        discountAmount: 0,
        discountPercent: 0,
        eligibleBrandIds: ["brand-hpi"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [
      { id: "p1", categoryId: null, categorySlug: null, brandId: "brand-hpi" },
    ],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true);
});
```

- [ ] **Step 2: Jalankan test — pastikan LULUS (voucher-list sudah benar untuk SHIPPING)**

Run: `npx tsx --test tests/voucher-list.test.ts`
Expected: PASS. (Guard ini mengunci perilaku SHIPPING sebelum refactor.)

- [ ] **Step 3: Dedup — pakai helper bersama**

Di `lib/voucher-list.ts`, ganti blok import (baris 49-54):

```ts
import {
  cartMatchesVoucherScope,
  voucherHasScope,
  formatVoucherBrandName,
  loadBrandNamesByIds,
  type EligibilityProductInput,
} from "@/lib/voucher-eligibility";
```

Ganti `hasProductScope` (baris 232-235):

```ts
    const hasProductScope = voucherHasScope(v);
```

Ganti `scopeUnmatched` (baris 244-247):

```ts
    const scopeUnmatched =
      cartProducts !== undefined && !cartMatchesVoucherScope(v, cartProducts);
```

- [ ] **Step 4: Jalankan test — pastikan tetap LULUS**

Run: `npx tsx --test tests/voucher-list.test.ts`
Expected: PASS (semua test lama termasuk scope gate + 2 test SHIPPING baru).

- [ ] **Step 5: Commit**

```bash
git add lib/voucher-list.ts tests/voucher-list.test.ts
git commit -m "refactor(voucher): voucher-list pakai predikat scope bersama + regression SHIPPING"
```

---

## Task 3: `orders.ts` — gate scope-agnostic + categorySlug (surface UANG)

**Files:**
- Modify: `app/api/orders/route.ts:26` (import), `:133-167` (product select), `:259` (setelah `productById`), `:319-333` (`eligibleProductSubtotal`), `:393-400` (gate)

**Interfaces:**
- Consumes: `cartMatchesVoucherScope` (Task 1).

- [ ] **Step 1: Tambah `categorySlug` ke product select**

Di `app/api/orders/route.ts`, pada `prisma.product.findMany` select (blok baris 133-167), tambahkan setelah `categoryId: true,` dan `brandId: true,`:

```ts
        category: { select: { slug: true } },
```

- [ ] **Step 2: Import helper**

Ganti baris 26:

```ts
import { cartMatchesVoucherScope, voucherMatchesProduct } from "@/lib/voucher-eligibility";
```

- [ ] **Step 3: Bangun `cartProductInputs`**

Tepat setelah `const productById = new Map(...)` (baris 259), tambahkan:

```ts
    const cartProductInputs = checkoutItems.map((item) => {
      const product = productById.get(item.productId);
      return {
        id: item.productId,
        categoryId: product?.categoryId ?? null,
        categorySlug: product?.category?.slug ?? null,
        brandId: product?.brandId ?? null,
      };
    });
```

- [ ] **Step 4: Teruskan `categorySlug` di `eligibleProductSubtotal`**

Di fungsi `eligibleProductSubtotal` (baris 319-333), pada objek yang dilempar ke `voucherMatchesProduct`, tambahkan `categorySlug`:

```ts
        const matches = voucherMatchesProduct(voucher, {
          id: item.productId,
          categoryId: product?.categoryId ?? null,
          categorySlug: product?.category?.slug ?? null,
          brandId: product?.brandId ?? null,
        });
```

- [ ] **Step 5: Ganti gate scope (baris 393-400) jadi scope-agnostic**

```ts
      if (!cartMatchesVoucherScope(voucher, cartProductInputs)) {
        throw new VoucherValidationError(
          "Voucher tidak berlaku untuk produk ini",
        );
      }
```

(Menggantikan blok `if (voucherScopeOf(voucher) === "PRODUCT" && eligibleProductSubtotal(voucher) <= 0) { ... }`. Satu gate ini menutup semua slot: free-shipping, product, loyalty, private.)

- [ ] **Step 6: Typecheck**

Run: `npx tsc --noEmit`
Expected: no type errors (exit 0).

- [ ] **Step 7: Commit**

```bash
git add app/api/orders/route.ts
git commit -m "fix(orders): gate scope voucher untuk semua discountScope + categorySlug (tutup kebocoran ongkir brand)"
```

---

## Task 4: `recalculate.ts` — 2 gate (member + manual) + categorySlug

**Files:**
- Modify: `app/api/checkout/recalculate/route.ts:19-23` (import), `:258-290` (product select), `:310` (setelah `productById`), `:389-403` (`eligibleProductSubtotal`), `:442` (gate member loop), `:554-558` (gate manual branch)

**Interfaces:**
- Consumes: `cartMatchesVoucherScope` (Task 1).

- [ ] **Step 1: Tambah `categorySlug` ke product select**

Di `prisma.product.findMany` select (blok baris 258-290), tambahkan setelah `categoryId: true,` / `brandId: true,`:

```ts
        category: { select: { slug: true } },
```

- [ ] **Step 2: Import helper**

Ganti blok import `@/lib/voucher-eligibility` (baris 19-23):

```ts
import {
  cartMatchesVoucherScope,
  voucherMatchesProduct,
  loadBrandNamesByIds,
  formatVoucherBrandName,
} from "@/lib/voucher-eligibility";
```

- [ ] **Step 3: Bangun `cartProductInputs`**

Tepat setelah `const productById = new Map(...)` (baris 310), tambahkan:

```ts
  const cartProductInputs = checkoutItems.map((item) => {
    const product = productById.get(item.productId);
    return {
      id: item.productId,
      categoryId: product?.categoryId ?? null,
      categorySlug: product?.category?.slug ?? null,
      brandId: product?.brandId ?? null,
    };
  });
```

- [ ] **Step 4: Teruskan `categorySlug` di `eligibleProductSubtotal`**

Di fungsi `eligibleProductSubtotal` (baris 389-403), objek ke `voucherMatchesProduct`, tambahkan `categorySlug`:

```ts
      const matches = voucherMatchesProduct(voucher, {
        id: item.productId,
        categoryId: product?.categoryId ?? null,
        categorySlug: product?.category?.slug ?? null,
        brandId: product?.brandId ?? null,
      });
```

- [ ] **Step 5: Ganti gate member loop (baris 442)**

```ts
    if (!cartMatchesVoucherScope(voucher, cartProductInputs)) {
      unavailable.push(
        normalizeUnavailable(voucher, "Voucher tidak berlaku untuk produk di keranjang", 0, brandNamesById),
      );
      continue;
    }
```

(Menggantikan blok `if (voucherScopeOf(voucher) === "PRODUCT" && eligibleProductSubtotal(voucher) <= 0) { ... }`. Cek `scope === "SHIPPING" && shippingFee <= 0` di atasnya TETAP.)

- [ ] **Step 6: Ganti gate cabang manual (baris 554-558)**

```ts
    } else if (!cartMatchesVoucherScope(manualVoucher, cartProductInputs)) {
      manualVoucherError = "Voucher tidak berlaku untuk produk di keranjang";
    } else {
```

(Menggantikan cabang `else if (voucherScopeOf(manualVoucher) === "PRODUCT" && eligibleProductSubtotal(manualVoucher) <= 0) { manualVoucherError = "Voucher tidak berlaku untuk produk ini"; } else {`.)

- [ ] **Step 7: Typecheck**

Run: `npx tsc --noEmit`
Expected: no type errors (exit 0).

- [ ] **Step 8: Commit**

```bash
git add app/api/checkout/recalculate/route.ts
git commit -m "fix(recalculate): gate scope 2 jalur (member+manual) untuk semua discountScope + categorySlug"
```

---

## Task 5: `vouchers/validate` (public) — terima `productIds` + gate

**Files:**
- Modify: `app/api/vouchers/validate/route.ts`

**Interfaces:**
- Consumes: `cartMatchesVoucherScope`, `voucherHasScope`, `EligibilityProductInput` (Task 1).

- [ ] **Step 1: Import helper**

Ganti blok import di atas file:

```ts
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  cartMatchesVoucherScope,
  voucherHasScope,
  type EligibilityProductInput,
} from "@/lib/voucher-eligibility";
```

- [ ] **Step 2: Terima `productIds` dari body**

Ganti baris 5:

```ts
  const { code, subtotal, productIds } = await request.json();
```

- [ ] **Step 3: Gate scope (setelah cek minimumOrder, sebelum hitung discount)**

Tepat setelah blok `if (subtotal < voucher.minimumOrder) { ... }` (baris 34-39) dan sebelum `let discount = 0;` (baris 41), sisipkan:

```ts
  // Scope gate: kalau client kirim productIds dan voucher di-scope ke
  // brand/kategori/produk, tolak kalau tidak ada produk keranjang yang cocok.
  // Backward-compat: productIds tidak dikirim -> skip (permisif).
  if (Array.isArray(productIds) && voucherHasScope(voucher)) {
    const ids = (productIds as unknown[])
      .map((id) => String(id).trim())
      .filter(Boolean);
    const products = ids.length
      ? await prisma.product.findMany({
          where: { id: { in: ids } },
          select: {
            id: true,
            categoryId: true,
            brandId: true,
            category: { select: { slug: true } },
          },
        })
      : [];
    const cartProducts: EligibilityProductInput[] = products.map((p) => ({
      id: p.id,
      categoryId: p.categoryId ?? null,
      categorySlug: p.category?.slug ?? null,
      brandId: p.brandId ?? null,
    }));
    if (!cartMatchesVoucherScope(voucher, cartProducts)) {
      return NextResponse.json({
        valid: false,
        error: "Voucher tidak berlaku untuk produk di keranjang",
      });
    }
  }
```

- [ ] **Step 4: Typecheck**

Run: `npx tsc --noEmit`
Expected: no type errors (exit 0).

- [ ] **Step 5: Commit**

```bash
git add app/api/vouchers/validate/route.ts
git commit -m "fix(vouchers/validate): gate scope keranjang saat productIds dikirim"
```

---

## Task 6: `validate-private` — terima `productIds` + gate

**Files:**
- Modify: `app/api/cart/vouchers/validate-private/route.ts:16-25` (import + schema), `:124-129` (setelah minimumOrder)

**Interfaces:**
- Consumes: `cartMatchesVoucherScope`, `voucherHasScope`, `EligibilityProductInput` (Task 1).

- [ ] **Step 1: Import helper + tambah `productIds` ke schema**

Tambahkan import (setelah import `voucher-helpers`, baris 16-20):

```ts
import {
  cartMatchesVoucherScope,
  voucherHasScope,
  type EligibilityProductInput,
} from "@/lib/voucher-eligibility";
```

Ganti `bodySchema` (baris 22-25):

```ts
const bodySchema = z.object({
  code: z.string().trim().min(1),
  subtotal: z.number().int().nonnegative(),
  productIds: z.array(z.string()).optional(),
});
```

- [ ] **Step 2: Gate scope (setelah cek minimumOrder, sebelum hitung discount)**

Tepat setelah blok `if (subtotal < voucher.minimumOrder) { ... }` (baris 124-129) dan sebelum `const discount = calcVoucherDiscount(...)` (baris 131), sisipkan:

```ts
  if (parsed.data.productIds && voucherHasScope(voucher)) {
    const ids = parsed.data.productIds.map((id) => id.trim()).filter(Boolean);
    const products = ids.length
      ? await prisma.product.findMany({
          where: { id: { in: ids } },
          select: {
            id: true,
            categoryId: true,
            brandId: true,
            category: { select: { slug: true } },
          },
        })
      : [];
    const cartProducts: EligibilityProductInput[] = products.map((p) => ({
      id: p.id,
      categoryId: p.categoryId ?? null,
      categorySlug: p.category?.slug ?? null,
      brandId: p.brandId ?? null,
    }));
    if (!cartMatchesVoucherScope(voucher, cartProducts)) {
      return NextResponse.json({
        ok: false,
        message: "Voucher tidak berlaku untuk produk di keranjang",
      });
    }
  }
```

- [ ] **Step 3: Typecheck**

Run: `npx tsc --noEmit`
Expected: no type errors (exit 0).

- [ ] **Step 4: Commit**

```bash
git add app/api/cart/vouchers/validate-private/route.ts
git commit -m "fix(validate-private): gate scope keranjang saat productIds dikirim"
```

---

## Task 7: Flutter service — param opsional `productIds` (aditif)

**Files:**
- Modify: `flutter_app/lib/services/voucher_service.dart:55-73`
- Modify: `flutter_app/lib/services/cart_service.dart:120-128`

**Interfaces:**
- Produces: `validate({..., List<String>? productIds})`, `validatePrivateVoucher({..., List<String>? productIds})` — param aditif, backward-compatible (tak ada pemanggil aktif saat ini).

- [ ] **Step 1: `voucher_service.dart` — tambah param + body**

Ganti signature `validate` (baris 55-58) dan body-nya (baris 67-73):

```dart
  Future<VoucherValidationResult> validate({
    required String code,
    int? subtotal,
    List<String>? productIds,
  }) async {
```

```dart
      final data = await apiClient.postJson(
        '/api/vouchers/validate',
        body: {
          'code': code.trim(),
          if (subtotal != null) 'subtotal': subtotal,
          if (productIds != null && productIds.isNotEmpty)
            'productIds': productIds,
        },
      );
```

- [ ] **Step 2: `cart_service.dart` — tambah param + body**

Ganti signature `validatePrivateVoucher` (baris 120-123) dan body-nya (baris 125-128):

```dart
  Future<CartPrivateVoucherResult> validatePrivateVoucher({
    required String code,
    required int subtotal,
    List<String>? productIds,
  }) async {
```

```dart
      final data = await apiClient.postJson(
        '/api/cart/vouchers/validate-private',
        body: {
          'code': code.trim(),
          'subtotal': subtotal,
          if (productIds != null && productIds.isNotEmpty)
            'productIds': productIds,
        },
      );
```

- [ ] **Step 3: Analyze**

Run: `cd flutter_app && flutter analyze`
Expected: "No issues found!" (atau tidak ada issue BARU pada 2 file ini).

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/services/voucher_service.dart flutter_app/lib/services/cart_service.dart
git commit -m "feat(flutter): param opsional productIds di validate/validatePrivateVoucher (dormant-safe)"
```

---

## Task 8: Parity listing web — kirim `productIds` ke `GET /api/cart/vouchers`

**Files:**
- Modify: `components/cart/CartVoucherSheet.tsx:40-57` (Props), `:162` (fetch), `:174` (deps)
- Modify: `app/cart/page.tsx` — derive `selectedProductIds`, fetch page-level (`:441`), prop ke `<CartVoucherSheet>` (`:1046-1073`)

**Interfaces:**
- `CartVoucherSheet` menerima prop baru `productIds: string[]`.

- [ ] **Step 1: `CartVoucherSheet.tsx` — tambah prop `productIds`**

Di `type Props` (baris 40-57), tambahkan setelah `subtotal: number;`:

```ts
  /** Id produk terpilih di cart — untuk gate voucher scoped (brand/kategori) */
  productIds: string[];
```

Tambahkan `productIds` ke destructuring parameter (baris 59-67), setelah `subtotal,`:

```ts
  productIds,
```

- [ ] **Step 2: `CartVoucherSheet.tsx` — sertakan productIds di fetch + deps**

Ganti isi `useEffect` fetch (baris 162) menjadi menyertakan `productIds`, dan tambahkan ke dependency array (baris 174). Ganti baris 162:

```ts
    fetch(
      `/api/cart/vouchers?subtotal=${subtotal}&productIds=${encodeURIComponent(productIds.join(","))}`,
    )
```

Ganti dependency array `useEffect` (baris 174) dari `[open, isLoggedIn, subtotal]` menjadi:

```ts
  }, [open, isLoggedIn, subtotal, productIds]);
```

- [ ] **Step 3: `app/cart/page.tsx` — derive `selectedProductIds`**

Tepat setelah `const selectedSubtotal = ...` (baris 400), tambahkan:

```ts
  const selectedProductIds = useMemo(
    () => Array.from(new Set(selectedItems.map((item) => item.productId))),
    [selectedItems],
  );
```

- [ ] **Step 4: `app/cart/page.tsx` — page-level fetch sertakan productIds**

Ganti fetch di baris 441:

```ts
    fetch(
      `/api/cart/vouchers?subtotal=${selectedSubtotal}&productIds=${encodeURIComponent(selectedProductIds.join(","))}`,
    )
```

Pada `useEffect` yang sama (blok dimulai baris 430), tambahkan `selectedProductIds` ke dependency array-nya — array itu memuat entri `selectedSubtotal,` (sekitar baris 512). Tambahkan `selectedProductIds,` sebagai entri baru; JANGAN hapus entri lain yang sudah ada.

- [ ] **Step 5: `app/cart/page.tsx` — teruskan prop ke `<CartVoucherSheet>`**

Di elemen `<CartVoucherSheet>` (baris 1046), tambahkan prop setelah `subtotal={selectedSubtotal}` (baris 1050):

```tsx
        productIds={selectedProductIds}
```

- [ ] **Step 6: Typecheck**

Run: `npx tsc --noEmit`
Expected: no type errors (exit 0).

- [ ] **Step 7: Commit**

```bash
git add components/cart/CartVoucherSheet.tsx app/cart/page.tsx
git commit -m "fix(cart-web): kirim productIds ke listing voucher (parity gate scope dgn Flutter)"
```

---

## Task 9: Verifikasi menyeluruh

**Files:** (tidak ada perubahan file — gate akhir)

- [ ] **Step 1: Semua unit test hijau**

Run: `npm test`
Expected: PASS semua (`tests/*.test.ts`), termasuk test scope Task 1 & 2.

- [ ] **Step 2: Typecheck penuh**

Run: `npx tsc --noEmit`
Expected: no type errors (exit 0).

- [ ] **Step 3: Lint (tangkap import tak terpakai, mis. `voucherMatchesProduct` di voucher-list)**

Run: `npm run lint`
Expected: no error pada file yang disentuh. Kalau ada "unused import" di `lib/voucher-list.ts`, hapus import yang tak lagi dipakai lalu commit ulang.

- [ ] **Step 4: Flutter analyze**

Run: `cd flutter_app && flutter analyze`
Expected: no issue baru pada `voucher_service.dart` / `cart_service.dart`.

- [ ] **Step 5: Commit (kalau ada perbaikan lint)**

```bash
git add -A
git commit -m "chore(voucher): bersihkan import + verifikasi menyeluruh"
```

---

## Catatan eksekusi

- **Urutan wajib:** Task 1 dulu (helper) sebelum Task 2-8 (semua konsumen).
- **Charging vs preview:** Task 3-4 menutup kebocoran uang (paling kritikal). Task 5-8 defense-in-depth / display parity (endpoint validate saat ini dormant; lihat spec §3.5).
- **Manual verify opsional** (butuh DB + voucher `FREEOKSHPI` brand HPI): keranjang tanpa produk HPI → recalculate menandai voucher unavailable, dan submit order dgn `freeShippingVoucherCode=FREEOKSHPI` → 400 "Voucher tidak berlaku untuk produk ini". Dengan produk HPI di keranjang → tetap ter-apply normal.
