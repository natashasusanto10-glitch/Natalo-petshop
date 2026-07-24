# Agregasi Notifikasi ala IG — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregasi notifikasi follow ("sinta dan 2 lainnya mulai mengikuti kamu") + push tray replace-not-stack (Android tag / iOS apns-collapse-id) dengan throttle re-push 5 menit, untuk follow (baru) dan like (retrofit).

**Architecture:** Perluas pola update-in-window jalur like (`lib/feed/activity-notifications.ts`) ke follow (`lib/social/notifications.ts`). Dua kolom baru di `Announcement` (`lastPushedAt`, `aggregatedCount`), satu header APNs baru (`apns-collapse-id`), satu case deep-link baru (`/akun/followers`). Semua keputusan desain sudah dikunci di spec `docs/superpowers/specs/2026-07-24-notif-aggregation-ig-design.md` (Keputusan 1–11) — plan ini implementasinya.

**Tech Stack:** Next.js + Prisma (Postgres), firebase-admin (FCM), Flutter (`natalo_petshop_flutter`), tes backend `npx tsx --test tests/<file>.test.ts` (node:test), tes Flutter `flutter test`.

## Global Constraints

- Spec acuan: `docs/superpowers/specs/2026-07-24-notif-aggregation-ig-design.md`. Konflik plan-vs-spec → spec menang, tanya user.
- Window agregasi = `LIKE_BATCH_WINDOW_MS` (30 menit). Throttle push = 5 menit per baris.
- Angka N agregat dihitung dari `UserFollow` dengan patokan TETAP `createdAt` baris agregat (`gte: baris.createdAt`) — BUKAN rolling `now-30m` (Keputusan 10).
- Kontrak agregat client = `aggregatedCount != null && aggregatedCount > 1`. Heuristik `actorAvatarUrls.length` DILARANG untuk keputusan pill/tap (Keputusan 9 spec).
- `apns-collapse-id` maksimal 64 byte, di-set di KEDUA shape FCM, hanya saat `payload.tag` ada (Keputusan 7).
- Brand-safety: follower admin → nama `OFFICIAL_BRAND_NAME`, foto di-drop dari avatar array (pakai helper existing `topLikerAvatars`/`notificationActorFields` — JANGAN tulis lookup mentah).
- Perilaku baris follow TUNGGAL (url profil follower, pill follow-back, dedup 7 hari) WAJIB identik dengan sekarang (regresi wajib, spec Testing #10).
- Migration idempotent: `ADD COLUMN IF NOT EXISTS`.
- Package Flutter: `natalo_petshop_flutter`. Semua teks user-facing bahasa Indonesia.
- Error notif tidak boleh menggagalkan aksi pemicunya: semua jalur kirim tetap try/catch + `console.warn` (pola existing).
- Kerja di branch baru dari `origin/main` (mis. `claude/notif-aggregation-ig`). JANGAN commit di checkout `main` yang dipakai worktree lain.

---

## File Structure

| File | Peran |
|---|---|
| `prisma/schema.prisma` + `prisma/migrations/20260724120000_add_announcement_aggregation/migration.sql` | Kolom `lastPushedAt DateTime?`, `aggregatedCount Int?` di `Announcement` |
| `lib/social/follow-aggregation.ts` (BARU) | Pure helpers teruji tanpa DB: judul agregat, keputusan throttle, konstanta |
| `lib/fcm.ts` | `apns-collapse-id` di kedua shape + helper truncate 64-byte |
| `lib/social/notifications.ts` | `sendFollowNotification` → alur agregasi (create/update + throttled re-push), deps injectable |
| `lib/feed/activity-notifications.ts` | `sendLikeNotification` update-branch → throttled re-push |
| `app/api/notifications/me/route.ts` | Expose `aggregatedCount`; `isAggregate` pindah ke `aggregatedCount` |
| `flutter_app/lib/models/app_notification.dart` | Field `aggregatedCount` |
| `flutter_app/lib/screens/notifications_screen.dart` | Pill gating + tap agregat → daftar follower sendiri |
| `flutter_app/lib/services/deep_link_service.dart` | Case `/akun/followers` |
| Tes: `tests/follow-aggregation.test.ts` (BARU), `tests/fcm-message-shape.test.ts`, `flutter_app/test/notifications_redesign_widget_test.dart` (tambah kasus), `flutter_app/test/services/deep_link_followers_route_test.dart` (BARU) | |

---

### Task 1: Kolom `lastPushedAt` + `aggregatedCount` (schema + migration)

**Files:**
- Modify: `prisma/schema.prisma` (model `Announcement`, setelah field `actorId`)
- Create: `prisma/migrations/20260724120000_add_announcement_aggregation/migration.sql`

**Interfaces:**
- Produces: `Announcement.lastPushedAt: DateTime?`, `Announcement.aggregatedCount: Int?` — dipakai Task 4, 5, 6.

- [ ] **Step 1: Tambah field di schema**

Di `prisma/schema.prisma`, model `Announcement`, sisip setelah blok `actorId String?` (sebelum `createdAt`):

```prisma
  /// Waktu push terakhir baris ini (throttle re-push agregat 5 menit).
  /// Null = belum pernah / baris pra-migration → boleh push.
  lastPushedAt   DateTime?
  /// Jumlah orang di baris agregat (follow: count UserFollow sejak
  /// createdAt baris). Null / 1 = baris tunggal (pill follow-back tampil).
  /// Client WAJIB gate agregasi pakai field ini, BUKAN panjang
  /// actorAvatarUrls (follower tanpa foto → array kosong).
  aggregatedCount Int?
```

- [ ] **Step 2: Tulis migration idempotent**

`prisma/migrations/20260724120000_add_announcement_aggregation/migration.sql`:

```sql
ALTER TABLE "Announcement"
ADD COLUMN IF NOT EXISTS "lastPushedAt" TIMESTAMP(3);

ALTER TABLE "Announcement"
ADD COLUMN IF NOT EXISTS "aggregatedCount" INTEGER;
```

- [ ] **Step 3: Generate client & cek kompilasi**

Run: `npx prisma generate && npx tsc --noEmit`
Expected: keduanya sukses tanpa error.

- [ ] **Step 4: Commit**

```bash
git add prisma/schema.prisma prisma/migrations/20260724120000_add_announcement_aggregation/migration.sql
git commit -m "feat(db): Announcement.lastPushedAt + aggregatedCount utk agregasi notif"
```

---

### Task 2: `apns-collapse-id` di `buildFcmMulticastMessage`

**Files:**
- Modify: `lib/fcm.ts` (fungsi `buildFcmMulticastMessage`, kedua shape)
- Test: `tests/fcm-message-shape.test.ts`

**Interfaces:**
- Consumes: `payload.tag?: string` (existing `FcmPayload`).
- Produces: header `apns.headers["apns-collapse-id"]` (≤64 byte) di kedua shape saat `tag` ada; helper exported `apnsCollapseId(tag: string): string`.

- [ ] **Step 1: Tulis failing test**

Tambah di `tests/fcm-message-shape.test.ts` (dalam `describe`, setelah test terakhir):

```ts
  test("apns-collapse-id = tag di KEDUA shape; >64 byte terpotong; tanpa tag absen", () => {
    const capable: any = buildFcmMulticastMessage(
      { ...base, renderClientSide: true },
      { clientRender: true },
    );
    assert.equal(capable.apns.headers["apns-collapse-id"], base.tag);
    const legacy: any = buildFcmMulticastMessage(base, { clientRender: false });
    assert.equal(legacy.apns.headers["apns-collapse-id"], base.tag);
    const longTag = "x".repeat(100);
    const long: any = buildFcmMulticastMessage(
      { ...base, tag: longTag },
      { clientRender: false },
    );
    assert.equal(long.apns.headers["apns-collapse-id"], "x".repeat(64));
    assert.equal(Buffer.byteLength(long.apns.headers["apns-collapse-id"]), 64);
    const { tag: _drop, ...noTagBase } = base;
    const noTag: any = buildFcmMulticastMessage(noTagBase, { clientRender: false });
    assert.equal(noTag.apns.headers["apns-collapse-id"], undefined);
  });
```

- [ ] **Step 2: Verifikasi gagal**

Run: `npx tsx --test tests/fcm-message-shape.test.ts`
Expected: FAIL — `apns-collapse-id` undefined.

- [ ] **Step 3: Implement**

Di `lib/fcm.ts`, sebelum `buildFcmMulticastMessage`, tambah helper exported:

```ts
/**
 * APNs `apns-collapse-id` — iOS REPLACE notif di tray yang punya collapse-id
 * sama (padanan `android.notification.tag`). Batas keras Apple: 64 byte;
 * lebih dari itu APNs REJECT seluruh push, jadi WAJIB dipotong. Tag kita
 * ASCII (eventType-id-id) → slice per-karakter == per-byte, aman.
 */
export function apnsCollapseId(tag: string): string {
  return tag.slice(0, 64);
}
```

Lalu di KEDUA blok `apns.headers` (shape clientRender dan shape lama), tambah setelah `"apns-push-type": "alert",`:

```ts
          ...(payload.tag
            ? { "apns-collapse-id": apnsCollapseId(payload.tag) }
            : {}),
```

- [ ] **Step 4: Verifikasi lulus + regresi**

Run: `npx tsx --test tests/fcm-message-shape.test.ts`
Expected: PASS semua (6 test).

- [ ] **Step 5: Commit**

```bash
git add lib/fcm.ts tests/fcm-message-shape.test.ts
git commit -m "feat(push): apns-collapse-id dari tag di kedua shape FCM (iOS replace-not-stack)"
```

---

### Task 3: Pure helpers `lib/social/follow-aggregation.ts`

**Files:**
- Create: `lib/social/follow-aggregation.ts`
- Test: `tests/follow-aggregation.test.ts` (BARU)

**Interfaces:**
- Produces (dipakai Task 4 & 5):
  - `FOLLOW_AGG_WINDOW_MS = 30 * 60 * 1000`
  - `AGG_PUSH_THROTTLE_MS = 5 * 60 * 1000`
  - `followAggTag(followingId: string): string`
  - `buildFollowAggTitle(latestName: string, total: number): string`
  - `shouldRePush(lastPushedAt: Date | null, now: Date): boolean`

- [ ] **Step 1: Tulis failing test**

`tests/follow-aggregation.test.ts`:

```ts
import test from "node:test";
import assert from "node:assert/strict";
import {
  AGG_PUSH_THROTTLE_MS,
  buildFollowAggTitle,
  followAggTag,
  shouldRePush,
} from "../lib/social/follow-aggregation";

test("judul agregat: nama terbaru + N-1 lainnya", () => {
  assert.equal(
    buildFollowAggTitle("sinta", 3),
    "sinta dan 2 lainnya mulai mengikuti kamu",
  );
  assert.equal(
    buildFollowAggTitle("budi", 2),
    "budi dan 1 lainnya mulai mengikuti kamu",
  );
});

test("tag agregat stabil per target", () => {
  assert.equal(followAggTag("u1"), "follow-agg-u1");
});

test("throttle: null → push; <5m → skip; tepat 5m & >5m → push", () => {
  const now = new Date("2026-07-24T10:10:00Z");
  assert.equal(shouldRePush(null, now), true);
  assert.equal(
    shouldRePush(new Date(now.getTime() - AGG_PUSH_THROTTLE_MS + 1), now),
    false,
  );
  assert.equal(
    shouldRePush(new Date(now.getTime() - AGG_PUSH_THROTTLE_MS), now),
    true,
  );
  assert.equal(
    shouldRePush(new Date(now.getTime() - AGG_PUSH_THROTTLE_MS - 1), now),
    true,
  );
});
```

- [ ] **Step 2: Verifikasi gagal**

Run: `npx tsx --test tests/follow-aggregation.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

`lib/social/follow-aggregation.ts`:

```ts
/**
 * Pure helpers agregasi notifikasi follow ala IG (spec
 * docs/superpowers/specs/2026-07-24-notif-aggregation-ig-design.md).
 * Tanpa I/O supaya teruji langsung (pola tests/ repo ini: node:test tanpa DB).
 */

/** Window agregasi — SAMA dengan LIKE_BATCH_WINDOW_MS jalur like. */
export const FOLLOW_AGG_WINDOW_MS = 30 * 60 * 1000;

/** Maks 1 re-push per baris agregat per 5 menit (Keputusan 2 spec). */
export const AGG_PUSH_THROTTLE_MS = 5 * 60 * 1000;

/** Tag baris agregat follow per target — juga jadi apns-collapse-id. */
export function followAggTag(followingId: string): string {
  return `follow-agg-${followingId}`;
}

/** "{terbaru} dan {N-1} lainnya mulai mengikuti kamu" (Keputusan 4). */
export function buildFollowAggTitle(latestName: string, total: number): string {
  return `${latestName} dan ${total - 1} lainnya mulai mengikuti kamu`;
}

/**
 * Boleh re-push? Null = baris pra-migration / belum pernah → boleh
 * (kondisi eksplisit, spec Error handling). Batas 5m INKLUSIF.
 */
export function shouldRePush(lastPushedAt: Date | null, now: Date): boolean {
  if (lastPushedAt == null) return true;
  return now.getTime() - lastPushedAt.getTime() >= AGG_PUSH_THROTTLE_MS;
}
```

- [ ] **Step 4: Verifikasi lulus**

Run: `npx tsx --test tests/follow-aggregation.test.ts`
Expected: PASS (3 test).

- [ ] **Step 5: Commit**

```bash
git add lib/social/follow-aggregation.ts tests/follow-aggregation.test.ts
git commit -m "feat(social): pure helpers agregasi follow (judul, tag, throttle 5m)"
```

---

### Task 4: `sendFollowNotification` — alur agregasi

**Files:**
- Modify: `lib/social/notifications.ts` (fungsi `sendFollowNotification`)
- Test: `tests/follow-aggregation-flow.test.ts` (BARU)

**Interfaces:**
- Consumes: Task 1 kolom, Task 3 helpers, existing `topLikerAvatars`/`notificationActorFields` (`lib/social/brand-user.ts`), `sendPushToUser`/`sendFcmToUser`.
- Produces: `sendFollowNotification(params, deps?)` dengan deps injectable `{ db?, push?, fcm?, now? }` — pola sama `notifyTaggedUsersOnVideoReady`. Baris agregat: `tag: followAggTag(followingId)`, `url: "/akun/followers"`, `aggregatedCount: N`, `actorName/actorAvatarUrl: null`, `actorAvatarUrls` ≤3 follower terbaru.

**Perilaku (dari spec, Arsitektur §1–2):**
1. Self-follow → return (existing).
2. Dedup 7-hari existing dicek DULU, tidak berubah (hanya efektif baris tunggal — match `url` profil follower yang cuma dimiliki baris tunggal).
3. Cari baris agregat hidup: `eventType "user_followed"`, `targetUserId`, `reads: none`, `createdAt >= now - FOLLOW_AGG_WINDOW_MS`. (Tanpa filter tag — baris TUNGGAL pun kandidat upgrade jadi agregat.)
4. Ketemu → `N = 1 + count(UserFollow where followingId, createdAt >= baris.createdAt)` — `1 +` karena follower pembuat baris follow-nya terjadi SEBELUM baris dibuat, jadi di luar rentang `gte`. Update baris: judul `buildFollowAggTitle`, body `"Lihat siapa saja yang baru mengikutimu."`, `aggregatedCount: N`, `url: "/akun/followers"`, `tag` kolom TIDAK ada di Announcement (tag hanya konsep push), `actorName/actorAvatarUrl: null` (aktor tunggal hilang, pola `likeRowActorFields(true, …)`), `actorId: null`, `actorAvatarUrls` = `topLikerAvatars` dari ≤3 follower terbaru (query `userFollow.findMany` orderBy `createdAt desc` take 5 include user role+photo — ambil 5 supaya drop admin/tanpa-foto masih bisa isi 3), `publishedAt: now`.
5. Re-push HANYA jika `shouldRePush(baris.lastPushedAt, now)`; payload push pakai judul agregat, `tag: followAggTag(followingId)`, `renderClientSide: true`, `actorAvatarUrl` = avatar follower TERBARU (filter https existing di fcm.ts tetap berlaku), `data.aggregated_count: String(N)`, `url: "/akun/followers"`. Sukses kirim → update `lastPushedAt: now`.
6. Tidak ketemu → jalur create existing PERSIS seperti sekarang (judul "Pengikut baru", url profil, actorId terisi, `aggregatedCount: null`), plus `lastPushedAt: now` di create (push memang terkirim saat itu).

- [ ] **Step 1: Refactor deps injectable (tanpa ubah perilaku)**

Ubah signature `sendFollowNotification` di `lib/social/notifications.ts`:

```ts
import {
  AGG_PUSH_THROTTLE_MS,
  buildFollowAggTitle,
  FOLLOW_AGG_WINDOW_MS,
  followAggTag,
  shouldRePush,
} from "@/lib/social/follow-aggregation";
import { topLikerAvatars } from "@/lib/social/brand-user";

type FollowNotifDeps = {
  db?: typeof prisma;
  push?: typeof sendPushToUser;
  fcm?: typeof sendFcmToUser;
  now?: () => Date;
};

export async function sendFollowNotification(
  params: { followerId: string; followingId: string },
  deps: FollowNotifDeps = {},
) {
  const db = deps.db ?? prisma;
  const push = deps.push ?? sendPushToUser;
  const fcm = deps.fcm ?? sendFcmToUser;
  const now = deps.now ? deps.now() : new Date();
  // ... body existing, semua `prisma.` → `db.`, `sendPushToUser` → `push`,
  // `sendFcmToUser` → `fcm`, `new Date()` per-call → turunan dari `now`.
```

Callers existing (cari dengan `grep -rn "sendFollowNotification(" app/ lib/`) memanggil dengan 1 argumen — tetap kompatibel.

- [ ] **Step 2: Tulis failing test alur**

`tests/follow-aggregation-flow.test.ts` — fake `db` object-literal yang merekam call (pola stub manual, tanpa lib mock). Kerangka lengkap:

```ts
import test from "node:test";
import assert from "node:assert/strict";
import { sendFollowNotification } from "../lib/social/notifications";
import { AGG_PUSH_THROTTLE_MS } from "../lib/social/follow-aggregation";

const T0 = new Date("2026-07-24T10:00:00Z");

function makeFollower(over: Partial<Record<string, unknown>> = {}) {
  return {
    id: "f1",
    name: "Sinta",
    username: "sinta",
    role: "CUSTOMER",
    profilePhotoUrl: "https://cdn/sinta.jpg",
    ...over,
  };
}

/** Fake prisma minimal utk jalur follow. Atur skenario via fields. */
function makeDb(scenario: {
  follower?: ReturnType<typeof makeFollower> | null;
  dedupHit?: boolean;
  aggRow?: {
    id: string;
    createdAt: Date;
    lastPushedAt: Date | null;
  } | null;
  followCountSince?: number;
  recentFollowers?: Array<{
    user: { role: string; profilePhotoUrl: string | null };
  }>;
}) {
  const calls: {
    updates: Array<{ where: unknown; data: Record<string, unknown> }>;
    creates: Array<{ data: Record<string, unknown> }>;
    countArgs: unknown[];
  } = { updates: [], creates: [], countArgs: [] };
  const db = {
    user: {
      findUnique: async () => scenario.follower ?? makeFollower(),
    },
    announcement: {
      findFirst: async (args: { where: Record<string, unknown> }) => {
        // Panggilan dedup punya `url` di where; pencarian agregat tidak.
        if ("url" in args.where) {
          return scenario.dedupHit ? { id: "dedup" } : null;
        }
        return scenario.aggRow ?? null;
      },
      update: async (args: { where: unknown; data: Record<string, unknown> }) => {
        calls.updates.push(args);
        return {};
      },
      create: async (args: { data: Record<string, unknown> }) => {
        calls.creates.push(args);
        return {};
      },
    },
    userFollow: {
      count: async (args: unknown) => {
        calls.countArgs.push(args);
        return scenario.followCountSince ?? 0;
      },
      findMany: async () => scenario.recentFollowers ?? [],
    },
  };
  return { db: db as never, calls };
}

test("follow pertama (tanpa baris hidup) → create tunggal, aggregatedCount null, url profil", async () => {
  const { db, calls } = makeDb({ aggRow: null });
  const pushes: unknown[] = [];
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    {
      db,
      push: async (_u, p) => void pushes.push(p),
      fcm: async () => {},
      now: () => T0,
    },
  );
  assert.equal(calls.creates.length, 1);
  const row = calls.creates[0].data;
  assert.equal(row.title, "Pengikut baru");
  assert.equal(row.url, "/u/sinta");
  assert.equal(row.aggregatedCount, null);
  assert.equal(row.actorId, "f1");
  assert.deepEqual(row.lastPushedAt, T0);
  assert.equal(pushes.length, 1);
});

test("follow kedua dalam window → update agregat: judul, count, avatar, aktor null, url followers", async () => {
  const { db, calls } = makeDb({
    aggRow: { id: "a1", createdAt: T0, lastPushedAt: T0 },
    followCountSince: 1,
    recentFollowers: [
      { user: { role: "CUSTOMER", profilePhotoUrl: "https://cdn/sinta.jpg" } },
      { user: { role: "CUSTOMER", profilePhotoUrl: "https://cdn/budi.jpg" } },
    ],
  });
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    {
      db,
      push: async () => {},
      fcm: async () => {},
      now: () => new Date(T0.getTime() + 2 * 60 * 1000),
    },
  );
  assert.equal(calls.updates.length, 1);
  const data = calls.updates[0].data;
  assert.equal(data.title, "sinta dan 1 lainnya mulai mengikuti kamu");
  assert.equal(data.aggregatedCount, 2);
  assert.equal(data.url, "/akun/followers");
  assert.equal(data.actorName, null);
  assert.equal(data.actorAvatarUrl, null);
  assert.equal(data.actorId, null);
  assert.deepEqual(data.actorAvatarUrls, [
    "https://cdn/sinta.jpg",
    "https://cdn/budi.jpg",
  ]);
  // Count anchored ke createdAt baris (Keputusan 10):
  const countArg = calls.countArgs[0] as {
    where: { createdAt: { gte: Date } };
  };
  assert.deepEqual(countArg.where.createdAt.gte, T0);
});

test("update <5m sejak lastPushedAt → TIDAK re-push, tapi baris tetap ter-update", async () => {
  const { db, calls } = makeDb({
    aggRow: { id: "a1", createdAt: T0, lastPushedAt: T0 },
    followCountSince: 1,
    recentFollowers: [],
  });
  const pushes: unknown[] = [];
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    {
      db,
      push: async (_u, p) => void pushes.push(p),
      fcm: async () => {},
      now: () => new Date(T0.getTime() + AGG_PUSH_THROTTLE_MS - 1000),
    },
  );
  assert.equal(pushes.length, 0);
  assert.equal(calls.updates.length, 1);
  assert.equal(calls.updates[0].data.lastPushedAt, undefined);
});

test("update >=5m → re-push dgn tag agregat + lastPushedAt maju", async () => {
  const later = new Date(T0.getTime() + AGG_PUSH_THROTTLE_MS);
  const { db, calls } = makeDb({
    aggRow: { id: "a1", createdAt: T0, lastPushedAt: T0 },
    followCountSince: 2,
    recentFollowers: [],
  });
  const pushes: Array<{ tag?: string; data?: Record<string, string> }> = [];
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    {
      db,
      push: async (_u, p) => void pushes.push(p as never),
      fcm: async () => {},
      now: () => later,
    },
  );
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].tag, "follow-agg-t1");
  assert.equal(pushes[0].data?.aggregated_count, "3");
  assert.deepEqual(calls.updates[0].data.lastPushedAt, later);
});

test("dedup 7-hari tetap jalan: refollow follower baris tunggal → skip total", async () => {
  const { db, calls } = makeDb({ dedupHit: true });
  const pushes: unknown[] = [];
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    { db, push: async (_u, p) => void pushes.push(p), fcm: async () => {}, now: () => T0 },
  );
  assert.equal(calls.creates.length, 0);
  assert.equal(calls.updates.length, 0);
  assert.equal(pushes.length, 0);
});

test("follower admin di agregat → avatar TIDAK bocor (drop dari array)", async () => {
  const { db, calls } = makeDb({
    aggRow: { id: "a1", createdAt: T0, lastPushedAt: null },
    followCountSince: 1,
    recentFollowers: [
      { user: { role: "ADMIN", profilePhotoUrl: "https://cdn/owner.jpg" } },
      { user: { role: "CUSTOMER", profilePhotoUrl: "https://cdn/budi.jpg" } },
    ],
  });
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    { db, push: async () => {}, fcm: async () => {}, now: () => T0 },
  );
  assert.deepEqual(calls.updates[0].data.actorAvatarUrls, [
    "https://cdn/budi.jpg",
  ]);
});

test("lastPushedAt null (baris pra-migration) → boleh push", async () => {
  const { db } = makeDb({
    aggRow: { id: "a1", createdAt: T0, lastPushedAt: null },
    followCountSince: 1,
    recentFollowers: [],
  });
  const pushes: unknown[] = [];
  await sendFollowNotification(
    { followerId: "f1", followingId: "t1" },
    { db, push: async (_u, p) => void pushes.push(p), fcm: async () => {}, now: () => T0 },
  );
  assert.equal(pushes.length, 1);
});
```

- [ ] **Step 3: Verifikasi gagal**

Run: `npx tsx --test tests/follow-aggregation-flow.test.ts`
Expected: FAIL — deps param belum ada / alur agregat belum ada.

- [ ] **Step 4: Implement alur agregasi**

Ganti isi `sendFollowNotification` (setelah blok dedup existing yang TIDAK berubah). Kode inti sesudah dedup:

```ts
    // ── Agregasi ala IG (spec 2026-07-24) ─────────────────────────────
    // Cari baris follow HIDUP (unread, dalam window) — tunggal ATAU sudah
    // agregat — untuk di-upgrade/di-update, alih-alih membuat baris baru.
    const liveRow = await db.announcement.findFirst({
      where: {
        targetUserId: params.followingId,
        source: SOCIAL_NOTIFICATION_SOURCE,
        eventType,
        createdAt: { gte: new Date(now.getTime() - FOLLOW_AGG_WINDOW_MS) },
        reads: { none: { userId: params.followingId } },
      },
      select: { id: true, createdAt: true, lastPushedAt: true },
      orderBy: { createdAt: "desc" },
    });

    if (liveRow) {
      // N per-ORANG: unique(followerId, followingId) di UserFollow menjamin
      // follow-unfollow-follow = 1 baris. Patokan TETAP createdAt baris
      // (bukan rolling now-30m) supaya 1 orang tak terhitung di 2 baris
      // (Keputusan 10). `1 +` = follower pembuat baris (follow-nya terjadi
      // sebelum baris dibuat, di luar gte).
      const sinceRow = await db.userFollow.count({
        where: {
          followingId: params.followingId,
          createdAt: { gte: liveRow.createdAt },
        },
      });
      const total = 1 + sinceRow;

      // ≤3 avatar follower terbaru, brand-safe (admin & tanpa-foto di-drop
      // oleh topLikerAvatars) — ambil 5 supaya drop masih bisa isi 3.
      const recent = await db.userFollow.findMany({
        where: { followingId: params.followingId },
        orderBy: { createdAt: "desc" },
        take: 5,
        select: { user: { select: { role: true, profilePhotoUrl: true } } },
      });
      const avatarUrls = topLikerAvatars(recent.map((r) => r.user));

      const aggTitle = buildFollowAggTitle(actorName, total);
      const aggBody = "Lihat siapa saja yang baru mengikutimu.";
      const aggUrl = "/akun/followers";
      const doPush = shouldRePush(liveRow.lastPushedAt, now);

      await db.announcement.update({
        where: { id: liveRow.id },
        data: {
          title: aggTitle,
          body: aggBody,
          url: aggUrl,
          aggregatedCount: total,
          // Aktor tunggal hilang di baris agregat (pola likeRowActorFields).
          actorName: null,
          actorAvatarUrl: null,
          actorId: null,
          actorAvatarUrls: avatarUrls,
          publishedAt: now,
          ...(doPush ? { lastPushedAt: now } : {}),
        },
      });

      if (doPush) {
        const aggPayload: PushPayload = {
          title: aggTitle,
          body: aggBody,
          url: aggUrl,
          tag: followAggTag(params.followingId),
          imageUrl: actorPhoto,
          renderClientSide: true,
          actorAvatarUrl: actorPhoto,
          data: {
            source: SOCIAL_NOTIFICATION_SOURCE,
            type: eventType,
            aggregated_count: String(total),
            url: aggUrl,
          },
        };
        await Promise.allSettled([
          push(params.followingId, aggPayload),
          fcm(params.followingId, aggPayload),
        ]);
      }
      return;
    }
```

Jalur create existing di bawahnya tetap, dengan 2 tambahan di `data` create: `lastPushedAt: now` dan (implisit) `aggregatedCount` biarkan null. `payload` create existing tidak berubah.

- [ ] **Step 5: Verifikasi lulus + regresi + kompilasi**

Run: `npx tsx --test tests/follow-aggregation-flow.test.ts && npx tsx --test tests/fcm-message-shape.test.ts && npx tsc --noEmit`
Expected: PASS semua.

- [ ] **Step 6: Commit**

```bash
git add lib/social/notifications.ts tests/follow-aggregation-flow.test.ts
git commit -m "feat(social): agregasi notif follow ala IG (update-in-window + re-push throttle 5m)"
```

---

### Task 5: Throttle re-push jalur like

**Files:**
- Modify: `lib/feed/activity-notifications.ts` (`sendLikeNotification`, cabang `recentUnread`)
- Test: `tests/follow-aggregation.test.ts` (helper `shouldRePush` sudah teruji Task 3 — task ini pakai review manual + tsc; perilaku DB-bound tidak ada seam injeksi di jalur like, konsisten dgn kondisi existing yang juga tanpa test DB)

**Interfaces:**
- Consumes: `shouldRePush`, `AGG_PUSH_THROTTLE_MS` (Task 3); kolom `lastPushedAt` (Task 1).

**Perilaku:** cabang update like (baris `recentUnread`) kini juga re-push ter-throttle — sebelumnya update in-app saja. Push pakai judul agregat like, `tag: feed-like-<postId>` (existing, sudah dipakai jalur create — Android replace by tag; iOS replace by collapse-id dari Task 2), `renderClientSide: true`, `prefCategory: "feed"`.

- [ ] **Step 1: Ambil `lastPushedAt` di query `recentUnread`**

Ubah `select: { id: true }` menjadi:

```ts
      select: { id: true, lastPushedAt: true },
```

- [ ] **Step 2: Re-push ter-throttle dalam cabang update**

Import di atas file:

```ts
import { shouldRePush } from "@/lib/social/follow-aggregation";
import { sendFcmToUser } from "@/lib/fcm";
import { sendPushToUser, type PushPayload } from "@/lib/push";
```

Dalam cabang `if (recentUnread) {` — setelah hitung `avatarUrls`, ganti blok `await prisma.announcement.update({...}); return;` dengan:

```ts
      const aggTitle = `${params.likeCount} orang menyukai Feed kamu`;
      const aggBody = `Postingan ${quoteFeedTitle(
        post.title
      )} mendapat beberapa like baru.`;
      const nowDate = new Date();
      const doPush = shouldRePush(recentUnread.lastPushedAt, nowDate);

      await prisma.announcement.update({
        where: { id: recentUnread.id },
        data: {
          title: aggTitle,
          body: aggBody,
          thumbnailUrl: thumb,
          ...likeRowActorFields(true, actorFields),
          actorAvatarUrls: avatarUrls,
          aggregatedCount: params.likeCount,
          publishedAt: nowDate,
          ...(doPush ? { lastPushedAt: nowDate } : {}),
        },
      });

      // Re-push ter-throttle (Keputusan 2 spec agregasi): tray ikut segar
      // ala IG — Android replace via tag, iOS via apns-collapse-id. Maks
      // 1 push per 5 menit per baris; di antaranya in-app saja (real-time
      // list menangkap gratis).
      if (doPush) {
        const likePayload: PushPayload = {
          title: aggTitle,
          body: aggBody,
          url: feedPostOwnerUrl(post.id),
          tag: `feed-like-${post.id}`,
          imageUrl: thumb,
          prefCategory: "feed",
          renderClientSide: true,
          actorAvatarUrl: actorFields.actorAvatarUrl,
          data: {
            source: SOCIAL_NOTIFICATION_SOURCE,
            type: "feed_new_like",
            post_id: post.id,
            like_count: String(params.likeCount),
            url: feedPostOwnerUrl(post.id),
          },
        };
        await Promise.allSettled([
          sendPushToUser(post.authorId, likePayload),
          sendFcmToUser(post.authorId, likePayload),
        ]);
      }
      return;
```

Catatan: `createFeedNotification` jalur create like TIDAK berubah (push pertama tetap instan); tambah saja `lastPushedAt` — di `lib/feed/notification-center.ts` `createFeedNotification`, dalam `prisma.announcement.create({ data: {...} })` tambahkan `lastPushedAt: new Date(),` (berlaku semua event yang lewat helper ini — akurat, karena create memang selalu push).

- [ ] **Step 3: Verifikasi kompilasi + suite regresi**

Run: `npx tsc --noEmit && npx tsx --test tests/fcm-message-shape.test.ts && npx tsx --test tests/follow-aggregation.test.ts && npx tsx --test tests/comment-notification-text.test.ts`
Expected: PASS semua.

- [ ] **Step 4: Commit**

```bash
git add lib/feed/activity-notifications.ts lib/feed/notification-center.ts
git commit -m "feat(feed): re-push ter-throttle 5m utk baris like agregat (tray segar ala IG)"
```

---

### Task 6: Read-path expose `aggregatedCount`

**Files:**
- Modify: `app/api/notifications/me/route.ts` (`mapAnnouncement` + pemanggil `resolveNotificationActor`)

**Interfaces:**
- Consumes: kolom `aggregatedCount` (Task 1).
- Produces: field API `aggregatedCount: number | null` di tiap item — dikonsumsi Flutter (Task 7).

- [ ] **Step 1: Tambah di tipe param + return `mapAnnouncement`**

Di signature `mapAnnouncement`, tambah setelah `actorId: string | null;`:

```ts
  aggregatedCount: number | null;
```

Di object return, tambah setelah `actorId: a.actorId,`:

```ts
    aggregatedCount: a.aggregatedCount,
```

- [ ] **Step 2: `isAggregate` pakai kontrak baru**

Di blok `resolveNotificationActor({...})`, ganti:

```ts
        isAggregate: (item.actorAvatarUrls?.length ?? 0) > 0,
```

menjadi:

```ts
        // Kontrak agregat = aggregatedCount (spec Keputusan 9). Fallback
        // panjang actorAvatarUrls utk baris like LAMA pra-migration yang
        // aggregatedCount-nya null tapi sudah agregat.
        isAggregate:
          (item.aggregatedCount ?? 0) > 1 ||
          (item.actorAvatarUrls?.length ?? 0) > 0,
```

- [ ] **Step 3: Verifikasi kompilasi**

Run: `npx tsc --noEmit`
Expected: sukses.

- [ ] **Step 4: Commit**

```bash
git add app/api/notifications/me/route.ts
git commit -m "feat(api): expose aggregatedCount di notifications/me (kontrak agregat client)"
```

---

### Task 7: Flutter — model + pill gating + tap agregat + deep-link `/akun/followers`

**Files:**
- Modify: `flutter_app/lib/models/app_notification.dart`
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (`NotificationRow` + `_navigateForNotification`)
- Modify: `flutter_app/lib/services/deep_link_service.dart` (case `akun`)
- Test: `flutter_app/test/notifications_redesign_widget_test.dart` (tambah kasus), `flutter_app/test/services/deep_link_followers_route_test.dart` (BARU)

**Interfaces:**
- Consumes: field API `aggregatedCount` (Task 6); `PublicProfileFollowListScreen` + pola `_ownPublicProfile()` (`member_screen.dart:393`).
- Produces: `AppNotification.aggregatedCount: int?`; getter `bool get isAggregated => (aggregatedCount ?? 0) > 1;`

- [ ] **Step 1: Model — field + parsing + copyWith**

`app_notification.dart`: tambah field setelah `actorAvatarUrls`:

```dart
  /// Jumlah orang di baris agregat (server: Announcement.aggregatedCount).
  /// Null / 1 = baris tunggal. KONTRAK gating pill/tap agregat — JANGAN
  /// pakai actorAvatarUrls.length (follower tanpa foto → array kosong).
  final int? aggregatedCount;
```

Constructor: `this.aggregatedCount,`. `fromApiJson`:

```dart
      aggregatedCount: (json['aggregatedCount'] as num?)?.toInt(),
```

`copyWith`: `aggregatedCount: aggregatedCount,`. Tambah getter:

```dart
  bool get isAggregated => (aggregatedCount ?? 0) > 1;
```

- [ ] **Step 2: Widget test failing — pill & tap gating**

Di `notifications_redesign_widget_test.dart`, ikuti pola test `NotificationRow` existing di file itu (pump `NotificationRow` dalam `MaterialApp`), tambah 3 kasus:

```dart
  testWidgets('follow agregat (aggregatedCount 2) → pill Ikuti HILANG',
      (tester) async {
    final notif = AppNotification(
      id: 'n1',
      title: 'sinta dan 1 lainnya mulai mengikuti kamu',
      body: '',
      type: 'social',
      eventType: 'user_followed',
      url: '/akun/followers',
      aggregatedCount: 2,
      createdAt: DateTime(2026, 7, 24),
      read: false,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationRow(notification: notif, onTap: () {}),
      ),
    ));
    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Mengikuti'), findsNothing);
  });

  testWidgets('follow tunggal (aggregatedCount null) → pill tetap tampil',
      (tester) async {
    final notif = AppNotification(
      id: 'n2',
      title: 'Pengikut baru',
      body: 'sinta mulai mengikuti kamu.',
      type: 'social',
      eventType: 'user_followed',
      url: '/u/sinta',
      createdAt: DateTime(2026, 7, 24),
      read: false,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationRow(notification: notif, onTap: () {}),
      ),
    ));
    expect(find.text('Ikuti'), findsOneWidget);
  });

  testWidgets(
      'agregat dgn actorAvatarUrls KOSONG (follower tanpa foto) → layout tetap benar (tanpa pill, tanpa crash)',
      (tester) async {
    final notif = AppNotification(
      id: 'n3',
      title: 'budi dan 3 lainnya mulai mengikuti kamu',
      body: '',
      type: 'social',
      eventType: 'user_followed',
      url: '/akun/followers',
      aggregatedCount: 4,
      actorAvatarUrls: const [],
      createdAt: DateTime(2026, 7, 24),
      read: false,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationRow(notification: notif, onTap: () {}),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Ikuti'), findsNothing);
  });
```

Run: `flutter test test/notifications_redesign_widget_test.dart` (dari `flutter_app/`)
Expected: kasus 1 & 3 FAIL (pill masih muncul).

- [ ] **Step 3: Implement gating di `NotificationRow`**

`notifications_screen.dart` — di `build` `NotificationRow`, ubah perhitungan `followBackUsername` (baris ~955):

```dart
    // Baris agregat (>=2 orang) kehilangan pill follow-back — tak ada 1
    // orang untuk di-follow-balik; tap baris → daftar follower sendiri
    // (spec agregasi Keputusan 3). Gate WAJIB via aggregatedCount, bukan
    // panjang actorAvatarUrls (follower tanpa foto → array kosong).
    final followBackUsername =
        notification.eventType?.toLowerCase() == 'user_followed' &&
                !notification.isAggregated
            ? extractProfileUsername(notification.url)
            : null;
```

- [ ] **Step 4: Tap agregat → daftar follower sendiri**

Di `_navigateForNotification` (state class `notifications_screen.dart`), dalam blok `if (eventType == 'user_followed') {`, tambah SEBELUM extract username:

```dart
      // Baris agregat → daftar follower milik SENDIRI (bukan profil 1
      // follower) — server sudah set url /akun/followers, tapi route by
      // intent lebih kokoh dari substring URL.
      if (item.isAggregated) {
        await _openOwnFollowers();
        return;
      }
```

Tambah method di state class yang sama (samakan pola `member_screen.dart:393-423` — `PublicProfile` dibangun dari `memberStore.profile`):

```dart
  /// Buka daftar follower milik sendiri (tap notif follow agregat).
  /// Reuse layar follow-list profil; profile dibangun dari memberStore
  /// (pola member_screen._ownPublicProfile). followersCount di header
  /// mungkin sedikit basi (hydrate ulang saat screen pop) — ok.
  Future<void> _openOwnFollowers() async {
    final profile = memberStore.profile;
    if (profile == null) {
      await Navigator.pushNamed(context, '/member');
      return;
    }
    final isOfficial = profile.isAdmin;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileFollowListScreen(
          profile: PublicProfile(
            id: profile.id,
            name: isOfficial ? kOfficialBrandName : (profile.name),
            username: profile.username,
            profilePhotoUrl: profile.profilePhotoUrl,
            bio: profile.bio,
            postCount: 0,
            followersCount: profile.followersCount,
            followingCount: profile.followingCount,
            isOwner: true,
            isOfficial: isOfficial,
          ),
          initialKind: FollowListKind.followers,
        ),
      ),
    );
  }
```

Import yang dibutuhkan (cek dulu yang sudah ada di file): `public_profile_follow_list_screen.dart`, `../models/public_profile.dart`, `../state/member_store.dart`, konstanta `kOfficialBrandName` (cari sumbernya: `grep -rn "kOfficialBrandName" flutter_app/lib | head -3` — pakai import yang sama dengan `member_screen.dart`). Kalau field `MemberProfile` beda nama (mis. `profile.name` nullable), sesuaikan dengan yang dipakai `member_screen._ownPublicProfile()` apa adanya.

- [ ] **Step 5: Deep-link case `/akun/followers` — test dulu**

`flutter_app/test/services/deep_link_followers_route_test.dart` (pola sama `push_notification_deep_link_race_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/deep_link_service.dart';

/// Case baru `/akun/followers` (notif follow agregat, spec agregasi
/// Keputusan 11 + gotcha PR #137: URL server tanpa case → nyasar /member).
void main() {
  testWidgets('deep-link /akun/followers membuka layar follower',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final service = DeepLinkService.test();
    service.navigatorKeyForTesting = navKey;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        initialRoute: '/',
        routes: {
          '/': (_) => const Scaffold(body: Text('BERANDA')),
          '/akun/followers': (_) => const Scaffold(body: Text('FOLLOWERS')),
          '/member': (_) => const Scaffold(body: Text('AKUN')),
        },
      ),
    );

    await service.handleExternalUri(
      Uri.parse('https://natalopetshop.com/akun/followers'),
    );
    await tester.pumpAndSettle();

    expect(find.text('FOLLOWERS'), findsOneWidget,
        reason: '/akun/followers WAJIB punya case sendiri, '
            'bukan jatuh ke /member (gotcha PR #137)');
    expect(find.text('AKUN'), findsNothing);
  });
}
```

Run: `flutter test test/services/deep_link_followers_route_test.dart`
Expected: FAIL — mendarat di AKUN (`/member`).

Catatan implementer: kalau `handleExternalUri` bukan nama method publiknya, cek nama yang dipakai `push_notification_service.dart:_handleDeepLink` (`deepLinkService.handleExternalUri(uri)`) — itu yang benar. Kalau route-map test tidak cocok dengan cara `_handleLegacy` push (pakai `nav.pushNamed('/akun/followers')`), pertahankan bentuk pushNamed ini.

- [ ] **Step 6: Implement case di `_handleLegacy`**

`deep_link_service.dart`, dalam `case 'akun':`, tambah cabang SEBELUM `else` terakhir (setelah cabang `postingan-saya`):

```dart
        } else if (segments.length > 1 && segments[1] == 'followers') {
          // /akun/followers — notif follow agregat ("X dan N lainnya mulai
          // mengikuti kamu") → daftar follower milik sendiri. WAJIB case
          // eksplisit (gotcha PR #137: tanpa ini jatuh ke /member).
          nav.pushNamed('/akun/followers');
```

Lalu daftarkan route `'/akun/followers'` di route-map app (cari lokasi: `grep -n "'/member/orders'" flutter_app/lib/main.dart` — tambahkan di map yang sama):

```dart
        '/akun/followers': (context) => const OwnFollowersScreen(),
```

`OwnFollowersScreen` = wrapper stateless kecil BARU di `flutter_app/lib/screens/own_followers_screen.dart` yang membangun `PublicProfileFollowListScreen` dari `memberStore.profile` (logika sama `_openOwnFollowers` Task 7 Step 4 — supaya jalur named-route cold-start tak butuh context layar notifikasi):

```dart
import 'package:flutter/material.dart';

import '../models/public_profile.dart';
import '../screens/public_profile_follow_list_screen.dart';
import '../state/member_store.dart';
// import konstanta kOfficialBrandName dari sumber yang sama dengan
// member_screen.dart (cek grep saat implement).

/// Daftar follower milik sendiri via named-route (deep-link
/// /akun/followers dari notif follow agregat). Kalau belum login /
/// profil belum ter-hydrate → redirect ke /member.
class OwnFollowersScreen extends StatelessWidget {
  const OwnFollowersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = memberStore.profile;
    if (profile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/member');
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final isOfficial = profile.isAdmin;
    return PublicProfileFollowListScreen(
      profile: PublicProfile(
        id: profile.id,
        name: isOfficial ? kOfficialBrandName : profile.name,
        username: profile.username,
        profilePhotoUrl: profile.profilePhotoUrl,
        bio: profile.bio,
        postCount: 0,
        followersCount: profile.followersCount,
        followingCount: profile.followingCount,
        isOwner: true,
        isOfficial: isOfficial,
      ),
      initialKind: FollowListKind.followers,
    );
  }
}
```

Refactor `_openOwnFollowers` (Step 4) supaya cukup `Navigator.pushNamed(context, '/akun/followers')` — satu sumber kebenaran, hapus duplikasi build-profile.

- [ ] **Step 7: Verifikasi semua tes Flutter**

Run (dari `flutter_app/`): `flutter analyze lib/models/app_notification.dart lib/screens/notifications_screen.dart lib/screens/own_followers_screen.dart lib/services/deep_link_service.dart && flutter test test/notifications_redesign_widget_test.dart test/services/deep_link_followers_route_test.dart test/notifications_redesign_logic_test.dart`
Expected: analyze clean, semua tes PASS.

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/models/app_notification.dart flutter_app/lib/screens/notifications_screen.dart flutter_app/lib/screens/own_followers_screen.dart flutter_app/lib/services/deep_link_service.dart flutter_app/lib/main.dart flutter_app/test/notifications_redesign_widget_test.dart flutter_app/test/services/deep_link_followers_route_test.dart
git commit -m "feat(app): baris notif follow agregat — pill off, tap ke daftar follower, deep-link /akun/followers"
```

---

### Task 8: Suite penuh + regresi lintas-file

**Files:** tidak ada file baru — verifikasi.

- [ ] **Step 1: Backend penuh**

Run: `npx tsc --noEmit && for f in tests/follow-aggregation.test.ts tests/follow-aggregation-flow.test.ts tests/fcm-message-shape.test.ts tests/notification-actor-fields.test.ts tests/comment-notification-text.test.ts tests/feed-tagged-notification.test.ts; do npx tsx --test "$f" || exit 1; done`
Expected: PASS semua.

- [ ] **Step 2: Flutter penuh (suite notifikasi + deep-link)**

Run (dari `flutter_app/`): `flutter test test/notifications_redesign_widget_test.dart test/notifications_redesign_logic_test.dart test/notification_order_routing_test.dart test/app_notification_comment_id_test.dart test/services/`
Expected: PASS semua.

- [ ] **Step 3: Commit penutup (kalau ada perbaikan)**

```bash
git add -A && git commit -m "test: regresi lintas-file agregasi notif" || echo "clean"
```

---

## Di luar plan (dari spec, jangan dikerjakan)

Agregasi komentar/mention/tag, badge count bottom-nav, preferensi per-event, quiet hours, soft-delete UserFollow, layar "follower dalam window ini". Migration ke DB production di-apply terpisah (pola repo: migration file dulu, apply saat rilis). Device-verify (Android+iOS replace-not-stack, termasuk notif ORDER ber-tag di iOS ikut jadi replace — Keputusan 7) setelah rilis.
