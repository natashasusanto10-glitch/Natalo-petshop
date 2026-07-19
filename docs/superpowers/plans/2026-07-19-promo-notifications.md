# Notifikasi Promo (Voucher & Diskon Produk) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Saat admin membuat Voucher (termasuk gratis ongkir) atau Diskon Produk "Promo Toko" dengan checkbox "Beri tahu pelanggan", semua user dapat notifikasi lonceng + push dengan gambar yang tepat dan routing presisi; promo terjadwal dikirim tepat saat mulai.

**Architecture:** Ikuti pola `lib/feed/publish-push.ts` — satu baris `Announcement` ber-`segment:"all"` (tampil di lonceng semua user) + push batch ke `resolveSegmentUserIds("all")`. Modul baru `lib/push-promo.ts` dengan builder murni teruji + fungsi dispatch ber-klaim-atomik anti-dobel. Cron per jam mengirim promo terjadwal saat mulai. Client Flutter membedakan ilustrasi voucher via `eventType` (bukan push `data`, yang tak sampai ke lonceng).

**Tech Stack:** Next.js (server actions + API routes), Prisma (migration SQL tulis-tangan), Node built-in test runner (`tsx --test`), Flutter (`flutter test`/`flutter analyze`).

## Global Constraints

- Baris `Announcement` promo WAJIB `segment:"all"` (BUKAN `"members"` — itu hanya pembeli PAID) dan `status:"PUBLISHED"`.
- Ilustrasi voucher dibedakan via `eventType` (`voucher_freeship_published` / `voucher_discount_published`), BUKAN `data.voucherKind` (baris lonceng dari `/api/notifications/me` tak punya `data` map).
- Push `PushPayload` WAJIB `prefCategory:"promo"` (gate preferensi #188; feed publish-push tak set ini — promo harus eksplisit).
- Anti-dobel WAJIB pakai klaim atomik `updateMany({ where:{ id, promoNotifiedAt:null }, data:{ promoNotifiedAt: now } })`; `count===0` → return tanpa kirim.
- Dispatch fire-and-forget di call-site (`.catch`) — kegagalan push tak boleh menggagalkan pembuatan promo. Panggil SEBELUM `redirect()` di server action (redirect melempar).
- Migration SQL pakai `ADD COLUMN IF NOT EXISTS` (Neon-drift resilient); timestamp folder harus > `20260719130000`.
- Brand-safety tidak relevan (promo tanpa aktor manusia) — tak ada field nama/foto pemilik.

---

### Task 1: Migration + Prisma schema — kolom promo-notify

**Files:**
- Modify: `prisma/schema.prisma` (model `Voucher` ~:789, model `ProductDiscount` ~:722)
- Create: `prisma/migrations/20260719140000_add_promo_notify_fields/migration.sql`

**Interfaces:**
- Produces: kolom `Voucher.notifyAtStart Boolean @default(false)`, `Voucher.promoNotifiedAt DateTime?`; `ProductDiscount.notifyAtStart Boolean @default(false)`, `ProductDiscount.promoNotifiedAt DateTime?`.

- [ ] **Step 1: Tambah field ke model Voucher di schema.prisma**

Di model `Voucher` (setelah baris `updatedAt DateTime @updatedAt`, ~:828), tambahkan:

```prisma
  notifyAtStart                     Boolean                     @default(false)
  promoNotifiedAt                   DateTime?
```

- [ ] **Step 2: Tambah field ke model ProductDiscount di schema.prisma**

Di model `ProductDiscount` (setelah `updatedAt DateTime @updatedAt`, ~:731), tambahkan:

```prisma
  notifyAtStart Boolean   @default(false)
  promoNotifiedAt DateTime?
```

- [ ] **Step 3: Tulis migration SQL**

Buat `prisma/migrations/20260719140000_add_promo_notify_fields/migration.sql`:

```sql
ALTER TABLE "Voucher"
ADD COLUMN IF NOT EXISTS "notifyAtStart" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS "promoNotifiedAt" TIMESTAMP(3);

ALTER TABLE "ProductDiscount"
ADD COLUMN IF NOT EXISTS "notifyAtStart" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS "promoNotifiedAt" TIMESTAMP(3);
```

- [ ] **Step 4: Regenerasi Prisma client**

Run: `npx prisma generate`
Expected: "Generated Prisma Client" tanpa error.

- [ ] **Step 5: Verifikasi tsc mengenali field baru**

Run: `npx tsc --noEmit 2>&1 | grep -i "notifyAtStart\|promoNotifiedAt" || echo "OK - no type errors on new fields"`
Expected: `OK - no type errors on new fields`

- [ ] **Step 6: Commit**

```bash
git add prisma/schema.prisma prisma/migrations/20260719140000_add_promo_notify_fields/migration.sql
git commit -m "feat(promo-notif): kolom notifyAtStart + promoNotifiedAt (Voucher, ProductDiscount)"
```

---

### Task 2: Builder murni konten notifikasi promo + predikat jadwal

**Files:**
- Create: `lib/push-promo-content.ts`
- Test: `tests/push-promo-content.test.ts`

**Interfaces:**
- Produces:
  - `buildVoucherPromoContent(v: { code: string; name: string|null; kind: string; discountPercent: number|null; discountAmount: number|null }): { title: string; body: string; eventType: string }`
  - `buildDiscountPromoContent(d: { name: string }, items: Array<{ product: { name: string; slug: string; imageUrl: string|null; price: number }; variant: { price: number }|null; discountedPrice: number }>): { title: string; body: string; url: string; thumbnailUrl: string|null }`
  - `isPromoDue(row: { notifyAtStart: boolean; promoNotifiedAt: Date|null; isActive: boolean; startsAt: Date; endsAt: Date|null }, now: Date): boolean` — `endsAt` null (voucher tanpa `expiresAt`) dianggap belum berakhir.
  - `maxDiscountPercent(items): number|null` (helper internal, export untuk test).

- [ ] **Step 1: Tulis test builder voucher**

Buat `tests/push-promo-content.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildVoucherPromoContent,
  buildDiscountPromoContent,
  maxDiscountPercent,
  isPromoDue,
} from "../lib/push-promo-content";

test("voucher gratis ongkir → eventType freeship + judul truk", () => {
  const r = buildVoucherPromoContent({
    code: "ONGKIRGRATIS",
    name: null,
    kind: "FREE_SHIPPING",
    discountPercent: null,
    discountAmount: null,
  });
  assert.equal(r.eventType, "voucher_freeship_published");
  assert.match(r.title, /Gratis Ongkir/i);
  assert.match(r.body, /ONGKIRGRATIS/);
});

test("voucher diskon persen → eventType discount + sebut persen & kode", () => {
  const r = buildVoucherPromoContent({
    code: "HEMAT20",
    name: "Hemat Juli",
    kind: "PRODUCT_DISCOUNT",
    discountPercent: 20,
    discountAmount: null,
  });
  assert.equal(r.eventType, "voucher_discount_published");
  assert.match(r.body, /20%/);
  assert.match(r.body, /HEMAT20/);
});

test("voucher diskon nominal → body sebut Rp", () => {
  const r = buildVoucherPromoContent({
    code: "POTONG5RB",
    name: null,
    kind: "PRODUCT_DISCOUNT",
    discountPercent: null,
    discountAmount: 5000,
  });
  assert.equal(r.eventType, "voucher_discount_published");
  assert.match(r.body, /Rp\s?5.?000/);
});
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `npx tsx --test tests/push-promo-content.test.ts`
Expected: FAIL "Cannot find module '../lib/push-promo-content'".

- [ ] **Step 3: Tulis builder voucher + diskon + predikat**

Buat `lib/push-promo-content.ts`:

```ts
/**
 * Builder murni konten notifikasi promo — dipisah dari dispatch (push-promo.ts)
 * supaya teruji tanpa DB/mock. Semua fungsi deterministik.
 */

/** Format angka Rupiah singkat: 5000 → "Rp5.000". */
function rp(n: number): string {
  return "Rp" + n.toLocaleString("id-ID");
}

export function buildVoucherPromoContent(v: {
  code: string;
  name: string | null;
  kind: string;
  discountPercent: number | null;
  discountAmount: number | null;
}): { title: string; body: string; eventType: string } {
  if (v.kind === "FREE_SHIPPING") {
    return {
      eventType: "voucher_freeship_published",
      title: "🚚 Gratis Ongkir dari Natalo!",
      body: `Voucher gratis ongkir ${v.code} sudah aktif. Klaim sekarang sebelum habis!`,
    };
  }
  const nilai =
    v.discountPercent && v.discountPercent > 0
      ? `Diskon ${v.discountPercent}%`
      : v.discountAmount && v.discountAmount > 0
        ? `Potongan ${rp(v.discountAmount)}`
        : "Voucher diskon";
  return {
    eventType: "voucher_discount_published",
    title: "🎟️ Voucher diskon baru buat kamu",
    body: `${nilai} pakai kode ${v.code}. Klaim sekarang di halaman voucher!`,
  };
}

/** Persen diskon tertinggi across item; null bila tak ada yang bisa dihitung.
 *  Harga asli = variant.price bila item ber-varian, else product.price.
 *  Item dengan harga asli <= 0 atau discountedPrice >= harga asli dilewati. */
export function maxDiscountPercent(
  items: Array<{
    product: { price: number };
    variant: { price: number } | null;
    discountedPrice: number;
  }>,
): number | null {
  let max: number | null = null;
  for (const it of items) {
    const original = it.variant ? it.variant.price : it.product.price;
    if (original <= 0 || it.discountedPrice >= original) continue;
    const pct = Math.round(((original - it.discountedPrice) / original) * 100);
    if (pct <= 0) continue;
    if (max === null || pct > max) max = pct;
  }
  return max;
}

export function buildDiscountPromoContent(
  d: { name: string },
  items: Array<{
    product: { name: string; slug: string; imageUrl: string | null; price: number };
    variant: { price: number } | null;
    discountedPrice: number;
  }>,
): { title: string; body: string; url: string; thumbnailUrl: string | null } {
  const pct = maxDiscountPercent(items);
  const thumbnailUrl = items[0]?.product.imageUrl ?? null;
  if (items.length === 1) {
    const p = items[0].product;
    const pctText = pct ? ` — hemat s/d ${pct}%` : "";
    return {
      title: `🔥 ${p.name} lagi diskon!`,
      body: `Harga spesial${pctText}. Cek sekarang sebelum promo berakhir.`,
      url: `/produk/${p.slug}`,
      thumbnailUrl,
    };
  }
  const pctText = pct ? ` diskon s/d ${pct}%` : " diskon";
  return {
    title: `🔥 Promo Toko: ${items.length} produk diskon`,
    body: `${items.length} produk pilihan${pctText}. Buruan cek sebelum kehabisan!`,
    url: "/products",
    thumbnailUrl,
  };
}

export function isPromoDue(
  row: {
    notifyAtStart: boolean;
    promoNotifiedAt: Date | null;
    isActive: boolean;
    startsAt: Date;
    endsAt: Date | null;
  },
  now: Date,
): boolean {
  if (!row.notifyAtStart) return false;
  if (row.promoNotifiedAt != null) return false;
  if (!row.isActive) return false;
  if (row.startsAt > now) return false;
  if (row.endsAt != null && row.endsAt <= now) return false;
  return true;
}
```

- [ ] **Step 4: Jalankan test voucher — pastikan LULUS**

Run: `npx tsx --test tests/push-promo-content.test.ts`
Expected: PASS (3 test).

- [ ] **Step 5: Tambah test diskon produk + isPromoDue**

Tambahkan ke `tests/push-promo-content.test.ts`:

```ts
test("diskon 1 produk → url slug + judul nama produk", () => {
  const r = buildDiscountPromoContent(
    { name: "Promo Kucing" },
    [
      {
        product: { name: "Royal Canin 2kg", slug: "royal-canin-2kg", imageUrl: "https://cdn/rc.jpg", price: 200000 },
        variant: null,
        discountedPrice: 150000,
      },
    ],
  );
  assert.equal(r.url, "/produk/royal-canin-2kg");
  assert.equal(r.thumbnailUrl, "https://cdn/rc.jpg");
  assert.match(r.title, /Royal Canin 2kg/);
  assert.match(r.body, /25%/); // (200000-150000)/200000 = 25%
});

test("diskon banyak produk → url katalog + hitung persen tertinggi", () => {
  const r = buildDiscountPromoContent(
    { name: "Promo Toko" },
    [
      { product: { name: "A", slug: "a", imageUrl: "https://cdn/a.jpg", price: 100000 }, variant: null, discountedPrice: 90000 }, // 10%
      { product: { name: "B", slug: "b", imageUrl: null, price: 100000 }, variant: null, discountedPrice: 60000 }, // 40%
    ],
  );
  assert.equal(r.url, "/products");
  assert.equal(r.thumbnailUrl, "https://cdn/a.jpg");
  assert.match(r.body, /40%/);
});

test("maxDiscountPercent: harga varian dipakai bila ada; harga asli 0 dilewati", () => {
  assert.equal(
    maxDiscountPercent([
      { product: { price: 0 }, variant: { price: 50000 }, discountedPrice: 25000 }, // varian 50%
      { product: { price: 0 }, variant: null, discountedPrice: 10000 }, // asli 0 → skip
    ]),
    50,
  );
});

test("maxDiscountPercent: semua tak valid → null", () => {
  assert.equal(
    maxDiscountPercent([
      { product: { price: 100 }, variant: null, discountedPrice: 100 }, // 0% skip
    ]),
    null,
  );
});

test("isPromoDue: aktif, mulai lewat, belum notif → true", () => {
  const now = new Date("2026-07-19T10:00:00Z");
  assert.equal(
    isPromoDue(
      { notifyAtStart: true, promoNotifiedAt: null, isActive: true, startsAt: new Date("2026-07-19T09:00:00Z"), endsAt: new Date("2026-07-25T00:00:00Z") },
      now,
    ),
    true,
  );
});

test("isPromoDue: sudah ter-notif / belum mulai / sudah berakhir → false", () => {
  const now = new Date("2026-07-19T10:00:00Z");
  const base = { notifyAtStart: true, isActive: true, startsAt: new Date("2026-07-19T09:00:00Z"), endsAt: null };
  assert.equal(isPromoDue({ ...base, promoNotifiedAt: new Date() }, now), false);
  assert.equal(isPromoDue({ ...base, promoNotifiedAt: null, startsAt: new Date("2026-07-20T00:00:00Z") }, now), false);
  assert.equal(isPromoDue({ ...base, promoNotifiedAt: null, endsAt: new Date("2026-07-19T00:00:00Z") }, now), false);
  assert.equal(isPromoDue({ ...base, promoNotifiedAt: null, notifyAtStart: false }, now), false);
});
```

- [ ] **Step 6: Jalankan semua test — pastikan LULUS**

Run: `npx tsx --test tests/push-promo-content.test.ts`
Expected: PASS (9 test).

- [ ] **Step 7: Commit**

```bash
git add lib/push-promo-content.ts tests/push-promo-content.test.ts
git commit -m "feat(promo-notif): builder murni konten voucher/diskon + isPromoDue (teruji)"
```

---

### Task 3: Fungsi dispatch push-promo (klaim atomik + Announcement + push batch)

**Files:**
- Create: `lib/push-promo.ts`
- Test: `tests/push-promo-dispatch.test.ts`

**Interfaces:**
- Consumes: `buildVoucherPromoContent`, `buildDiscountPromoContent` (Task 2); `resolveSegmentUserIds` dari `lib/feed/publish-push.ts:31`; `sendPushToUser`/`PushPayload` dari `lib/push.ts`; `sendFcmToUser` dari `lib/fcm.ts`; `prisma` dari `lib/prisma`.
- Produces: `sendVoucherPromoPush(voucherId: string): Promise<void>`, `sendProductDiscountPromoPush(discountId: string): Promise<void>`, dan helper murni `claimSucceeded(count: number): boolean` (export untuk test).

- [ ] **Step 1: Tulis test helper klaim**

Buat `tests/push-promo-dispatch.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { claimSucceeded } from "../lib/push-promo";

test("claimSucceeded: count 1 → true (baris berhasil diklaim)", () => {
  assert.equal(claimSucceeded(1), true);
});

test("claimSucceeded: count 0 → false (sudah diklaim proses lain)", () => {
  assert.equal(claimSucceeded(0), false);
});
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `npx tsx --test tests/push-promo-dispatch.test.ts`
Expected: FAIL "Cannot find module '../lib/push-promo'".

- [ ] **Step 3: Tulis modul dispatch**

Buat `lib/push-promo.ts`:

```ts
/**
 * Dispatch notifikasi promo (voucher & diskon produk) — pola sama dgn
 * lib/feed/publish-push.ts: SATU baris Announcement segment "all" (tampil di
 * lonceng semua user) + push batch ke resolveSegmentUserIds("all").
 *
 * Anti-dobel: klaim atomik promoNotifiedAt via updateMany(where null) SEBELUM
 * dispatch — route (kirim langsung) dan cron (kirim saat mulai) bisa menyentuh
 * baris yang sama; klaim menjamin push terkirim tepat sekali.
 *
 * Errors di-swallow — kegagalan push tak boleh menggagalkan pembuatan promo.
 */
import { prisma } from "@/lib/prisma";
import { sendPushToUser, type PushPayload } from "@/lib/push";
import { sendFcmToUser } from "@/lib/fcm";
import { resolveSegmentUserIds } from "@/lib/feed/publish-push";
import {
  buildVoucherPromoContent,
  buildDiscountPromoContent,
} from "@/lib/push-promo-content";

const BATCH_SIZE = 50;

/** Klaim atomik berhasil bila tepat 1 baris ter-update (promoNotifiedAt null→now). */
export function claimSucceeded(count: number): boolean {
  return count === 1;
}

async function dispatchBatch(userIds: string[], payload: PushPayload): Promise<void> {
  for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
    const batch = userIds.slice(i, i + BATCH_SIZE);
    await Promise.allSettled(
      batch.flatMap((userId) => [
        sendPushToUser(userId, payload),
        sendFcmToUser(userId, payload),
      ]),
    );
  }
}

export async function sendVoucherPromoPush(voucherId: string): Promise<void> {
  try {
    const now = new Date();
    // Klaim atomik dulu — cegah route+cron dobel-kirim.
    const claim = await prisma.voucher.updateMany({
      where: { id: voucherId, promoNotifiedAt: null },
      data: { promoNotifiedAt: now },
    });
    if (!claimSucceeded(claim.count)) return;

    const v = await prisma.voucher.findUnique({
      where: { id: voucherId },
      select: {
        code: true,
        name: true,
        kind: true,
        discountPercent: true,
        discountAmount: true,
        isActive: true,
        startsAt: true,
        expiresAt: true,
      },
    });
    if (!v || !v.isActive) return;
    if (v.startsAt > now) return;
    if (v.expiresAt != null && v.expiresAt <= now) return;

    const { title, body, eventType } = buildVoucherPromoContent({
      code: v.code,
      name: v.name,
      kind: v.kind,
      discountPercent: v.discountPercent,
      discountAmount: v.discountAmount,
    });
    const url = "/member/vouchers";

    await prisma.announcement.create({
      data: {
        title,
        body,
        url,
        segment: "all",
        status: "PUBLISHED",
        type: "promo",
        eventType,
        thumbnailUrl: null,
        ctaLabel: "Lihat Voucher",
        publishedAt: now,
      },
    });

    const userIds = await resolveSegmentUserIds("all");
    if (userIds.length === 0) return;
    const payload: PushPayload = {
      title,
      body,
      url,
      tag: `voucher-promo-${voucherId}`,
      prefCategory: "promo",
      data: { type: eventType, voucherKind: v.kind },
    };
    await dispatchBatch(userIds, payload);
  } catch (err) {
    console.warn("[push-promo] voucher failed:", err);
  }
}

export async function sendProductDiscountPromoPush(discountId: string): Promise<void> {
  try {
    const now = new Date();
    const claim = await prisma.productDiscount.updateMany({
      where: { id: discountId, promoNotifiedAt: null },
      data: { promoNotifiedAt: now },
    });
    if (!claimSucceeded(claim.count)) return;

    const d = await prisma.productDiscount.findUnique({
      where: { id: discountId },
      select: {
        name: true,
        isActive: true,
        startsAt: true,
        endsAt: true,
        items: {
          where: { isItemActive: true },
          select: {
            discountedPrice: true,
            product: { select: { name: true, slug: true, imageUrl: true, price: true } },
            variant: { select: { price: true } },
          },
        },
      },
    });
    if (!d || !d.isActive) return;
    if (d.startsAt > now) return;
    if (d.endsAt <= now) return;
    if (d.items.length === 0) return;

    const { title, body, url, thumbnailUrl } = buildDiscountPromoContent(
      { name: d.name },
      d.items,
    );

    await prisma.announcement.create({
      data: {
        title,
        body,
        url,
        segment: "all",
        status: "PUBLISHED",
        type: "promo",
        eventType: "product_discount_published",
        thumbnailUrl,
        ctaLabel: "Lihat Promo",
        publishedAt: now,
      },
    });

    const userIds = await resolveSegmentUserIds("all");
    if (userIds.length === 0) return;
    const payload: PushPayload = {
      title,
      body,
      url,
      tag: `discount-promo-${discountId}`,
      prefCategory: "promo",
      imageUrl: thumbnailUrl,
      data: { type: "product_discount_published" },
    };
    await dispatchBatch(userIds, payload);
  } catch (err) {
    console.warn("[push-promo] discount failed:", err);
  }
}
```

- [ ] **Step 4: Jalankan test + tsc — pastikan LULUS**

Run: `npx tsx --test tests/push-promo-dispatch.test.ts && npx tsc --noEmit 2>&1 | grep -i "push-promo" || echo "OK"`
Expected: test PASS (2), lalu `OK` (tak ada type error di push-promo).

- [ ] **Step 5: Commit**

```bash
git add lib/push-promo.ts tests/push-promo-dispatch.test.ts
git commit -m "feat(promo-notif): dispatch voucher/diskon (klaim atomik + Announcement all + push batch)"
```

---

### Task 4: Wire Server Action voucher — checkbox + kirim langsung/terjadwal

**Files:**
- Modify: `app/admin/(protected)/vouchers/new/page.tsx` (server action `createVoucher` :10-160 + form JSX :178+)

**Interfaces:**
- Consumes: `sendVoucherPromoPush` dari `lib/push-promo.ts` (Task 3).

- [ ] **Step 1: Import fungsi dispatch**

Di atas file (`page.tsx`, setelah import `prisma`), tambahkan:

```ts
import { sendVoucherPromoPush } from "@/lib/push-promo";
```

- [ ] **Step 2: Baca checkbox + set notifyAtStart + select hasil create**

Di server action `createVoucher`, ganti blok `const isActive = formData.get("isActive") === "on";` (~:126) menjadi:

```ts
    const isActive = formData.get("isActive") === "on";
    const notifyCustomers = formData.get("notifyCustomers") === "on";
```

Lalu ganti `await prisma.voucher.create({ data: { ... } });` (~:131-157) — tambahkan `notifyAtStart: notifyCustomers,` ke dalam `data`, dan tambahkan `select` + tangkap hasilnya:

```ts
    const created = await prisma.voucher.create({
      data: {
        name,
        code,
        description,
        discountPercent,
        discountAmount,
        maxDiscountAmount,
        minimumOrder,
        maxUsage,
        usageLimitPerUser,
        usageLimitPeriod,
        startsAt,
        expiresAt,
        isActive,
        sourceType,
        type,
        kind,
        visibility,
        discountType: discountPercent ? "PERCENTAGE" : "FIXED_AMOUNT",
        discountScope,
        eligibleUserIds,
        eligibleProductIds,
        eligibleCategoryIds,
        eligibleBrandIds,
        notifyAtStart: notifyCustomers,
      },
      select: { id: true, isActive: true, startsAt: true, expiresAt: true },
    });
```

- [ ] **Step 3: Kirim notif langsung bila aktif & sudah mulai (SEBELUM redirect)**

Tepat sebelum `redirect("/admin/vouchers");` (~:159), tambahkan:

```ts
    // Kirim notif langsung bila dicentang & voucher sudah aktif sekarang.
    // Voucher terjadwal (startsAt > now) diurus cron promo-notify.
    // redirect() melempar — panggil push SEBELUMnya (fire-and-forget).
    if (
      notifyCustomers &&
      created.isActive &&
      created.startsAt <= new Date() &&
      (created.expiresAt == null || created.expiresAt > new Date())
    ) {
      void sendVoucherPromoPush(created.id).catch((e) =>
        console.warn("[voucher-create] promo push:", e),
      );
    }
```

- [ ] **Step 4: Tambah checkbox di form JSX**

Di dalam `<form action={createVoucher} ...>` (~:178), sebelum tombol submit, tambahkan (setelah field `isActive` bila ada, atau di akhir form sebelum `<SubmitButton>`):

```tsx
        <label className="flex items-start gap-3 rounded-xl border border-zinc-200 p-3">
          <input
            type="checkbox"
            name="notifyCustomers"
            className="mt-1 h-4 w-4"
          />
          <span className="text-sm text-zinc-700">
            <span className="font-bold text-zinc-950">Beri tahu pelanggan</span>
            <br />
            Kirim notifikasi &amp; push ke semua pelanggan saat voucher aktif.
          </span>
        </label>
```

- [ ] **Step 5: Verifikasi tsc bersih**

Run: `npx tsc --noEmit 2>&1 | grep -i "vouchers/new" || echo "OK"`
Expected: `OK`.

- [ ] **Step 6: Commit**

```bash
git add "app/admin/(protected)/vouchers/new/page.tsx"
git commit -m "feat(promo-notif): checkbox beri tahu pelanggan + kirim voucher promo (server action)"
```

---

### Task 5: Wire POST route Promo Toko — Zod field + checkbox di form

**Files:**
- Modify: `app/api/admin/discounts/promo-toko/route.ts` (Zod `createSchema` :31-37, create :192-208)
- Modify: `components/admin/PromoTokoForm.tsx` (state + body fetch :224-264)

**Interfaces:**
- Consumes: `sendProductDiscountPromoPush` dari `lib/push-promo.ts` (Task 3).

- [ ] **Step 1: Import dispatch + tambah field Zod**

Di `route.ts`, tambahkan import setelah `import { assertSameOrigin }`:

```ts
import { sendProductDiscountPromoPush } from "@/lib/push-promo";
```

Di `createSchema` (`:31-37`), tambahkan field ke object (setelah `items:`):

```ts
    items: z.array(itemSchema).min(1).max(500),
    notifyCustomers: z.boolean().default(false),
```

- [ ] **Step 2: Set notifyAtStart + kirim notif setelah create**

Ganti `const discount = await prisma.productDiscount.create({ ... });` (`:192-208`) — tambahkan `notifyAtStart: body.notifyCustomers,` ke `data`. Lalu tepat sebelum `return NextResponse.json(discount, { status: 201 });` (`:213`), tambahkan:

```ts
  // Kirim notif langsung bila dicentang & promo sudah aktif (startsAt <= now < endsAt).
  // Promo terjadwal (startsAt > now) diurus cron promo-notify.
  if (
    body.notifyCustomers &&
    discount.startsAt <= now &&
    discount.endsAt > now
  ) {
    void sendProductDiscountPromoPush(discount.id).catch((e) =>
      console.warn("[promo-toko-create] promo push:", e),
    );
  }
```

(`now` sudah dideklarasi di `:118`. `discount` sudah punya `startsAt`/`endsAt` via `include: { items: true }` yang mengembalikan seluruh kolom scalar.)

- [ ] **Step 3: Tambah state checkbox di PromoTokoForm**

Di `components/admin/PromoTokoForm.tsx`, cari deklarasi `useState` untuk form (dekat atas komponen), tambahkan:

```tsx
  const [notifyCustomers, setNotifyCustomers] = useState(false);
```

- [ ] **Step 4: Kirim di body fetch**

Di `handleSubmit` (`:224`), pada objek body `fetch` (`:250`, `JSON.stringify({...})`), tambahkan field `notifyCustomers`:

```tsx
        body: JSON.stringify({
          name,
          startsAt,
          endsAt,
          items,
          notifyCustomers,
        }),
```

(Nama variabel `name`/`startsAt`/`endsAt`/`items` mengikuti yang sudah ada di `handleSubmit` — jangan ubah, hanya tambah `notifyCustomers`.)

- [ ] **Step 5: Tambah checkbox di JSX form**

Sebelum tombol submit di JSX (dekat `<Link href="/admin/diskon/promo-toko"` ~:520 atau tombol simpan), tambahkan:

```tsx
        <label className="flex items-start gap-3 rounded-xl border border-zinc-200 p-3">
          <input
            type="checkbox"
            checked={notifyCustomers}
            onChange={(e) => setNotifyCustomers(e.target.checked)}
            className="mt-1 h-4 w-4"
          />
          <span className="text-sm text-zinc-700">
            <span className="font-bold text-zinc-950">Beri tahu pelanggan</span>
            <br />
            Kirim notifikasi &amp; push ke semua pelanggan saat promo aktif.
          </span>
        </label>
```

- [ ] **Step 6: Verifikasi tsc bersih**

Run: `npx tsc --noEmit 2>&1 | grep -iE "promo-toko|PromoTokoForm" || echo "OK"`
Expected: `OK`.

- [ ] **Step 7: Commit**

```bash
git add "app/api/admin/discounts/promo-toko/route.ts" components/admin/PromoTokoForm.tsx
git commit -m "feat(promo-notif): checkbox beri tahu pelanggan + kirim diskon promo (POST route)"
```

---

### Task 6: Cron promo-notify — kirim promo terjadwal saat mulai

**Files:**
- Create: `app/api/cron/promo-notify/route.ts`
- Modify: `vercel.json` (`crons` array :16+)

**Interfaces:**
- Consumes: `isPromoDue` dari `lib/push-promo-content.ts` (Task 2); `sendVoucherPromoPush`/`sendProductDiscountPromoPush` dari `lib/push-promo.ts` (Task 3).

- [ ] **Step 1: Tulis route cron**

Buat `app/api/cron/promo-notify/route.ts`:

```ts
/**
 * Cron promo-notify — jalan tiap jam. Kirim notifikasi promo (voucher +
 * Promo Toko) yang dijadwalkan mulai di masa depan (notifyAtStart=true,
 * belum ter-notif) begitu waktu mulai tercapai. Promo yang aktif saat dibuat
 * sudah dikirim langsung dari server action / POST route; cron ini backstop
 * untuk yang terjadwal.
 *
 * Idempotensi dijamin klaim atomik di dalam sendVoucherPromoPush /
 * sendProductDiscountPromoPush (updateMany where promoNotifiedAt null).
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  sendVoucherPromoPush,
  sendProductDiscountPromoPush,
} from "@/lib/push-promo";

const LIMIT = 20;

export async function GET(request: NextRequest) {
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret) {
    const auth = request.headers.get("authorization");
    if (auth !== `Bearer ${cronSecret}`) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
  }

  const now = new Date();

  const vouchers = await prisma.voucher.findMany({
    where: {
      notifyAtStart: true,
      promoNotifiedAt: null,
      isActive: true,
      startsAt: { lte: now },
      OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
    },
    select: { id: true },
    take: LIMIT,
  });

  const discounts = await prisma.productDiscount.findMany({
    where: {
      notifyAtStart: true,
      promoNotifiedAt: null,
      isActive: true,
      startsAt: { lte: now },
      endsAt: { gt: now },
    },
    select: { id: true },
    take: LIMIT,
  });

  for (const v of vouchers) await sendVoucherPromoPush(v.id);
  for (const d of discounts) await sendProductDiscountPromoPush(d.id);

  return NextResponse.json({
    ok: true,
    vouchers: vouchers.length,
    discounts: discounts.length,
  });
}
```

- [ ] **Step 2: Daftarkan cron di vercel.json**

Di `vercel.json`, dalam array `"crons"` (`:16`), tambahkan satu entri (misal setelah entri `order-confirm-reminder`):

```json
    {
      "path": "/api/cron/promo-notify",
      "schedule": "0 * * * *"
    }
```

(Pastikan koma antar-objek benar — sisipkan sebelum penutup `]`.)

- [ ] **Step 3: Verifikasi tsc + JSON valid**

Run: `npx tsc --noEmit 2>&1 | grep -i "promo-notify" || echo "OK"; node -e "JSON.parse(require('fs').readFileSync('vercel.json','utf8')); console.log('vercel.json valid')"`
Expected: `OK` lalu `vercel.json valid`.

- [ ] **Step 4: Commit**

```bash
git add "app/api/cron/promo-notify/route.ts" vercel.json
git commit -m "feat(promo-notif): cron promo-notify tiap jam (kirim promo terjadwal saat mulai)"
```

---

### Task 7: Client Flutter — ilustrasi voucher via eventType + routing diskon 1-produk

**Files:**
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (`_NotificationVisual.from` :1216, `_navigateForNotification` product-slug branch :285)
- Test: `flutter_app/test/notifications_redesign_widget_test.dart`

**Interfaces:**
- Consumes: `AppNotification.eventType` (sudah di-parse, `models/app_notification.dart:64`); `_extractProductSlug` (`notifications_screen.dart:448`), `productService.fetchProductBySlug` (`:420`), route `/product-detail` + `ProductDetailArgs` (`:435-442`).

- [ ] **Step 1: Tambah cabang ilustrasi voucher di _NotificationVisual.from**

Di `_NotificationVisual.from` (`:1216`), SEBELUM cabang `if (_isVoucherNotification(item))` (`:1243`), sisipkan:

```dart
    final ev = item.eventType?.trim().toLowerCase() ?? '';
    if (ev == 'voucher_freeship_published') {
      return const _NotificationVisual(
        icon: Icons.local_shipping_rounded,
        color: _brandBlue,
        label: 'Gratis Ongkir',
      );
    }
    if (ev == 'voucher_discount_published') {
      return const _NotificationVisual(
        icon: Icons.sell_rounded,
        color: Color(0xFF16A34A),
        label: 'Voucher',
      );
    }
```

- [ ] **Step 2: Tambah routing diskon 1-produk (slug → detail) di _navigateForNotification**

Di `_navigateForNotification`, GANTI blok generik (`:285-288`):

```dart
    if (url.contains('/products') || url.contains('/produk')) {
      await Navigator.pushNamed(context, '/products');
      return;
    }
```

menjadi (fetch-by-slug bila ada slug spesifik, else katalog):

```dart
    if (url.contains('/produk/') || url.contains('/products/')) {
      final slug = _extractProductSlug(url);
      if (slug != null) {
        await _openProductBySlug(slug);
        return;
      }
    }
    if (url.contains('/products') || url.contains('/produk')) {
      await Navigator.pushNamed(context, '/products');
      return;
    }
```

- [ ] **Step 3: Tambah helper _openProductBySlug**

Setelah method `_openOrderInApp` (`:320`) atau dekat helper produk existing, tambahkan method di dalam State class:

```dart
  /// Fetch produk by slug lalu buka detailnya. Spinner saat fetch; fallback
  /// ke katalog kalau produk tak ada / fetch gagal. Pola sama _openReviewedProduct.
  Future<void> _openProductBySlug(String slug) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );
    Product? product;
    try {
      product = await productService.fetchProductBySlug(slug);
    } catch (_) {
      product = null;
    }
    rootNav.pop();
    if (!mounted) return;
    if (product == null) {
      await Navigator.pushNamed(context, '/products');
      return;
    }
    await Navigator.pushNamed(
      context,
      '/product-detail',
      arguments: ProductDetailArgs(product: product),
    );
  }
```

(Bila `ProductDetailArgs` mensyaratkan named param lain, ikuti signature yang dipakai di `_openReviewedProduct` `:438` — hanya buang `focusReviewSection: true`.)

- [ ] **Step 4: Tulis widget test ilustrasi voucher**

Tambahkan ke `flutter_app/test/notifications_redesign_widget_test.dart` (dalam `void main()`):

```dart
  testWidgets('voucher gratis ongkir → ikon truk di avatar kiri', (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'vf1', 'title': '🚚 Gratis Ongkir dari Natalo!', 'body': 'Klaim sekarang',
      'type': 'promo', 'eventType': 'voucher_freeship_published',
      'url': '/member/vouchers',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.byIcon(Icons.local_shipping_rounded), findsOneWidget);
  });

  testWidgets('voucher diskon → ikon sell/tag di avatar kiri', (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'vd1', 'title': '🎟️ Voucher diskon baru', 'body': 'Diskon 20% pakai HEMAT20',
      'type': 'promo', 'eventType': 'voucher_discount_published',
      'url': '/member/vouchers',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.byIcon(Icons.sell_rounded), findsOneWidget);
  });
```

- [ ] **Step 5: Jalankan analyze + test**

Run: `cd flutter_app && flutter analyze lib/screens/notifications_screen.dart && flutter test test/notifications_redesign_widget_test.dart`
Expected: analyze "No issues found" (atau hanya info pre-existing), test semua PASS.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/notifications_screen.dart flutter_app/test/notifications_redesign_widget_test.dart
git commit -m "feat(promo-notif): ilustrasi voucher via eventType (truk/tag) + routing diskon 1-produk ke detail"
```

---

## Self-Review

**Spec coverage:**
- P (skema + migration) → Task 1 ✅
- Builder murni + isPromoDue → Task 2 ✅
- Dispatch (segment all, status PUBLISHED, prefCategory promo, klaim atomik) → Task 3 ✅
- Voucher server action + checkbox → Task 4 ✅
- Promo Toko POST route + checkbox → Task 5 ✅
- Cron promo-notify + vercel.json → Task 6 ✅
- Ilustrasi eventType + routing diskon → Task 7 ✅
- Acceptance criteria 1-5 semua tercakup ✅

**Placeholder scan:** Tak ada TBD/TODO; semua step punya kode lengkap.

**Type consistency:** `buildVoucherPromoContent`/`buildDiscountPromoContent`/`isPromoDue`/`maxDiscountPercent` (Task 2) dipakai konsisten di Task 3 & 6. `sendVoucherPromoPush`/`sendProductDiscountPromoPush` (Task 3) dipakai konsisten di Task 4/5/6. `resolveSegmentUserIds("all")` cocok dgn signature `lib/feed/publish-push.ts:31`. Field `Announcement` (segment/status/type/eventType/thumbnailUrl/ctaLabel/publishedAt) semua terverifikasi ada.

**Catatan deploy:** Migration deploy DULU (Task 1) sebelum backend baru aktif. Client (Task 7) butuh rilis app Flutter — sampai itu, app lama tetap tampil notif polos (ikon kategori promo) + routing url fallback; ilustrasi & routing presisi menyusul.
