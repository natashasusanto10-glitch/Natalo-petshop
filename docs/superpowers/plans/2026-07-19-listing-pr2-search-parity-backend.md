# Listing PR2 — Search Backend Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the search stack (`lib/search.ts` → `/api/search`) feature parity with the products stack (`lib/products.ts` → `/api/products`) — real sales-based best-seller, trending, and discount-only filtering — plus fix two pre-existing bugs, so that PR3 can migrate `/products` onto search **without losing anything**.

**Architecture:** The two stacks currently duplicate all filtering/ranking logic, and `lib/products.ts` already imports from `lib/search.ts` — so search **cannot** import products back (circular). Fix: extract the ranking + discount logic into a new shared module `lib/product-ranking.ts` that both import. Within that module, the DB-hitting functions are thin wrappers around **pure, unit-testable cores** (`computeTrendingRanking`, `discountOnlyWhere`, `productRankWhere`), matching this repo's testing convention.

**Tech Stack:** Next.js App Router, Prisma (PostgreSQL/Neon), TypeScript, `node:test` via `tsx`.

## Global Constraints

- **Read-only additive backend work only.** No new endpoints, no `prisma/schema.prisma` changes, no migrations, no writes, no changes to cart/checkout/voucher/loyalty/auth. No `flutter_app/**`.
- **Behavior of `/api/products` must not change.** Task 2 is a pure move-and-rewire refactor; if any observable behavior of `getProducts` changes, that is a defect.
- **Never import `lib/products.ts` from `lib/search.ts`** — `lib/products.ts:9` already does `import { productSearchWhere } from "@/lib/search"`. Circular imports break the build. All sharing goes through the new `lib/product-ranking.ts`.
- **Meilisearch is OFF** (no `MEILISEARCH_*` vars in the Preview env; `isMeiliEnabled()` returns false). `searchProductsFromDb` is the live path. Do **not** attempt a Meili reindex; the Meili branch is out of scope for this PR.
- **`buildDbProductWhere` / `buildDbSearchPageArgs` (`lib/search.ts:288–342`) are exported but NOT called** by `searchProductsFromDb`, which builds its `where` inline. Adding filters to those two functions would be **silently dead code**. All filter changes go into the inline builder inside `searchProductsFromDb`.
- **Sorting must never remove items.** `lib/products.ts` conflates filter+sort for `popular=best-seller`/`trending` (it returns *only* products that sold). In the search model, sort and filter are separate concerns, so unranked products go to the **tail** of the list, not dropped. This is a deliberate, documented deviation — see Task 4.
- Testing convention: pure helpers in `lib/` get `node:test` tests run with `npx tsx --test tests/<name>.test.ts`; DB-touching functions are not unit-tested. Do **not** scaffold a new test runner or mock Prisma.
- **Commit after every task.** Conventional-commit messages.

---

## File Structure

**Created:**
- `lib/product-ranking.ts` — the shared module. Pure cores (`productRankWhere`, `discountOnlyWhere`, `computeTrendingRanking`, `withAnd`/`toAndArray`, `wibDateKey`, constants) + thin DB wrappers (`getBestSellerProductIds`, `getTrendingProductIds`).
- `tests/product-ranking.test.ts` — unit tests for the pure cores.

**Modified:**
- `lib/products.ts` — delete the moved code, import from `lib/product-ranking.ts` instead. No behavior change.
- `lib/search.ts` — `SearchSort` gains `"trending"`; `SearchOptions`/`NormalizedSearchOptions` gain `discountOnly`; `searchProductsFromDb` gains the visibility fix, deterministic `orderBy`, discount filtering, and rank-map sorting.
- `app/api/search/route.ts` — parse `discount_only`, accept `sort=trending`.

---

## Task 1: Shared ranking module (`lib/product-ranking.ts`) with pure, tested cores

**Files:**
- Create: `lib/product-ranking.ts`
- Test: `tests/product-ranking.test.ts`

**Interfaces:**
- Produces (consumed by Tasks 2, 3, 4):
  ```ts
  export const VALID_SALES_ORDER_STATUSES: OrderStatus[]
  export const TRENDING_WINDOW_DAYS: number          // 14
  export const WIB_OFFSET_MS: number                 // 7*60*60*1000
  export function wibDateKey(date: Date): string
  export function toAndArray(and: Prisma.ProductWhereInput["AND"]): Prisma.ProductWhereInput[]
  export function withAnd(where: Prisma.ProductWhereInput, condition: Prisma.ProductWhereInput): Prisma.ProductWhereInput
  export function productRankWhere(where: Prisma.ProductWhereInput): Prisma.ProductWhereInput
  export function discountOnlyWhere(now?: Date): Prisma.ProductWhereInput
  export type TrendingRow = { productId: string; quantity: number; order: { id: string; userId: string | null; customerEmail: string | null; customerPhone: string | null; createdAt: Date } }
  export function computeTrendingRanking(rows: TrendingRow[], opts?: { take?: number; skip?: number }): string[]
  export function getBestSellerProductIds(args: { productWhere: Prisma.ProductWhereInput; take?: number; skip?: number }): Promise<string[]>
  export function getTrendingProductIds(args: { productWhere: Prisma.ProductWhereInput; take?: number; skip?: number }): Promise<string[]>
  ```

- [ ] **Step 1: Write the failing test**

Create `tests/product-ranking.test.ts`:

```ts
import test from "node:test";
import assert from "node:assert/strict";
import {
  productRankWhere,
  discountOnlyWhere,
  computeTrendingRanking,
  withAnd,
  toAndArray,
  wibDateKey,
  type TrendingRow,
} from "../lib/product-ranking";

function order(id: string, createdAt: string, userId: string | null = null) {
  return {
    id,
    userId,
    customerEmail: null,
    customerPhone: null,
    createdAt: new Date(createdAt),
  };
}

test("toAndArray normalizes undefined / single / array", () => {
  assert.deepEqual(toAndArray(undefined), []);
  assert.deepEqual(toAndArray({ isActive: true }), [{ isActive: true }]);
  assert.deepEqual(toAndArray([{ isActive: true }]), [{ isActive: true }]);
});

test("withAnd appends without dropping existing AND", () => {
  const result = withAnd({ isActive: true, AND: [{ stock: { gt: 0 } }] }, { price: { gt: 0 } });
  assert.equal(result.isActive, true);
  assert.deepEqual(result.AND, [{ stock: { gt: 0 } }, { price: { gt: 0 } }]);
});

test("productRankWhere requires sellable price+stock for both variant shapes", () => {
  const result = productRankWhere({ isActive: true });
  const and = toAndArray(result.AND);
  assert.equal(and.length, 1);
  const or = (and[0] as { OR: unknown[] }).OR;
  assert.equal(or.length, 2);
  assert.deepEqual(or[0], { hasVariants: false, price: { gt: 0 }, stock: { gt: 0 } });
});

test("discountOnlyWhere matches active flash sale OR active promo toko", () => {
  const now = new Date("2026-07-19T00:00:00.000Z");
  const where = discountOnlyWhere(now);
  const or = (where as { OR: Array<Record<string, unknown>> }).OR;
  assert.equal(or.length, 2);
  // Flash sale branch: discountPrice set AND flashSaleEndsAt in the future
  assert.deepEqual(or[0], {
    AND: [{ discountPrice: { not: null } }, { flashSaleEndsAt: { gt: now } }],
  });
  // Promo Toko branch: an active discount item whose window contains `now`
  const promo = or[1] as { discountItems: { some: Record<string, unknown> } };
  assert.equal(promo.discountItems.some.isItemActive, true);
  assert.deepEqual(promo.discountItems.some.discount, {
    isActive: true,
    startsAt: { lte: now },
    endsAt: { gt: now },
  });
});

test("wibDateKey shifts UTC into WIB before taking the date", () => {
  // 2026-07-19T18:00Z is 2026-07-20 01:00 WIB → next day
  assert.equal(wibDateKey(new Date("2026-07-19T18:00:00.000Z")), "2026-07-20");
  assert.equal(wibDateKey(new Date("2026-07-19T02:00:00.000Z")), "2026-07-19");
});

test("computeTrendingRanking drops products bought on fewer than 2 distinct days", () => {
  const rows: TrendingRow[] = [
    // p1: 2 distinct WIB days, 2 buyers → qualifies
    { productId: "p1", quantity: 3, order: order("o1", "2026-07-10T03:00:00.000Z", "u1") },
    { productId: "p1", quantity: 2, order: order("o2", "2026-07-11T03:00:00.000Z", "u2") },
    // p2: high volume but a single day → filtered out
    { productId: "p2", quantity: 50, order: order("o3", "2026-07-10T03:00:00.000Z", "u3") },
  ];
  assert.deepEqual(computeTrendingRanking(rows), ["p1"]);
});

test("computeTrendingRanking ranks by score: sold*0.5 + buyers*0.3 + days*0.2", () => {
  const rows: TrendingRow[] = [
    // low: 2 sold, 2 buyers, 2 days → 1.0 + 0.6 + 0.4 = 2.0
    { productId: "low", quantity: 1, order: order("o1", "2026-07-10T03:00:00.000Z", "u1") },
    { productId: "low", quantity: 1, order: order("o2", "2026-07-11T03:00:00.000Z", "u2") },
    // high: 10 sold, 2 buyers, 2 days → 5.0 + 0.6 + 0.4 = 6.0
    { productId: "high", quantity: 5, order: order("o3", "2026-07-10T03:00:00.000Z", "u4") },
    { productId: "high", quantity: 5, order: order("o4", "2026-07-11T03:00:00.000Z", "u5") },
  ];
  assert.deepEqual(computeTrendingRanking(rows), ["high", "low"]);
});

test("computeTrendingRanking counts guest orders by email/phone, not as one buyer", () => {
  const rows: TrendingRow[] = [
    {
      productId: "p1",
      quantity: 1,
      order: { id: "o1", userId: null, customerEmail: "a@x.com", customerPhone: null, createdAt: new Date("2026-07-10T03:00:00.000Z") },
    },
    {
      productId: "p1",
      quantity: 1,
      order: { id: "o2", userId: null, customerEmail: "b@x.com", customerPhone: null, createdAt: new Date("2026-07-11T03:00:00.000Z") },
    },
  ];
  assert.deepEqual(computeTrendingRanking(rows), ["p1"]);
});

test("computeTrendingRanking applies skip/take after ranking", () => {
  const rows: TrendingRow[] = [];
  for (const [id, qty] of [["a", 30], ["b", 20], ["c", 10]] as const) {
    rows.push({ productId: id, quantity: qty, order: order(`${id}1`, "2026-07-10T03:00:00.000Z", `${id}u1`) });
    rows.push({ productId: id, quantity: qty, order: order(`${id}2`, "2026-07-11T03:00:00.000Z", `${id}u2`) });
  }
  assert.deepEqual(computeTrendingRanking(rows), ["a", "b", "c"]);
  assert.deepEqual(computeTrendingRanking(rows, { take: 2 }), ["a", "b"]);
  assert.deepEqual(computeTrendingRanking(rows, { skip: 1, take: 1 }), ["b"]);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx tsx --test tests/product-ranking.test.ts`
Expected: FAIL — cannot find module `../lib/product-ranking`.

- [ ] **Step 3: Create `lib/product-ranking.ts`**

This is a **move** of existing logic out of `lib/products.ts` (lines 344–355, 357–379, 430–432, 434–453, 455–480, 482–563, and the `discountOnly` block at 990–1016), with the trending scoring split into a pure core. Keep the logic byte-identical in behavior.

```ts
import type { OrderStatus, Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";

/**
 * Ranking + promo helpers dipakai BERSAMA oleh lib/products.ts dan
 * lib/search.ts. Modul terpisah supaya tidak ada circular import
 * (lib/products.ts sudah import dari lib/search.ts).
 *
 * Fungsi murni di atas, wrapper yang menyentuh DB di bawah.
 */

export const VALID_SALES_ORDER_STATUSES: OrderStatus[] = [
  "PAID",
  "PROCESSING",
  "READY_FOR_PICKUP",
  "SHIPPED",
  "DELIVERED",
];

export const TRENDING_WINDOW_DAYS = 14;
export const WIB_OFFSET_MS = 7 * 60 * 60 * 1000;

export function wibDateKey(date: Date) {
  return new Date(date.getTime() + WIB_OFFSET_MS).toISOString().slice(0, 10);
}

export function toAndArray(and: Prisma.ProductWhereInput["AND"]) {
  if (!and) return [];
  return Array.isArray(and) ? and : [and];
}

export function withAnd(
  where: Prisma.ProductWhereInput,
  condition: Prisma.ProductWhereInput,
): Prisma.ProductWhereInput {
  return {
    ...where,
    AND: [...toAndArray(where.AND), condition],
  };
}

/** Produk hanya layak masuk ranking kalau benar-benar bisa dibeli. */
export function productRankWhere(
  where: Prisma.ProductWhereInput,
): Prisma.ProductWhereInput {
  return withAnd(where, {
    OR: [
      { hasVariants: false, price: { gt: 0 }, stock: { gt: 0 } },
      {
        hasVariants: true,
        variants: {
          some: {
            deletedAt: null,
            isActive: true,
            price: { gt: 0 },
            stock: { gt: 0 },
          },
        },
      },
    ],
  });
}

/** Flash Sale aktif ATAU Promo Toko aktif pada `now`. */
export function discountOnlyWhere(now: Date = new Date()): Prisma.ProductWhereInput {
  return {
    OR: [
      // Flash Sale aktif: punya discountPrice + flashSaleEndsAt future
      {
        AND: [{ discountPrice: { not: null } }, { flashSaleEndsAt: { gt: now } }],
      },
      // Punya ProductDiscountItem aktif (Promo Toko)
      {
        discountItems: {
          some: {
            isItemActive: true,
            discount: {
              isActive: true,
              startsAt: { lte: now },
              endsAt: { gt: now },
            },
          },
        },
      },
    ],
  };
}

export type TrendingRow = {
  productId: string;
  quantity: number;
  order: {
    id: string;
    userId: string | null;
    customerEmail: string | null;
    customerPhone: string | null;
    createdAt: Date;
  };
};

/**
 * Inti skoring trending — MURNI, tanpa DB, supaya bisa di-unit-test.
 * Skor = totalSold*0.5 + pembeli unik*0.3 + hari-beli unik*0.2,
 * hanya produk yang dibeli minimal 2 hari berbeda (anti-spike).
 */
export function computeTrendingRanking(
  rows: TrendingRow[],
  { take, skip }: { take?: number; skip?: number } = {},
): string[] {
  const stats = new Map<
    string,
    { totalSold: number; buyerIds: Set<string>; purchaseDays: Set<string> }
  >();

  for (const row of rows) {
    const productStats = stats.get(row.productId) ?? {
      totalSold: 0,
      buyerIds: new Set<string>(),
      purchaseDays: new Set<string>(),
    };
    productStats.totalSold += row.quantity;
    productStats.buyerIds.add(
      row.order.userId ??
        row.order.customerEmail ??
        row.order.customerPhone ??
        `order:${row.order.id}`,
    );
    productStats.purchaseDays.add(wibDateKey(row.order.createdAt));
    stats.set(row.productId, productStats);
  }

  return Array.from(stats.entries())
    .map(([productId, productStats]) => {
      const purchaseFrequencyDays = productStats.purchaseDays.size;
      const trendingScore =
        productStats.totalSold * 0.5 +
        productStats.buyerIds.size * 0.3 +
        purchaseFrequencyDays * 0.2;
      return {
        productId,
        totalSold: productStats.totalSold,
        purchaseFrequencyDays,
        trendingScore,
      };
    })
    .filter((item) => item.totalSold > 0 && item.purchaseFrequencyDays >= 2)
    .sort((a, b) => {
      if (b.trendingScore !== a.trendingScore)
        return b.trendingScore - a.trendingScore;
      if (b.totalSold !== a.totalSold) return b.totalSold - a.totalSold;
      return b.purchaseFrequencyDays - a.purchaseFrequencyDays;
    })
    .slice(skip ?? 0, typeof take === "number" ? (skip ?? 0) + take : undefined)
    .map((item) => item.productId);
}

/** Urutan produk by penjualan asli (agregasi OrderItem). */
export async function getBestSellerProductIds({
  productWhere,
  take,
  skip,
}: {
  productWhere: Prisma.ProductWhereInput;
  take?: number;
  skip?: number;
}) {
  const rows = await prisma.orderItem.groupBy({
    by: ["productId"],
    where: {
      order: {
        paymentStatus: "PAID",
        status: { in: VALID_SALES_ORDER_STATUSES },
      },
      product: productRankWhere(productWhere),
    },
    _sum: { quantity: true },
    orderBy: { _sum: { quantity: "desc" } },
    ...(typeof take === "number" ? { take } : {}),
    ...(typeof skip === "number" && skip > 0 ? { skip } : {}),
  });

  return rows.map((row) => row.productId);
}

/** Urutan produk by skor trending 14 hari terakhir. */
export async function getTrendingProductIds({
  productWhere,
  take,
  skip,
}: {
  productWhere: Prisma.ProductWhereInput;
  take?: number;
  skip?: number;
}) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - TRENDING_WINDOW_DAYS);

  const rows = await prisma.orderItem.findMany({
    where: {
      order: {
        createdAt: { gte: cutoff },
        paymentStatus: "PAID",
        status: { in: VALID_SALES_ORDER_STATUSES },
      },
      product: productRankWhere(productWhere),
    },
    select: {
      productId: true,
      quantity: true,
      order: {
        select: {
          id: true,
          userId: true,
          customerEmail: true,
          customerPhone: true,
          createdAt: true,
        },
      },
    },
  });

  return computeTrendingRanking(rows, { take, skip });
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx tsx --test tests/product-ranking.test.ts`
Expected: PASS (9 tests).

- [ ] **Step 5: Typecheck**

Run: `npx tsc --noEmit`
Expected: no new errors. (This repo has 2 pre-existing unrelated errors in `app/api/admin/reset-all/route.ts` referencing `tx.chatMessage`/`tx.chatThread` — ignore those, do not fix them.)

- [ ] **Step 6: Commit**

```bash
git add lib/product-ranking.ts tests/product-ranking.test.ts
git commit -m "feat(ranking): shared product-ranking module with pure, tested scoring cores"
```

---

## Task 2: Rewire `lib/products.ts` onto the shared module (behavior-preserving)

**Files:**
- Modify: `lib/products.ts`

**Interfaces:**
- Consumes: everything exported by `lib/product-ranking.ts` (Task 1).
- Produces: no new exports. `getProducts` behavior must be **identical** — this is a pure move-and-rewire.

- [ ] **Step 1: Add the import**

At the top of `lib/products.ts`, alongside the existing `import { productSearchWhere } from "@/lib/search";`, add:

```ts
import {
  VALID_SALES_ORDER_STATUSES,
  TRENDING_WINDOW_DAYS,
  WIB_OFFSET_MS,
  wibDateKey,
  toAndArray,
  withAnd,
  productRankWhere,
  discountOnlyWhere,
  getBestSellerProductIds,
  getTrendingProductIds,
} from "@/lib/product-ranking";
```

- [ ] **Step 2: Delete the now-duplicated definitions**

Delete these from `lib/products.ts` (they now live in `lib/product-ranking.ts`). Match by literal content — line numbers may have drifted:

1. `const VALID_SALES_ORDER_STATUSES: OrderStatus[] = [ ... ];` (was ~344–351)
2. `const TRENDING_WINDOW_DAYS = 14;` and `const WIB_OFFSET_MS = 7 * 60 * 60 * 1000;` (was ~353, ~356) — **keep** `NEW_PRODUCT_WINDOW_DAYS` and `SEARCH_POPULAR_WINDOW_DAYS`, they are not moving.
3. `function toAndArray(...)` and `function withAnd(...)` (was ~365–379)
4. `function wibDateKey(date: Date) { ... }` (was ~430–432)
5. `function productRankWhere(...)` (was ~434–453)
6. `async function getBestSellerProductIds({ ... })` (was ~455–480)
7. `async function getTrendingProductIds({ ... })` (was ~482–563)

Keep `isOrderDrivenPopularFilter` in `lib/products.ts` — it is products-specific (it maps the `PopularFilter` enum, which search does not use).

**IMPORTANT — the moved symbols are still used by code that STAYS in `lib/products.ts`.** Deleting the definitions without the Step 1 import will break the build. Verified current usage sites (line numbers may drift; the point is they exist):
- `WIB_OFFSET_MS` → used by `startOfWibDay` (~381, ~387) and `startOfWibWeek` (~392, ~400), both of which stay.
- `VALID_SALES_ORDER_STATUSES` → also used at ~308 (outside the moved functions).
- `productRankWhere` → also used at ~579 and ~617.
- `withAnd` → also used at ~618, ~820, ~910.
- `toAndArray` → used by `withAnd` only, but export it anyway (the test covers it).

After deleting `VALID_SALES_ORDER_STATUSES`, the type `OrderStatus` becomes unused in this file. Change the import at line 11 from:

```ts
import type { OrderStatus, Prisma } from "@prisma/client";
```

to:

```ts
import type { Prisma } from "@prisma/client";
```

If `npm run lint` or `tsc` reports any other symbol as unused or undefined after the move, fix it the same way — the goal is zero new errors with **no behavior change**.

- [ ] **Step 3: Replace the inline `discountOnly` block with the shared helper**

Find this block (was ~990–1016):

```ts
  if (discountOnly) {
    const now = new Date();
    and.push({
      OR: [
        // Flash Sale aktif: punya discountPrice + flashSaleEndsAt future
        {
          AND: [
            { discountPrice: { not: null } },
            { flashSaleEndsAt: { gt: now } },
          ],
        },
        // Punya ProductDiscountItem aktif (Promo Toko)
        {
          discountItems: {
            some: {
              isItemActive: true,
              discount: {
                isActive: true,
                startsAt: { lte: now },
                endsAt: { gt: now },
              },
            },
          },
        },
      ],
    });
  }
```

Replace with:

```ts
  if (discountOnly) {
    and.push(discountOnlyWhere());
  }
```

- [ ] **Step 4: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no new errors, 0 lint errors.

- [ ] **Step 5: Verify `/api/products` behavior is unchanged**

Start (or reuse) the dev server for this worktree, then compare the three order-driven filters against real data. A dev server for this worktree runs on port **3022** (`preview_start` with name `listing-pr2-filters`). Run via Bash:

```bash
curl -s "http://localhost:3022/api/products?limit=5&popular=best-seller" | head -c 400
curl -s "http://localhost:3022/api/products?limit=5&popular=trending" | head -c 400
curl -s "http://localhost:3022/api/products?limit=5&discountOnly=true" | head -c 400
```

Expected: all three return HTTP 200 JSON with an `items` array (each may legitimately be empty if the Preview DB has no matching data — what matters is **no error** and the same shape as before the refactor). Record the actual output in your report.

- [ ] **Step 6: Commit**

```bash
git add lib/products.ts
git commit -m "refactor(products): source ranking + discount helpers from shared module"
```

---

## Task 3: `lib/search.ts` — visibility fix, deterministic order, and `discountOnly`

**Files:**
- Modify: `lib/search.ts`

**Interfaces:**
- Consumes: `discountOnlyWhere` from `lib/product-ranking.ts` (Task 1); `productIsVisibleWhere` from `@/lib/product/admin-product-form` (existing, returns `{ creationState: "ready" }`; that module imports only `prisma` + `./product-video`, so there is **no** import cycle).
- Produces: `SearchOptions.discountOnly?: boolean` and the same key on `NormalizedSearchOptions`, consumed by Task 5 (`/api/search`).

- [ ] **Step 1: Add the imports**

At the top of `lib/search.ts`, add:

```ts
import { discountOnlyWhere } from "@/lib/product-ranking";
import { productIsVisibleWhere } from "@/lib/product/admin-product-form";
```

- [ ] **Step 2: Add `discountOnly` to the options types**

Find:

```ts
export interface SearchOptions {
  q?: string;
  categorySlug?: string[];
  brandSlug?: string[];
  minPrice?: number;
  maxPrice?: number;
  inStock?: boolean;
  minRating?: number;
  sort?: SearchSort;
  page?: number;
  perPage?: number;
}
```

Replace with:

```ts
export interface SearchOptions {
  q?: string;
  categorySlug?: string[];
  brandSlug?: string[];
  minPrice?: number;
  maxPrice?: number;
  inStock?: boolean;
  minRating?: number;
  discountOnly?: boolean;
  sort?: SearchSort;
  page?: number;
  perPage?: number;
}
```

Then find:

```ts
export type NormalizedSearchOptions = Required<
  Pick<SearchOptions, "q" | "categorySlug" | "brandSlug" | "sort" | "page" | "perPage">
> &
  Pick<SearchOptions, "minPrice" | "maxPrice" | "inStock" | "minRating">;
```

Replace with:

```ts
export type NormalizedSearchOptions = Required<
  Pick<SearchOptions, "q" | "categorySlug" | "brandSlug" | "sort" | "page" | "perPage">
> &
  Pick<SearchOptions, "minPrice" | "maxPrice" | "inStock" | "minRating" | "discountOnly">;
```

- [ ] **Step 3: Thread `discountOnly` through `searchProducts()`**

In `searchProducts`, find:

```ts
  const {
    q = "",
    categorySlug = [],
    brandSlug = [],
    minPrice,
    maxPrice,
    inStock,
    minRating,
    sort = "relevance",
    page = 1,
    perPage = 24,
  } = opts;
```

Replace with:

```ts
  const {
    q = "",
    categorySlug = [],
    brandSlug = [],
    minPrice,
    maxPrice,
    inStock,
    minRating,
    discountOnly,
    sort = "relevance",
    page = 1,
    perPage = 24,
  } = opts;
```

Then find:

```ts
  const normalized = {
    q,
    categorySlug,
    brandSlug,
    minPrice,
    maxPrice,
    inStock,
    minRating,
    sort,
    page,
    perPage: limit,
  };
```

Replace with:

```ts
  const normalized = {
    q,
    categorySlug,
    brandSlug,
    minPrice,
    maxPrice,
    inStock,
    minRating,
    discountOnly,
    sort,
    page,
    perPage: limit,
  };
```

- [ ] **Step 4: Fix visibility + add the discount filter in the inline where builder**

Inside `searchProductsFromDb`, find:

```ts
  const where: Prisma.ProductWhereInput = {
    isActive: true,
    ...(candidateIds ? { id: { in: candidateIds } } : {}),
    ...(opts.categorySlug.length > 0 ? { category: { slug: { in: opts.categorySlug } } } : {}),
    ...(opts.brandSlug.length > 0 ? { brand: { slug: { in: opts.brandSlug } } } : {}),
  };
```

Replace with:

```ts
  const where: Prisma.ProductWhereInput = {
    isActive: true,
    // Produk yang masih setengah jadi (creationState "creating") TIDAK boleh
    // bocor ke pelanggan. /api/products sudah pakai guard ini; search belum,
    // jadi produk stuck bisa muncul di /search. Samakan.
    ...productIsVisibleWhere(),
    ...(candidateIds ? { id: { in: candidateIds } } : {}),
    ...(opts.categorySlug.length > 0 ? { category: { slug: { in: opts.categorySlug } } } : {}),
    ...(opts.brandSlug.length > 0 ? { brand: { slug: { in: opts.brandSlug } } } : {}),
  };
```

Then find:

```ts
  const andFilters = [priceWhere, stockWhere, ratingWhere].filter(
    (f): f is Prisma.ProductWhereInput => Boolean(f),
  );
  if (andFilters.length > 0) where.AND = andFilters;
```

Replace with:

```ts
  const discountWhere: Prisma.ProductWhereInput | undefined = opts.discountOnly
    ? discountOnlyWhere()
    : undefined;

  const andFilters = [priceWhere, stockWhere, ratingWhere, discountWhere].filter(
    (f): f is Prisma.ProductWhereInput => Boolean(f),
  );
  if (andFilters.length > 0) where.AND = andFilters;
```

- [ ] **Step 5: Give the 2000-row cap a deterministic order**

Find:

```ts
  const products = await prisma.product.findMany({
    where,
    include: getProductSearchInclude(),
    take: candidateIds ? undefined : 2000,
  });
```

Replace with:

```ts
  // NOTE: tanpa orderBy, `take: 2000` mengambil 2000 baris ARBITRER — begitu
  // katalog lewat 2000 produk, hasilnya jadi non-deterministik. Beri urutan
  // tetap (terbaru dulu) supaya potongannya stabil & bisa dijelaskan.
  const products = await prisma.product.findMany({
    where,
    include: getProductSearchInclude(),
    orderBy: [{ createdAt: "desc" }, { id: "asc" }],
    take: candidateIds ? undefined : 2000,
  });
```

- [ ] **Step 6: Tighten the discount filter after mapping**

The `where`-level filter can admit a variant product whose computed effective price is not actually lower (see spec §4.6). Make the result match the card badge exactly.

Find:

```ts
  const docs = products.map((product) =>
    mapProductToSearchDoc(product as ProductForSearchDoc),
  );
```

Replace with:

```ts
  const allDocs = products.map((product) =>
    mapProductToSearchDoc(product as ProductForSearchDoc),
  );
  // `where` di atas sudah menyaring kasar; di sini disamakan persis dengan
  // badge diskon di kartu produk (butuh harga efektif yang benar-benar turun).
  const docs = opts.discountOnly
    ? allDocs.filter(
        (doc) => doc.discount_price !== null && doc.discount_price < doc.price_min,
      )
    : allDocs;
```

- [ ] **Step 7: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no new errors, 0 lint errors.

- [ ] **Step 8: Commit**

```bash
git add lib/search.ts
git commit -m "fix(search): hide unfinished products, deterministic row cap, add discountOnly filter"
```

---

## Task 4: `lib/search.ts` — real sales-based `best_seller` + new `trending` sort

**Files:**
- Modify: `lib/search.ts`

**Interfaces:**
- Consumes: `getBestSellerProductIds`, `getTrendingProductIds` from `lib/product-ranking.ts` (Task 1); the `where` built in Task 3.
- Produces: `SearchSort` gains `"trending"`, consumed by Task 5.

**Design note (deliberate deviation — do not "fix" this):** `lib/products.ts` returns *only* products that have sales for `best-seller`/`trending`, because it re-queries `id: { in: rankedIds }`. In the search stack, sort and filter are separate concerns and a sort must never remove results (otherwise `sort=best_seller` combined with a price filter can yield a surprising empty page). So ranked products come first in rank order, and unranked products follow in the existing comparator's order.

- [ ] **Step 1: Add `"trending"` to the sort union**

Find:

```ts
export type SearchSort =
  | "relevance"
  | "price_asc"
  | "price_desc"
  | "newest"
  | "rating_desc"
  | "best_seller";
```

Replace with:

```ts
export type SearchSort =
  | "relevance"
  | "price_asc"
  | "price_desc"
  | "newest"
  | "rating_desc"
  | "best_seller"
  | "trending";
```

- [ ] **Step 2: Build the rank map before sorting**

Inside `searchProductsFromDb`, immediately AFTER the `docs` assignment from Task 3 Step 6 and BEFORE the `let items: ProductSearchDoc[];` declaration, insert:

```ts
  // best_seller & trending di-rank dari data penjualan asli (OrderItem),
  // bukan proksi review_count. Pakai `where` yang sama supaya ranking
  // menghormati filter aktif.
  let salesRank: Map<string, number> | null = null;
  if (opts.sort === "best_seller" || opts.sort === "trending") {
    const rankedIds =
      opts.sort === "trending"
        ? await getTrendingProductIds({ productWhere: where })
        : await getBestSellerProductIds({ productWhere: where });
    if (rankedIds.length > 0) {
      salesRank = new Map(rankedIds.map((id, index) => [id, index]));
    }
  }
```

- [ ] **Step 3: Apply the rank map in the sort branch**

Find:

```ts
  let items: ProductSearchDoc[];
  if (candidateIds && opts.sort === "relevance") {
    const orderMap = new Map(candidateIds.map((id, i) => [id, i]));
    items = [...docs].sort(
      (a, b) => (orderMap.get(a.id) ?? Infinity) - (orderMap.get(b.id) ?? Infinity),
    );
  } else {
    items = [...docs].sort(compareSearchItems(opts.sort, q));
  }
```

Replace with:

```ts
  let items: ProductSearchDoc[];
  if (candidateIds && opts.sort === "relevance") {
    const orderMap = new Map(candidateIds.map((id, i) => [id, i]));
    items = [...docs].sort(
      (a, b) => (orderMap.get(a.id) ?? Infinity) - (orderMap.get(b.id) ?? Infinity),
    );
  } else if (salesRank) {
    const rank = salesRank;
    const tiebreak = compareSearchItems(opts.sort, q);
    // Produk tanpa penjualan TIDAK dibuang — didorong ke ekor. Sort tidak
    // boleh menghilangkan hasil (beda dengan /api/products yang menggabung
    // filter+sort dalam satu param `popular`).
    items = [...docs].sort((a, b) => {
      const rankA = rank.get(a.id) ?? Infinity;
      const rankB = rank.get(b.id) ?? Infinity;
      if (rankA !== rankB) return rankA - rankB;
      return tiebreak(a, b);
    });
  } else {
    items = [...docs].sort(compareSearchItems(opts.sort, q));
  }
```

- [ ] **Step 4: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no new errors, 0 lint errors. (Adding `"trending"` to the union needs no new branch in `compareSearchItems` — it falls through to the default relevance return, which is only ever used as a tiebreak here.)

- [ ] **Step 5: Commit**

```bash
git add lib/search.ts
git commit -m "feat(search): rank best_seller by real sales and add trending sort"
```

---

## Task 5: `/api/search` — accept `discount_only` and `sort=trending`

**Files:**
- Modify: `app/api/search/route.ts`

**Interfaces:**
- Consumes: `SearchSort` (now including `"trending"`) and `SearchOptions.discountOnly` from Tasks 3–4.

- [ ] **Step 1: Add `trending` to the accepted sorts**

Find:

```ts
const VALID_SORT: SearchSort[] = [
  "relevance",
  "price_asc",
  "price_desc",
  "newest",
  "rating_desc",
  "best_seller",
];
```

Replace with:

```ts
const VALID_SORT: SearchSort[] = [
  "relevance",
  "price_asc",
  "price_desc",
  "newest",
  "rating_desc",
  "best_seller",
  "trending",
];
```

- [ ] **Step 2: Parse `discount_only`**

Find:

```ts
      inStock: sp.get("in_stock") === "true",
      minRating: sp.get("min_rating")
        ? Number(sp.get("min_rating"))
        : undefined,
```

Replace with:

```ts
      inStock: sp.get("in_stock") === "true",
      minRating: sp.get("min_rating")
        ? Number(sp.get("min_rating"))
        : undefined,
      discountOnly: sp.get("discount_only") === "true",
```

- [ ] **Step 3: Update the route's doc comment**

Find:

```ts
 *   in_stock       "true" | "false"
 *   min_rating     number 1–5
 *   sort           relevance | price_asc | price_desc | newest | rating_desc | best_seller
```

Replace with:

```ts
 *   in_stock       "true" | "false"
 *   min_rating     number 1–5
 *   discount_only  "true" | "false" — hanya produk Flash Sale / Promo Toko aktif
 *   sort           relevance | price_asc | price_desc | newest | rating_desc | best_seller | trending
```

- [ ] **Step 4: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no new errors, 0 lint errors.

- [ ] **Step 5: Commit**

```bash
git add app/api/search/route.ts
git commit -m "feat(api): expose discount_only filter and trending sort on /api/search"
```

---

## Task 6: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Static checks**

```bash
npx tsc --noEmit
npm run lint
npm test
```
Expected: tsc shows only the 2 pre-existing `app/api/admin/reset-all/route.ts` errors; lint 0 errors; all tests pass including the 9 new `tests/product-ranking.test.ts` cases.

- [ ] **Step 2: Live API verification**

Ensure the dev server for this worktree is running (`preview_start` with name `listing-pr2-filters`, port 3022). Prefer `curl` via Bash over browser tooling. For each command, record the `total` value and the first item's name:

```bash
# baseline: unfiltered browse still works
curl -s "http://localhost:3022/api/search?per_page=3" | head -c 300
# new: discount-only
curl -s "http://localhost:3022/api/search?per_page=3&discount_only=true" | head -c 300
# new: trending sort
curl -s "http://localhost:3022/api/search?per_page=3&sort=trending" | head -c 300
# changed: best_seller now sales-based
curl -s "http://localhost:3022/api/search?per_page=3&sort=best_seller" | head -c 300
# combination: sort must never empty the page
curl -s "http://localhost:3022/api/search?per_page=3&sort=best_seller&min_price=1000000" | head -c 300
```

Expected: every call returns HTTP 200 JSON. `discount_only=true` must return a `total` **less than or equal to** the unfiltered total. The `sort=best_seller&min_price=...` combination must still return items (proving sort does not drop results) unless the price filter alone genuinely matches nothing — verify that by running the same URL without `sort`.

- [ ] **Step 3: Verify the visibility fix**

Confirm no `creating`-state product can be returned. Run:

```bash
curl -s "http://localhost:3022/api/search?per_page=60" | grep -o '"total":[0-9]*'
```

Then compare against a direct count of ready+active products. If you have DB access via a script, prefer that; otherwise assert the weaker but still meaningful check that `/api/search`'s total is **≤** `/api/products`' total for an equivalent unfiltered query:

```bash
curl -s "http://localhost:3022/api/products?limit=1" | grep -o '"total":[0-9]*'
```

Record both numbers in your report and state explicitly whether search's total dropped after this change (it should drop by exactly the number of non-ready products, which may legitimately be 0 in the Preview DB).

- [ ] **Step 4: Confirm `/search` page still works end-to-end**

```bash
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3022/search?q=makanan"
curl -s "http://localhost:3022/api/search?q=makanan&per_page=3" | head -c 300
```
Expected: 200, and a sensible keyword result — confirming the trigram/candidate path was not broken by the where changes.

- [ ] **Step 5: Confirm diff scope**

```bash
git diff --name-only origin/main...HEAD
```
Expected exactly:
```
app/api/search/route.ts
docs/superpowers/plans/2026-07-19-listing-pr2-search-parity-backend.md
docs/superpowers/specs/2026-07-07-listing-desktop-etalase-design.md
lib/product-ranking.ts
lib/products.ts
lib/search.ts
tests/product-ranking.test.ts
```
Assert there is **no** `prisma/schema.prisma`, `flutter_app/**`, or any migration file. Note: `flutter_app/pubspec.yaml` may show as modified in `git status` from another session's work — it must **not** appear in this diff and must **not** be committed.

- [ ] **Step 6: Commit (if any notes were added)**

```bash
git commit -m "chore(search): PR2 verification notes" --allow-empty
```

---

## Self-Review (completed at authoring time)

- **Spec coverage (§4.4, §4.5, §4.6):** shared module avoiding the circular import → Task 1; `discountOnly` → Tasks 1, 3, 5; real best-seller → Tasks 1, 4; trending → Tasks 1, 4, 5; visibility bug (§4.5.1) → Task 3 Step 4; `take: 2000` determinism (§4.5.2) → Task 3 Step 5; the "don't edit dead `buildDbProductWhere`" gotcha (§4.6) → stated in Global Constraints and all edits target the inline builder; the discount post-map tightening (§4.6) → Task 3 Step 6; the trending-can-return-few fallback (§4.6) → solved by the push-to-tail design in Task 4.
- **Out of scope (deliberate):** the Meili branch (`searchProductsFromMeili`) gains nothing here — Meili is off, and `sold_count` would require a doc-shape change plus reindex; recorded in spec §11. `/products` frontend migration is PR3.
- **Placeholder scan:** none — every code step contains literal code.
- **Type/name consistency:** `TrendingRow`, `computeTrendingRanking`, `discountOnlyWhere`, `productRankWhere`, `getBestSellerProductIds`, `getTrendingProductIds` are defined in Task 1 and consumed with identical signatures in Tasks 2–4; `discountOnly` is added to both `SearchOptions` and `NormalizedSearchOptions` in Task 3 before Task 5 reads it; `"trending"` is added to `SearchSort` in Task 4 before Task 5 lists it in `VALID_SORT`.
