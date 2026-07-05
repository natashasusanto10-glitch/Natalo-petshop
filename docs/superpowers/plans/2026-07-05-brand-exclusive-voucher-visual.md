# Brand Exclusive Voucher — Visual + Cart Availability Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a distinct amber "Khusus {brand}" treatment for brand-scoped vouchers everywhere a voucher appears (product detail, Voucher Saya, cart picker, checkout), and fix a real bug where `/api/cart/vouchers` marks brand-scoped vouchers as "available" even when the cart has no matching product.

**Architecture:** Backend resolves brand names for scoped vouchers via a small shared helper (`lib/voucher-eligibility.ts`) and threads a boolean/name through the three existing voucher-serving endpoints. The cart-availability bug is fixed by teaching `buildVoucherListItems` to optionally accept the cart's product list and gate `applicable` on `voucherMatchesProduct`. On the Flutter side, two existing models (`ProductVoucherPreview`, `MemberVoucher`) get one new `brandName` field + `isBrandExclusive` getter, and four screens get a small amber branch added to their *existing* color/label/icon logic — no new widgets, no new voucher type.

**Tech Stack:** Next.js 16 API routes, Prisma 6.19/Postgres, `tsx --test` for backend unit tests, Flutter/Dart for the customer app.

## Global Constraints

- Colors (exact hex, from approved mockup): fill `#F7A100`, soft background `#FEF0DC`, soft border `#FCD9A0`, dark text/icon tone `#B85C00`.
- Badge/label copy: `"Khusus {brandName}"` for chips/pills/type-labels, `"KHUSUS BRAND"` (uppercase, letter-spacing) only for the dedicated sheet-card badge in product detail, `"Berlaku untuk {brandName}"` for subtitle clauses.
- No new voucher type/enum. "Brand exclusive" is derived purely from `eligibleBrandIds.length > 0` on the existing `PUBLIC_PRODUCT_DISCOUNT` voucher type.
- Reuse `voucherMatchesProduct` from `lib/voucher-eligibility.ts` for all scope-matching — never re-implement the match logic inline.
- Multi-brand display format: 1 brand → its name; 2+ brands → `"{first} & N brand lain"`.
- The `/api/cart/vouchers` `productIds` query param is additive/optional — when absent, behavior is unchanged (old app builds still work during rollout).
- All new user-facing strings are Indonesian, matching existing tone in each file.
- Every backend step that changes `lib/voucher-list.ts` must keep `tests/voucher-list.test.ts` passing.

---

### Task 0: Fix pre-existing broken test fixture (prerequisite)

**Context:** `tests/voucher-list.test.ts`'s `voucher()` fixture never sets `eligibleBrandIds`, but production code at `lib/voucher-list.ts:227` already reads `v.eligibleBrandIds.length` unconditionally (added in an earlier session). Right now 4 of the file's tests crash with `TypeError: Cannot read properties of undefined (reading 'length')`. This must be fixed before Task 1 touches this file further, otherwise new tests get added on top of a broken baseline.

**Files:**
- Modify: `tests/voucher-list.test.ts:21-55` (the `voucher()` fixture function)

**Interfaces:**
- Produces: a working `voucher()` test fixture that all later tasks' new tests can call unchanged.

- [ ] **Step 1: Confirm the failure baseline**

Run: `cd "C:\Users\USER\Desktop\natalopetshopflutter" && npx tsx --test tests/voucher-list.test.ts`
Expected: 4 failing tests, all with `TypeError: Cannot read properties of undefined (reading 'length') at buildVoucherListItems (lib/voucher-list.ts:228:26)`.

- [ ] **Step 2: Add the missing default field to the fixture**

In `tests/voucher-list.test.ts`, find this block (around line 48-53):

```ts
    eligibleUserIds: [],
    eligibleProductIds: [],
    eligibleCategoryIds: [],
    createdAt: new Date("2026-01-01T00:00:00Z"),
    updatedAt: new Date("2026-01-01T00:00:00Z"),
```

Replace with:

```ts
    eligibleUserIds: [],
    eligibleProductIds: [],
    eligibleCategoryIds: [],
    eligibleBrandIds: [],
    createdAt: new Date("2026-01-01T00:00:00Z"),
    updatedAt: new Date("2026-01-01T00:00:00Z"),
```

- [ ] **Step 3: Run tests to verify all pass now**

Run: `npx tsx --test tests/voucher-list.test.ts`
Expected: all tests pass (0 failures). The suite has no assertions on `eligibleBrandIds` yet, so this step only fixes the crash — no behavior changes.

- [ ] **Step 4: Commit**

```bash
git add tests/voucher-list.test.ts
git commit -m "fix(test): tambah eligibleBrandIds default di voucher-list fixture

Fixture voucher() tidak pernah set eligibleBrandIds walau
buildVoucherListItems sudah baca field ini sejak fitur target-brand
ditambahkan -- 4 test crash TypeError undefined.length. Prasyarat
sebelum menambah test baru di file yang sama."
```

---

### Task 1: Shared brand-name resolution helper

**Files:**
- Modify: `lib/voucher-eligibility.ts`
- Test: `tests/voucher-eligibility.test.ts` (new)

**Interfaces:**
- Produces: `formatVoucherBrandName(eligibleBrandIds: string[], brandNamesById: Map<string, string>): string | null` (pure, unit-tested) and `loadBrandNamesByIds(brandIds: string[]): Promise<Map<string, string>>` (thin Prisma wrapper, used by later tasks, not unit-tested — matches this codebase's existing convention of only unit-testing the pure extracted function, e.g. `buildVoucherListItems` vs `listUserVouchers`).
- Consumes: nothing new — `prisma` from `@/lib/prisma`.

- [ ] **Step 1: Write the failing test for the pure formatter**

Create `tests/voucher-eligibility.test.ts`:

```ts
/**
 * Tests untuk `formatVoucherBrandName` -- pure function yang format nama
 * brand voucher jadi label display ("Khusus {brand}" / "{brand} & N brand
 * lain"). `loadBrandNamesByIds` tidak di-test di sini karena cuma thin
 * Prisma wrapper (pola sama dengan buildVoucherListItems vs
 * listUserVouchers di lib/voucher-list.ts).
 */
import assert from "node:assert/strict";
import test from "node:test";
import { formatVoucherBrandName } from "@/lib/voucher-eligibility";

test("formatVoucherBrandName: eligibleBrandIds kosong -> null", () => {
  const result = formatVoucherBrandName([], new Map());
  assert.equal(result, null);
});

test("formatVoucherBrandName: 1 brand -> nama brand apa adanya", () => {
  const brandNamesById = new Map([["brand-1", "Wolly+"]]);
  const result = formatVoucherBrandName(["brand-1"], brandNamesById);
  assert.equal(result, "Wolly+");
});

test("formatVoucherBrandName: 2 brand -> '{pertama} & 1 brand lain'", () => {
  const brandNamesById = new Map([
    ["brand-1", "Wolly+"],
    ["brand-2", "Happy Dog"],
  ]);
  const result = formatVoucherBrandName(["brand-1", "brand-2"], brandNamesById);
  assert.equal(result, "Wolly+ & 1 brand lain");
});

test("formatVoucherBrandName: 3 brand -> '{pertama} & 2 brand lain'", () => {
  const brandNamesById = new Map([
    ["brand-1", "Wolly+"],
    ["brand-2", "Happy Dog"],
    ["brand-3", "Royal Canin"],
  ]);
  const result = formatVoucherBrandName(
    ["brand-1", "brand-2", "brand-3"],
    brandNamesById,
  );
  assert.equal(result, "Wolly+ & 2 brand lain");
});

test("formatVoucherBrandName: brandId tidak ketemu di map -> di-skip, bukan crash", () => {
  const brandNamesById = new Map([["brand-1", "Wolly+"]]);
  // brand-2 dihapus/tidak aktif tapi masih nyantol di eligibleBrandIds lama.
  const result = formatVoucherBrandName(["brand-1", "brand-2"], brandNamesById);
  assert.equal(result, "Wolly+");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx --test tests/voucher-eligibility.test.ts`
Expected: FAIL — `formatVoucherBrandName is not a function` (not exported yet).

- [ ] **Step 3: Implement `formatVoucherBrandName` and `loadBrandNamesByIds`**

In `lib/voucher-eligibility.ts`, add `prisma` import at the top and append both functions at the end of the file:

```ts
import { prisma } from "@/lib/prisma";
```

Append to the end of the file:

```ts
/**
 * Batch-resolve brand id -> nama, untuk display voucher scoped ke brand
 * (mis. "Khusus Wolly+"). Dipakai oleh lib/voucher-list.ts dan
 * app/api/checkout/recalculate/route.ts -- satu tempat supaya query batch
 * (bukan N+1 per voucher) konsisten di semua caller.
 */
export async function loadBrandNamesByIds(
  brandIds: string[]
): Promise<Map<string, string>> {
  const uniqueIds = Array.from(new Set(brandIds));
  if (uniqueIds.length === 0) return new Map();
  const brands = await prisma.brand.findMany({
    where: { id: { in: uniqueIds } },
    select: { id: true, name: true },
  });
  return new Map(brands.map((b) => [b.id, b.name]));
}

/**
 * Format label display dari eligibleBrandIds voucher. null kalau voucher
 * tidak scoped ke brand manapun (termasuk kalau semua id-nya sudah tidak
 * ketemu lagi di brandNamesById, mis. brand dihapus).
 */
export function formatVoucherBrandName(
  eligibleBrandIds: string[],
  brandNamesById: Map<string, string>
): string | null {
  const names = eligibleBrandIds
    .map((id) => brandNamesById.get(id))
    .filter((name): name is string => Boolean(name));
  if (names.length === 0) return null;
  if (names.length === 1) return names[0];
  return `${names[0]} & ${names.length - 1} brand lain`;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx tsx --test tests/voucher-eligibility.test.ts`
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/voucher-eligibility.ts tests/voucher-eligibility.test.ts
git commit -m "feat(voucher): helper resolve + format nama brand untuk display

loadBrandNamesByIds (batch Prisma lookup) + formatVoucherBrandName
(pure formatter, 1 brand vs N brand lain) -- satu sumber kebenaran
dipakai oleh endpoint cart/vouchers, product vouchers, dan checkout
recalculate supaya tidak duplicate logic 3x."
```

---

### Task 2: Fix cart voucher availability bug + add brandName to `/api/cart/vouchers`

**Context:** `buildVoucherListItems` currently computes `applicable` purely from subtotal — it never checks whether the cart actually contains a product matching `eligibleProductIds`/`eligibleCategoryIds`/`eligibleBrandIds`. This is the bug: a Happy Dog voucher shows as "available" in the cart picker even when the cart has zero Happy Dog products.

**Files:**
- Modify: `lib/voucher-list.ts`
- Test: `tests/voucher-list.test.ts`

**Interfaces:**
- Consumes: `voucherMatchesProduct`, `formatVoucherBrandName`, `loadBrandNamesByIds`, `EligibilityProductInput` from `@/lib/voucher-eligibility` (Task 1).
- Produces: `VoucherListItem.brandName: string | null`; `buildVoucherListItems(input: {..., cartProducts?: EligibilityProductInput[], brandNamesById?: Map<string, string>})`; `listUserVouchers(params: {..., cartProducts?: EligibilityProductInput[]})`. Both new params are optional so existing callers (none yet, this is the only caller today) are unaffected. `cartProducts` semantics: `undefined` = "caller doesn't know cart contents, skip scope gate" (permissive/old behavior); an array (including `[]`) = "this is exactly what's in the cart, gate scoped vouchers against it."

- [ ] **Step 1: Write failing tests for the availability bug fix and brandName**

Append to `tests/voucher-list.test.ts` (before the final closing of the file, after the last existing test):

```ts
// ─── cartProducts scope gate (bug fix) ───────────────────────────────

test("voucher brand-scoped + cartProducts TIDAK ada brand yang cocok -> unavailable", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-happydog",
        code: "HAPPYDOG15",
        eligibleBrandIds: ["brand-happydog"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [
      { id: "prod-1", categoryId: null, categorySlug: null, brandId: "brand-wollyplus" },
    ],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, false);
  assert.ok(
    items[0].disabledReason?.includes("tidak berlaku"),
    `expected scope-mismatch reason, got: ${items[0].disabledReason}`,
  );
});

test("voucher brand-scoped + cartProducts ADA brand yang cocok -> applicable", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-happydog",
        code: "HAPPYDOG15",
        eligibleBrandIds: ["brand-happydog"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [
      { id: "prod-1", categoryId: null, categorySlug: null, brandId: "brand-happydog" },
    ],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true);
});

test("voucher brand-scoped + cartProducts TIDAK diberikan (undefined) -> permissive, tetap applicable (backward-compat)", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-happydog",
        code: "HAPPYDOG15",
        eligibleBrandIds: ["brand-happydog"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    // cartProducts sengaja tidak di-pass -- simulasi app lama yang belum
    // update, endpoint tidak boleh regress jadi mengunci voucher yang
    // sebelumnya applicable.
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true);
});

test("voucher tanpa scope apapun + cartProducts kosong -> tetap applicable (bukan false-positive)", () => {
  const items = buildVoucherListItems({
    vouchers: [voucher({ id: "v-all", code: "ALL10" })],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].applicable, true);
});

// ─── brandName field ──────────────────────────────────────────────────

test("voucher dengan eligibleBrandIds + brandNamesById -> brandName terisi", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({ id: "v-b", code: "B15", eligibleBrandIds: ["brand-1"] }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    brandNamesById: new Map([["brand-1", "Wolly+"]]),
  });
  assert.equal(items[0].brandName, "Wolly+");
});

test("voucher tanpa eligibleBrandIds -> brandName null", () => {
  const items = buildVoucherListItems({
    vouchers: [voucher({ id: "v-noscope", code: "NOSCOPE" })],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
  });
  assert.equal(items[0].brandName, null);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx tsx --test tests/voucher-list.test.ts`
Expected: FAIL — `cartProducts`/`brandNamesById` don't exist yet on the type, `items[0].brandName` is `undefined` not matching assertions (TS will also complain if you typecheck, but `tsx` runs untyped at test time — the assertion failures are what matter here).

- [ ] **Step 3: Implement the scope gate + brandName in `buildVoucherListItems`**

In `lib/voucher-list.ts`, add the import at the top (after the existing `voucher-kind` import):

```ts
import {
  voucherMatchesProduct,
  formatVoucherBrandName,
  loadBrandNamesByIds,
  type EligibilityProductInput,
} from "@/lib/voucher-eligibility";
```

Add `brandName` to the `VoucherListItem` type (after `hasProductScope`):

```ts
  hasProductScope: boolean;
  /** Nama brand untuk display ("Khusus {brand}") -- null kalau voucher tidak scoped ke brand manapun. */
  brandName: string | null;
```

Replace the `buildVoucherListItems` signature and body's filter/transform loop. Change the function signature from:

```ts
export function buildVoucherListItems(input: {
  vouchers: Voucher[];
  userUsedOrders: VoucherUsageOrder[];
  userCtx: VoucherUserContext;
  subtotal: number;
  now: Date;
}): VoucherListItem[] {
  const { vouchers, userUsedOrders, userCtx, subtotal, now } = input;
```

to:

```ts
export function buildVoucherListItems(input: {
  vouchers: Voucher[];
  userUsedOrders: VoucherUsageOrder[];
  userCtx: VoucherUserContext;
  subtotal: number;
  now: Date;
  /** undefined = cart contents unknown, skip scope gate (backward-compat). Array (incl. []) = exact cart contents, gate scoped vouchers against it. */
  cartProducts?: EligibilityProductInput[];
  brandNamesById?: Map<string, string>;
}): VoucherListItem[] {
  const { vouchers, userUsedOrders, userCtx, subtotal, now, cartProducts, brandNamesById = new Map() } = input;
```

Inside the `for (const v of vouchers)` loop, replace:

```ts
    // Transient disabled state: belum mulai / NEW_MEMBER mismatch /
    // subtotal kurang. Voucher tetap tampil dengan reason.
    const disabledReason = getVoucherDisabledReason(v, subtotal, userCtx, now);
    const discount = disabledReason ? 0 : calcVoucherDiscount(subtotal, v);
    const isFreeShipping = isFreeShippingVoucher(v);
    // Free shipping voucher: applicable bahkan kalau discount=0 (karena
    // discount-nya di shipping fee, dihitung di checkout/recalculate
    // bukan di sini — listing tidak tau shipping fee).
    const applicable =
      disabledReason === null && (discount > 0 || isFreeShipping);

    const hasProductScope =
      v.eligibleProductIds.length > 0 ||
      v.eligibleCategoryIds.length > 0 ||
      v.eligibleBrandIds.length > 0;
```

with:

```ts
    const hasProductScope =
      v.eligibleProductIds.length > 0 ||
      v.eligibleCategoryIds.length > 0 ||
      v.eligibleBrandIds.length > 0;

    // Bug fix: voucher scoped ke produk/kategori/brand tertentu HARUS
    // dicek terhadap isi cart yang sesungguhnya -- sebelumnya listing ini
    // cuma hitung dari subtotal, jadi voucher "Khusus Happy Dog" muncul
    // "available" walau keranjang tidak ada produk Happy Dog sama sekali,
    // baru gagal saat checkout/recalculate (yang sudah benar). cartProducts
    // undefined (caller belum kirim, mis. app lama) tetap permissive supaya
    // tidak regress voucher yang sebelumnya applicable.
    const scopeUnmatched =
      hasProductScope &&
      cartProducts !== undefined &&
      !cartProducts.some((p) => voucherMatchesProduct(v, p));

    // Transient disabled state: belum mulai / NEW_MEMBER mismatch /
    // subtotal kurang / scope tidak cocok dengan isi cart. Voucher tetap
    // tampil dengan reason.
    const disabledReason =
      getVoucherDisabledReason(v, subtotal, userCtx, now) ??
      (scopeUnmatched ? "Voucher tidak berlaku untuk produk di keranjang" : null);
    const discount = disabledReason ? 0 : calcVoucherDiscount(subtotal, v);
    const isFreeShipping = isFreeShippingVoucher(v);
    // Free shipping voucher: applicable bahkan kalau discount=0 (karena
    // discount-nya di shipping fee, dihitung di checkout/recalculate
    // bukan di sini — listing tidak tau shipping fee).
    const applicable =
      disabledReason === null && (discount > 0 || isFreeShipping);

    const brandName = formatVoucherBrandName(v.eligibleBrandIds, brandNamesById);
```

Then in the `items.push({...})` call, add `brandName,` after `hasProductScope,`:

```ts
      hasProductScope,
      brandName,
    });
```

- [ ] **Step 4: Thread `cartProducts` through `listUserVouchers`**

In `lib/voucher-list.ts`, update `ListUserVouchersParams` type (add after `subtotal`):

```ts
export type ListUserVouchersParams = {
  /** Required — voucher Natalo wajib login. */
  userId: string;
  /** Cart subtotal saat ini. 0 untuk halaman member voucher tanpa cart context. */
  subtotal: number;
  /** Product di cart untuk scope-gate voucher brand/kategori/produk. undefined = skip gate (lihat buildVoucherListItems). */
  cartProducts?: EligibilityProductInput[];
  /** Override untuk testing. Default new Date(). */
  now?: Date;
};
```

Update `listUserVouchers` to resolve brand names and pass both through. Replace:

```ts
export async function listUserVouchers(
  params: ListUserVouchersParams,
): Promise<ListUserVouchersResult> {
  const { userId, subtotal } = params;
  const now = params.now ?? new Date();
```

with:

```ts
export async function listUserVouchers(
  params: ListUserVouchersParams,
): Promise<ListUserVouchersResult> {
  const { userId, subtotal, cartProducts } = params;
  const now = params.now ?? new Date();
```

Then, right after the `Promise.all([...])` block that fetches `vouchers, userUsedOrders, user, successfulOrderCount` (before `const userCtx = {...}`), add:

```ts
  const allBrandIds = vouchers.flatMap((v) => v.eligibleBrandIds);
  const brandNamesById = await loadBrandNamesByIds(allBrandIds);
```

Finally, update the `buildVoucherListItems` call at the end of `listUserVouchers` to pass both new fields:

```ts
  return {
    items: buildVoucherListItems({
      vouchers,
      userUsedOrders,
      userCtx,
      subtotal,
      now,
      cartProducts,
      brandNamesById,
    }),
  };
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `npx tsx --test tests/voucher-list.test.ts`
Expected: all tests pass (the 10 pre-existing tests + 6 new ones from Step 1 = 16 total).

- [ ] **Step 6: Commit**

```bash
git add lib/voucher-list.ts tests/voucher-list.test.ts
git commit -m "fix(voucher): cart picker cek isi cart untuk voucher scoped brand/kategori/produk

buildVoucherListItems sebelumnya hitung applicable murni dari subtotal
-- voucher scoped (mis. Khusus Happy Dog) muncul 'available' di cart
picker walau keranjang tidak ada produk yang cocok, baru gagal saat
checkout/recalculate. Tambah param opsional cartProducts (undefined =
permissive/backward-compat untuk app lama) yang gate applicable lewat
voucherMatchesProduct yang sudah ada. Sekalian tambah field brandName
untuk display 'Khusus {brand}' di UI."
```

---

### Task 3: Wire `productIds` into `/api/cart/vouchers`

**Files:**
- Modify: `app/api/cart/vouchers/route.ts`

**Interfaces:**
- Consumes: `listUserVouchers` (Task 2, now accepts `cartProducts`), `EligibilityProductInput` type from `@/lib/voucher-eligibility`, `prisma` from `@/lib/prisma`.
- Produces: `GET /api/cart/vouchers?subtotal=N&productIds=id1,id2` — `productIds` optional; absent param → old permissive behavior, present (even empty string) → strict scope gate.

- [ ] **Step 1: Update the route handler**

Replace the full contents of `app/api/cart/vouchers/route.ts` with:

```ts
/**
 * GET /api/cart/vouchers?subtotal=N&productIds=id1,id2,id3
 *
 * Return daftar voucher member Natalo (sourceType=CUSTOMER) untuk user
 * login + cart subtotal saat ini.
 *
 * `productIds` (opsional, comma-separated): id produk yang ADA di cart
 * saat ini. Kalau diberikan (termasuk string kosong = cart kosong),
 * voucher yang scoped ke produk/kategori/brand tertentu di-gate
 * `applicable=false` kalau tidak ada satupun productIds yang cocok --
 * lihat lib/voucher-list.ts untuk detail bug yang diperbaiki param ini.
 * Kalau parameter ini TIDAK dikirim sama sekali (app lama yang belum
 * update), behavior lama tetap jalan (permissive, tidak gate scope).
 *
 * Logic visibility ada di `lib/voucher-list.ts` (single source of truth).
 *
 * Response shape:
 *   { available: VoucherListItem[], unavailable: VoucherListItem[] }
 *
 * Guest dapat 401 — tidak boleh lihat voucher member.
 *
 * SELLER_MANUAL voucher TIDAK pernah muncul di endpoint ini (rahasia,
 * harus di-validate via /api/cart/vouchers/validate-private).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { listUserVouchers } from "@/lib/voucher-list";
import { prisma } from "@/lib/prisma";
import type { EligibilityProductInput } from "@/lib/voucher-eligibility";

export async function GET(request: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json(
      {
        error: "LOGIN_REQUIRED",
        message: "Login dulu untuk melihat voucher member.",
      },
      { status: 401 },
    );
  }

  const subtotalRaw = request.nextUrl.searchParams.get("subtotal");
  const subtotal = Math.max(0, parseInt(subtotalRaw ?? "0", 10) || 0);

  const productIdsRaw = request.nextUrl.searchParams.get("productIds");
  let cartProducts: EligibilityProductInput[] | undefined;
  if (productIdsRaw !== null) {
    const ids = productIdsRaw
      .split(",")
      .map((id) => id.trim())
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
    cartProducts = products.map((p) => ({
      id: p.id,
      categoryId: p.categoryId ?? null,
      categorySlug: p.category?.slug ?? null,
      brandId: p.brandId ?? null,
    }));
  }

  const { items } = await listUserVouchers({
    userId: session.sub,
    subtotal,
    cartProducts,
  });

  return NextResponse.json({
    available: items.filter((it) => it.applicable),
    unavailable: items.filter((it) => !it.applicable),
  });
}
```

- [ ] **Step 2: Typecheck**

Run: `npx tsc --noEmit`
Expected: no new errors from this file.

- [ ] **Step 3: Commit**

```bash
git add app/api/cart/vouchers/route.ts
git commit -m "feat(api): /api/cart/vouchers terima productIds untuk gate scope voucher

Query param opsional -- absent = behavior lama (app belum update),
present (termasuk kosong) = strict gate pakai cartProducts dari
lib/voucher-list.ts. Lengkapi fix availability bug di task sebelumnya."
```

---

### Task 4: `isBrandExclusive` in `lib/product-vouchers.ts`

**Files:**
- Modify: `lib/product-vouchers.ts`

**Interfaces:**
- Produces: `ProductVoucherPreview.isBrandExclusive: boolean`, `ProductVoucherItem.isBrandExclusive: boolean` — consumed by Task 5.

- [ ] **Step 1: Add the field to both output types**

In `lib/product-vouchers.ts`, add `isBrandExclusive: boolean;` to `ProductVoucherPreview` (after `loginRequired`):

```ts
export type ProductVoucherPreview = {
  id: string;
  title: string;
  description: string | null;
  badgeLabel: string;
  sheetTitle: string;
  sheetSubtitle: string;
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  savingAmount: number | null;
  expiresAt: string | null;
  type: "PUBLIC_PRODUCT_DISCOUNT" | "PUBLIC_FREE_SHIPPING";
  discountScope: "PRODUCT" | "SHIPPING";
  targetUser: "ALL_MEMBERS" | "NEW_MEMBER";
  loginRequired: true;
  isBrandExclusive: boolean;
};
```

Add the same field to `ProductVoucherItem` (after `isExpired`):

```ts
export type ProductVoucherItem = {
  id: string;
  title: string;
  description: string | null;
  label: string;
  type: "member";
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  kind:
    | "PRODUCT_DISCOUNT"
    | "FREE_SHIPPING"
    | "LOYALTY_CLAIM"
    | "MANUAL_PRIVATE";
  targetUser: "ALL_MEMBERS" | "NEW_MEMBER";
  usageLimitPeriod: VoucherUsageLimitPeriodValue;
  minPurchase: number;
  expiresAt: string | null;
  visibility: "member";
  isPrivate: false;
  isManualOnly: false;
  usedByCurrentUser: false;
  isActive: true;
  isExpired: false;
  isBrandExclusive: boolean;
};
```

- [ ] **Step 2: Populate the field in `buildProductVoucherPreview`**

In `buildProductVoucherPreview`, add `isBrandExclusive: voucher.eligibleBrandIds.length > 0,` to the returned object (after `loginRequired: true,`):

```ts
    type:
      voucher.discountScope === "SHIPPING"
        ? "PUBLIC_FREE_SHIPPING"
        : "PUBLIC_PRODUCT_DISCOUNT",
    discountScope: voucher.discountScope,
    targetUser: voucher.targetUser,
    loginRequired: true,
    isBrandExclusive: voucher.eligibleBrandIds.length > 0,
  };
}
```

- [ ] **Step 3: Populate the field in `loadVisibleProductVouchers`'s mapping**

In `loadVisibleProductVouchers`, find the final `.map((voucher) => ({...}))` block and add `isBrandExclusive: voucher.eligibleBrandIds.length > 0,` after `isExpired: false,`:

```ts
      isPrivate: false,
      isManualOnly: false,
      usedByCurrentUser: false,
      isActive: true,
      isExpired: false,
      isBrandExclusive: voucher.eligibleBrandIds.length > 0,
    }));
```

(`voucher.eligibleBrandIds` is already selected in this query's Prisma `select` block — no query change needed.)

- [ ] **Step 4: Typecheck**

Run: `npx tsc --noEmit`
Expected: no new errors.

- [ ] **Step 5: Commit**

```bash
git add lib/product-vouchers.ts
git commit -m "feat(voucher): isBrandExclusive flag di ProductVoucherPreview/Item

Boolean murni dari eligibleBrandIds.length > 0 -- brand NAME resolution
sengaja tidak di sini (butuh 1 extra query, biar route.ts yang sudah
punya product.brandId di tangan yang urus, hindari N+1 di listing bulk)."
```

---

### Task 5: Attach `brandName` in `/api/products/[slug]/vouchers`

**Files:**
- Modify: `app/api/products/[slug]/vouchers/route.ts`

**Interfaces:**
- Consumes: `isBrandExclusive` (Task 4), `prisma.brand`.
- Produces: every voucher object returned by this endpoint gains `brandName: string | null`.

- [ ] **Step 1: Update the route handler**

Replace the full contents of `app/api/products/[slug]/vouchers/route.ts` with:

```ts
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { getProductBySlug } from "@/lib/products";
import {
  loadPublicProductVoucherPreview,
  loadPublicShippingVoucherPreview,
  loadVisibleProductVouchers,
} from "@/lib/product-vouchers";
import { prisma } from "@/lib/prisma";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ slug: string }> }
) {
  const { slug } = await params;
  const product =
    (await getProductBySlug(slug)) ??
    (await prisma.product.findUnique({
      where: { id: slug },
      select: {
        id: true,
        price: true,
        categoryId: true,
        brandId: true,
        category: { select: { slug: true } },
      },
    }));
  if (!product) {
    return NextResponse.json({ vouchers: [] }, { status: 404 });
  }

  const session = await getSession("CUSTOMER");
  // brandId WAJIB ikut — tanpa ini voucherMatchesProduct tidak pernah bisa
  // cocokkan voucher scoped-brand (mis. "Happy Dog") lewat endpoint ini,
  // beda dengan /api/products listing yang sudah include brandId.
  const previewInput = {
    id: product.id,
    price: product.price,
    categoryId: product.categoryId ?? null,
    categorySlug:
      "categorySlug" in product
        ? product.categorySlug ?? null
        : "category" in product
        ? product.category?.slug ?? null
        : null,
    brandId: product.brandId ?? null,
  };

  // Brand produk ini sendiri -- dipakai untuk label "Khusus {brand}" di
  // voucher manapun yang match lewat scope brand. Tidak perlu resolve
  // SEMUA eligibleBrandIds voucher (voucher bisa multi-brand) karena di
  // context halaman produk ini, brand yang relevan cuma satu: brand
  // produk yang sedang dilihat.
  const brandName = product.brandId
    ? (
        await prisma.brand.findUnique({
          where: { id: product.brandId },
          select: { name: true },
        })
      )?.name ?? null
    : null;

  const attachBrandName = <T extends { isBrandExclusive?: boolean }>(
    voucher: T
  ) => ({
    ...voucher,
    brandName: voucher.isBrandExclusive ? brandName : null,
  });

  const [publicVoucher, shippingVoucher, memberVouchers] = await Promise.all([
    loadPublicProductVoucherPreview(previewInput, {
      userId: session?.sub ?? null,
    }),
    loadPublicShippingVoucherPreview(previewInput, {
      userId: session?.sub ?? null,
    }),
    // previewInput diteruskan supaya voucher scoped (brand/kategori/produk)
    // difilter sesuai produk yang sedang dilihat — root cause fix voucher
    // brand X muncul di halaman produk brand lain.
    session
      ? loadVisibleProductVouchers(session.sub, previewInput)
      : Promise.resolve([]),
  ]);

  const vouchers = [
    ...(publicVoucher ? [attachBrandName(publicVoucher)] : []),
    ...(shippingVoucher && shippingVoucher.id !== publicVoucher?.id
      ? [attachBrandName(shippingVoucher)]
      : []),
    ...memberVouchers
      .filter(
        (voucher) =>
          voucher.id !== publicVoucher?.id && voucher.id !== shippingVoucher?.id
      )
      .map(attachBrandName),
  ];

  return NextResponse.json({ vouchers });
}
```

- [ ] **Step 2: Typecheck**

Run: `npx tsc --noEmit`
Expected: no new errors.

- [ ] **Step 3: Manual smoke check against a real brand-scoped voucher**

Run (adjust slug to a real product with a brand-exclusive voucher in your dev DB):

```bash
curl -s "http://localhost:3000/api/products/<slug-produk-happy-dog>/vouchers" | node -e "process.stdin.once('data', d => console.log(JSON.parse(d)))"
```

Expected: the brand-scoped voucher entry has `"isBrandExclusive": true, "brandName": "Happy Dog"` (or whatever the real brand name is); non-scoped vouchers have `"isBrandExclusive": false, "brandName": null`.

- [ ] **Step 4: Commit**

```bash
git add app/api/products/[slug]/vouchers/route.ts
git commit -m "feat(api): brandName di response /api/products/{slug}/vouchers

Resolve brand produk sekali (single lookup, bukan N+1), attach ke
voucher manapun yang isBrandExclusive -- Flutter product detail bisa
render 'Khusus {brand}' tanpa lookup tambahan."
```

---

### Task 6: `brandName` in checkout `/api/checkout/recalculate`

**Context:** Checkout's own availability logic (`eligibleProductSubtotal`) is already correct (fixed in an earlier session) — this task only adds display data, no bug fix.

**Files:**
- Modify: `app/api/checkout/recalculate/route.ts`

**Interfaces:**
- Consumes: `loadBrandNamesByIds`, `formatVoucherBrandName` from `@/lib/voucher-eligibility` (Task 1).
- Produces: `normalizeVoucher(...)` and `normalizeUnavailable(...)` output objects gain `brandName: string | null`.

- [ ] **Step 1: Import the helpers**

In `app/api/checkout/recalculate/route.ts`, update the existing import line:

```ts
import { voucherMatchesProduct } from "@/lib/voucher-eligibility";
```

to:

```ts
import {
  voucherMatchesProduct,
  loadBrandNamesByIds,
  formatVoucherBrandName,
} from "@/lib/voucher-eligibility";
```

- [ ] **Step 2: Resolve brand names once for all customer vouchers**

Right after the `customerVouchers` filter block (after the closing `);` of `const customerVouchers = customerVouchersRaw.filter(...)`, before `const userCtx = {...}`), add:

```ts
  const brandNamesById = await loadBrandNamesByIds(
    customerVouchers.flatMap((v) => v.eligibleBrandIds)
  );
```

- [ ] **Step 3: Thread `brandNamesById` into `normalizeVoucher` and `normalizeUnavailable`**

Change the function signatures and bodies. Replace:

```ts
function normalizeVoucher(voucher: VoucherRow, discount: number) {
  const kind = effectiveKind(voucher);
  return {
    code: voucher.code,
    discount,
    description: voucher.description ?? describeDiscount(discount),
    minimumOrder: voucher.minimumOrder,
    expiresAt: voucher.expiresAt,
    sourceType: voucher.sourceType,
    kind,
    slot: voucherSlotForKind(kind),
    type: voucherTypeOf(voucher),
    discountScope: voucherScopeOf(voucher),
    targetUser: voucher.targetUser,
    status: "available" as const,
  };
}
```

with:

```ts
function normalizeVoucher(
  voucher: VoucherRow,
  discount: number,
  brandNamesById: Map<string, string> = new Map(),
) {
  const kind = effectiveKind(voucher);
  return {
    code: voucher.code,
    discount,
    description: voucher.description ?? describeDiscount(discount),
    minimumOrder: voucher.minimumOrder,
    expiresAt: voucher.expiresAt,
    sourceType: voucher.sourceType,
    kind,
    slot: voucherSlotForKind(kind),
    type: voucherTypeOf(voucher),
    discountScope: voucherScopeOf(voucher),
    targetUser: voucher.targetUser,
    status: "available" as const,
    brandName: formatVoucherBrandName(voucher.eligibleBrandIds, brandNamesById),
  };
}
```

Note the default `= new Map()`: there is a THIRD call site at (currently) line 548 — `manualApplied = normalizeVoucher(manualVoucher, discount);`, inside the private manual-code path, entirely separate from the `customerVouchers` loop. Manual/private codes are out of scope for brand-exclusive display (non-goal — see spec), so this call site is intentionally left unchanged; the default parameter means it keeps compiling and simply resolves `brandName: null` for that path instead of needing a fourth thread-through.

Replace:

```ts
function normalizeUnavailable(
  voucher: VoucherRow,
  reason: string,
  shortfall = 0,
) {
  const kind = effectiveKind(voucher);
  return {
    code: voucher.code,
    description: voucher.description ?? "",
    minimumOrder: voucher.minimumOrder,
    shortfall,
    expiresAt: voucher.expiresAt,
    reason,
    sourceType: voucher.sourceType,
    kind,
    slot: voucherSlotForKind(kind),
    type: voucherTypeOf(voucher),
    discountScope: voucherScopeOf(voucher),
    targetUser: voucher.targetUser,
    status: "unavailable" as const,
  };
}
```

with:

```ts
function normalizeUnavailable(
  voucher: VoucherRow,
  reason: string,
  shortfall = 0,
  brandNamesById: Map<string, string> = new Map(),
) {
  const kind = effectiveKind(voucher);
  return {
    code: voucher.code,
    description: voucher.description ?? "",
    minimumOrder: voucher.minimumOrder,
    shortfall,
    expiresAt: voucher.expiresAt,
    reason,
    sourceType: voucher.sourceType,
    kind,
    slot: voucherSlotForKind(kind),
    type: voucherTypeOf(voucher),
    discountScope: voucherScopeOf(voucher),
    targetUser: voucher.targetUser,
    status: "unavailable" as const,
    brandName: formatVoucherBrandName(voucher.eligibleBrandIds, brandNamesById),
  };
}
```

- [ ] **Step 4: Update every call site to pass `brandNamesById`**

In the `for (const voucher of customerVouchers)` loop, update every call:

```ts
    if (disabledReason) {
      unavailable.push(normalizeUnavailable(voucher, disabledReason, 0));
      continue;
    }
```
→
```ts
    if (disabledReason) {
      unavailable.push(normalizeUnavailable(voucher, disabledReason, 0, brandNamesById));
      continue;
    }
```

```ts
      unavailable.push(
        normalizeUnavailable(
          voucher,
          `Belanja kurang Rp${new Intl.NumberFormat("id-ID").format(shortfall)} lagi`,
          shortfall,
        ),
      );
```
→
```ts
      unavailable.push(
        normalizeUnavailable(
          voucher,
          `Belanja kurang Rp${new Intl.NumberFormat("id-ID").format(shortfall)} lagi`,
          shortfall,
          brandNamesById,
        ),
      );
```

```ts
    if (voucherScopeOf(voucher) === "SHIPPING" && shippingFee <= 0) {
      unavailable.push(
        normalizeUnavailable(voucher, "Pilih pengiriman untuk menggunakan gratis ongkir", 0),
      );
      continue;
    }
    if (voucherScopeOf(voucher) === "PRODUCT" && eligibleProductSubtotal(voucher) <= 0) {
      unavailable.push(
        normalizeUnavailable(voucher, "Voucher tidak berlaku untuk produk ini", 0),
      );
      continue;
    }

    const discount = checkoutVoucherDiscount(voucher);
    if (discount <= 0) {
      unavailable.push(
        normalizeUnavailable(voucher, "Voucher tidak memiliki potongan untuk checkout ini", 0),
      );
      continue;
    }

    available.push(normalizeVoucher(voucher, discount));
```
→
```ts
    if (voucherScopeOf(voucher) === "SHIPPING" && shippingFee <= 0) {
      unavailable.push(
        normalizeUnavailable(voucher, "Pilih pengiriman untuk menggunakan gratis ongkir", 0, brandNamesById),
      );
      continue;
    }
    if (voucherScopeOf(voucher) === "PRODUCT" && eligibleProductSubtotal(voucher) <= 0) {
      unavailable.push(
        normalizeUnavailable(voucher, "Voucher tidak berlaku untuk produk ini", 0, brandNamesById),
      );
      continue;
    }

    const discount = checkoutVoucherDiscount(voucher);
    if (discount <= 0) {
      unavailable.push(
        normalizeUnavailable(voucher, "Voucher tidak memiliki potongan untuk checkout ini", 0, brandNamesById),
      );
      continue;
    }

    available.push(normalizeVoucher(voucher, discount, brandNamesById));
```

- [ ] **Step 5: Typecheck**

Run: `npx tsc --noEmit`
Expected: no new errors. The third call site (`manualApplied = normalizeVoucher(manualVoucher, discount);`, private manual-code path) is unaffected by design — its default `brandNamesById = new Map()` keeps it compiling without modification.

- [ ] **Step 6: Commit**

```bash
git add app/api/checkout/recalculate/route.ts
git commit -m "feat(api): brandName di checkout recalculate available/unavailable voucher

Availability sudah benar dari sesi sebelumnya (eligibleProductSubtotal)
-- ini cuma nambah data display biar sheet voucher checkout juga bisa
render badge 'Khusus {brand}' konsisten dengan cart & product detail."
```

---

### Task 7: Backend full verification checkpoint

**Files:** none (verification only)

- [ ] **Step 1: Run the full backend test suite**

Run: `npm test`
Expected: all tests pass, including the 16 in `voucher-list.test.ts` and 5 in `voucher-eligibility.test.ts`, and no regressions in the other 18 test files.

- [ ] **Step 2: Run the production build**

Run: `npx next build`
Expected: exit code 0, no TypeScript errors, all pages generate successfully (per this codebase's established rule: `next build` is the authoritative pre-push check, not `tsc` alone).

- [ ] **Step 3: If either fails, stop and fix before proceeding to Flutter tasks**

Do not proceed to Task 8 until both Step 1 and Step 2 are clean.

---

### Task 8: `ProductVoucherPreview` Dart model — `brandName`

**Files:**
- Modify: `flutter_app/lib/models/product.dart:174-293` (the `ProductVoucherPreview` class)

**Interfaces:**
- Produces: `ProductVoucherPreview.brandName: String?`, `ProductVoucherPreview.isBrandExclusive` getter — consumed by Task 10 (product_detail_screen.dart).

- [ ] **Step 1: Add the field, constructor param, getter, and JSON parsing**

In `flutter_app/lib/models/product.dart`, add `brandName` to the field list (after `loginRequired`):

```dart
  final String? expiresAt;
  final String type;
  final String discountScope;
  final String targetUser;
  final bool loginRequired;
  final String? brandName;
```

Add to the constructor (after `required this.loginRequired,`):

```dart
    this.type = 'PUBLIC_PRODUCT_DISCOUNT',
    this.discountScope = 'PRODUCT',
    this.targetUser = 'ALL_MEMBERS',
    required this.loginRequired,
    this.brandName,
  });
```

Add the getter after `isShippingVoucher` (before `factory ProductVoucherPreview.fromJson`):

```dart
  bool get isShippingVoucher {
    final normalizedType = type.trim().toUpperCase();
    final normalizedScope = discountScope.trim().toUpperCase();
    return normalizedType == 'PUBLIC_FREE_SHIPPING' ||
        normalizedType == 'FREE_SHIPPING' ||
        normalizedScope == 'SHIPPING';
  }

  /// True kalau voucher ini scoped ke brand tertentu (backend kirim
  /// brandName != null hanya kalau eligibleBrandIds voucher non-kosong DAN
  /// cocok dengan brand produk yang sedang dilihat).
  bool get isBrandExclusive => brandName != null && brandName!.trim().isNotEmpty;
```

In `factory ProductVoucherPreview.fromJson`, add `brandName` to the returned constructor call (after `loginRequired: json['loginRequired'] != false,`):

```dart
      loginRequired: json['loginRequired'] != false,
      brandName: _stringOrNull(json['brandName']),
    );
  }
```

- [ ] **Step 2: Verify it compiles**

Run: `cd flutter_app && dart analyze lib/models/product.dart`
Expected: no errors (the `_stringOrNull` helper already exists in this file, used elsewhere in the same factory).

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/models/product.dart
git commit -m "feat(voucher): brandName + isBrandExclusive di ProductVoucherPreview

Field baru dari response /api/products/{slug}/vouchers -- dipakai
untuk render badge 'Khusus {brand}' di product detail."
```

---

### Task 9: `MemberVoucher` Dart model — `brandName`

**Files:**
- Modify: `flutter_app/lib/models/member_profile.dart:166-274` (the `MemberVoucher` class)

**Interfaces:**
- Produces: `MemberVoucher.brandName: String?`, `MemberVoucher.isBrandExclusive` getter — consumed by Task 11 (member_vouchers_screen.dart), Task 12 (cart_screen.dart), Task 13 (checkout_screen.dart).

- [ ] **Step 1: Add the field, constructor param, getter, and JSON parsing**

In `flutter_app/lib/models/member_profile.dart`, add `brandName` to the field list (after `disabledReason`):

```dart
  /// Alasan voucher disabled (untuk display di list inelibible). null kalau applicable.
  final String? disabledReason;

  /// Nama brand kalau voucher ini scoped ke brand tertentu (backend kirim
  /// null kalau voucher tidak scoped ke brand manapun).
  final String? brandName;
```

Add to the constructor (after `this.disabledReason,`):

```dart
    this.disabledReason,
    this.brandName,
  });
```

Add `brandName` parsing in `factory MemberVoucher.fromApiJson` — in the returned `MemberVoucher(...)` call, add after `disabledReason: disabledReason?.isEmpty == true ? null : disabledReason,`:

```dart
      disabledReason: disabledReason?.isEmpty == true ? null : disabledReason,
      brandName: _nullableString(json['brandName']),
    );
  }
```

(`_nullableString` already exists in this file, used earlier in the same factory for `apiTitle`.)

Add the getter after `isProductScope` (end of the class body, before the closing `}`):

```dart
  bool get isFreeShipping => type == 'PUBLIC_FREE_SHIPPING';
  bool get isProductDiscount => type == 'PUBLIC_PRODUCT_DISCOUNT';
  bool get isLoyaltyClaim => type == 'LOYALTY_POINT_CLAIM';
  bool get isPrivateManual => type == 'PRIVATE_MANUAL_CODE';
  bool get isShippingDiscount => discountScope == 'SHIPPING';
  bool get isProductScope => discountScope != 'SHIPPING';

  /// True kalau voucher ini scoped ke brand tertentu.
  bool get isBrandExclusive => brandName != null && brandName!.trim().isNotEmpty;
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd flutter_app && dart analyze lib/models/member_profile.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/models/member_profile.dart
git commit -m "feat(voucher): brandName + isBrandExclusive di MemberVoucher

Dipakai bareng di cart picker, halaman Voucher Saya, dan checkout --
ketiganya sudah pakai model MemberVoucher yang sama."
```

---

### Task 10: Send `productIds` from Flutter cart to `/api/cart/vouchers`

**Files:**
- Modify: `flutter_app/lib/services/member_service.dart:325-372`
- Modify: `flutter_app/lib/screens/cart_screen.dart:428-431` (the `_syncVouchersForSelection` call site)

**Interfaces:**
- Consumes: `CartItem.productId` (existing getter, `flutter_app/lib/models/cart_item.dart:53`), `cartStore.items` (existing, `flutter_app/lib/state/cart_store.dart:61`).
- Produces: `memberService.fetchCartVouchers(int subtotal, List<String> productIds)` — signature change, both call sites in the codebase updated together in this task.

- [ ] **Step 1: Update `fetchCartVouchers` signature**

In `flutter_app/lib/services/member_service.dart`, replace:

```dart
  Future<({List<MemberVoucher> available, List<MemberVoucher> unavailable})>
      fetchCartVouchers(int subtotal) async {
    try {
      final data = await apiClient.getJson(
        '/api/cart/vouchers',
        query: {'subtotal': '$subtotal'},
      );
```

with:

```dart
  Future<({List<MemberVoucher> available, List<MemberVoucher> unavailable})>
      fetchCartVouchers(int subtotal, List<String> productIds) async {
    try {
      final data = await apiClient.getJson(
        '/api/cart/vouchers',
        query: {'subtotal': '$subtotal', 'productIds': productIds.join(',')},
      );
```

- [ ] **Step 2: Update `fetchVouchers()` to pass the whole cart's product ids**

In the same file, replace:

```dart
  Future<List<MemberVoucher>> fetchVouchers() async {
    try {
      final result = await fetchCartVouchers(cartStore.subtotal.round());
      return [...result.available, ...result.unavailable];
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchVouchers] $e');
      return const [];
    }
  }
```

with:

```dart
  Future<List<MemberVoucher>> fetchVouchers() async {
    try {
      final productIds =
          cartStore.items.map((item) => item.productId).toSet().toList();
      final result =
          await fetchCartVouchers(cartStore.subtotal.round(), productIds);
      return [...result.available, ...result.unavailable];
    } catch (e) {
      if (kDebugMode) debugPrint('[memberService.fetchVouchers] $e');
      return const [];
    }
  }
```

- [ ] **Step 3: Update the cart screen's call site**

In `flutter_app/lib/screens/cart_screen.dart`, find (around line 428-431):

```dart
      try {
        final result = await memberService.fetchCartVouchers(subtotal);
        available = result.available;
        unavailable = result.unavailable;
```

Replace with:

```dart
      try {
        final productIds =
            _selectedItems.map((item) => item.productId).toSet().toList();
        final result =
            await memberService.fetchCartVouchers(subtotal, productIds);
        available = result.available;
        unavailable = result.unavailable;
```

- [ ] **Step 4: Verify it compiles**

Run: `cd flutter_app && dart analyze lib/services/member_service.dart lib/screens/cart_screen.dart`
Expected: no errors. (There should be no other call sites of `fetchCartVouchers` — confirm with `grep -rn "fetchCartVouchers" flutter_app/lib` if analyze surfaces any missed call site.)

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/member_service.dart flutter_app/lib/screens/cart_screen.dart
git commit -m "fix(voucher): kirim productIds cart ke /api/cart/vouchers

Melengkapi fix backend -- tanpa ini endpoint tetap permissive (param
absent) walau sudah bisa gate scope. cart_screen kirim item yang
DIPILIH user (_selectedItems), fetchVouchers() (dipakai halaman
Voucher Saya) kirim SELURUH isi cart."
```

---

### Task 11: Amber styling in `product_detail_screen.dart`

**Files:**
- Modify: `flutter_app/lib/screens/product_detail_screen.dart`

**Interfaces:**
- Consumes: `ProductVoucherPreview.isBrandExclusive`, `.brandName` (Task 8).

- [ ] **Step 1: Add the amber color constants**

Near the top of `flutter_app/lib/screens/product_detail_screen.dart`, after the existing color consts (after `const _successGreen = Color(0xFF16A34A);` at line 45), add:

```dart
const _successGreen = Color(0xFF16A34A);
const _brandExclusiveAmber = Color(0xFFF7A100);
const _brandExclusiveSoftBg = Color(0xFFFEF0DC);
const _brandExclusiveSoftBorder = Color(0xFFFCD9A0);
const _brandExclusiveDark = Color(0xFFB85C00);
```

- [ ] **Step 2: Update `_VoucherChip` (rail chip)**

Replace the `_VoucherChip` class body:

```dart
class _VoucherChip extends StatelessWidget {
  final ProductVoucherPreview voucher;

  /// Hero = di-FILL solid (anchor rail) — dipakai saat tak ada chip diskon
  /// harga, supaya rail tetap punya satu chip mencolok.
  final bool hero;

  const _VoucherChip({required this.voucher, this.hero = false});

  @override
  Widget build(BuildContext context) {
    final shipping = voucher.isShippingVoucher;
    final tone = shipping ? _successGreen : _discountRed;
    final icon = shipping
        ? Icons.local_shipping_rounded
        : Icons.confirmation_number_rounded;
    // Hero non-ongkir → fill solid + teks/ikon putih. Selain itu soft (bg
    // pucat + teks tone). Voucher ongkir selalu hijau soft.
    final fill = hero && !shipping;
    final bg = fill
        ? _discountRed
        : (shipping ? const Color(0xFFEFFAF4) : _softDiscountBg);
    final fg = fill ? Colors.white : tone;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: fill
            ? null
            : Border.all(
                color: shipping
                    ? const Color(0xFFC7F0D8)
                    : const Color(0xFFFFC9D0),
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            _voucherChipText(voucher),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
```

with:

```dart
class _VoucherChip extends StatelessWidget {
  final ProductVoucherPreview voucher;

  /// Hero = di-FILL solid (anchor rail) — dipakai saat tak ada chip diskon
  /// harga, supaya rail tetap punya satu chip mencolok.
  final bool hero;

  const _VoucherChip({required this.voucher, this.hero = false});

  @override
  Widget build(BuildContext context) {
    final shipping = voucher.isShippingVoucher;
    final brandExclusive = voucher.isBrandExclusive;
    final tone = shipping
        ? _successGreen
        : brandExclusive
            ? _brandExclusiveDark
            : _discountRed;
    final icon = shipping
        ? Icons.local_shipping_rounded
        : brandExclusive
            ? Icons.workspace_premium_rounded
            : Icons.confirmation_number_rounded;
    // Hero non-ongkir → fill solid + teks/ikon putih. Selain itu soft (bg
    // pucat + teks tone). Voucher ongkir selalu hijau soft. Brand-exclusive
    // selalu fill solid oranye (senada saturasi dgn merah hero, bukan
    // muncul cuma saat hero) supaya langsung kebeda dari voucher biasa.
    final fill = brandExclusive || (hero && !shipping);
    final bg = brandExclusive
        ? _brandExclusiveAmber
        : fill
            ? _discountRed
            : (shipping ? const Color(0xFFEFFAF4) : _softDiscountBg);
    final fg = fill ? Colors.white : tone;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: fill
            ? null
            : Border.all(
                color: shipping
                    ? const Color(0xFFC7F0D8)
                    : const Color(0xFFFFC9D0),
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            _voucherChipText(voucher),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Update `_voucherChipText` to show the brand name**

Find `_voucherChipText` (around line 1675) and replace:

```dart
String _voucherChipText(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) return 'Gratis Ongkir';
  final amount = voucher.discountAmount ?? voucher.savingAmount;
```

with:

```dart
String _voucherChipText(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) return 'Gratis Ongkir';
  if (voucher.isBrandExclusive) return 'Khusus ${voucher.brandName}';
  final amount = voucher.discountAmount ?? voucher.savingAmount;
```

- [ ] **Step 4: Update `_voucherSheetSubtitle` to prepend the brand clause**

Find `_voucherSheetSubtitle` (around line 1693) and replace:

```dart
String _voucherSheetSubtitle(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) {
    return 'Bisa digunakan saat checkout';
  }
  final minimum = voucher.minimumOrder;
  if (minimum > 0) {
    return 'Potongan belanja saat checkout • Min. belanja ${formatRupiahCompact(minimum)}';
  }
  return 'Potongan belanja saat checkout';
}
```

with:

```dart
String _voucherSheetSubtitle(ProductVoucherPreview voucher) {
  if (voucher.isShippingVoucher) {
    return 'Bisa digunakan saat checkout';
  }
  final minimum = voucher.minimumOrder;
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
```

- [ ] **Step 5: Update `_VoucherSheetCard` to render the "KHUSUS BRAND" badge and amber card**

Replace the `_VoucherSheetCard` class body:

```dart
class _VoucherSheetCard extends StatelessWidget {
  final ProductVoucherPreview voucher;

  const _VoucherSheetCard({required this.voucher});

  @override
  Widget build(BuildContext context) {
    final shipping = voucher.isShippingVoucher;
    final tone = shipping ? _successGreen : _discountRed;
    final bg = shipping ? const Color(0xFFF0FDF4) : _softDiscountBg;
    final border = shipping ? const Color(0xFFBBF7D0) : const Color(0xFFFFC9D0);
    final subtitle = _voucherSheetSubtitle(voucher);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _voucherChipText(voucher),
                  style: TextStyle(
                    color: tone,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _textMedium,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          shipping
              ? Icon(
                  Icons.local_shipping_rounded,
                  color: tone,
                  size: 24,
                )
              : const _DiscountVoucherIcon(),
        ],
      ),
    );
  }
}
```

with:

```dart
class _VoucherSheetCard extends StatelessWidget {
  final ProductVoucherPreview voucher;

  const _VoucherSheetCard({required this.voucher});

  @override
  Widget build(BuildContext context) {
    final shipping = voucher.isShippingVoucher;
    final brandExclusive = voucher.isBrandExclusive;
    final tone = shipping
        ? _successGreen
        : brandExclusive
            ? _brandExclusiveDark
            : _discountRed;
    final bg = shipping
        ? const Color(0xFFF0FDF4)
        : brandExclusive
            ? _brandExclusiveSoftBg
            : _softDiscountBg;
    final border = shipping
        ? const Color(0xFFBBF7D0)
        : brandExclusive
            ? _brandExclusiveSoftBorder
            : const Color(0xFFFFC9D0);
    final subtitle = _voucherSheetSubtitle(voucher);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (brandExclusive) ...[
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
                Text(
                  _voucherChipText(voucher),
                  style: TextStyle(
                    color: tone,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _textMedium,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          shipping
              ? Icon(
                  Icons.local_shipping_rounded,
                  color: tone,
                  size: 24,
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
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Verify it compiles**

Run: `cd flutter_app && dart analyze lib/screens/product_detail_screen.dart`
Expected: no errors.

- [ ] **Step 7: Run `dart format` to normalize any indentation drift**

Run: `cd flutter_app && dart format lib/screens/product_detail_screen.dart`

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/screens/product_detail_screen.dart
git commit -m "feat(ui): styling voucher brand-exclusive di product detail

Rail chip fill oranye solid #F7A100 + ikon award, card sheet dgn badge
'KHUSUS BRAND' + bg oranye soft, subtitle 'Berlaku untuk {brand}'.
Sesuai mockup yang disetujui -- konsisten dgn saturasi merah/hijau yg
sudah ada, bukan tipe voucher baru."
```

---

### Task 12: Amber styling in `member_vouchers_screen.dart` ("Voucher Saya")

**Files:**
- Modify: `flutter_app/lib/screens/member_vouchers_screen.dart`

**Interfaces:**
- Consumes: `MemberVoucher.isBrandExclusive`, `.brandName` (Task 9).

- [ ] **Step 1: Add the badge above `voucher.code` in `_VoucherCard`**

In `flutter_app/lib/screens/member_vouchers_screen.dart`, find this block inside `_VoucherCard.build` (around line 401-414):

```dart
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          voucher.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _brandBlue,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
```

Replace with:

```dart
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (voucher.isBrandExclusive) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF0DC),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFFCD9A0),
                              ),
                            ),
                            child: Text(
                              'KHUSUS ${voucher.brandName!.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB85C00),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          voucher.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _brandBlue,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
```

(The disabled-reason banner further down already renders `voucher.disabledReason` verbatim — the new "Voucher tidak berlaku untuk produk di keranjang" reason from Task 2 will show there automatically, no change needed.)

- [ ] **Step 2: Verify it compiles**

Run: `cd flutter_app && dart analyze lib/screens/member_vouchers_screen.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/screens/member_vouchers_screen.dart
git commit -m "feat(ui): badge KHUSUS BRAND di halaman Voucher Saya

Voucher brand-exclusive tetap tampil di list 'semua voucher saya' tapi
sekarang dengan badge supaya user paham scope-nya sebelum coba pakai."
```

---

### Task 13: Amber styling in `cart_screen.dart` (cart voucher picker)

**Files:**
- Modify: `flutter_app/lib/screens/cart_screen.dart`

**Interfaces:**
- Consumes: `MemberVoucher.isBrandExclusive`, `.brandName` (Task 9).

- [ ] **Step 1: Add the amber color constants**

Near the top of `flutter_app/lib/screens/cart_screen.dart`, after the existing voucher color consts (after `const _shippingGreenBorder = Color(0xFFA6F4C5);` at line 39), add:

```dart
const _shippingGreenBorder = Color(0xFFA6F4C5);
const _brandExclusiveAmber = Color(0xFFF7A100);
const _brandExclusiveAmberSoft = Color(0xFFFEF0DC);
const _brandExclusiveAmberBorder = Color(0xFFFCD9A0);
```

- [ ] **Step 2: Branch the "available product vouchers" `_CartVoucherCard` call**

Find (around line 2817-2846):

```dart
                    for (final voucher in availableProductVouchers) ...[
                      _CartVoucherCard(
                        title: voucher.title,
                        subtitle: voucher.description,
                        // Loyalty voucher = "Reward Poin" badge + star purple
                        // match styling checkout. Product discount = "Diskon"
                        // tag pink. Differentiate icon supaya user paham
                        // type voucher langsung dari visual.
                        badge:
                            voucher.isLoyaltyClaim ? 'Reward Poin' : 'Diskon',
                        trailing: formatRupiah(voucher.discount),
                        icon: voucher.isLoyaltyClaim
                            ? Icons.stars_rounded
                            : Icons.local_offer_rounded,
                        accent: voucher.isLoyaltyClaim
                            ? _loyaltyPurple
                            : _discountRed,
                        background: voucher.isLoyaltyClaim
                            ? _loyaltyPurpleSoft
                            : _discountRedSoft,
                        border: voucher.isLoyaltyClaim
                            ? _loyaltyPurpleBorder
                            : _discountRedBorder,
                        selected: voucher.isLoyaltyClaim
                            ? _selectedLoyalty?.code == voucher.code
                            : _selectedProductDiscount?.code == voucher.code,
                        enabled: true,
                        onTap: () => _pickDiscount(voucher),
                      ),
                      const SizedBox(height: 10),
                    ],
```

Replace with:

```dart
                    for (final voucher in availableProductVouchers) ...[
                      _CartVoucherCard(
                        title: voucher.title,
                        subtitle: voucher.description,
                        // Brand-exclusive selalu badge nama brand + oranye,
                        // di atas prioritas loyalty/diskon biasa. Loyalty
                        // voucher = "Reward Poin" badge + star purple match
                        // styling checkout. Product discount = "Diskon" tag
                        // pink. Differentiate icon supaya user paham type
                        // voucher langsung dari visual.
                        badge: voucher.isBrandExclusive
                            ? 'Khusus ${voucher.brandName}'
                            : voucher.isLoyaltyClaim
                                ? 'Reward Poin'
                                : 'Diskon',
                        trailing: formatRupiah(voucher.discount),
                        icon: voucher.isBrandExclusive
                            ? Icons.workspace_premium_rounded
                            : voucher.isLoyaltyClaim
                                ? Icons.stars_rounded
                                : Icons.local_offer_rounded,
                        accent: voucher.isBrandExclusive
                            ? _brandExclusiveAmber
                            : voucher.isLoyaltyClaim
                                ? _loyaltyPurple
                                : _discountRed,
                        background: voucher.isBrandExclusive
                            ? _brandExclusiveAmberSoft
                            : voucher.isLoyaltyClaim
                                ? _loyaltyPurpleSoft
                                : _discountRedSoft,
                        border: voucher.isBrandExclusive
                            ? _brandExclusiveAmberBorder
                            : voucher.isLoyaltyClaim
                                ? _loyaltyPurpleBorder
                                : _discountRedBorder,
                        selected: voucher.isLoyaltyClaim
                            ? _selectedLoyalty?.code == voucher.code
                            : _selectedProductDiscount?.code == voucher.code,
                        enabled: true,
                        onTap: () => _pickDiscount(voucher),
                      ),
                      const SizedBox(height: 10),
                    ],
```

- [ ] **Step 3: Branch the "unavailable product vouchers" `_CartVoucherCard` call**

Find (around line 2894-2915, the mirror block under "Belum bisa dipakai"):

```dart
                      for (final voucher in unavailableProductVouchers) ...[
                        _CartVoucherCard(
                          title: voucher.title,
                          subtitle: voucher.disabledReason ??
                              'Voucher belum memenuhi syarat.',
                          badge:
                              voucher.isLoyaltyClaim ? 'Reward Poin' : 'Diskon',
                          trailing: voucher.discount > 0
                              ? formatRupiah(voucher.discount)
                              : null,
                          icon: voucher.isLoyaltyClaim
                              ? Icons.stars_rounded
                              : Icons.local_offer_outlined,
                          accent: voucher.isLoyaltyClaim
                              ? _loyaltyPurple
                              : _discountRed,
```

Replace with:

```dart
                      for (final voucher in unavailableProductVouchers) ...[
                        _CartVoucherCard(
                          title: voucher.title,
                          subtitle: voucher.disabledReason ??
                              'Voucher belum memenuhi syarat.',
                          badge: voucher.isBrandExclusive
                              ? 'Khusus ${voucher.brandName}'
                              : voucher.isLoyaltyClaim
                                  ? 'Reward Poin'
                                  : 'Diskon',
                          trailing: voucher.discount > 0
                              ? formatRupiah(voucher.discount)
                              : null,
                          icon: voucher.isBrandExclusive
                              ? Icons.workspace_premium_rounded
                              : voucher.isLoyaltyClaim
                                  ? Icons.stars_rounded
                                  : Icons.local_offer_outlined,
                          accent: voucher.isBrandExclusive
                              ? _brandExclusiveAmber
                              : voucher.isLoyaltyClaim
                                  ? _loyaltyPurple
                                  : _discountRed,
```

Leave the rest of that `_CartVoucherCard` call unchanged — the lines immediately after are:

```dart
                          background: cs.surfaceContainerHighest,
                          border: cs.outlineVariant,
                          selected: false,
                          enabled: false,
                          onTap: null,
```

This codebase already overrides `background`/`border` to neutral gray for ALL disabled cards regardless of voucher type, so no further change is needed there — disabled styling intentionally ignores accent color.

- [ ] **Step 4: Verify it compiles**

Run: `cd flutter_app && dart analyze lib/screens/cart_screen.dart`
Expected: no errors.

- [ ] **Step 5: Run `dart format`**

Run: `cd flutter_app && dart format lib/screens/cart_screen.dart`

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/cart_screen.dart
git commit -m "feat(ui): styling voucher brand-exclusive di cart picker

Badge pill 'Khusus {brand}' + oranye #F7A100 menggantikan badge
'Diskon' biasa, prioritas di atas loyalty/diskon standar. Reuse
_CartVoucherCard yang sudah ada -- tidak ada widget baru."
```

---

### Task 14: Amber styling in `checkout_screen.dart` (checkout voucher sheet)

**Files:**
- Modify: `flutter_app/lib/screens/checkout_screen.dart`

**Interfaces:**
- Consumes: `MemberVoucher.isBrandExclusive`, `.brandName` (Task 9).

- [ ] **Step 1: Branch `_voucherTypeLabel`**

Find (around line 4396-4407):

```dart
String _voucherTypeLabel(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return 'Voucher Gratis Ongkir';
  }
  if (voucher.isLoyaltyClaim) {
    return 'Voucher Reward Poin';
  }
  if (voucher.isPrivateManual) {
    return 'Voucher Kode Khusus';
  }
  return 'Voucher Diskon Produk';
}
```

Replace with:

```dart
String _voucherTypeLabel(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return 'Voucher Gratis Ongkir';
  }
  if (voucher.isBrandExclusive) {
    return 'Khusus ${voucher.brandName}';
  }
  if (voucher.isLoyaltyClaim) {
    return 'Voucher Reward Poin';
  }
  if (voucher.isPrivateManual) {
    return 'Voucher Kode Khusus';
  }
  return 'Voucher Diskon Produk';
}
```

- [ ] **Step 2: Branch `_voucherAccentColor`**

Find (around line 4442-4448):

```dart
Color _voucherAccentColor(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return const Color(0xFF12A66A);
  }
  if (voucher.isLoyaltyClaim) return const Color(0xFF7C3AED);
  return const Color(0xFFE91E63);
}
```

Replace with:

```dart
Color _voucherAccentColor(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return const Color(0xFF12A66A);
  }
  if (voucher.isBrandExclusive) return const Color(0xFFF7A100);
  if (voucher.isLoyaltyClaim) return const Color(0xFF7C3AED);
  return const Color(0xFFE91E63);
}
```

- [ ] **Step 3: Branch `_voucherIcon`**

Find (around line 4450-4457):

```dart
IconData _voucherIcon(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return Icons.local_shipping_outlined;
  }
  if (voucher.isLoyaltyClaim) return Icons.stars_rounded;
  if (voucher.isPrivateManual) return Icons.confirmation_number_outlined;
  return Icons.sell_outlined;
}
```

Replace with:

```dart
IconData _voucherIcon(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return Icons.local_shipping_outlined;
  }
  if (voucher.isBrandExclusive) return Icons.workspace_premium_rounded;
  if (voucher.isLoyaltyClaim) return Icons.stars_rounded;
  if (voucher.isPrivateManual) return Icons.confirmation_number_outlined;
  return Icons.sell_outlined;
}
```

- [ ] **Step 4: Verify it compiles**

Run: `cd flutter_app && dart analyze lib/screens/checkout_screen.dart`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/checkout_screen.dart
git commit -m "feat(ui): styling voucher brand-exclusive di checkout

3 pure function (_voucherTypeLabel/_voucherAccentColor/_voucherIcon)
dipakai baik di compact applied-chip maupun full list card -- 1
perubahan kecil otomatis konsisten di semua tampilan voucher checkout."
```

---

### Task 15: Full Flutter verification checkpoint

**Files:** none (verification only)

- [ ] **Step 1: Run static analysis across the whole app**

Run: `cd flutter_app && flutter analyze`
Expected: no new errors or warnings introduced by this plan (pre-existing warnings, if any, are out of scope).

- [ ] **Step 2: Manual smoke test — product detail (requires a real brand-exclusive voucher in the dev DB, e.g. from Task 5's Step 3)**

Run the app on an emulator/simulator against the dev backend, then:
1. Open a product belonging to the brand the test voucher targets.
2. Confirm the rail shows an amber "Khusus {brand}" chip.
3. Tap "Lihat semua" and confirm the sheet card shows the "KHUSUS BRAND" badge, amber background, and "Berlaku untuk {brand}" subtitle.
4. Open a product from a DIFFERENT brand and confirm the voucher does not appear at all (this was already fixed in a prior session — this step is a regression check, not new behavior).

- [ ] **Step 3: Manual smoke test — cart availability fix**

1. Add ONLY a non-matching-brand product to the cart.
2. Open the cart voucher picker ("Pilih voucher atau promo").
3. Confirm the brand-exclusive voucher now appears under "Belum bisa dipakai" with reason "Voucher tidak berlaku untuk produk di keranjang" — NOT under the available list (this is the bug fix; before this plan, it would incorrectly show as available).
4. Add a matching-brand product to the cart, refresh, and confirm the voucher now appears as available with the amber "Khusus {brand}" badge.

- [ ] **Step 4: Manual smoke test — Voucher Saya + checkout**

1. Open "Voucher Saya" and confirm the brand-exclusive voucher shows the amber "KHUSUS {BRAND}" pill badge.
2. Proceed to checkout with a matching-brand product in the cart and confirm the checkout voucher sheet shows the amber "Khusus {brand}" treatment (both in the compact applied-chip view and the full list).

- [ ] **Step 5: If any check fails, stop and fix before considering this plan complete**

---

## Summary of what this plan does NOT do (confirmed non-goals, don't add scope)

- No new `VoucherType`/`VoucherScopeType` enum, no `memberExclusive`/`cashback` logic.
- No changes to `checkout/recalculate`'s discount/availability math (already correct).
- No golden/widget tests added for the touched Flutter widgets (none existed before this plan; adding a test harness is a separate decision, not implied by this feature).
- No UI for showing the full brand list when a voucher spans many brands (summary format "{first} & N brand lain" is sufficient per spec).
