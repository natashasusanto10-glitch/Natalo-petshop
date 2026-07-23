# Spec B — Tandai Orang (Tag People) ala Instagram — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** User bisa menandai user lain di post feed (titik interaktif di foto ala IG, daftar nama untuk video), yang ditandai dapat notifikasi `feed_tagged`, post masuk tab **Ditandai** di profil (mengisi cangkang kosong Spec A), dan yang ditandai punya kendali: hapus tag dirinya + sembunyikan dari profilnya.

**Architecture:** Tabel baru `FeedTaggedUser` meniru pola `FeedPostProduct` (relasi FeedPost, unik per user per post). Backend: validasi + serialisasi tag di helper murni `lib/feed/tagged-users.ts` (testable tanpa DB, dipakai POST create + serializer), endpoint self-service `/api/feed/posts/[id]/tags/me` (DELETE/PATCH), dan perluasan `content=tagged` di endpoint profil publik yang juga dipakai profil sendiri. Flutter: model `FeedTaggedUser` di `feed_post.dart` (lossless round-trip), layar composer `FeedTagPeopleScreen` (foto: pill drag-and-drop; video: list), overlay pill di viewer (`_PhotoCarouselPostView`) + sheet video, plumbing tag mengikuti jalur `taggedProductIds` existing lewat `feedUploadStore`.

**Tech Stack:** Next.js App Router + Prisma (Neon Postgres), node:test via `tsx --test` untuk backend (BUKAN vitest — konvensi repo), Flutter/Dart + `flutter_test`, UploadThing/Bunny existing untuk media (tidak disentuh).

**Spec sumber:** `docs/superpowers/specs/2026-07-23-tag-people-spec-b-design.md` — baca dulu kalau ragu konteks.

## Global Constraints

Disalin verbatim dari spec (mengikat untuk SEMUA task):

- Maks **20 tag per post**; unik `(feedPostId, taggedUserId)` — satu orang satu tag per post.
- Koordinat `x`,`y` = pecahan **0–1** dari lebar/tinggi foto (Float nullable; null untuk video). `mediaId` nullable (null untuk video).
- **Migration file sungguhan + apply ke kedua database Neon — BUKAN `db push`** (insiden schema-drift product-video).
- **WAJIB `lib/social/brand-user.ts`** di setiap endpoint feed/social yang menyentuh identitas user: akun official tampil sebagai brand "Natalo Petshop", bukan data asli pemilik.
- `FeedPost.toJson` WAJIB **lossless** — `taggedUsers` ikut `fromJson` DAN `toJson`, round-trip utuh.
- Animasi pill muncul: pop scale-fade **`easeOutCubic`** (konsisten Spec A).
- **Semua teks UI bahasa Indonesia.**
- Push notif: **`sendPushToUser` + `sendFcmToUser` TANPA `sendApnsToUser`** (gotcha notif iOS dobel).
- Notif `feed_tagged` pakai **`prefCategory: "feed"`** (toggle "Aktivitas Feed" existing). Tidak ada notifikasi ke diri sendiri.
- `mediaIndex`→`mediaId` di-mapping **dalam transaksi yang sama** dengan `feedMedia.createMany`.
- Remove/hide tag **hanya boleh oleh user yang ditandai** (baris miliknya sendiri).
- `hidden=true` di-exclude dari tab Ditandai di **kedua** layar (profil sendiri & publik — hidden berlaku global).
- Badge viewer **selalu tampil** (tanpa auto-fade — keputusan spec).
- Overlay pill **tidak boleh merusak double-tap like** (pakai `onTap` + `onDoubleTap` di GestureDetector yang sama — Flutter menunda single-tap otomatis).
- Deep-link notif: `/feed/<postId>` (case `feed` sudah ada di `deep_link_service.dart:322` — jangan bikin URL baru tanpa case).
- Nomor baris di plan ini snapshot saat penulisan — kalau meleset, cari via string/nama simbol, bukan baris mentah.

---

### Task 1: Prisma model `FeedTaggedUser` + migration

**Files:**
- Modify: `prisma/schema.prisma` (model `FeedPost` ~line 1266 tambah relasi, model `FeedMedia` ~1387 tambah relasi, model baru setelah `FeedPostProduct` ~1420, model `User` tambah relasi `feedTaggedIn`)
- Create: `prisma/migrations/<timestamp>_add_feed_tagged_user/migration.sql` (di-generate Prisma)

**Interfaces:**
- Produces: model Prisma `FeedTaggedUser { id, feedPostId, mediaId?, taggedUserId, x?, y?, hidden, createdAt }` + relasi `FeedPost.taggedUsers`, `FeedMedia.taggedUsers`, `User.feedTaggedIn`.

- [ ] **Step 1: Tambah model di schema.prisma**

Setelah model `FeedPostProduct` (sekitar line 1445), tambahkan:

```prisma
// Tag People (Spec B) — user lain yang ditandai di post, ala Instagram.
// Foto: mediaId + koordinat x/y (pecahan 0-1 dari dimensi foto).
// Video: mediaId/x/y null — tag berupa daftar nama saja.
// hidden: user yang ditandai menyembunyikan post ini dari tab Ditandai
// profilnya (berlaku global — profil publik juga exclude).
model FeedTaggedUser {
  id           String     @id @default(cuid())
  feedPostId   String
  feedPost     FeedPost   @relation(fields: [feedPostId], references: [id], onDelete: Cascade)
  mediaId      String?
  media        FeedMedia? @relation(fields: [mediaId], references: [id], onDelete: Cascade)
  taggedUserId String
  taggedUser   User       @relation("FeedTaggedIn", fields: [taggedUserId], references: [id], onDelete: Cascade)
  x            Float?
  y            Float?
  hidden       Boolean    @default(false)
  createdAt    DateTime   @default(now())

  // Satu orang satu tag per post (sesuai IG).
  @@unique([feedPostId, taggedUserId])
  // Query tab Ditandai: WHERE taggedUserId=X AND hidden=false.
  @@index([taggedUserId, hidden])
  @@index([feedPostId])
}
```

Di model `FeedPost`, di blok relasi (dekat `taggedProducts FeedPostProduct[]` ~line 1370), tambahkan:

```prisma
  // Tag People (Spec B) — user yang ditandai di post ini.
  taggedUsers    FeedTaggedUser[]
```

Di model `FeedMedia` (setelah `createdAt` ~line 1415), tambahkan:

```prisma
  taggedUsers FeedTaggedUser[]
```

Di model `User`, di blok relasi feed (cari `FeedAuthor` untuk lokasi blok), tambahkan:

```prisma
  feedTaggedIn FeedTaggedUser[] @relation("FeedTaggedIn")
```

- [ ] **Step 2: Generate migration file sungguhan (BUKAN db push)**

```bash
npx prisma migrate dev --name add_feed_tagged_user
```

Verifikasi file `prisma/migrations/*_add_feed_tagged_user/migration.sql` berisi `CREATE TABLE "FeedTaggedUser"` + unique index `("feedPostId","taggedUserId")` + index `("taggedUserId","hidden")`. Kalau env DB lokal tidak tersedia, pakai `npx prisma migrate dev --create-only --name add_feed_tagged_user` lalu commit file-nya — apply ke Neon dilakukan saat deploy (lihat Catatan eksekusi).

- [ ] **Step 3: Verifikasi client & typecheck**

```bash
npx prisma generate && npx tsc --noEmit
```

Expected: exit 0, `prisma.feedTaggedUser` tersedia di client.

- [ ] **Step 4: Commit**

```bash
git add prisma/schema.prisma prisma/migrations && git commit -m "feat(feed): tabel FeedTaggedUser untuk Tag People (Spec B)"
```

---

### Task 2: Helper validasi + serialisasi `lib/feed/tagged-users.ts` (TDD)

**Files:**
- Create: `lib/feed/tagged-users.ts`
- Test: `tests/feed-tagged-users.test.ts`

**Interfaces:**
- Produces:
  - `const MAX_TAGGED_USERS_PER_POST = 20`
  - `parseTaggedUsersInput(raw: unknown, opts: { mediaCount: number; isVideo: boolean }): { ok: true; tags: Array<{ userId: string; mediaIndex: number | null; x: number | null; y: number | null }> } | { ok: false; error: string }`
  - `serializeTaggedUsers(rows: Array<{ mediaId: string | null; x: number | null; y: number | null; hidden: boolean; taggedUser: { id: string; username: string | null; name: string | null; role: string; profilePhotoUrl: string | null } }>, mediaIdToIndex: Map<string, number>): Array<{ userId: string; username: string | null; name: string; profilePhotoUrl: string | null; mediaId: string | null; mediaIndex: number | null; x: number | null; y: number | null }>`
- Consumes: `brandDisplayName`, `brandPhotoUrl` dari `lib/social/brand-user.ts`.

- [ ] **Step 1: Tulis test yang gagal**

Buat `tests/feed-tagged-users.test.ts`:

```ts
import test from "node:test";
import assert from "node:assert/strict";
import {
  MAX_TAGGED_USERS_PER_POST,
  parseTaggedUsersInput,
  serializeTaggedUsers,
} from "../lib/feed/tagged-users";

test("limit 20 tag per post", () => {
  const raw = Array.from({ length: 21 }, (_, i) => ({
    userId: `u${i}`,
    mediaIndex: 0,
    x: 0.5,
    y: 0.5,
  }));
  const result = parseTaggedUsersInput(raw, { mediaCount: 3, isVideo: false });
  assert.equal(result.ok, false);
  assert.equal(MAX_TAGGED_USERS_PER_POST, 20);
});

test("koordinat harus 0-1", () => {
  const bad = parseTaggedUsersInput(
    [{ userId: "u1", mediaIndex: 0, x: 1.2, y: 0.5 }],
    { mediaCount: 1, isVideo: false },
  );
  assert.equal(bad.ok, false);
  const good = parseTaggedUsersInput(
    [{ userId: "u1", mediaIndex: 0, x: 0, y: 1 }],
    { mediaCount: 1, isVideo: false },
  );
  assert.equal(good.ok, true);
});

test("mediaIndex harus menunjuk foto yang ada", () => {
  const result = parseTaggedUsersInput(
    [{ userId: "u1", mediaIndex: 3, x: 0.5, y: 0.5 }],
    { mediaCount: 3, isVideo: false },
  );
  assert.equal(result.ok, false);
});

test("duplikat userId di-dedupe (yang pertama menang)", () => {
  const result = parseTaggedUsersInput(
    [
      { userId: "u1", mediaIndex: 0, x: 0.1, y: 0.1 },
      { userId: "u1", mediaIndex: 1, x: 0.9, y: 0.9 },
    ],
    { mediaCount: 2, isVideo: false },
  );
  assert.equal(result.ok, true);
  if (result.ok) {
    assert.equal(result.tags.length, 1);
    assert.equal(result.tags[0].mediaIndex, 0);
  }
});

test("video: mediaIndex/x/y dipaksa null", () => {
  const result = parseTaggedUsersInput(
    [{ userId: "u1" }, { userId: "u2", x: 0.5, y: 0.5, mediaIndex: 0 }],
    { mediaCount: 0, isVideo: true },
  );
  assert.equal(result.ok, true);
  if (result.ok) {
    for (const tag of result.tags) {
      assert.equal(tag.mediaIndex, null);
      assert.equal(tag.x, null);
      assert.equal(tag.y, null);
    }
  }
});

test("raw bukan array / kosong → ok dengan tags []", () => {
  assert.deepEqual(parseTaggedUsersInput(undefined, { mediaCount: 1, isVideo: false }), {
    ok: true,
    tags: [],
  });
  assert.deepEqual(parseTaggedUsersInput([], { mediaCount: 1, isVideo: false }), {
    ok: true,
    tags: [],
  });
});

test("serialize: admin di-brand-kan, mediaId → mediaIndex", () => {
  const rows = [
    {
      mediaId: "m2",
      x: 0.3,
      y: 0.7,
      hidden: false,
      taggedUser: {
        id: "admin1",
        username: "natalopetshop",
        name: "Natasha",
        role: "ADMIN",
        profilePhotoUrl: "https://cdn/x/natasha.jpg",
      },
    },
    {
      mediaId: "m1",
      x: 0.5,
      y: 0.5,
      hidden: false,
      taggedUser: {
        id: "cust1",
        username: "asiong",
        name: "Asiong",
        role: "CUSTOMER",
        profilePhotoUrl: "https://cdn/x/asiong.jpg",
      },
    },
  ];
  const out = serializeTaggedUsers(
    rows,
    new Map([
      ["m1", 0],
      ["m2", 1],
    ]),
  );
  assert.equal(out[0].name, "Natalo Petshop Official");
  assert.equal(out[0].profilePhotoUrl, null); // klien render logo brand
  assert.equal(out[0].mediaIndex, 1);
  assert.equal(out[1].name, "Asiong");
  assert.equal(out[1].mediaIndex, 0);
});
```

- [ ] **Step 2: Jalankan test — expect gagal**

```bash
npx tsx --test tests/feed-tagged-users.test.ts
```

Expected failure: `Cannot find module '../lib/feed/tagged-users'`.

- [ ] **Step 3: Implement helper**

Buat `lib/feed/tagged-users.ts`:

```ts
/**
 * Tag People (Spec B) — validasi input + serialisasi FeedTaggedUser.
 * Pure functions (no Prisma) supaya bisa di-unit-test via node:test.
 * Dipakai POST /api/feed/posts, POST /api/feed/bunny/upload-url, dan
 * semua serializer post yang membawa taggedUsers[].
 */
import { brandDisplayName, brandPhotoUrl } from "@/lib/social/brand-user";

export const MAX_TAGGED_USERS_PER_POST = 20;

export type TaggedUserInput = {
  userId: string;
  mediaIndex: number | null;
  x: number | null;
  y: number | null;
};

export type ParseTaggedUsersResult =
  | { ok: true; tags: TaggedUserInput[] }
  | { ok: false; error: string };

function isFraction(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 1;
}

export function parseTaggedUsersInput(
  raw: unknown,
  opts: { mediaCount: number; isVideo: boolean },
): ParseTaggedUsersResult {
  if (raw === undefined || raw === null) return { ok: true, tags: [] };
  if (!Array.isArray(raw)) {
    return { ok: false, error: "taggedUsers harus berupa array." };
  }
  if (raw.length > MAX_TAGGED_USERS_PER_POST) {
    return {
      ok: false,
      error: `Maksimal ${MAX_TAGGED_USERS_PER_POST} orang yang bisa ditandai per postingan.`,
    };
  }
  const seen = new Set<string>();
  const tags: TaggedUserInput[] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null) {
      return { ok: false, error: "Entri taggedUsers tidak valid." };
    }
    const entry = item as Record<string, unknown>;
    const userId = String(entry.userId ?? "").trim();
    if (!userId) return { ok: false, error: "userId tag wajib diisi." };
    if (seen.has(userId)) continue; // dedupe — tag pertama menang
    seen.add(userId);

    if (opts.isVideo) {
      // Video: daftar nama saja — koordinat & media diabaikan.
      tags.push({ userId, mediaIndex: null, x: null, y: null });
      continue;
    }

    const rawIndex = entry.mediaIndex;
    const mediaIndex =
      typeof rawIndex === "number" && Number.isInteger(rawIndex) ? rawIndex : NaN;
    if (!Number.isInteger(mediaIndex) || mediaIndex < 0 || mediaIndex >= opts.mediaCount) {
      return { ok: false, error: "mediaIndex tag menunjuk foto yang tidak ada." };
    }
    if (!isFraction(entry.x) || !isFraction(entry.y)) {
      return { ok: false, error: "Koordinat tag harus di rentang 0-1." };
    }
    tags.push({ userId, mediaIndex, x: entry.x, y: entry.y });
  }
  return { ok: true, tags };
}

export type TaggedUserRow = {
  mediaId: string | null;
  x: number | null;
  y: number | null;
  hidden: boolean;
  taggedUser: {
    id: string;
    username: string | null;
    name: string | null;
    role: string;
    profilePhotoUrl: string | null;
  };
};

export type SerializedTaggedUser = {
  userId: string;
  username: string | null;
  name: string;
  profilePhotoUrl: string | null;
  mediaId: string | null;
  mediaIndex: number | null;
  x: number | null;
  y: number | null;
};

/**
 * Shape response taggedUsers[] untuk semua endpoint post. Identitas akun
 * official WAJIB di-brand-kan (brand-user.ts) — nama/foto asli pemilik
 * tidak boleh bocor.
 */
export function serializeTaggedUsers(
  rows: TaggedUserRow[],
  mediaIdToIndex: Map<string, number>,
): SerializedTaggedUser[] {
  return rows.map((row) => ({
    userId: row.taggedUser.id,
    username: row.taggedUser.username,
    name: brandDisplayName(row.taggedUser.role, row.taggedUser.name),
    profilePhotoUrl: brandPhotoUrl(row.taggedUser.role, row.taggedUser.profilePhotoUrl),
    mediaId: row.mediaId,
    mediaIndex: row.mediaId != null ? mediaIdToIndex.get(row.mediaId) ?? null : null,
    x: row.x,
    y: row.y,
  }));
}

/**
 * Select fragment standar untuk relasi taggedUsers di query post.
 * hidden ikut di-select supaya serializer/route bisa filter kalau perlu.
 */
export const TAGGED_USERS_SELECT = {
  orderBy: { createdAt: "asc" as const },
  select: {
    mediaId: true,
    x: true,
    y: true,
    hidden: true,
    taggedUser: {
      select: {
        id: true,
        username: true,
        name: true,
        role: true,
        profilePhotoUrl: true,
      },
    },
  },
} as const;
```

- [ ] **Step 4: Jalankan test — expect hijau**

```bash
npx tsx --test tests/feed-tagged-users.test.ts && npx tsc --noEmit
```

- [ ] **Step 5: Commit**

```bash
git add lib/feed/tagged-users.ts tests/feed-tagged-users.test.ts && git commit -m "feat(feed): helper validasi + serialisasi tagged users (Spec B)"
```

---

### Task 3: POST create menerima `taggedUsers` (foto + video) + simpan dalam transaksi

**Files:**
- Modify: `app/api/feed/posts/route.ts` (`CreatePostBody` ~line 86, validasi sebelum transaksi, dalam `prisma.$transaction` ~line 497 setelah `feedMedia.createMany` ~line 578)
- Modify: `app/api/feed/bunny/upload-url/route.ts` (body `taggedUsers` untuk video, simpan di transaksi ~line 297)

**Interfaces:**
- Consumes: `parseTaggedUsersInput`, `MAX_TAGGED_USERS_PER_POST` (Task 2); `prisma.feedTaggedUser` (Task 1).
- Produces: kontrak body `taggedUsers: [{userId, mediaIndex, x, y}]` (foto) / `[{userId}]` (video).

- [ ] **Step 1: Tulis test validasi tambahan (failing)**

Tambah di `tests/feed-tagged-users.test.ts` (kontrak yang dipakai route — memastikan pesan error stabil untuk client):

```ts
test("pesan error limit menyebut angka 20 (dipakai snackbar client)", () => {
  const raw = Array.from({ length: 21 }, (_, i) => ({
    userId: `u${i}`,
    mediaIndex: 0,
    x: 0.5,
    y: 0.5,
  }));
  const result = parseTaggedUsersInput(raw, { mediaCount: 1, isVideo: false });
  assert.equal(result.ok, false);
  if (!result.ok) assert.match(result.error, /20/);
});
```

- [ ] **Step 2: Jalankan — expect gagal** (test baru belum lolos kalau pesan tidak memuat "20"; kalau sudah lolos dari Task 2, lanjut — test ini tetap berharga sebagai kunci kontrak)

```bash
npx tsx --test tests/feed-tagged-users.test.ts
```

- [ ] **Step 3: Wire di `app/api/feed/posts/route.ts`**

1. Import:

```ts
import {
  parseTaggedUsersInput,
  type TaggedUserInput,
} from "@/lib/feed/tagged-users";
```

2. Tambah field di `CreatePostBody` (setelah `images?` ~line 117):

```ts
  // Tag People (Spec B): user lain yang ditandai. Foto: mediaIndex +
  // koordinat 0-1. Video: cukup userId (mediaIndex/x/y diabaikan).
  taggedUsers?: Array<{
    userId?: string;
    mediaIndex?: number | null;
    x?: number | null;
    y?: number | null;
  }>;
```

3. Setelah blok validasi photo (`photoInputs` sudah terbentuk, sebelum `resolveInitialPostStatus` ~line 484), tambahkan:

```ts
  // ── Tag People (Spec B) ───────────────────────────────────────────
  const taggedParse = parseTaggedUsersInput(body.taggedUsers, {
    mediaCount: kind === "PHOTO_CAROUSEL" ? photoInputs.length : 0,
    isVideo: kind !== "PHOTO_CAROUSEL",
  });
  if (!taggedParse.ok) {
    return NextResponse.json({ error: taggedParse.error }, { status: 400 });
  }
  let taggedUsers: TaggedUserInput[] = taggedParse.tags;
  if (taggedUsers.length > 0) {
    // Validasi user benar-benar ada (dan punya username → bisa dinavigasi).
    const found = await prisma.user.findMany({
      where: { id: { in: taggedUsers.map((t) => t.userId) } },
      select: { id: true },
    });
    if (found.length !== taggedUsers.length) {
      return NextResponse.json(
        { error: "Ada akun yang ditandai tapi tidak ditemukan." },
        { status: 400 },
      );
    }
  }
```

4. Di DALAM `prisma.$transaction`, SETELAH blok `feedMedia.createMany` (~line 578), tambahkan (mapping mediaIndex→mediaId di transaksi yang sama — konstrain spec):

```ts
    // Tag People — map mediaIndex → FeedMedia.id yang baru dibuat.
    // WAJIB dalam transaksi yang sama dengan feedMedia.createMany.
    if (taggedUsers.length > 0) {
      const mediaRows =
        kind === "PHOTO_CAROUSEL"
          ? await tx.feedMedia.findMany({
              where: { postId: created.id },
              orderBy: { sortOrder: "asc" },
              select: { id: true },
            })
          : [];
      await tx.feedTaggedUser.createMany({
        data: taggedUsers.map((tag) => ({
          feedPostId: created.id,
          taggedUserId: tag.userId,
          mediaId:
            tag.mediaIndex != null ? mediaRows[tag.mediaIndex]?.id ?? null : null,
          x: tag.x,
          y: tag.y,
        })),
        skipDuplicates: true,
      });
    }
```

- [ ] **Step 4: Wire di `app/api/feed/bunny/upload-url/route.ts` (jalur video)**

Video customer di-create lewat route provision ini (BUKAN `/api/feed/posts` — lihat `bunny_upload_service.dart:118`). Tambahkan hal yang sama:

1. Import `parseTaggedUsersInput`, `type TaggedUserInput` dari `@/lib/feed/tagged-users`.
2. Tambah `taggedUsers?: unknown;` di type body (~line 111 dekat `productIds?: unknown`).
3. Setelah validasi `productIds` (~line 180), tambahkan:

```ts
  const taggedParse = parseTaggedUsersInput(body.taggedUsers, {
    mediaCount: 0,
    isVideo: true,
  });
  if (!taggedParse.ok) {
    return NextResponse.json({ error: taggedParse.error }, { status: 400 });
  }
  let taggedUsers: TaggedUserInput[] = taggedParse.tags;
  if (taggedUsers.length > 0) {
    const found = await prisma.user.findMany({
      where: { id: { in: taggedUsers.map((t) => t.userId) } },
      select: { id: true },
    });
    if (found.length !== taggedUsers.length) {
      return NextResponse.json(
        { error: "Ada akun yang ditandai tapi tidak ditemukan." },
        { status: 400 },
      );
    }
  }
```

4. Di dalam `prisma.$transaction` (~line 297), setelah `tx.feedPost.create`, tambahkan:

```ts
    if (taggedUsers.length > 0) {
      await tx.feedTaggedUser.createMany({
        data: taggedUsers.map((tag) => ({
          feedPostId: created.id,
          taggedUserId: tag.userId,
          mediaId: null,
          x: null,
          y: null,
        })),
        skipDuplicates: true,
      });
    }
```

- [ ] **Step 5: Verifikasi + commit**

```bash
npx tsx --test tests/feed-tagged-users.test.ts && npx tsc --noEmit
git add app/api/feed/posts/route.ts app/api/feed/bunny/upload-url/route.ts tests/feed-tagged-users.test.ts && git commit -m "feat(feed): POST create terima taggedUsers foto+video (Spec B)"
```

---

### Task 4: `taggedUsers[]` di semua serializer post + `content=tagged` di profil

**Files:**
- Modify: `lib/feed/queries.ts` (select `listFeedPosts` ~line 275 area `taggedProducts`, serializer ~line 541)
- Modify: `app/api/u/[username]/route.ts` (`normalizeContentFilter` ~line 99, `contentWhere` ~line 152, select ~line 195, serializer post, `ProfileContentFilter` ~line 64)
- Modify: `app/api/feed/my-posts/route.ts` (select + serializer)
- Modify: `app/api/feed/posts/[id]/route.ts` (select + serializer single post)
- Test: `tests/feed-tagged-users.test.ts` (sudah meng-cover brand-safety serializer di Task 2)

**Interfaces:**
- Consumes: `TAGGED_USERS_SELECT`, `serializeTaggedUsers` (Task 2).
- Produces: field response `taggedUsers: [{userId, username, name, profilePhotoUrl, mediaId, mediaIndex, x, y}]` di feed list, single post, profil publik, my-posts; filter `content=tagged` di `GET /api/u/[username]`.

- [ ] **Step 1: `lib/feed/queries.ts`**

1. Import `TAGGED_USERS_SELECT, serializeTaggedUsers` dari `@/lib/feed/tagged-users`.
2. Di select `listFeedPosts` (setelah blok `media:` ~line 317): `taggedUsers: TAGGED_USERS_SELECT,`
3. Di serializer (return object per post, dekat `taggedProducts` ~line 541), tambahkan:

```ts
      taggedUsers: serializeTaggedUsers(
        p.taggedUsers,
        new Map(p.media.map((m, index) => [m.id, index])),
      ),
```

(`p.media` sudah di-order `sortOrder asc` di select — index array = mediaIndex.)

- [ ] **Step 2: `app/api/u/[username]/route.ts` — select, serializer, dan `content=tagged`**

1. Import `TAGGED_USERS_SELECT, serializeTaggedUsers` dari `@/lib/feed/tagged-users`.
2. `type ProfileContentFilter = "all" | "video" | "shoppable" | "tagged";` dan `normalizeContentFilter` (~line 99):

```ts
function normalizeContentFilter(raw: string | null): ProfileContentFilter {
  return raw === "video" || raw === "shoppable" || raw === "tagged" ? raw : "all";
}
```

3. Where — untuk `tagged`, post BUKAN milik author profil (post orang lain yang menandai dia), jadi `baseWhere.authorId` tidak berlaku. Ganti konstruksi `listingWhere` (~line 152):

```ts
  const contentWhere: Prisma.FeedPostWhereInput =
    content === "video"
      ? { videoUrl: { not: null } }
      : content === "shoppable"
      ? {
          OR: [{ productId: { not: null } }, { taggedProducts: { some: {} } }],
        }
      : {};
  // Tab Ditandai (Spec B): post siapa pun yang menandai target user,
  // exclude yang user itu sembunyikan (hidden berlaku global).
  const taggedWhere: Prisma.FeedPostWhereInput = {
    taggedUsers: { some: { taggedUserId: target.id, hidden: false } },
    kind: { in: [...new Set([...VISIBLE_KINDS, ...ADMIN_VISIBLE_KINDS])] },
    status: "ACTIVE",
    deletedAt: null,
    encodingStatus: "ready",
  };
  const listingWhere: Prisma.FeedPostWhereInput =
    content === "tagged" ? taggedWhere : { AND: [baseWhere, contentWhere] };
```

(`totalCount` untuk header stats tetap pakai `baseWhere` — jumlah postingan milik user, tidak berubah.)

4. Di select `prisma.feedPost.findMany` (setelah blok `media:` ~line 210): `taggedUsers: TAGGED_USERS_SELECT,`. Untuk `content=tagged` juga select `author: { select: { id: true, name: true, username: true, role: true, profilePhotoUrl: true } }` supaya kartu grid bisa render author asli post (bukan pemilik profil) — serialize author lewat `brandDisplayName`/`brandPhotoUrl` (sudah di-import di file ini).
5. Di serializer post response, tambahkan:

```ts
      taggedUsers: serializeTaggedUsers(
        post.taggedUsers,
        new Map(post.media.map((m, index) => [m.id, index])),
      ),
```

- [ ] **Step 3: `app/api/feed/my-posts/route.ts` dan `app/api/feed/posts/[id]/route.ts`**

Sama polanya: import helper, tambah `taggedUsers: TAGGED_USERS_SELECT` di select `feedPost` (dekat select `media`), dan `taggedUsers: serializeTaggedUsers(post.taggedUsers, new Map(post.media.map((m, i) => [m.id, i])))` di serializer masing-masing. Kedua file sudah import dari `lib/social/brand-user.ts` — brand-safety datang dari `serializeTaggedUsers` sendiri.

- [ ] **Step 4: Verifikasi + commit**

```bash
npx tsc --noEmit && npm test
git add lib/feed/queries.ts "app/api/u/[username]/route.ts" app/api/feed/my-posts/route.ts "app/api/feed/posts/[id]/route.ts" && git commit -m "feat(feed): taggedUsers di serializer post + content=tagged profil (Spec B)"
```

---

### Task 5: Notifikasi `feed_tagged`

**Files:**
- Modify: `lib/feed/notification-center.ts` (`FeedNotificationEventType` ~line 13, `derivePrefCategory` ~line 62)
- Modify: `lib/feed/activity-notifications.ts` (fungsi baru `sendTaggedUserNotifications`, template `sendMentionNotifications` ~line 185)
- Modify: `app/api/feed/posts/route.ts` + `app/api/feed/bunny/upload-url/route.ts` (panggil setelah transaksi sukses)
- Test: `tests/feed-tagged-notification.test.ts`

**Interfaces:**
- Produces: `sendTaggedUserNotifications(params: { actorUserId: string; recipientUserIds: string[]; postId: string }): Promise<void>`; event type `"feed_tagged"`; helper teks `buildTaggedNotificationTitle(actorName: string): string` (exported dari `notification-center.ts` supaya testable).
- Consumes: `createFeedNotification` (~line 103 `notification-center.ts` — internal sudah pakai `sendPushToUser` + `sendFcmToUser`, TANPA `sendApnsToUser`).

- [ ] **Step 1: Test failing**

Buat `tests/feed-tagged-notification.test.ts`:

```ts
import test from "node:test";
import assert from "node:assert/strict";
import {
  buildTaggedNotificationTitle,
  derivePrefCategoryForTest,
} from "../lib/feed/notification-center";

test("teks notif tagged sesuai spec", () => {
  assert.equal(
    buildTaggedNotificationTitle("asiong"),
    "asiong menandai Anda dalam postingan",
  );
});

test("feed_tagged ter-gate preferensi kategori feed", () => {
  assert.equal(derivePrefCategoryForTest("feed_tagged"), "feed");
});
```

Catatan: `derivePrefCategory` saat ini module-private (~line 62). Export alias test-nya:

```ts
export const derivePrefCategoryForTest = derivePrefCategory;
```

- [ ] **Step 2: Run — expect fail**

```bash
npx tsx --test tests/feed-tagged-notification.test.ts
```

Expected: module tidak export `buildTaggedNotificationTitle` / `derivePrefCategoryForTest`.

- [ ] **Step 3: Implement `notification-center.ts`**

1. Tambah `| "feed_tagged"` di union `FeedNotificationEventType` (~line 21, setelah `"feed_mention"`).
2. Di `derivePrefCategory` (~line 62), tambah `case "feed_tagged":` di kelompok yang return `"feed"` (bersama `feed_mention`).
3. `deriveNotificationCategory` — TIDAK diubah (default null = tap-to-open).
4. Tambah export (dekat `buildCommentNotificationText` ~line 88):

```ts
/**
 * Teks notif Tag People (Spec B): "[Nama] menandai Anda dalam postingan".
 * Penandai official → nama brand (caller yang resolve actorName).
 */
export function buildTaggedNotificationTitle(actorName: string): string {
  return `${actorName} menandai Anda dalam postingan`;
}

export const derivePrefCategoryForTest = derivePrefCategory;
```

- [ ] **Step 4: Implement `sendTaggedUserNotifications` di `activity-notifications.ts`**

Setelah `sendMentionNotifications`, tambahkan (pola sama persis — resolve actor + post, brand-safe, Promise.allSettled, dedupe tag):

```ts
/**
 * Tag People (Spec B) — notif ke user yang ditandai di post baru.
 * Dipanggil dari POST create SETELAH transaksi sukses. Self-tag di-skip.
 * Deep-link: /feed/<postId> (case `feed` sudah ada di deep_link_service).
 */
export async function sendTaggedUserNotifications(params: {
  actorUserId: string;
  recipientUserIds: string[];
  postId: string;
}) {
  if (params.recipientUserIds.length === 0) return;
  try {
    const [actor, post] = await Promise.all([
      prisma.user.findUnique({
        where: { id: params.actorUserId },
        select: { name: true, username: true, role: true, profilePhotoUrl: true },
      }),
      prisma.feedPost.findUnique({
        where: { id: params.postId },
        select: {
          id: true,
          title: true,
          thumbnailUrl: true,
          media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
        },
      }),
    ]);
    if (!post) return;
    const actorName = isAdminRole(actor?.role)
      ? OFFICIAL_BRAND_NAME
      : actor?.username && actor.username.length > 0
        ? actor.username
        : actor?.name?.trim() || "Seseorang";
    const actorFields = notificationActorFields(
      actor?.role,
      actor?.name,
      actor?.profilePhotoUrl,
    );

    // Tidak ada notifikasi ke diri sendiri (self-tag boleh, tanpa notif).
    const recipients = params.recipientUserIds.filter(
      (id) => id !== params.actorUserId,
    );

    await Promise.allSettled(
      recipients.map((recipientUserId) =>
        createFeedNotification({
          userId: recipientUserId,
          eventType: "feed_tagged",
          title: buildTaggedNotificationTitle(actorName),
          message: truncateFeedText(post.title) || "Lihat postingannya sekarang.",
          feedPostId: post.id,
          thumbnailUrl: feedNotificationThumbnail(post),
          url: `/feed/${encodeURIComponent(post.id)}`,
          ctaLabel: "Lihat Postingan",
          tag: `feed-tagged-${params.postId}-${recipientUserId}`,
          data: { post_id: params.postId },
          surface: SOCIAL_NOTIFICATION_SOURCE,
          actor: {
            avatarUrl: actorFields.actorAvatarUrl,
            name: actorFields.actorName,
          },
        }),
      ),
    );
  } catch (err) {
    console.warn("[feed-activity] sendTaggedUserNotifications:", err);
  }
}
```

Tambahkan `buildTaggedNotificationTitle` ke import dari `./notification-center` di atas file.

- [ ] **Step 5: Panggil dari kedua route create**

Di `app/api/feed/posts/route.ts`, setelah blok mention-notif (~line 633, sesudah `sendMentionNotifications` selesai), tambahkan:

```ts
  // Tag People notif — WAJIB await (Vercel void-promise freeze).
  if (taggedUsers.length > 0) {
    try {
      const { sendTaggedUserNotifications } = await import(
        "@/lib/feed/activity-notifications"
      );
      await sendTaggedUserNotifications({
        actorUserId: session.sub,
        recipientUserIds: taggedUsers.map((t) => t.userId),
        postId: post.id,
      });
    } catch (err) {
      console.warn("[posts] tagged notif failed:", err);
    }
  }
```

Blok yang sama di `app/api/feed/bunny/upload-url/route.ts` setelah transaksi provision sukses.

- [ ] **Step 6: Verifikasi + commit**

```bash
npx tsx --test tests/feed-tagged-notification.test.ts && npx tsc --noEmit
git add lib/feed/notification-center.ts lib/feed/activity-notifications.ts app/api/feed/posts/route.ts app/api/feed/bunny/upload-url/route.ts tests/feed-tagged-notification.test.ts && git commit -m "feat(feed): notifikasi feed_tagged ke user yang ditandai (Spec B)"
```

---

### Task 6: Endpoint self-service `DELETE` + `PATCH /api/feed/posts/[id]/tags/me`

**Files:**
- Create: `app/api/feed/posts/[id]/tags/me/route.ts`
- Test: `tests/feed-tag-self-service.test.ts`

**Interfaces:**
- Produces: `DELETE /api/feed/posts/[id]/tags/me` → `{ok: true}` (hapus baris tag milik session user); `PATCH` body `{hidden: boolean}` → `{ok: true, hidden}`; helper murni `parseHiddenBody(raw: unknown): { ok: true; hidden: boolean } | { ok: false; error: string }` di `lib/feed/tagged-users.ts` (testable).
- Consumes: `getSession("CUSTOMER")` dari `lib/auth`, `assertSameOrigin` (pola route mutasi feed lain), `prisma.feedTaggedUser`.

- [ ] **Step 1: Test failing untuk `parseHiddenBody`**

Buat `tests/feed-tag-self-service.test.ts`:

```ts
import test from "node:test";
import assert from "node:assert/strict";
import { parseHiddenBody } from "../lib/feed/tagged-users";

test("parseHiddenBody: hanya boolean yang valid", () => {
  assert.deepEqual(parseHiddenBody({ hidden: true }), { ok: true, hidden: true });
  assert.deepEqual(parseHiddenBody({ hidden: false }), { ok: true, hidden: false });
  assert.equal(parseHiddenBody({ hidden: "true" }).ok, false);
  assert.equal(parseHiddenBody({}).ok, false);
  assert.equal(parseHiddenBody(null).ok, false);
});
```

- [ ] **Step 2: Run — expect fail** (`parseHiddenBody` belum ada)

```bash
npx tsx --test tests/feed-tag-self-service.test.ts
```

- [ ] **Step 3: Implement**

Tambah di `lib/feed/tagged-users.ts`:

```ts
export function parseHiddenBody(
  raw: unknown,
): { ok: true; hidden: boolean } | { ok: false; error: string } {
  if (typeof raw === "object" && raw !== null) {
    const hidden = (raw as Record<string, unknown>).hidden;
    if (typeof hidden === "boolean") return { ok: true, hidden };
  }
  return { ok: false, error: "Body harus {hidden: boolean}." };
}
```

Buat `app/api/feed/posts/[id]/tags/me/route.ts`:

```ts
/**
 * Tag People (Spec B) — self-service untuk user yang DITANDAI:
 *   DELETE → "Hapus saya dari post" (hapus baris tag miliknya sendiri).
 *   PATCH {hidden} → "Sembunyikan/Tampilkan di profil saya".
 * Otorisasi: session user == taggedUserId (baris orang lain tidak
 * tersentuh — where compound unique feedPostId+taggedUserId).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession, assertSameOrigin } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { parseHiddenBody } from "@/lib/feed/tagged-users";

async function requireSession(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return { reject: csrfReject, session: null };
  const session = await getSession("CUSTOMER");
  if (!session) {
    return {
      reject: NextResponse.json(
        { error: "LOGIN_REQUIRED", message: "Login dulu." },
        { status: 401 },
      ),
      session: null,
    };
  }
  return { reject: null, session };
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const { reject, session } = await requireSession(request);
  if (reject || !session) return reject;

  const deleted = await prisma.feedTaggedUser.deleteMany({
    where: { feedPostId: id, taggedUserId: session.sub },
  });
  if (deleted.count === 0) {
    return NextResponse.json(
      { error: "Kamu tidak ditandai di postingan ini." },
      { status: 404 },
    );
  }
  return NextResponse.json({ ok: true });
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const { reject, session } = await requireSession(request);
  if (reject || !session) return reject;

  const body = await request.json().catch(() => null);
  const parsed = parseHiddenBody(body);
  if (!parsed.ok) {
    return NextResponse.json({ error: parsed.error }, { status: 400 });
  }

  const updated = await prisma.feedTaggedUser.updateMany({
    where: { feedPostId: id, taggedUserId: session.sub },
    data: { hidden: parsed.hidden },
  });
  if (updated.count === 0) {
    return NextResponse.json(
      { error: "Kamu tidak ditandai di postingan ini." },
      { status: 404 },
    );
  }
  return NextResponse.json({ ok: true, hidden: parsed.hidden });
}
```

Catatan: cek dulu nama export CSRF helper — route mutasi lain (`app/api/feed/posts/route.ts:147` pakai `assertSameOrigin`); import dari modul yang sama dengan file itu (kalau di sana dari `@/lib/csrf` atau `@/lib/auth`, ikuti persis).

- [ ] **Step 4: Verifikasi + commit**

```bash
npx tsx --test tests/feed-tag-self-service.test.ts && npx tsc --noEmit
git add "app/api/feed/posts/[id]/tags/me/route.ts" lib/feed/tagged-users.ts tests/feed-tag-self-service.test.ts && git commit -m "feat(feed): endpoint hapus/sembunyikan tag diri sendiri (Spec B)"
```

---

### Task 7: Flutter model `FeedTaggedUser` + `FeedPost.taggedUsers` lossless

**Files:**
- Modify: `flutter_app/lib/models/feed_post.dart` (field baru + `fromJson` ~line 611, `toJson` ~line 769, `copyWith` ~line 560, kelas baru dekat `FeedMedia` ~line 869)
- Test: `flutter_app/test/feed_tagged_user_model_test.dart`

**Interfaces:**
- Produces:

```dart
class FeedTaggedUser {
  final String userId;
  final String? username;
  final String name;
  final String? profilePhotoUrl;
  final String? mediaId;
  final int? mediaIndex;
  final double? x;
  final double? y;
  const FeedTaggedUser({...});
  factory FeedTaggedUser.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

dan `final List<FeedTaggedUser> taggedUsers;` di `FeedPost` (default `const []`).

- [ ] **Step 1: Test failing — round-trip lossless**

Buat `flutter_app/test/feed_tagged_user_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/models/feed_post.dart';

void main() {
  Map<String, dynamic> basePostJson() => {
        'id': 'post1',
        'title': 'halo',
        'kind': 'PHOTO_CAROUSEL',
        'author': {'id': 'a1', 'name': 'Asiong', 'username': 'asiong'},
        'taggedUsers': [
          {
            'userId': 'u1',
            'username': 'budi',
            'name': 'Budi',
            'profilePhotoUrl': 'https://cdn/x/budi.jpg',
            'mediaId': 'm1',
            'mediaIndex': 0,
            'x': 0.25,
            'y': 0.75,
          },
          {
            'userId': 'u2',
            'username': 'cici',
            'name': 'Cici',
            'profilePhotoUrl': null,
            'mediaId': null,
            'mediaIndex': null,
            'x': null,
            'y': null,
          },
        ],
      };

  test('fromJson parse taggedUsers', () {
    final post = FeedPost.fromJson(basePostJson());
    expect(post.taggedUsers, hasLength(2));
    expect(post.taggedUsers.first.userId, 'u1');
    expect(post.taggedUsers.first.x, 0.25);
    expect(post.taggedUsers.last.mediaIndex, isNull);
  });

  test('toJson lossless round-trip taggedUsers', () {
    final post = FeedPost.fromJson(basePostJson());
    final roundTripped = FeedPost.fromJson(post.toJson());
    expect(roundTripped.taggedUsers, hasLength(2));
    final a = roundTripped.taggedUsers.first;
    expect(a.userId, 'u1');
    expect(a.username, 'budi');
    expect(a.name, 'Budi');
    expect(a.profilePhotoUrl, 'https://cdn/x/budi.jpg');
    expect(a.mediaId, 'm1');
    expect(a.mediaIndex, 0);
    expect(a.x, 0.25);
    expect(a.y, 0.75);
    final b = roundTripped.taggedUsers.last;
    expect(b.userId, 'u2');
    expect(b.x, isNull);
  });

  test('taggedUsers absen → list kosong', () {
    final json = basePostJson()..remove('taggedUsers');
    expect(FeedPost.fromJson(json).taggedUsers, isEmpty);
  });
}
```

(Cek nama package di `flutter_app/pubspec.yaml` — kalau bukan `natalo_app`, sesuaikan import mengikuti test existing seperti `test/feed_upload_store_test.dart`.)

- [ ] **Step 2: Run — expect fail**

```bash
cd flutter_app && flutter test test/feed_tagged_user_model_test.dart
```

Expected: compile error `taggedUsers` bukan member `FeedPost`.

- [ ] **Step 3: Implement**

Di `feed_post.dart`, sebelum kelas `FeedMedia` (~line 869), tambahkan:

```dart
/// Tag People (Spec B) — 1 user yang ditandai di post. Foto: mediaIndex +
/// koordinat pecahan 0-1; video: semuanya null (daftar nama saja).
class FeedTaggedUser {
  final String userId;
  final String? username;
  final String name;
  final String? profilePhotoUrl;
  final String? mediaId;
  final int? mediaIndex;
  final double? x;
  final double? y;

  const FeedTaggedUser({
    required this.userId,
    this.username,
    this.name = '',
    this.profilePhotoUrl,
    this.mediaId,
    this.mediaIndex,
    this.x,
    this.y,
  });

  factory FeedTaggedUser.fromJson(Map<String, dynamic> json) {
    return FeedTaggedUser(
      userId: (json['userId'] as String?) ?? '',
      username: json['username'] as String?,
      name: (json['name'] as String?) ?? '',
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      mediaId: json['mediaId'] as String?,
      mediaIndex: (json['mediaIndex'] as num?)?.toInt(),
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'username': username,
        'name': name,
        'profilePhotoUrl': profilePhotoUrl,
        'mediaId': mediaId,
        'mediaIndex': mediaIndex,
        'x': x,
        'y': y,
      };
}
```

Di `FeedPost`:
1. Field: `final List<FeedTaggedUser> taggedUsers;` + constructor param `this.taggedUsers = const [],`.
2. `copyWith`: param `List<FeedTaggedUser>? taggedUsers2` — HATI-HATI: sudah ada param `taggedProducts`; beri nama param `taggedUsers` (tidak bentrok) dan `taggedUsers: taggedUsers ?? this.taggedUsers,`.
3. `fromJson` (~line 611, dekat parsing `taggedProducts`):

```dart
    final taggedUsersJson = (json['taggedUsers'] as List?) ?? const [];
    final taggedUsers = taggedUsersJson
        .whereType<Map<String, dynamic>>()
        .map(FeedTaggedUser.fromJson)
        .toList();
```

lalu masukkan `taggedUsers: taggedUsers,` ke constructor call.
4. `toJson` (~line 769, setelah `'products':`): `'taggedUsers': taggedUsers.map((t) => t.toJson()).toList(),`

- [ ] **Step 4: Run — expect hijau + analyze**

```bash
cd flutter_app && flutter test test/feed_tagged_user_model_test.dart && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/models/feed_post.dart flutter_app/test/feed_tagged_user_model_test.dart && git commit -m "feat(app): model FeedTaggedUser + FeedPost.taggedUsers lossless (Spec B)"
```

---

### Task 8: Composer — entry row "Tandai Orang" + plumbing upload (foto & video, draft persist)

**Files:**
- Modify: `flutter_app/lib/screens/feed_new_post_screen.dart` (state `_userTags`, row entry di area `kShopTagEnabled` ~line 610, `_upload` ~line 385)
- Modify: `flutter_app/lib/models/feed_create_post_draft.dart` (field `taggedUsers` + `copyWith`)
- Modify: `flutter_app/lib/state/feed_draft_store.dart` (persist/restore `taggedUsers` di JSON draft, pola `caption` line 22/77/92/241)
- Modify: `flutter_app/lib/state/feed_upload_store.dart` (`FeedUploadTask.taggedUsers`, `startPhotoUpload` ~line 218, `startVideoUpload` ~line 340, persist-pending JSON ~line 847, restore ~line 699)
- Modify: `flutter_app/lib/services/feed_photo_service.dart` (`createPhotoPost` ~line 218 body `taggedUsers`)
- Modify: `flutter_app/lib/services/bunny_upload_service.dart` (`provisionUpload` ~line 118 body `taggedUsers`)
- Create: `flutter_app/lib/models/new_post_user_tag.dart`
- Test: `flutter_app/test/feed_create_post_draft_test.dart` (extend), `flutter_app/test/new_post_user_tag_test.dart`

**Interfaces:**
- Produces:

```dart
class NewPostUserTag {
  final String userId;
  final String username;
  final String name;
  final String? profilePhotoUrl;
  final int? mediaIndex; // null untuk video
  final double? x;
  final double? y;
  const NewPostUserTag({...});
  NewPostUserTag copyWith({int? mediaIndex, double? x, double? y});
  Map<String, dynamic> toJson();       // persist draft (semua field)
  Map<String, dynamic> toApiJson();    // payload API: {userId, mediaIndex, x, y}
  factory NewPostUserTag.fromJson(Map<String, dynamic> json);
}
```

- Consumes: `feedUploadStore.startPhotoUpload/startVideoUpload`, `FeedCreatePostDraft.copyWith` (pola `taggedProductIds` di `feed_create_post_draft.dart:15`).

- [ ] **Step 1: Test failing model + draft round-trip**

Buat `flutter_app/test/new_post_user_tag_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/models/new_post_user_tag.dart';

void main() {
  test('toApiJson hanya kirim field kontrak API', () {
    const tag = NewPostUserTag(
      userId: 'u1',
      username: 'budi',
      name: 'Budi',
      profilePhotoUrl: 'https://cdn/b.jpg',
      mediaIndex: 2,
      x: 0.4,
      y: 0.6,
    );
    expect(tag.toApiJson(), {
      'userId': 'u1',
      'mediaIndex': 2,
      'x': 0.4,
      'y': 0.6,
    });
  });

  test('fromJson/toJson round-trip untuk draft persist', () {
    const tag = NewPostUserTag(
      userId: 'u1',
      username: 'budi',
      name: 'Budi',
      mediaIndex: 0,
      x: 0.1,
      y: 0.9,
    );
    final back = NewPostUserTag.fromJson(tag.toJson());
    expect(back.userId, 'u1');
    expect(back.username, 'budi');
    expect(back.mediaIndex, 0);
    expect(back.x, 0.1);
    expect(back.y, 0.9);
  });
}
```

Extend `flutter_app/test/feed_create_post_draft_test.dart`:

```dart
  test('copyWith membawa taggedUsers', () {
    const draft = FeedCreatePostDraft(caption: 'x');
    final tagged = draft.copyWith(taggedUsers: const [
      NewPostUserTag(userId: 'u1', username: 'budi', name: 'Budi'),
    ]);
    expect(tagged.taggedUsers, hasLength(1));
    expect(tagged.copyWith(caption: 'y').taggedUsers, hasLength(1));
  });
```

- [ ] **Step 2: Run — expect fail**

```bash
cd flutter_app && flutter test test/new_post_user_tag_test.dart test/feed_create_post_draft_test.dart
```

- [ ] **Step 3: Implement model + draft**

Buat `flutter_app/lib/models/new_post_user_tag.dart`:

```dart
/// Tag orang yang sedang disusun di composer (Spec B). Berbeda dari
/// FeedTaggedUser (shape response server) — ini shape client-side yang
/// membawa identitas untuk render pill + koordinat untuk payload API.
class NewPostUserTag {
  final String userId;
  final String username;
  final String name;
  final String? profilePhotoUrl;
  final int? mediaIndex; // null untuk video
  final double? x; // pecahan 0-1
  final double? y;

  const NewPostUserTag({
    required this.userId,
    required this.username,
    this.name = '',
    this.profilePhotoUrl,
    this.mediaIndex,
    this.x,
    this.y,
  });

  NewPostUserTag copyWith({int? mediaIndex, double? x, double? y}) {
    return NewPostUserTag(
      userId: userId,
      username: username,
      name: name,
      profilePhotoUrl: profilePhotoUrl,
      mediaIndex: mediaIndex ?? this.mediaIndex,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }

  /// Payload API — kontrak body POST create: {userId, mediaIndex, x, y}.
  Map<String, dynamic> toApiJson() => {
        'userId': userId,
        'mediaIndex': mediaIndex,
        'x': x,
        'y': y,
      };

  /// Persist penuh (draft video + pending upload) — round-trip fromJson.
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'username': username,
        'name': name,
        'profilePhotoUrl': profilePhotoUrl,
        'mediaIndex': mediaIndex,
        'x': x,
        'y': y,
      };

  factory NewPostUserTag.fromJson(Map<String, dynamic> json) {
    return NewPostUserTag(
      userId: (json['userId'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      mediaIndex: (json['mediaIndex'] as num?)?.toInt(),
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
    );
  }
}
```

Di `feed_create_post_draft.dart`: import model, tambah `final List<NewPostUserTag> taggedUsers;` (default `const []`), param constructor, param + assignment `copyWith` — persis pola `taggedProductIds` (line 15/34/55/69).

Di `feed_draft_store.dart`: di serialisasi draft (dekat `'caption': caption` line 77) tambah `'taggedUsers': taggedUsers.map((t) => t.toJson()).toList(),`; di parse (line 92 & 241 dekat `caption`) tambah:

```dart
      taggedUsers: ((json['taggedUsers'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(NewPostUserTag.fromJson)
          .toList(),
```

(Terapkan di KEDUA titik parse — draft list dan pending payload — supaya draft video persist/restore membawa tag, konstrain spec §2 "Kirim".)

- [ ] **Step 4: Plumb upload store + services**

`feed_upload_store.dart`:
1. `FeedUploadTask`: tambah `final List<NewPostUserTag> taggedUsers;` (default `const []`), ikutkan di `copyWith` internal (line ~100) dan persist JSON (`'taggedUsers': task.taggedUsers.map((t) => t.toJson()).toList()` dekat `'productIds'` line 847) + restore (line ~699, pola `productIds`).
2. `startPhotoUpload` (~line 218): param baru `List<NewPostUserTag> taggedUsers = const []`, teruskan ke `FeedUploadTask`.
3. `_runPhotoUpload` → `createPhotoPost(..., taggedUsers: task.taggedUsers)` (~line 302).
4. `startVideoUpload` (~line 340): `taggedUsers: draft.taggedUsers` ke task; `_runVideoUpload` → `bunnyService.provisionUpload(..., taggedUsers: task.taggedUsers)` (~line 470); jalur restore-pending (~line 742) map balik ke draft `taggedUsers`.

`feed_photo_service.dart` `createPhotoPost` (~line 218): param `List<NewPostUserTag> taggedUsers = const []`, di body (~line 249 dekat `productIds`):

```dart
      if (taggedUsers.isNotEmpty)
        'taggedUsers': taggedUsers.map((t) => t.toApiJson()).toList(),
```

`bunny_upload_service.dart` `provisionUpload` (~line 118): param `List<NewPostUserTag> taggedUsers = const []`, di body:

```dart
        if (taggedUsers.isNotEmpty)
          'taggedUsers': taggedUsers.map((t) => t.toApiJson()).toList(),
```

- [ ] **Step 5: Entry row di `feed_new_post_screen.dart`**

1. State: `List<NewPostUserTag> _userTags = [];` di `_FeedNewPostScreenState`.
2. Di build, ganti area `if (kShopTagEnabled) ...[` (~line 610) — flag tetap ada untuk section produk, tapi SEBELUM blok itu (selalu tampil) tambahkan baris entry:

```dart
                    const SizedBox(height: 26),
                    _TagPeopleRow(
                      tags: _userTags,
                      onTap: _openTagPeople,
                    ),
```

3. Widget row (letakkan dekat `_CaptionTrigger`):

```dart
/// Baris entry "Tandai Orang" (Spec B) — area bekas Tag Produk. Subtitle
/// ringkasan: 1 orang → username, >1 → "N orang".
class _TagPeopleRow extends StatelessWidget {
  final List<NewPostUserTag> tags;
  final VoidCallback onTap;

  const _TagPeopleRow({required this.tags, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = tags.isEmpty
        ? null
        : tags.length == 1
            ? tags.first.username
            : '${tags.length} orang';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(Icons.person_pin_outlined, size: 22, color: cs.onSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tandai Orang',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: cs.onSurface)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 22, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
```

4. Handler `_openTagPeople` — navigasi ke layar Task 9/10 (kompilasi sementara: sampai Task 9 selesai, boleh commit Task 8 bersama stub layar; kalau ingin task independen, buat `FeedTagPeopleScreen`/`FeedTagPeopleVideoScreen` stub minimal di Task 8 lalu diisi Task 9-10 — pilih opsi stub):

```dart
  Future<void> _openTagPeople() async {
    final result = _isVideo
        ? await Navigator.of(context).push<List<NewPostUserTag>>(
            MaterialPageRoute(
              builder: (_) => FeedTagPeopleVideoScreen(initialTags: _userTags),
            ),
          )
        : await Navigator.of(context).push<List<NewPostUserTag>>(
            MaterialPageRoute(
              builder: (_) => FeedTagPeopleScreen(
                photoFiles: _photoFiles,
                initialTags: _userTags,
              ),
            ),
          );
    if (result != null && mounted) setState(() => _userTags = result);
  }
```

5. Di `_upload` (~line 385): video → `draft.copyWith(caption: ..., taggedProductIds: ..., taggedUsers: _userTags)`; foto → `feedUploadStore.startPhotoUpload(..., taggedUsers: _userTags)`.
6. Draft save/restore composer: di `_saveDraftAndExit` dan restore path, ikutkan `_userTags` lewat field draft yang baru (video); untuk foto, `_userTags` hilang saat keluar tanpa kirim (paritas dengan foto yang memang tidak punya draft store — perilaku existing).

- [ ] **Step 6: Verifikasi + commit**

```bash
cd flutter_app && flutter test test/new_post_user_tag_test.dart test/feed_create_post_draft_test.dart test/feed_upload_store_test.dart test/feed_draft_store_test.dart && flutter analyze
git add flutter_app/lib flutter_app/test && git commit -m "feat(app): entry Tandai Orang + plumbing taggedUsers ke jalur upload (Spec B)"
```

---

### Task 9: Widget pill bersama + `FeedTagPeopleScreen` (foto)

**Files:**
- Create: `flutter_app/lib/widgets/feed_user_tag_pill.dart` (pill + fungsi clamp/flip murni — dipakai composer & viewer)
- Create: `flutter_app/lib/screens/feed_tag_people_screen.dart` (layar foto; stub Task 8 diganti implementasi penuh)
- Test: `flutter_app/test/feed_user_tag_pill_test.dart`, `flutter_app/test/feed_tag_people_screen_test.dart`

**Interfaces:**
- Produces:

```dart
/// Hasil layout pill: offset kiri-atas badan pill (px, relatif area foto)
/// + apakah panah pointer di bawah pill (flip karena dekat tepi bawah).
class TagPillPlacement {
  final Offset topLeft;
  final bool arrowBelow;
  const TagPillPlacement(this.topLeft, this.arrowBelow);
}

/// Pure function — clamp badan pill agar utuh dalam batas foto + flip
/// panah. anchor = titik tap/simpan (px). Aturan sama untuk composer &
/// viewer (konstrain spec §2).
TagPillPlacement placeTagPill({
  required Offset anchor,
  required Size pillSize,
  required Size photoSize,
  double arrowHeight = 6,
  double margin = 4,
});

class FeedUserTagPill extends StatelessWidget {
  final String username;
  final bool arrowBelow;
  final bool showRemove;      // composer: tap pill → X
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  const FeedUserTagPill({...});
}

class FeedTagPeopleScreen extends StatefulWidget {
  final List<File> photoFiles;
  final List<NewPostUserTag> initialTags;
  const FeedTagPeopleScreen({...});
  // Navigator.pop(List<NewPostUserTag>) saat tombol selesai.
}
```

- Consumes: `/api/users/search` (`?q=` + `?suggested=1`, pola UI `feed_user_search_screen.dart` / `mention_picker.dart`), `NewPostUserTag` (Task 8), `AppHaptics` (`utils/haptics.dart`), limit 20 + snackbar via `AppToast`.

- [ ] **Step 1: Test failing — clamp/flip**

Buat `flutter_app/test/feed_user_tag_pill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/widgets/feed_user_tag_pill.dart';

void main() {
  const photo = Size(300, 400);
  const pill = Size(80, 28);

  test('anchor tengah → pill di bawah anchor, panah di atas pill', () {
    final p = placeTagPill(
        anchor: const Offset(150, 200), pillSize: pill, photoSize: photo);
    expect(p.arrowBelow, isFalse);
    expect(p.topLeft.dx, 150 - 40); // center horizontal di anchor
    expect(p.topLeft.dy, greaterThan(200)); // badan di bawah titik
  });

  test('anchor dekat tepi kanan → badan di-clamp tetap utuh', () {
    final p = placeTagPill(
        anchor: const Offset(298, 200), pillSize: pill, photoSize: photo);
    expect(p.topLeft.dx + pill.width, lessThanOrEqualTo(photo.width));
    expect(p.topLeft.dx, greaterThanOrEqualTo(0));
  });

  test('anchor dekat tepi bawah → flip: panah di bawah pill', () {
    final p = placeTagPill(
        anchor: const Offset(150, 396), pillSize: pill, photoSize: photo);
    expect(p.arrowBelow, isTrue);
    expect(p.topLeft.dy + pill.height, lessThanOrEqualTo(photo.height));
  });

  test('anchor dekat tepi kiri → clamp kiri', () {
    final p = placeTagPill(
        anchor: const Offset(2, 200), pillSize: pill, photoSize: photo);
    expect(p.topLeft.dx, greaterThanOrEqualTo(0));
  });
}
```

- [ ] **Step 2: Run — expect fail**

```bash
cd flutter_app && flutter test test/feed_user_tag_pill_test.dart
```

- [ ] **Step 3: Implement `feed_user_tag_pill.dart`**

```dart
import 'package:flutter/material.dart';

class TagPillPlacement {
  final Offset topLeft;
  final bool arrowBelow;
  const TagPillPlacement(this.topLeft, this.arrowBelow);
}

/// Clamp + flip bersama composer & viewer (spec §2/§3): badan pill selalu
/// utuh dalam batas foto; default badan di BAWAH anchor dengan panah
/// menunjuk ke atas (ke titik), kalau tidak muat di bawah → badan di ATAS
/// anchor dengan panah di bawah pill.
TagPillPlacement placeTagPill({
  required Offset anchor,
  required Size pillSize,
  required Size photoSize,
  double arrowHeight = 6,
  double margin = 4,
}) {
  final belowTop = anchor.dy + arrowHeight;
  final fitsBelow = belowTop + pillSize.height + margin <= photoSize.height;
  final arrowBelow = !fitsBelow;
  final rawTop = arrowBelow
      ? anchor.dy - arrowHeight - pillSize.height
      : belowTop;
  final left = (anchor.dx - pillSize.width / 2)
      .clamp(margin, (photoSize.width - pillSize.width - margin).clamp(margin, double.infinity))
      .toDouble();
  final top = rawTop
      .clamp(margin, (photoSize.height - pillSize.height - margin).clamp(margin, double.infinity))
      .toDouble();
  return TagPillPlacement(Offset(left, top), arrowBelow);
}

/// Pill gelap username putih + panah pointer, ala IG. Muncul dengan pop
/// scale-fade easeOutCubic (dibungkus caller via animasi implicit di sini).
class FeedUserTagPill extends StatelessWidget {
  final String username;
  final bool arrowBelow;
  final bool showRemove;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const FeedUserTagPill({
    super.key,
    required this.username,
    this.arrowBelow = false,
    this.showRemove = false,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final arrow = CustomPaint(
      size: const Size(10, 6),
      painter: _TagArrowPainter(pointsUp: !arrowBelow),
    );
    final body = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (showRemove) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: arrowBelow ? [body, arrow] : [arrow, body],
    );
  }
}

class _TagArrowPainter extends CustomPainter {
  final bool pointsUp;
  const _TagArrowPainter({required this.pointsUp});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.78);
    final path = Path();
    if (pointsUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TagArrowPainter old) =>
      old.pointsUp != pointsUp;
}
```

- [ ] **Step 4: Test failing — layar foto**

Buat `flutter_app/test/feed_tag_people_screen_test.dart` (mock search via injectable fetcher, pola mock di test composer existing `feed_new_post_screen_test.dart`):

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/models/new_post_user_tag.dart';
import 'package:natalo_app/screens/feed_tag_people_screen.dart';

void main() {
  const tag = NewPostUserTag(
      userId: 'u1', username: 'budi', name: 'Budi', mediaIndex: 0, x: 0.5, y: 0.5);

  Future<void> pump(WidgetTester tester,
      {List<NewPostUserTag> initial = const []}) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedTagPeopleScreen(
        photoFiles: [File('test/assets/placeholder.png')],
        initialTags: initial,
        searchUsers: (q, {suggested = false}) async => const [],
      ),
    ));
    await tester.pump();
  }

  testWidgets('judul, tombol selesai, dan hint tampil', (tester) async {
    await pump(tester);
    expect(find.text('Tandai Orang'), findsOneWidget);
    expect(find.text('Ketuk foto untuk menandai orang'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('initial tag dirender sebagai pill', (tester) async {
    await pump(tester, initial: const [tag]);
    expect(find.text('budi'), findsOneWidget);
  });

  testWidgets('tap pill → tombol X → hapus', (tester) async {
    await pump(tester, initial: const [tag]);
    await tester.tap(find.text('budi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('budi'), findsNothing);
  });

  testWidgets('tombol selesai pop dengan list tag', (tester) async {
    List<NewPostUserTag>? popped;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            popped = await Navigator.of(context).push<List<NewPostUserTag>>(
              MaterialPageRoute(
                builder: (_) => FeedTagPeopleScreen(
                  photoFiles: [File('test/assets/placeholder.png')],
                  initialTags: const [tag],
                  searchUsers: (q, {suggested = false}) async => const [],
                ),
              ),
            );
          },
          child: const Text('go'),
        );
      }),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(popped, hasLength(1));
  });
}
```

(Kalau `test/assets/placeholder.png` belum ada, buat PNG 1x1 di path itu dan daftarkan pola loading image file di test — layar harus toleran `Image.file` gagal decode di test env: bungkus `errorBuilder`.)

- [ ] **Step 5: Implement `feed_tag_people_screen.dart` (foto)**

Struktur (implementasi lengkap, ~ikuti kerangka ini):

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/new_post_user_tag.dart';
import '../services/api_client.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../widgets/app_toast.dart';
import '../widgets/feed_user_tag_pill.dart';
import '../widgets/profile_avatar.dart';

const _kMaxTags = 20;

/// Hasil pencarian akun untuk picker — subset field /api/users/search.
class TagSearchUser {
  final String id;
  final String username;
  final String name;
  final String? profilePhotoUrl;
  const TagSearchUser({
    required this.id,
    required this.username,
    this.name = '',
    this.profilePhotoUrl,
  });
}

typedef TagUserSearchFn = Future<List<TagSearchUser>> Function(
  String query, {
  bool suggested,
});

/// Default: GET /api/users/search?q=..&limit=8 / ?suggested=1 (pra-ketik).
Future<List<TagSearchUser>> defaultTagUserSearch(
  String query, {
  bool suggested = false,
}) async {
  final data = await apiClient.getJson(
    '/api/users/search',
    query: suggested && query.isEmpty
        ? {'suggested': '1', 'limit': '8'}
        : {'q': query, 'limit': '8'},
  );
  final users = (data['users'] as List?) ?? const [];
  return users
      .whereType<Map<String, dynamic>>()
      .map((u) => TagSearchUser(
            id: (u['id'] as String?) ?? '',
            username: (u['username'] as String?) ?? '',
            name: (u['name'] as String?) ?? '',
            profilePhotoUrl: u['profilePhotoUrl'] as String?,
          ))
      .toList();
}

class FeedTagPeopleScreen extends StatefulWidget {
  final List<File> photoFiles;
  final List<NewPostUserTag> initialTags;
  final TagUserSearchFn searchUsers;

  const FeedTagPeopleScreen({
    super.key,
    required this.photoFiles,
    this.initialTags = const [],
    this.searchUsers = defaultTagUserSearch,
  });

  @override
  State<FeedTagPeopleScreen> createState() => _FeedTagPeopleScreenState();
}
```

State + perilaku (WAJIB semua poin spec §2):
- `late List<NewPostUserTag> _tags = [...widget.initialTags];`, `int _pageIndex = 0;`, `PageController`.
- **AppBar:** judul tengah "Tandai Orang"; kanan atas tombol selesai: `Container` lingkaran 36px warna `NataloColors.primary` + `Icon(Icons.check, color: Colors.white)`, `onTap: () => Navigator.of(context).pop(List<NewPostUserTag>.of(_tags))`. Tanpa tooltip/splash (konvensi Global Icon Clean Interaction).
- **Body:** `Column`: `Expanded(PageView.builder)` foto (`Image.file`, `fit: BoxFit.contain`, `errorBuilder` aman-test) dibungkus `LayoutBuilder` untuk tahu ukuran render foto; di bawahnya indikator halaman dots (render hanya kalau `photoFiles.length > 1`, pola dots `_PhotoCarouselPostView`); paling bawah hint `Text('Ketuk foto untuk menandai orang')` gaya muted.
- **Tap foto** (`GestureDetector onTapUp` di tiap page): kalau `_tags.length >= _kMaxTags` → `AppToast.showBanner(context, 'Maksimal 20 orang per postingan.', kind: ToastKind.info); return;`. Simpan `Offset` tap sebagai pecahan (`localPosition.dx / renderWidth`, `.dy / renderHeight`), buka panel pencarian fullscreen (push `MaterialPageRoute` fade in-file `_TagUserSearchPanel`).
- **`_TagUserSearchPanel`** (widget privat di file ini, UI meniru `feed_user_search_screen.dart`): search bar "Cari akun" + tombol "Batal" (pop), debounce 300ms, saat query kosong panggil `widget.searchUsers('', suggested: true)` (saran pra-ketik), hasil `ListTile` avatar (`ProfileAvatar`)+nama+username; tap → `Navigator.pop(TagSearchUser)`.
- Pilih akun → kalau userId sudah ada di `_tags` → pindahkan koordinatnya ke titik baru (unik per post); kalau baru → `_tags.add(NewPostUserTag(userId: u.id, username: u.username, name: u.name, profilePhotoUrl: u.profilePhotoUrl, mediaIndex: _pageIndex, x: fx, y: fy))` + `AppHaptics.tap()`.
- **Render pill per-slide:** `Stack` di atas foto; untuk tiap tag dengan `mediaIndex == index`, hitung anchor px = `Offset(tag.x! * w, tag.y! * h)`, ukur pill via `TextPainter` (atau konstanta lebar dari `username.length` — pakai `TextPainter` agar akurat), panggil `placeTagPill`, `Positioned` + `FeedUserTagPill`. Animasi muncul:

```dart
TweenAnimationBuilder<double>(
  tween: Tween(begin: 0.6, end: 1),
  duration: const Duration(milliseconds: 220),
  curve: Curves.easeOutCubic,
  builder: (context, v, child) =>
      Opacity(opacity: v.clamp(0, 1), child: Transform.scale(scale: v, child: child)),
  child: pill,
)
```

- **Drag pill:** bungkus pill `GestureDetector(onPanStart: (_) => AppHaptics.tap(), onPanUpdate: ...)` update `x/y` pecahan (clamp 0-1) via `_tags[i] = _tags[i].copyWith(x: nx, y: ny)`; posisi akhir = yang tersimpan.
- **Tap pill → X:** state `String? _revealRemoveUserId;` — tap pill toggle `showRemove` untuk tag itu; tap X → `_tags.removeWhere((t) => t.userId == id)`.

- [ ] **Step 6: Run semua test task ini + analyze**

```bash
cd flutter_app && flutter test test/feed_user_tag_pill_test.dart test/feed_tag_people_screen_test.dart && flutter analyze
```

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/widgets/feed_user_tag_pill.dart flutter_app/lib/screens/feed_tag_people_screen.dart flutter_app/test/feed_user_tag_pill_test.dart flutter_app/test/feed_tag_people_screen_test.dart flutter_app/test/assets && git commit -m "feat(app): layar Tandai Orang foto + pill drag/clamp/flip (Spec B)"
```

---

### Task 10: `FeedTagPeopleVideoScreen` (daftar sederhana)

**Files:**
- Modify: `flutter_app/lib/screens/feed_tag_people_screen.dart` (widget kedua di file yang sama — reuse `_TagUserSearchPanel` + `TagSearchUser`)
- Test: `flutter_app/test/feed_tag_people_video_screen_test.dart`

**Interfaces:**
- Produces: `class FeedTagPeopleVideoScreen extends StatefulWidget { final List<NewPostUserTag> initialTags; final TagUserSearchFn searchUsers; }` — pop `List<NewPostUserTag>` (semua `mediaIndex/x/y` null).

- [ ] **Step 1: Test failing**

Buat `flutter_app/test/feed_tag_people_video_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/models/new_post_user_tag.dart';
import 'package:natalo_app/screens/feed_tag_people_screen.dart';

void main() {
  const tag = NewPostUserTag(userId: 'u1', username: 'budi', name: 'Budi');

  testWidgets('daftar tag tampil + bisa hapus', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedTagPeopleVideoScreen(
        initialTags: const [tag],
        searchUsers: (q, {suggested = false}) async => const [],
      ),
    ));
    await tester.pump();
    expect(find.text('Tandai Orang'), findsOneWidget);
    expect(find.text('budi'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('budi'), findsNothing);
  });

  testWidgets('limit 20 → row tambah nonaktif + snackbar', (tester) async {
    final many = List.generate(
        20, (i) => NewPostUserTag(userId: 'u$i', username: 'user$i'));
    await tester.pumpWidget(MaterialApp(
      home: FeedTagPeopleVideoScreen(
        initialTags: many,
        searchUsers: (q, {suggested = false}) async => const [],
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Tambah orang'));
    await tester.pump();
    expect(find.text('Maksimal 20 orang per postingan.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — expect fail** (`FeedTagPeopleVideoScreen` belum ada)

```bash
cd flutter_app && flutter test test/feed_tag_people_video_screen_test.dart
```

- [ ] **Step 3: Implement**

Di `feed_tag_people_screen.dart` tambahkan:

```dart
/// Varian video (spec §2): daftar sederhana — cari → tambah → hapus.
/// Tanpa titik/koordinat; semua NewPostUserTag punya mediaIndex/x/y null.
class FeedTagPeopleVideoScreen extends StatefulWidget {
  final List<NewPostUserTag> initialTags;
  final TagUserSearchFn searchUsers;

  const FeedTagPeopleVideoScreen({
    super.key,
    this.initialTags = const [],
    this.searchUsers = defaultTagUserSearch,
  });

  @override
  State<FeedTagPeopleVideoScreen> createState() =>
      _FeedTagPeopleVideoScreenState();
}

class _FeedTagPeopleVideoScreenState extends State<FeedTagPeopleVideoScreen> {
  late final List<NewPostUserTag> _tags = [...widget.initialTags];

  Future<void> _addPerson() async {
    if (_tags.length >= _kMaxTags) {
      AppToast.showBanner(
        context,
        'Maksimal 20 orang per postingan.',
        kind: ToastKind.info,
      );
      return;
    }
    final picked = await Navigator.of(context).push<TagSearchUser>(
      MaterialPageRoute(
        builder: (_) => _TagUserSearchPanel(searchUsers: widget.searchUsers),
        fullscreenDialog: true,
      ),
    );
    if (picked == null || !mounted) return;
    if (_tags.any((t) => t.userId == picked.id)) return; // unik per post
    setState(() {
      _tags.add(NewPostUserTag(
        userId: picked.id,
        username: picked.username,
        name: picked.name,
        profilePhotoUrl: picked.profilePhotoUrl,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Tandai Orang'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () =>
                  Navigator.of(context).pop(List<NewPostUserTag>.of(_tags)),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: NataloColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.person_add_alt_1_outlined, color: cs.onSurface),
            title: const Text('Tambah orang'),
            onTap: _addPerson,
          ),
          for (final tag in _tags)
            ListTile(
              leading: ProfileAvatar(
                imageUrl: tag.profilePhotoUrl,
                name: tag.name.isNotEmpty ? tag.name : tag.username,
                size: 40,
              ),
              title: Text(tag.name.isNotEmpty ? tag.name : tag.username),
              subtitle: Text('@${tag.username}'),
              trailing: GestureDetector(
                onTap: () =>
                    setState(() => _tags.removeWhere((t) => t.userId == tag.userId)),
                child: Icon(Icons.close, size: 20, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
```

(Sesuaikan konstruktor `ProfileAvatar` dengan API asli widget-nya — cek `flutter_app/lib/widgets/profile_avatar.dart` sebelum pakai.)

- [ ] **Step 4: Run + analyze + commit**

```bash
cd flutter_app && flutter test test/feed_tag_people_video_screen_test.dart && flutter analyze
git add flutter_app/lib/screens/feed_tag_people_screen.dart flutter_app/test/feed_tag_people_video_screen_test.dart && git commit -m "feat(app): layar Tandai Orang varian video (Spec B)"
```

---

### Task 11: Viewer — badge + toggle pill foto + navigasi profil (tanpa merusak double-tap like)

**Files:**
- Create: `flutter_app/lib/widgets/feed_tagged_users_overlay.dart` (badge + layer pill viewer, reuse `placeTagPill`/`FeedUserTagPill`)
- Modify: `flutter_app/lib/screens/feed_screen.dart` (`_PhotoCarouselPostView` ~line 1415: GestureDetector media ~line 2174 tambah `onTap`, Stack overlay, state `_showTagPills`)
- Test: `flutter_app/test/feed_tagged_users_overlay_test.dart`

**Interfaces:**
- Produces:

```dart
/// Badge ikon orang (siluet putih, lingkaran semi-transparan) pojok
/// kiri-bawah — selalu tampil kalau ada tag (tanpa auto-fade, spec §3).
class FeedTaggedBadge extends StatelessWidget {
  final VoidCallback? onTap;
}

/// Layer pill untuk slide foto aktif. visible di-toggle parent; pill
/// muncul pop-fade easeOutCubic. onTapUser → parent navigasi/aksi.
class FeedTaggedUsersOverlay extends StatelessWidget {
  final List<FeedTaggedUser> tags;   // sudah difilter per mediaIndex
  final bool visible;
  final Size photoSize;
  final ValueChanged<FeedTaggedUser> onTapUser;
}
```

- Consumes: `FeedTaggedUser` (Task 7), `placeTagPill` + `FeedUserTagPill` (Task 9).

- [ ] **Step 1: Test failing**

Buat `flutter_app/test/feed_tagged_users_overlay_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/models/feed_post.dart';
import 'package:natalo_app/widgets/feed_tagged_users_overlay.dart';

void main() {
  const tag = FeedTaggedUser(
      userId: 'u1', username: 'budi', name: 'Budi', mediaIndex: 0, x: 0.5, y: 0.5);

  testWidgets('visible=false → pill tak dirender', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedTaggedUsersOverlay(
        tags: const [tag],
        visible: false,
        photoSize: const Size(300, 400),
        onTapUser: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('budi'), findsNothing);
  });

  testWidgets('visible=true → pill muncul; tap → callback', (tester) async {
    FeedTaggedUser? tapped;
    await tester.pumpWidget(MaterialApp(
      home: FeedTaggedUsersOverlay(
        tags: const [tag],
        visible: true,
        photoSize: const Size(300, 400),
        onTapUser: (t) => tapped = t,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('budi'));
    expect(tapped?.userId, 'u1');
  });

  testWidgets('badge tampil dengan ikon orang', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FeedTaggedBadge(onTap: () {})),
    ));
    expect(find.byIcon(Icons.person), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — expect fail**

```bash
cd flutter_app && flutter test test/feed_tagged_users_overlay_test.dart
```

- [ ] **Step 3: Implement `feed_tagged_users_overlay.dart`**

```dart
import 'package:flutter/material.dart';
import '../models/feed_post.dart';
import 'feed_user_tag_pill.dart';

class FeedTaggedBadge extends StatelessWidget {
  final VoidCallback? onTap;

  const FeedTaggedBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.person, size: 16, color: Colors.white),
      ),
    );
  }
}

class FeedTaggedUsersOverlay extends StatelessWidget {
  final List<FeedTaggedUser> tags;
  final bool visible;
  final Size photoSize;
  final ValueChanged<FeedTaggedUser> onTapUser;

  const FeedTaggedUsersOverlay({
    super.key,
    required this.tags,
    required this.visible,
    required this.photoSize,
    required this.onTapUser,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || tags.isEmpty) return const SizedBox.shrink();
    return Stack(
      children: [
        for (final tag in tags)
          if (tag.x != null && tag.y != null)
            _positionedPill(context, tag),
      ],
    );
  }

  Widget _positionedPill(BuildContext context, FeedTaggedUser tag) {
    final username = tag.username ?? tag.name;
    final painter = TextPainter(
      text: TextSpan(
        text: username,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pillSize = Size(painter.width + 20, 27);
    final placement = placeTagPill(
      anchor: Offset(tag.x! * photoSize.width, tag.y! * photoSize.height),
      pillSize: pillSize,
      photoSize: photoSize,
    );
    return Positioned(
      left: placement.topLeft.dx,
      top: placement.topLeft.dy - (placement.arrowBelow ? 0 : 6),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => Opacity(
          opacity: v.clamp(0, 1),
          child: Transform.scale(scale: v, child: child),
        ),
        child: FeedUserTagPill(
          username: username,
          arrowBelow: placement.arrowBelow,
          onTap: () => onTapUser(tag),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire ke `_PhotoCarouselPostView` (`feed_screen.dart`)**

1. State baru di `_PhotoCarouselPostViewState` (~line 1436): `bool _showTagPills = false;`
2. Helper: `List<FeedTaggedUser> get _tagsForCurrentPhoto => widget.post.taggedUsers.where((t) => t.mediaIndex == _photoIndex).toList();` dan `bool get _hasTags => widget.post.taggedUsers.isNotEmpty;`
3. Di GestureDetector media (~line 2174, yang sudah punya `onDoubleTap: _onDoubleTapLike`), TAMBAH `onTap` di detector yang SAMA (Flutter otomatis menunda single-tap saat onDoubleTap terdaftar — konstrain spec):

```dart
            onTap: _hasTags ? _toggleTagPills : null,
```

dengan handler:

```dart
  void _toggleTagPills() {
    if (widget.post.taggedUsers.isEmpty) return;
    setState(() => _showTagPills = !_showTagPills);
  }
```

4. Ganti slide → pill ikut slide otomatis (filter `_tagsForCurrentPhoto` per build); di `onPageChanged` (~line 2183) tidak perlu reset `_showTagPills` (spec: "Ganti slide carousel → pill ikut ganti").
5. Overlay + badge: bungkus PageView dalam `Stack` (atau tambah ke Stack existing bila sudah ada) dengan:

```dart
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_showTagPills,
                  child: LayoutBuilder(
                    builder: (context, constraints) => FeedTaggedUsersOverlay(
                      tags: _tagsForCurrentPhoto,
                      visible: _showTagPills,
                      photoSize: constraints.biggest,
                      onTapUser: _onTapTaggedUser,
                    ),
                  ),
                ),
              ),
              if (_hasTags)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: FeedTaggedBadge(onTap: _toggleTagPills),
                ),
```

Catatan koordinat: koordinat tag relatif terhadap FOTO, sementara media dirender `BoxFit.contain`/`cover` — pakai `LayoutBuilder` di layer yang tepat menutupi area foto ter-render; kalau area foto ≠ area container (letterbox contain), hitung rect foto dari `photo.aspectRatio` (helper `FeedMedia.aspectRatio` sudah ada) dan bungkus overlay di `Positioned` sesuai rect itu. Implementasikan helper kecil `Rect fittedPhotoRect(Size container, double aspectRatio, BoxFit fit)` di `feed_user_tag_pill.dart` bila dibutuhkan (unit-test tambahan boleh menempel di `feed_user_tag_pill_test.dart`).
6. Navigasi profil:

```dart
  void _onTapTaggedUser(FeedTaggedUser tag) {
    final username = tag.username;
    if (username == null || username.isEmpty) return;
    // Nama sendiri → Opsi Tag (Task 12); orang lain → profil publik.
    if (_isSelfTag(tag)) {
      _openTagOptions(tag); // diimplementasikan Task 12; stub dulu: no-op
      return;
    }
    Navigator.of(context).pushNamed('/u', arguments: username);
  }
```

`_isSelfTag`: bandingkan `tag.userId` dengan id user login — pakai sumber yang sama dengan yang dipakai layar ini untuk cek kepemilikan (cari `memberStore`/`accountOwnerId()` di `feed_screen.dart` dan ikuti; `accountOwnerId()` dari `utils/owner_scope.dart` dipakai di `feed_user_search_screen.dart:28`).

- [ ] **Step 5: Run + analyze + commit**

```bash
cd flutter_app && flutter test test/feed_tagged_users_overlay_test.dart && flutter analyze
git add flutter_app/lib/widgets/feed_tagged_users_overlay.dart flutter_app/lib/screens/feed_screen.dart flutter_app/test/feed_tagged_users_overlay_test.dart && git commit -m "feat(app): badge + overlay pill tag di viewer foto (Spec B)"
```

---

### Task 12: Sheet "Opsi Tag" + sheet video "Ditandai dalam video ini" + service call

**Files:**
- Create: `flutter_app/lib/widgets/feed_tag_options_sheet.dart` (kedua sheet)
- Modify: `flutter_app/lib/services/feed_service.dart` (2 method baru)
- Modify: `flutter_app/lib/screens/feed_screen.dart` (wire `_openTagOptions` foto; badge video → sheet daftar di `FeedVideoPostView`)
- Test: `flutter_app/test/feed_tag_options_sheet_test.dart`

**Interfaces:**
- Produces:

```dart
// feed_service.dart
Future<void> removeMyTag(String postId);              // DELETE /api/feed/posts/<id>/tags/me
Future<void> setMyTagHidden(String postId, bool hidden); // PATCH  {hidden}

// feed_tag_options_sheet.dart
/// Sheet "Opsi Tag" untuk nama sendiri. onRemoved dipanggil SEBELUM await
/// network selesai (optimistic — pill/baris hilang seketika, spec §3).
Future<void> showFeedTagOptionsSheet(
  BuildContext context, {
  required String postId,
  required bool hidden,
  required VoidCallback onRemoved,
  required ValueChanged<bool> onHiddenChanged,
  Future<void> Function(String postId)? removeTag,          // injectable utk test
  Future<void> Function(String postId, bool hidden)? setHidden,
});

/// Sheet video: daftar avatar+nama+username; tap → profil; baris nama
/// sendiri → pintu Opsi Tag yang sama.
Future<void> showFeedTaggedUsersSheet(
  BuildContext context, {
  required FeedPost post,
  required String? selfUserId,
  required VoidCallback onSelfRemoved,
  required ValueChanged<bool> onSelfHiddenChanged,
});
```

- Consumes: endpoint Task 6, `apiClient` (pola method mutasi existing di `feed_service.dart`), `AppToast`.

- [ ] **Step 1: Test failing**

Buat `flutter_app/test/feed_tag_options_sheet_test.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/widgets/feed_tag_options_sheet.dart';

void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required VoidCallback onRemoved,
    ValueChanged<bool>? onHiddenChanged,
    bool hidden = false,
    Future<void> Function(String)? removeTag,
    Future<void> Function(String, bool)? setHidden,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showFeedTagOptionsSheet(
            context,
            postId: 'p1',
            hidden: hidden,
            onRemoved: onRemoved,
            onHiddenChanged: onHiddenChanged ?? (_) {},
            removeTag: removeTag ?? (_) async {},
            setHidden: setHidden ?? (_, __) async {},
          ),
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Hapus saya: konfirmasi ringan lalu onRemoved optimistic',
      (tester) async {
    var removed = false;
    final networkDone = Completer<void>();
    await openSheet(
      tester,
      onRemoved: () => removed = true,
      removeTag: (_) => networkDone.future, // network belum selesai
    );
    await tester.tap(find.text('Hapus saya dari post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus')); // tombol konfirmasi
    await tester.pump();
    expect(removed, isTrue); // TANPA menunggu networkDone → optimistic
    networkDone.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('toggle Sembunyikan memanggil setHidden(true)', (tester) async {
    bool? sent;
    await openSheet(
      tester,
      onRemoved: () {},
      setHidden: (_, hidden) async => sent = hidden,
    );
    await tester.tap(find.text('Sembunyikan dari profil saya'));
    await tester.pumpAndSettle();
    expect(sent, isTrue);
  });

  testWidgets('hidden=true → label jadi Tampilkan di profil saya',
      (tester) async {
    await openSheet(tester, onRemoved: () {}, hidden: true);
    expect(find.text('Tampilkan di profil saya'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — expect fail**

```bash
cd flutter_app && flutter test test/feed_tag_options_sheet_test.dart
```

- [ ] **Step 3: Implement service + sheets**

`feed_service.dart` — ikuti pola method mutasi existing (mis. like/save di file yang sama, pakai `apiClient`):

```dart
  /// Tag People (Spec B) — hapus tag diri sendiri dari post.
  Future<void> removeMyTag(String postId) async {
    await apiClient.deleteJson(
      '/api/feed/posts/${Uri.encodeComponent(postId)}/tags/me',
    );
  }

  /// Sembunyikan/tampilkan post ber-tag dari tab Ditandai profil sendiri.
  Future<void> setMyTagHidden(String postId, bool hidden) async {
    await apiClient.patchJson(
      '/api/feed/posts/${Uri.encodeComponent(postId)}/tags/me',
      body: {'hidden': hidden},
    );
  }
```

(Cek nama method HTTP di `api_client.dart` — kalau belum ada `deleteJson`/`patchJson`, pakai bentuk yang tersedia di sana atau `http` langsung mengikuti pola `feed_photo_service.dart`.)

`feed_tag_options_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import '../models/feed_post.dart';
import '../services/feed_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/profile_avatar.dart';

Future<void> showFeedTagOptionsSheet(
  BuildContext context, {
  required String postId,
  required bool hidden,
  required VoidCallback onRemoved,
  required ValueChanged<bool> onHiddenChanged,
  Future<void> Function(String postId)? removeTag,
  Future<void> Function(String postId, bool hidden)? setHidden,
}) {
  final doRemove = removeTag ?? feedService.removeMyTag;
  final doSetHidden = setHidden ?? feedService.setMyTagHidden;
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Opsi Tag',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined,
                  color: Colors.red),
              title: const Text('Hapus saya dari post',
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: sheetContext,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Hapus tag?'),
                    content: const Text(
                        'Kamu tidak akan ditandai lagi di postingan ini.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Batal'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Hapus',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                // Optimistic: pill/baris hilang SEKETIKA, network menyusul.
                onRemoved();
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                try {
                  await doRemove(postId);
                } catch (_) {
                  if (context.mounted) {
                    AppToast.showBanner(
                      context,
                      'Gagal menghapus tag. Coba lagi.',
                      kind: ToastKind.error,
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text(hidden
                  ? 'Tampilkan di profil saya'
                  : 'Sembunyikan dari profil saya'),
              onTap: () async {
                final next = !hidden;
                onHiddenChanged(next);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                try {
                  await doSetHidden(postId, next);
                } catch (_) {
                  onHiddenChanged(!next); // rollback
                  if (context.mounted) {
                    AppToast.showBanner(
                      context,
                      'Gagal menyimpan. Coba lagi.',
                      kind: ToastKind.error,
                    );
                  }
                }
              },
            ),
            ListTile(
              title: const Center(child: Text('Batal')),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      );
    },
  );
}

/// Sheet video "Ditandai dalam video ini" — satu-satunya surface tag utk
/// video (spec §3, wajib ada).
Future<void> showFeedTaggedUsersSheet(
  BuildContext context, {
  required FeedPost post,
  required String? selfUserId,
  required VoidCallback onSelfRemoved,
  required ValueChanged<bool> onSelfHiddenChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Ditandai dalam video ini',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final tag in post.taggedUsers)
                    ListTile(
                      leading: ProfileAvatar(
                        imageUrl: tag.profilePhotoUrl,
                        name: tag.name.isNotEmpty
                            ? tag.name
                            : (tag.username ?? ''),
                        size: 40,
                      ),
                      title: Text(
                          tag.name.isNotEmpty ? tag.name : (tag.username ?? '')),
                      subtitle: tag.username == null
                          ? null
                          : Text('@${tag.username}'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (tag.userId == selfUserId) {
                          // Baris nama sendiri → pintu Opsi Tag yang sama.
                          showFeedTagOptionsSheet(
                            context,
                            postId: post.id,
                            hidden: false,
                            onRemoved: onSelfRemoved,
                            onHiddenChanged: onSelfHiddenChanged,
                          );
                        } else if (tag.username != null &&
                            tag.username!.isNotEmpty) {
                          Navigator.of(context)
                              .pushNamed('/u', arguments: tag.username);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
```

(Sesuaikan `ProfileAvatar` + akses singleton `feedService` dengan API asli di repo — cek `feed_service.dart` bagaimana instance-nya diekspos.)

- [ ] **Step 4: Wire ke viewer**

1. Foto (`_PhotoCarouselPostViewState`): implement `_openTagOptions(FeedTaggedUser tag)` — panggil `showFeedTagOptionsSheet` dengan `onRemoved: () => setState(() { /* buang tag dari list lokal via post.copyWith(taggedUsers: ...) atau state List lokal */ })`. Simpan salinan `List<FeedTaggedUser> _tags` di state (`initState`/`didUpdateWidget` dari `widget.post.taggedUsers`) supaya optimistic-remove gampang; overlay & badge baca `_tags`, bukan `widget.post.taggedUsers` langsung. Untuk `hidden` awal: server tidak mengirim flag `hidden` per-viewer di response post (hanya identitas) — default `false`; kalau ingin akurat, tambahkan `viewerTagHidden: boolean` ke serializer (opsional, TIDAK wajib spec; tandai sebagai catatan PR).
2. Video (`FeedVideoPostView` di `feed_screen.dart`): kalau `post.taggedUsers.isNotEmpty`, render `FeedTaggedBadge` pojok kiri-bawah media (posisi konsisten foto), `onTap: () => showFeedTaggedUsersSheet(context, post: post, selfUserId: ..., onSelfRemoved: ..., onSelfHiddenChanged: ...)`. Optimistic remove video = buang baris dari list state lokal yang sama.

- [ ] **Step 5: Run + analyze + commit**

```bash
cd flutter_app && flutter test test/feed_tag_options_sheet_test.dart && flutter analyze
git add flutter_app/lib/widgets/feed_tag_options_sheet.dart flutter_app/lib/services/feed_service.dart flutter_app/lib/screens/feed_screen.dart flutter_app/test/feed_tag_options_sheet_test.dart && git commit -m "feat(app): sheet Opsi Tag + Ditandai dalam video ini (Spec B)"
```

---

### Task 13: Isi tab Ditandai (member + profil publik) + regresi penuh

**Files:**
- Modify: `flutter_app/lib/services/profile_service.dart` (enum filter ~line 8-21: `shoppable('shoppable')` → apiValue `'tagged'`)
- Modify: `flutter_app/lib/screens/public_profile_screen.dart` (hapus `_shortCircuitTaggedContent` ~line 488 + kedua call-site-nya ~line 504 dan di jalur refresh/reload)
- Modify: `flutter_app/lib/screens/member_screen.dart` (`_taggedPosts` ~line 425 dari `const []` jadi state hasil fetch)
- Test: `flutter_app/test/public_profile_tagged_tab_test.dart` (atau extend test profil existing bila ada)

**Interfaces:**
- Consumes: `GET /api/u/{username}?content=tagged` (Task 4) via `ProfileService.fetchPublicProfile(content: PublicProfileContentFilter.shoppable)` — enum NAME tetap `shoppable` (dipakai luas sejak Spec A, label UI sudah "Ditandai"), hanya `apiValue` yang berubah jadi `'tagged'`.
- Produces: tab Ditandai berisi data sungguhan di kedua layar; empty state teks Spec A dipertahankan.

- [ ] **Step 1: Test failing — enum apiValue + short-circuit hilang**

Buat `flutter_app/test/public_profile_tagged_tab_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_app/services/profile_service.dart';

void main() {
  test('filter Ditandai memanggil content=tagged', () {
    expect(PublicProfileContentFilter.shoppable.apiValue, 'tagged');
  });
}
```

- [ ] **Step 2: Run — expect fail** (`apiValue` masih `'shoppable'`)

```bash
cd flutter_app && flutter test test/public_profile_tagged_tab_test.dart
```

- [ ] **Step 3: Implement**

1. `profile_service.dart` line 10: `shoppable('tagged');` + update komentar doc endpoint (`content=all|video|tagged`). Server tetap menerima `'shoppable'` untuk klien lama (Task 4 mempertahankan case-nya) — forward-compat aman.
2. `public_profile_screen.dart`: hapus method `_shortCircuitTaggedContent` (~line 488-499) dan SEMUA call-site (`_activateContent` ~line 504, plus jalur `_load`/`_refresh` — cari string `_shortCircuitTaggedContent` sampai 0 hit). Filter shoppable kini fetch network normal seperti filter lain. Empty state existing untuk konten kosong tetap dipakai ("Belum ada postingan yang menandai" versi orang-ketiga — verifikasi string persisnya di widget empty-state Spec A di file ini, JANGAN diganti).
3. `member_screen.dart`: ganti getter `_taggedPosts` (~line 425):

```dart
  // Tab "Ditandai" (Spec B) — post orang lain yang menandai user ini.
  // Fetch lewat endpoint profil publik milik sendiri (content=tagged);
  // hidden sudah di-exclude server-side.
  List<FeedPost> _taggedPostsData = const [];
  bool _taggedLoaded = false;
  List<FeedPost> get _taggedPosts => _taggedPostsData;

  Future<void> _loadTaggedPosts() async {
    final username = /* username user login — sumber sama dengan header
        profil di layar ini (cari field profil/memberStore yang sudah
        menampilkan @username) */;
    if (username == null || username.isEmpty) return;
    try {
      final result = await ProfileService.instance.fetchPublicProfile(
        username: username,
        content: PublicProfileContentFilter.shoppable,
      );
      if (!mounted) return;
      setState(() {
        _taggedPostsData = result.posts;
        _taggedLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _taggedLoaded = true);
    }
  }
```

Panggil `_loadTaggedPosts()` lazily saat tab Ditandai pertama kali dipilih (cari handler perpindahan tab di layar ini) + saat pull-to-refresh. Grid & buka post: `_taggedPosts` sudah dikonsumsi widget grid existing dari Spec A — reuse persis widget tab Postingan/Video (tidak ada layout baru). Sesuaikan cara akses `ProfileService` dengan API sebenarnya (instance vs constructor — lihat pemakaian di `public_profile_screen.dart`).
4. Sinkron "Hapus saya"/"Sembunyikan" (Task 12): setelah aksi sukses di viewer, post harus keluar dari tab Ditandai user itu — cukup andalkan refetch saat tab dibuka lagi (fetch lazily di atas) + set `_taggedLoaded = false` lewat listener/route-return bila tersedia; JANGAN bangun store sinkronisasi baru untuk ini.

- [ ] **Step 4: Regresi penuh**

```bash
cd flutter_app && flutter analyze && flutter test
npx tsc --noEmit && npm test
```

Expected: semua hijau. Kalau ada golden test profil gagal, inspect `failures/` diff dulu (gotcha repo: golden bisa stale, bukan flaky) — layout grid seharusnya TIDAK berubah (reuse widget).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/profile_service.dart flutter_app/lib/screens/public_profile_screen.dart flutter_app/lib/screens/member_screen.dart flutter_app/test/public_profile_tagged_tab_test.dart && git commit -m "feat(app): tab Ditandai terisi data sungguhan (Spec B)"
```

---

## Catatan eksekusi

- **Subagent WAJIB verifikasi `pwd` + `git branch --show-current` sebelum edit file apa pun** (insiden sebelumnya: sesi paralel mengedit `public_profile_screen.dart` di branch lain). Kerja HANYA di worktree `C:\Users\USER\Desktop\natalopetshopflutter\.claude\worktrees\natalo-app-audit-fixes-e73353`, path absolut.
- **Migration Prisma WAJIB di-apply ke KEDUA database Neon sebelum deploy** (`npx prisma migrate deploy` per `DATABASE_URL`) — insiden schema-drift product-video terjadi karena kolom masuk lewat `db push` ke satu DB saja. `/api/admin/diag` bisa dipakai untuk cek DB aktif.
- Konvensi test backend repo ini adalah **node:test via `npx tsx --test tests/<file>.test.ts`** (`npm test` menjalankan semuanya) — BUKAN vitest. Test menyasar helper murni di `lib/`, bukan route handler langsung.
- PR #245 (Spec A) belum merge — kalau branch ini tidak memuat Spec A (cek keberadaan `kShopTagEnabled` + tab "Ditandai"), rebase/merge dulu sebelum Task 8+.
- Spec B belum device-verify sampai rilis app; jangan klaim selesai tanpa `flutter analyze` + `flutter test` + `npm test` + `npx tsc --noEmit` hijau.
