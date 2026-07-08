# Abandoned-Cart Cron Guardrail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the abandoned-cart cron (`GET /api/cron/abandoned-cart`) from sending push notifications for cart items that are no longer purchasable, or that are likely stale "ghost" rows left behind by a failed cart sync.

**Architecture:** Two independent guardrails run before the cron sends any push. Guardrail 1 reuses the existing stock/availability snapshot helper (`getCartStockSnapshots`, already used by `GET /api/cart`) to drop items whose product/variant is no longer purchasable. Guardrail 2 requires an item to be seen "eligible" across two consecutive hourly cron runs before it is actually notified — tracked via a new nullable `abandonedCandidateAt` column on `CartItem` that gets wiped every time the row is resynced from the client (because `PUT /api/cart` deletes and recreates every row on every sync). Both guardrails are implemented as small, pure, unit-tested functions in a new `lib/abandoned-cart-guardrail.ts`, then wired into the existing cron route.

**Tech Stack:** Next.js API route (`app/api/cron/abandoned-cart/route.ts`), Prisma (PostgreSQL), Node's built-in test runner (`node:test` via `tsx --test`), TypeScript.

## Global Constraints

- Do not modify `PUT /api/cart` (`app/api/cart/route.ts`) or `flutter_app/lib/state/cart_store.dart` — sync-mechanism fixes are explicitly out of scope for this plan (see spec's "Out of Scope" section).
- New `abandonedCandidateAt` column must be nullable, default `null`, no backfill.
- All abandoned-cart push notifications will now be delayed by roughly one cron cycle (~1 hour) — this is an accepted, intentional trade-off, not a bug to work around.
- Items dropped by Guardrail 1 (unavailable product/variant) must NOT have `notifiedAbandonedAt` or `abandonedCandidateAt` touched.
- Follow existing test convention: pure-function unit tests with `node:test` + `node:assert/strict`, no DB mocking (see `tests/cart-stock.test.ts` for the established style).
- Spec: `docs/superpowers/specs/2026-07-05-abandoned-cart-cron-guardrail-design.md`.

---

## Task 1: Add `abandonedCandidateAt` column to `CartItem`

**Files:**
- Modify: `prisma/schema.prisma` (model `CartItem`, currently at lines 236-261)
- Create: `prisma/migrations/20260705120000_add_abandoned_cart_candidate_at/migration.sql`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `CartItem.abandonedCandidateAt` (`DateTime | null` in Prisma Client types) — Task 3's cron route selects and updates this field.

- [ ] **Step 1: Read the current `CartItem` model to confirm line numbers haven't shifted**

Run: `grep -n "model CartItem" -A 26 prisma/schema.prisma`

Expected output (must match exactly before editing):

```prisma
model CartItem {
  id                  String    @id @default(cuid())
  userId              String
  user                User      @relation(fields: [userId], references: [id], onDelete: Cascade)
  productId           String
  variantId           String?
  variantLabel        String?
  name                String
  price               Int
  quantity            Int
  weightGram          Int       @default(500)
  imageUrl            String?
  stock               Int?
  // Track last abandoned-cart push notification — supaya cron tidak
  // spam user yang sama tiap jam. Set timestamp setelah push terkirim,
  // clear (set null) saat user checkout atau update cart.
  notifiedAbandonedAt DateTime?
  createdAt           DateTime  @default(now())
  updatedAt           DateTime  @updatedAt

  @@unique([userId, productId, variantId])
  @@index([userId])
  // Index untuk cron query: cari CartItem yang createdAt > 4 jam lalu
  // dan belum di-notify. WHERE notifiedAbandonedAt IS NULL AND createdAt < ...
  @@index([notifiedAbandonedAt, createdAt])
}
```

If the output differs, re-locate the model with `grep -n "model CartItem"` before continuing.

- [ ] **Step 2: Add the new column to the model**

Replace the block found in Step 1 with:

```prisma
model CartItem {
  id                    String    @id @default(cuid())
  userId                String
  user                  User      @relation(fields: [userId], references: [id], onDelete: Cascade)
  productId             String
  variantId             String?
  variantLabel          String?
  name                  String
  price                 Int
  quantity              Int
  weightGram            Int       @default(500)
  imageUrl              String?
  stock                 Int?
  // Track last abandoned-cart push notification — supaya cron tidak
  // spam user yang sama tiap jam. Set timestamp setelah push terkirim,
  // clear (set null) saat user checkout atau update cart.
  notifiedAbandonedAt   DateTime?
  // Tanda "pertama kali dicurigai abandoned" oleh cron — dipakai untuk
  // syarat 2-putaran-berturut sebelum benar-benar kirim notifikasi.
  // Reset otomatis jadi null setiap kali row ini disinkron ulang (row
  // lama di-delete, row baru dibuat oleh PUT /api/cart replace-total),
  // sehingga tidak perlu invalidasi manual.
  abandonedCandidateAt  DateTime?
  createdAt             DateTime  @default(now())
  updatedAt             DateTime  @updatedAt

  @@unique([userId, productId, variantId])
  @@index([userId])
  // Index untuk cron query: cari CartItem yang createdAt > 4 jam lalu
  // dan belum di-notify. WHERE notifiedAbandonedAt IS NULL AND createdAt < ...
  @@index([notifiedAbandonedAt, createdAt])
}
```

- [ ] **Step 3: Create the migration file**

Create `prisma/migrations/20260705120000_add_abandoned_cart_candidate_at/migration.sql`:

```sql
-- Tanda "pertama kali dicurigai abandoned" oleh cron abandoned-cart —
-- syarat 2-putaran-berturut sebelum kirim notifikasi. Nullable, tidak
-- perlu backfill.
ALTER TABLE "CartItem"
  ADD COLUMN IF NOT EXISTS "abandonedCandidateAt" TIMESTAMP(3);
```

- [ ] **Step 4: Validate the schema and regenerate Prisma Client**

Run: `npx prisma validate`
Expected: `The schema at prisma/schema.prisma is valid 🚀`

Run: `npx prisma generate`
Expected: completes with `✔ Generated Prisma Client` and no errors.

- [ ] **Step 5: Commit**

```bash
git add prisma/schema.prisma prisma/migrations/20260705120000_add_abandoned_cart_candidate_at
git commit -m "$(cat <<'EOF'
feat(db): tambah kolom abandonedCandidateAt di CartItem

Kolom nullable untuk syarat 2-putaran-berturut cron abandoned-cart
sebelum kirim notifikasi — beri row cart hantu (dari sync yang gagal)
kesempatan sembuh sendiri lewat resync sebelum benar-benar di-notify.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Pure guardrail helper functions (with tests)

**Files:**
- Create: `lib/abandoned-cart-guardrail.ts`
- Create: `tests/abandoned-cart-guardrail.test.ts`

**Interfaces:**
- Consumes: `cartStockKey`, `type CartStockSnapshot` from `lib/cart-stock.ts` (already exported — `cartStockKey(item: { productId: string; variantId: string | null })` returns `` `${productId}:${variantId ?? ""}` ``; `CartStockSnapshot` has fields `productId: string`, `variantId: string | null`, `isAvailable: boolean`).
- Produces (for Task 3):
  - `filterAvailableAbandonedCartItems<T extends { productId: string; variantId: string | null }>(items: T[], snapshots: CartStockSnapshot[]): T[]`
  - `splitAbandonedCartCandidates<T extends { id: string; abandonedCandidateAt: Date | null }>(items: T[]): { toMark: T[]; toNotify: T[] }`

- [ ] **Step 1: Write the failing tests**

Create `tests/abandoned-cart-guardrail.test.ts`:

```typescript
import assert from "node:assert/strict";
import test from "node:test";
import {
  filterAvailableAbandonedCartItems,
  splitAbandonedCartCandidates,
} from "@/lib/abandoned-cart-guardrail";
import type { CartStockSnapshot } from "@/lib/cart-stock";

function snapshot(overrides: Partial<CartStockSnapshot>): CartStockSnapshot {
  return {
    key: "prod-1:",
    productId: "prod-1",
    variantId: null,
    variantLabel: null,
    name: "Produk 1",
    requestedQuantity: 1,
    availableStock: 10,
    isAvailable: true,
    source: "product",
    ...overrides,
  };
}

test("filterAvailableAbandonedCartItems keeps only items whose snapshot is available", () => {
  const items = [
    { id: "item-1", productId: "prod-1", variantId: null },
    { id: "item-2", productId: "prod-2", variantId: null },
  ];
  const snapshots = [
    snapshot({ key: "prod-1:", productId: "prod-1", isAvailable: true }),
    snapshot({ key: "prod-2:", productId: "prod-2", isAvailable: false }),
  ];

  const result = filterAvailableAbandonedCartItems(items, snapshots);

  assert.equal(result.length, 1);
  assert.equal(result[0].id, "item-1");
});

test("filterAvailableAbandonedCartItems matches variant-specific items independently", () => {
  const items = [
    { id: "item-1", productId: "prod-1", variantId: "variant-a" },
    { id: "item-2", productId: "prod-1", variantId: "variant-b" },
  ];
  const snapshots = [
    snapshot({
      key: "prod-1:variant-a",
      productId: "prod-1",
      variantId: "variant-a",
      isAvailable: true,
      source: "variant",
    }),
    snapshot({
      key: "prod-1:variant-b",
      productId: "prod-1",
      variantId: "variant-b",
      isAvailable: false,
      source: "variant",
    }),
  ];

  const result = filterAvailableAbandonedCartItems(items, snapshots);

  assert.equal(result.length, 1);
  assert.equal(result[0].id, "item-1");
});

test("filterAvailableAbandonedCartItems drops items with no matching snapshot", () => {
  const items = [{ id: "item-1", productId: "prod-missing", variantId: null }];

  const result = filterAvailableAbandonedCartItems(items, []);

  assert.equal(result.length, 0);
});

test("splitAbandonedCartCandidates marks first-time-eligible items as candidates, not ready to notify", () => {
  const items = [
    { id: "item-1", abandonedCandidateAt: null },
    { id: "item-2", abandonedCandidateAt: null },
  ];

  const result = splitAbandonedCartCandidates(items);

  assert.equal(result.toMark.length, 2);
  assert.equal(result.toNotify.length, 0);
  assert.deepEqual(
    result.toMark.map((i) => i.id),
    ["item-1", "item-2"],
  );
});

test("splitAbandonedCartCandidates notifies items already marked as candidates in a prior run", () => {
  const items = [
    { id: "item-1", abandonedCandidateAt: new Date("2026-07-05T09:00:00Z") },
    { id: "item-2", abandonedCandidateAt: null },
  ];

  const result = splitAbandonedCartCandidates(items);

  assert.equal(result.toNotify.length, 1);
  assert.equal(result.toNotify[0].id, "item-1");
  assert.equal(result.toMark.length, 1);
  assert.equal(result.toMark[0].id, "item-2");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npx tsx --test tests/abandoned-cart-guardrail.test.ts`
Expected: FAIL — `Cannot find module '@/lib/abandoned-cart-guardrail'` (module does not exist yet).

- [ ] **Step 3: Implement the minimal code to make the tests pass**

Create `lib/abandoned-cart-guardrail.ts`:

```typescript
import { cartStockKey, type CartStockSnapshot } from "@/lib/cart-stock";

/**
 * Guardrail 1: buang item cart yang produk/variannya sudah tidak bisa
 * dibeli (nonaktif, dihapus, atau stok habis) sebelum masuk pertimbangan
 * notifikasi abandoned-cart.
 */
export function filterAvailableAbandonedCartItems<
  T extends { productId: string; variantId: string | null },
>(items: T[], snapshots: CartStockSnapshot[]): T[] {
  const availableKeys = new Set(
    snapshots.filter((snapshot) => snapshot.isAvailable).map((snapshot) => cartStockKey(snapshot)),
  );
  return items.filter((item) => availableKeys.has(cartStockKey(item)));
}

export type AbandonedCartCandidateSplit<T> = {
  toMark: T[];
  toNotify: T[];
};

/**
 * Guardrail 2: item yang baru pertama kali terlihat eligible (belum ada
 * abandonedCandidateAt) ditandai sebagai kandidat dulu, belum
 * dinotifikasi. Item yang sudah jadi kandidat sejak run sebelumnya (dan
 * masih ada/eligible) baru masuk batch notifikasi.
 */
export function splitAbandonedCartCandidates<
  T extends { abandonedCandidateAt: Date | null },
>(items: T[]): AbandonedCartCandidateSplit<T> {
  const toMark: T[] = [];
  const toNotify: T[] = [];
  for (const item of items) {
    if (item.abandonedCandidateAt == null) {
      toMark.push(item);
    } else {
      toNotify.push(item);
    }
  }
  return { toMark, toNotify };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npx tsx --test tests/abandoned-cart-guardrail.test.ts`
Expected: all 5 tests pass, e.g. `# pass 5`, `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add lib/abandoned-cart-guardrail.ts tests/abandoned-cart-guardrail.test.ts
git commit -m "$(cat <<'EOF'
feat(cart): pure guardrail helpers untuk cron abandoned-cart

filterAvailableAbandonedCartItems (buang produk/varian yang sudah
tidak bisa dibeli) dan splitAbandonedCartCandidates (syarat
2-putaran-berturut) — pure functions, diuji terpisah dari DB/cron
route mengikuti pola tests/cart-stock.test.ts.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Wire both guardrails into the cron route

**Files:**
- Modify: `app/api/cron/abandoned-cart/route.ts` (full file, currently 118 lines)

**Interfaces:**
- Consumes:
  - `filterAvailableAbandonedCartItems`, `splitAbandonedCartCandidates` from `lib/abandoned-cart-guardrail.ts` (Task 2).
  - `getCartStockSnapshots(items: CartStockInput[]): Promise<CartStockSnapshot[]>` from `lib/cart-stock-server.ts` (pre-existing; `CartStockInput` requires `productId`, `variantId`, `variantLabel`, `name`, `quantity`).
  - `CartItem.abandonedCandidateAt` (Task 1).
- Produces: nothing consumed by later tasks — this is the last task in the plan.

- [ ] **Step 1: Read the current route file to confirm it matches expectations**

Run: `cat app/api/cron/abandoned-cart/route.ts`

Confirm it matches the 118-line version with the `GET` handler doing: header auth check, `prisma.cartItem.findMany` with `select: { id, userId, name, imageUrl, createdAt }`, group-by-user loop, `Promise.allSettled` dispatch, final JSON response with `{ ok, checked, usersTotal, notified, failedUsers }`.

- [ ] **Step 2: Replace the full route file**

Replace the entire contents of `app/api/cron/abandoned-cart/route.ts` with:

```typescript
/**
 * GET /api/cron/abandoned-cart — Vercel cron (hourly)
 *
 * Cari CartItem yang sudah lebih dari 4 jam di cart dan belum di-checkout
 * (createdAt < now - 4h, notifiedAbandonedAt IS NULL). Group by userId,
 * send 1 push reminder per user dengan preview item teratas.
 *
 * Guardrail sebelum kirim (docs/superpowers/specs/2026-07-05-abandoned-cart-cron-guardrail-design.md):
 * 1. Skip item yang produk/variannya sudah tidak bisa dibeli (nonaktif,
 *    dihapus, atau stok habis) — dicek lewat getCartStockSnapshots(),
 *    fungsi yang sama dipakai GET /api/cart.
 * 2. Syarat 2-putaran-berturut: item yang baru pertama kali terlihat
 *    eligible ditandai `abandonedCandidateAt` dulu, BELUM dinotifikasi.
 *    Baru dinotifikasi di run berikutnya kalau masih eligible & belum
 *    disinkron ulang (row abandonedCandidateAt reset otomatis tiap kali
 *    PUT /api/cart replace-total membuat ulang row ini). Ini menambah
 *    jeda ~1 jam ke SEMUA notifikasi abandoned-cart secara sengaja —
 *    beri kesempatan row cart "hantu" (dari sync yang gagal) sembuh
 *    sendiri sebelum benar-benar dinotifikasi.
 *
 * Anti-spam:
 * - Skip item yang sudah pernah di-notify (notifiedAbandonedAt != null).
 * - Skip item lebih tua dari 7 hari (out-of-mind, bukan intent aktif).
 * - 1 push per user per cron run (bukan per item).
 * - Tag "abandoned-cart-{userId}" — push replace di device, tidak stack.
 *
 * Trigger:
 * - Schedule di vercel.json: "0 * * * *" (setiap jam tepat).
 * - Auth: Vercel auto-injects CRON_SECRET header — verify di handler.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getCartStockSnapshots } from "@/lib/cart-stock-server";
import {
  filterAvailableAbandonedCartItems,
  splitAbandonedCartCandidates,
} from "@/lib/abandoned-cart-guardrail";
import {
  ABANDONED_CART_DELAY_MS,
  ABANDONED_CART_MAX_AGE_MS,
  sendAbandonedCartPush,
} from "@/lib/push-marketing";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: NextRequest) {
  // Verify Vercel cron header — public route, but only Vercel infra
  // can set this header. Production safety.
  const authHeader = request.headers.get("authorization");
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const now = Date.now();
  const oldestEligible = new Date(now - ABANDONED_CART_MAX_AGE_MS);
  const newestEligible = new Date(now - ABANDONED_CART_DELAY_MS);

  // Fetch eligible cart items, grouped by userId.
  const items = await prisma.cartItem.findMany({
    where: {
      notifiedAbandonedAt: null,
      createdAt: {
        gte: oldestEligible,
        lte: newestEligible,
      },
    },
    select: {
      id: true,
      userId: true,
      name: true,
      imageUrl: true,
      createdAt: true,
      productId: true,
      variantId: true,
      variantLabel: true,
      quantity: true,
      abandonedCandidateAt: true,
    },
    orderBy: { createdAt: "asc" },
  });

  if (items.length === 0) {
    return NextResponse.json({
      ok: true,
      message: "No abandoned cart items eligible.",
      checked: 0,
      skippedUnavailable: 0,
      markedAsCandidate: 0,
      usersTotal: 0,
      notified: 0,
      failedUsers: 0,
    });
  }

  // Guardrail 1 — buang item yang produk/variannya sudah tidak bisa dibeli.
  const snapshots = await getCartStockSnapshots(
    items.map((item) => ({
      productId: item.productId,
      variantId: item.variantId,
      variantLabel: item.variantLabel,
      name: item.name,
      quantity: item.quantity,
    })),
  );
  const availableItems = filterAvailableAbandonedCartItems(items, snapshots);
  const skippedUnavailable = items.length - availableItems.length;

  // Guardrail 2 — syarat 2-putaran-berturut sebelum benar-benar notify.
  const { toMark, toNotify } = splitAbandonedCartCandidates(availableItems);

  if (toMark.length > 0) {
    await prisma.cartItem
      .updateMany({
        where: { id: { in: toMark.map((item) => item.id) } },
        data: { abandonedCandidateAt: new Date() },
      })
      .catch(() => {});
  }

  if (toNotify.length === 0) {
    return NextResponse.json({
      ok: true,
      checked: items.length,
      skippedUnavailable,
      markedAsCandidate: toMark.length,
      usersTotal: 0,
      notified: 0,
      failedUsers: 0,
    });
  }

  // Group by userId — 1 push per user dengan preview item teratas.
  const byUser = new Map<
    string,
    Array<{ id: string; name: string; imageUrl: string | null }>
  >();
  for (const item of toNotify) {
    if (!byUser.has(item.userId)) byUser.set(item.userId, []);
    byUser.get(item.userId)!.push({
      id: item.id,
      name: item.name,
      imageUrl: item.imageUrl,
    });
  }

  let notified = 0;
  const failedUsers: string[] = [];

  // Dispatch parallel per user.
  await Promise.allSettled(
    Array.from(byUser.entries()).map(async ([userId, userItems]) => {
      const ok = await sendAbandonedCartPush(userId, userItems);
      if (ok) {
        notified += 1;
        // Mark all eligible items for this user as notified.
        await prisma.cartItem
          .updateMany({
            where: {
              id: { in: userItems.map((i) => i.id) },
            },
            data: {
              notifiedAbandonedAt: new Date(),
            },
          })
          .catch(() => {});
      } else {
        failedUsers.push(userId);
      }
    }),
  );

  return NextResponse.json({
    ok: true,
    checked: items.length,
    skippedUnavailable,
    markedAsCandidate: toMark.length,
    usersTotal: byUser.size,
    notified,
    failedUsers: failedUsers.length,
  });
}
```

- [ ] **Step 3: Typecheck**

Run: `npx tsc --noEmit`
Expected: no output, exit code 0 (no type errors).

- [ ] **Step 4: Run the full test suite to confirm no regressions**

Run: `npm test`
Expected: all tests pass, including the 5 new tests from Task 2 and the pre-existing `tests/cart-stock.test.ts` and `tests/push-notifications.test.ts` suites.

- [ ] **Step 5: Commit**

```bash
git add app/api/cron/abandoned-cart/route.ts
git commit -m "$(cat <<'EOF'
fix(cron): terapkan guardrail stok & 2-putaran-berturut di abandoned-cart

Cron sekarang skip item yang produknya sudah tidak bisa dibeli, dan
mensyaratkan item terlihat eligible di 2 run cron berturut sebelum
benar-benar kirim notifikasi — beri kesempatan row cart hantu (dari
sync gagal) sembuh sendiri via resync sebelum dinotifikasi. Menambah
jeda ~1 jam ke semua notifikasi abandoned-cart (disengaja).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** Guardrail 1 (skip unavailable product/variant, reuse `getCartStockSnapshots`) → Task 3 wiring + Task 2 pure filter. Guardrail 2 (2-consecutive-run confirmation, `abandonedCandidateAt` column, auto-reset via resync) → Task 1 (schema) + Task 2 (pure split) + Task 3 (wiring). Observability (response JSON breakdown: `checked`, `skippedUnavailable`, `markedAsCandidate`, `notified`) → Task 3. Error handling (`.catch(() => {})`, `Promise.allSettled`) → preserved from existing code in Task 3. Testing plan (pure-function unit tests, no DB mocking, matches `cart-stock.test.ts` style) → Task 2. Out-of-scope items (sync mechanism, `loadFromServer()`) → intentionally not covered by any task, per Global Constraints.
- **Placeholder scan:** no TBD/TODO; every step has complete, runnable code or exact commands with expected output.
- **Type consistency:** `filterAvailableAbandonedCartItems<T extends { productId: string; variantId: string | null }>` in Task 2 matches how Task 3 calls it (`items` from `prisma.cartItem.findMany` has `productId: string` and `variantId: string | null` per Prisma schema). `splitAbandonedCartCandidates<T extends { abandonedCandidateAt: Date | null }>` matches Task 3's `availableItems` (same `items` shape, includes `abandonedCandidateAt` from the Task 1 column, selected in Task 3's `findMany`). `AbandonedCartCandidateSplit<T>` field names `toMark`/`toNotify` used consistently in Task 2's implementation, tests, and Task 3's destructuring (`const { toMark, toNotify } = ...`).
