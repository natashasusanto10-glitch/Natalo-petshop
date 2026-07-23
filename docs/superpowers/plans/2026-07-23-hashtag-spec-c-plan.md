# Hashtag (Spec C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hashtag `#kucing` di caption jadi tappable → halaman hashtag (grid post ber-tag, terbaru dulu); composer memberi saran hashtag saat mengetik `#`.

**Architecture:** Tabel `Hashtag` (name unik lowercase + `postCount` aproksimatif) + junction `FeedPostHashtag`, di-parse server-side dari caption (`title` + `description`) dalam transaksi create yang sudah ada. Flutter memperluas parser bersama `buildMentionSpans` (yang juga dipakai `MentionText`) sehingga caption feed, komentar, dan detail post semuanya kebagian; halaman hashtag reuse `GalleryPostTile` + mixin `PostGalleryOpener` (multi-author); picker composer meniru `MentionPickerController` 1:1.

**Tech Stack:** Next.js App Router + Prisma + Neon (backend, test `npx tsx --test`), Flutter (test `flutter test`).

## Global Constraints

(Disalin verbatim dari spec `docs/superpowers/specs/2026-07-23-hashtag-spec-c-design.md` — berlaku implisit untuk SEMUA task.)

- Maks **5 hashtag unik per post**; pesan persis `"Maksimal 5 hashtag per postingan."` — 3 lapis: editor caption blokir simpan, submit post cek ulang, server 400.
- Regex `#([a-z0-9_]+)` case-insensitive **dengan boundary**: `#` valid hanya jika didahului awal-teks atau whitespace (`harga#promo` dan `natalo.com/#promo` BUKAN tag). Teknik bebas (grup awal `(^|\s)`) asal identik server ↔ Flutter.
- Filter panjang **2–50** di fungsi extract (kedua sisi); duplikat dihitung sekali; normalisasi **lowercase** untuk simpan/query/navigasi.
- Migration file sungguhan — **BUKAN `db push`** — apply ke kedua database Neon.
- `postCount` = sinyal **aproksimatif** HANYA untuk urutan autocomplete; header halaman hashtag pakai hitungan sungguhan dari query.
- Visibilitas halaman hashtag = **`PUBLIC_FEED_POST_WHERE`** (`lib/feed/queries.ts:43`) — status ACTIVE + deletedAt null + encodingStatus ready.
- Response post pakai **serializer feed existing** (brand-safe `lib/social/brand-user.ts` otomatis).
- **Tanpa notifikasi** hashtag; tanpa follow-hashtag; tanpa live-highlight editor.
- Style span hashtag: biru `Color(0xFF0B7FEA)` (sama mention) + **FontWeight.w600** (mention tetap w800).
- Delete post: default **soft** (`deletedAt`) → junction dibiarkan (halaman ter-filter); admin hard (`?hard=1`) → cascade + decrement `postCount`.
- Admin create memakai route yang SAMA dengan client (`POST /api/feed/posts` + `bunny/upload-url`) — dua route itu = SEMUA jalur create.
- Halaman hashtag WAJIB multi-author: `PostGalleryOpener` dengan `authorPerPost => true`.
- §3b spec (kualitas UI premium): `Semantics` di semua elemen interaktif baru; baris picker ≥48dp; animasi baru lewat `MotionPrefs.effective`; error TIDAK menyamar jadi empty (pakai error view + coba-lagi standar); haptic pilih saran = `AppHaptics.tap()` + `HapticFeedback.selectionClick()` (paritas `insertMention`); token NataloColors, tanpa hex baru.
- Empty state halaman: `"Belum ada postingan dengan tag ini."`
- Autocomplete: `q` kosong → list kosong tanpa error; maks 8; urut `postCount` desc; debounce **300ms**. (Catatan sadar: MentionPicker pakai 200ms — spec mengunci 300ms utk hashtag; JANGAN "menyamakan" tanpa keputusan user.)
- Route Flutter baru: `'/hashtag'` dengan `arguments` String (nama lowercase tanpa `#`), pola `onGenerateRoute` switch `main.dart`.
- Semua teks UI bahasa Indonesia.

---

## File Map

| File | Peran |
|---|---|
| `prisma/schema.prisma` + `prisma/migrations/20260723200000_add_hashtags/migration.sql` | Model `Hashtag`, `FeedPostHashtag` |
| `lib/feed/hashtags.ts` (BARU) | Pure helpers: extract/validate/sync/decrement/search/list |
| `tests/feed-hashtags.test.ts` (BARU) | Test helpers backend |
| `app/api/feed/posts/route.ts` | Gate 400 + sync dalam tx (foto/PROMO, client+admin) |
| `app/api/feed/bunny/upload-url/route.ts` | Gate 400 + sync dalam tx (video, client+admin) |
| `app/api/admin/feed/posts/[id]/route.ts` | Decrement saat hard delete |
| `app/api/feed/hashtags/[name]/route.ts` (BARU) | Halaman hashtag (posts + count akurat + cursor) |
| `app/api/feed/hashtags/search/route.ts` (BARU) | Autocomplete |
| `flutter_app/lib/utils/mention_text.dart` | Parser bersama + hashtag (dipakai SEMUA permukaan) |
| `flutter_app/lib/services/feed_service.dart` | `fetchHashtagPosts`, `searchHashtags` |
| `flutter_app/lib/screens/hashtag_screen.dart` (BARU) | Halaman hashtag |
| `flutter_app/lib/widgets/hashtag_picker.dart` (BARU) | `HashtagPickerController` + panel saran |
| `flutter_app/lib/screens/feed_caption_edit_screen.dart` | Pasang picker + validasi limit 5 |
| `flutter_app/lib/main.dart` | Route `'/hashtag'` |
| Call sites render: `flutter_app/lib/features/feed/widgets/feed_creator_overlay.dart`, `flutter_app/lib/widgets/feed_comment_sheet.dart`, `flutter_app/lib/screens/member_post_detail_screen.dart` | Teruskan `onHashtagTap` |

---

### Task 1: Skema Prisma + migration

**Files:**
- Modify: `prisma/schema.prisma`
- Create: `prisma/migrations/20260723200000_add_hashtags/migration.sql`

**Interfaces:**
- Produces: model `Hashtag { id, name(unik lowercase), postCount, createdAt }`, `FeedPostHashtag { id, feedPostId, hashtagId, createdAt }` + back-relations `FeedPost.hashtags`, dipakai Task 3–8.

- [ ] **Step 1: Tambah model di schema.prisma** — letakkan setelah model `FeedTaggedUser` (±baris 1448), tambah juga back-relation di `FeedPost`:

```prisma
model Hashtag {
  id        String   @id @default(cuid())
  /// Nama tag TANPA '#', SELALU lowercase (normalisasi di lib/feed/hashtags.ts).
  name      String   @unique
  /// Sinyal popularitas APROKSIMATIF — hanya untuk urutan autocomplete.
  /// Header halaman hashtag pakai hitungan query sungguhan (spec §1).
  postCount Int      @default(0)
  createdAt DateTime @default(now())
  posts     FeedPostHashtag[]
}

model FeedPostHashtag {
  id         String   @id @default(cuid())
  feedPostId String
  hashtagId  String
  createdAt  DateTime @default(now())
  post       FeedPost @relation(fields: [feedPostId], references: [id], onDelete: Cascade)
  hashtag    Hashtag  @relation(fields: [hashtagId], references: [id], onDelete: Cascade)

  @@unique([feedPostId, hashtagId])
  @@index([hashtagId])
}
```

Di model `FeedPost`, tambah relasi: `hashtags FeedPostHashtag[]` (di dekat `taggedUsers FeedTaggedUser[]`).

- [ ] **Step 2: Tulis migration SQL tangan** (pola sama `20260723120000_add_feed_tagged_user`):

```sql
-- CreateTable
CREATE TABLE "Hashtag" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "postCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Hashtag_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FeedPostHashtag" (
    "id" TEXT NOT NULL,
    "feedPostId" TEXT NOT NULL,
    "hashtagId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "FeedPostHashtag_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Hashtag_name_key" ON "Hashtag"("name");
CREATE UNIQUE INDEX "FeedPostHashtag_feedPostId_hashtagId_key" ON "FeedPostHashtag"("feedPostId", "hashtagId");
CREATE INDEX "FeedPostHashtag_hashtagId_idx" ON "FeedPostHashtag"("hashtagId");

-- AddForeignKey
ALTER TABLE "FeedPostHashtag" ADD CONSTRAINT "FeedPostHashtag_feedPostId_fkey" FOREIGN KEY ("feedPostId") REFERENCES "FeedPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FeedPostHashtag" ADD CONSTRAINT "FeedPostHashtag_hashtagId_fkey" FOREIGN KEY ("hashtagId") REFERENCES "Hashtag"("id") ON DELETE CASCADE ON UPDATE CASCADE;
```

- [ ] **Step 3: Verifikasi** — `npx prisma validate` → valid; `npx prisma generate` → sukses; `npx tsc --noEmit` → tanpa error baru. JANGAN `db push`. (Apply migration ke kedua Neon = langkah deploy, di luar sandbox — catat di PR.)
- [ ] **Step 4: Commit** — `git add prisma/ && git commit -m "feat(db): model Hashtag + FeedPostHashtag (Spec C)"`

---

### Task 2: Pure helper extract + validasi (`lib/feed/hashtags.ts`)

**Files:**
- Create: `lib/feed/hashtags.ts`
- Test: `tests/feed-hashtags.test.ts`

**Interfaces:**
- Produces: `extractHashtags(text: string): string[]` (lowercase, dedup, urutan kemunculan, panjang 2–50, boundary), `isValidHashtagName(name: string): boolean`, `MAX_HASHTAGS_PER_POST = 5`, `HASHTAG_LIMIT_MESSAGE = "Maksimal 5 hashtag per postingan."` — dipakai Task 3–5, 7 dan (mirror) Task 9.

- [ ] **Step 1: Tulis failing test** (`tests/feed-hashtags.test.ts`, pola node:test `tests/feed-tagged-users.test.ts`):

```ts
import test from "node:test";
import assert from "node:assert/strict";
import {
  extractHashtags,
  isValidHashtagName,
  MAX_HASHTAGS_PER_POST,
  HASHTAG_LIMIT_MESSAGE,
} from "../lib/feed/hashtags";

test("extractHashtags: dasar — lowercase, urutan kemunculan", () => {
  assert.deepEqual(extractHashtags("Halo #KucingLucu dan #anjing_kecil"), [
    "kucinglucu",
    "anjing_kecil",
  ]);
});

test("extractHashtags: boundary — mid-word & URL fragment ditolak", () => {
  assert.deepEqual(extractHashtags("harga#promo cek natalo.com/#promo"), []);
  assert.deepEqual(extractHashtags("#promo di awal teks"), ["promo"]);
  assert.deepEqual(extractHashtags("baris\n#baru juga valid"), ["baru"]);
});

test("extractHashtags: panjang 2-50 di-filter", () => {
  assert.deepEqual(extractHashtags("#a #ab"), ["ab"]);
  const long = "x".repeat(51);
  const max = "y".repeat(50);
  assert.deepEqual(extractHashtags(`#${long} #${max}`), [max]);
});

test("extractHashtags: dedup case-insensitive, sekali hitung", () => {
  assert.deepEqual(extractHashtags("#Kucing #kucing #KUCING #lain"), [
    "kucing",
    "lain",
  ]);
});

test("extractHashtags: angka & underscore boleh; teks kosong aman", () => {
  assert.deepEqual(extractHashtags("#tag_2026 ok"), ["tag_2026"]);
  assert.deepEqual(extractHashtags(""), []);
});

test("isValidHashtagName: hanya nama kanonik yang lolos", () => {
  assert.equal(isValidHashtagName("kucing_2"), true);
  assert.equal(isValidHashtagName("ab"), true);
  assert.equal(isValidHashtagName("a"), false);
  assert.equal(isValidHashtagName("Kucing"), false); // wajib lowercase
  assert.equal(isValidHashtagName("ku cing"), false);
  assert.equal(isValidHashtagName("x".repeat(51)), false);
});

test("konstanta limit & pesan sesuai spec", () => {
  assert.equal(MAX_HASHTAGS_PER_POST, 5);
  assert.equal(HASHTAG_LIMIT_MESSAGE, "Maksimal 5 hashtag per postingan.");
});
```

- [ ] **Step 2: Run — pastikan FAIL**: `npx tsx --test tests/feed-hashtags.test.ts` → gagal (module belum ada).
- [ ] **Step 3: Implementasi minimal** (`lib/feed/hashtags.ts`):

```ts
/**
 * Hashtag (Spec C) — SATU sumber aturan parsing, di-mirror persis di
 * flutter_app/lib/utils/mention_text.dart. Ubah di sini ⇒ ubah di sana.
 *
 * Boundary: '#' hanya valid di awal teks atau setelah whitespace —
 * "harga#promo" dan "natalo.com/#promo" BUKAN tag (spec §1).
 */
const HASHTAG_SOURCE = /(^|\s)#([a-z0-9_]+)/gi;

export const MAX_HASHTAGS_PER_POST = 5;
export const HASHTAG_LIMIT_MESSAGE = "Maksimal 5 hashtag per postingan.";

const MIN_NAME_LENGTH = 2;
const MAX_NAME_LENGTH = 50;

/** Nama kanonik: lowercase [a-z0-9_], panjang 2-50, tanpa '#'. */
export function isValidHashtagName(name: string): boolean {
  if (name.length < MIN_NAME_LENGTH || name.length > MAX_NAME_LENGTH) {
    return false;
  }
  return /^[a-z0-9_]+$/.test(name);
}

/**
 * Extract hashtag dari teks caption: lowercase, dedup (sekali hitung),
 * urutan kemunculan pertama, filter panjang 2-50 (filter di fungsi, bukan
 * regex — pola sama extractMentionHandles di lib/feed/mentions.ts).
 */
export function extractHashtags(text: string): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const match of text.matchAll(HASHTAG_SOURCE)) {
    const name = match[2].toLowerCase();
    if (name.length < MIN_NAME_LENGTH || name.length > MAX_NAME_LENGTH) {
      continue;
    }
    if (seen.has(name)) continue;
    seen.add(name);
    result.push(name);
  }
  return result;
}
```

- [ ] **Step 4: Run — pastikan PASS**: `npx tsx --test tests/feed-hashtags.test.ts` → semua hijau. Juga `npx tsc --noEmit`.
- [ ] **Step 5: Commit** — `git add lib/feed/hashtags.ts tests/feed-hashtags.test.ts && git commit -m "feat(feed): extractHashtags + validasi (Spec C)"`

---

### Task 3: Helper transaksi `syncPostHashtags` + `decrementHashtagCounts`

**Files:**
- Modify: `lib/feed/hashtags.ts` (append)
- Test: `tests/feed-hashtags.test.ts` (append)

**Interfaces:**
- Consumes: `extractHashtags` (Task 2).
- Produces: `syncPostHashtags(tx: HashtagTx, feedPostId: string, captionText: string): Promise<void>` dan `decrementHashtagCounts(tx: HashtagTx, feedPostId: string): Promise<void>`; type `HashtagTx` (subset TransactionClient — injectable utk test, pola db-injectable `lib/feed/queries.ts`).

- [ ] **Step 1: Tulis failing test** (append; fake tx merekam panggilan):

```ts
import { syncPostHashtags, decrementHashtagCounts } from "../lib/feed/hashtags";

function makeFakeTx() {
  const calls: { method: string; args: unknown }[] = [];
  let nextId = 0;
  const tx = {
    hashtag: {
      upsert: async (args: { where: { name: string } }) => {
        calls.push({ method: "hashtag.upsert", args });
        return { id: `h${nextId++}`, name: args.where.name };
      },
      updateMany: async (args: unknown) => {
        calls.push({ method: "hashtag.updateMany", args });
        return { count: 1 };
      },
    },
    feedPostHashtag: {
      createMany: async (args: unknown) => {
        calls.push({ method: "feedPostHashtag.createMany", args });
        return { count: 1 };
      },
      findMany: async (args: unknown) => {
        calls.push({ method: "feedPostHashtag.findMany", args });
        return [{ hashtagId: "h0" }, { hashtagId: "h1" }];
      },
    },
  };
  return { tx, calls };
}

test("syncPostHashtags: upsert per tag (increment postCount) + junction createMany", async () => {
  const { tx, calls } = makeFakeTx();
  await syncPostHashtags(tx, "post1", "Halo #kucing dan #Anjing");
  const upserts = calls.filter((c) => c.method === "hashtag.upsert");
  assert.equal(upserts.length, 2);
  const first = upserts[0].args as {
    where: { name: string };
    create: { name: string; postCount: number };
    update: { postCount: { increment: number } };
  };
  assert.equal(first.where.name, "kucing");
  assert.equal(first.create.postCount, 1);
  assert.equal(first.update.postCount.increment, 1);
  const cm = calls.find((c) => c.method === "feedPostHashtag.createMany")!
    .args as { data: { feedPostId: string; hashtagId: string }[] };
  assert.deepEqual(
    cm.data.map((d) => d.feedPostId),
    ["post1", "post1"],
  );
});

test("syncPostHashtags: caption tanpa tag → tidak menyentuh db", async () => {
  const { tx, calls } = makeFakeTx();
  await syncPostHashtags(tx, "post1", "caption polos tanpa tag");
  assert.equal(calls.length, 0);
});

test("decrementHashtagCounts: baca junction lalu decrement tiap hashtagId", async () => {
  const { tx, calls } = makeFakeTx();
  await decrementHashtagCounts(tx, "post1");
  assert.equal(
    calls.filter((c) => c.method === "feedPostHashtag.findMany").length,
    1,
  );
  const upd = calls.find((c) => c.method === "hashtag.updateMany")!.args as {
    where: { id: { in: string[] }; postCount: { gt: number } };
    data: { postCount: { decrement: number } };
  };
  assert.deepEqual(upd.where.id.in, ["h0", "h1"]);
  assert.equal(upd.where.postCount.gt, 0); // guard: jangan minus
  assert.equal(upd.data.postCount.decrement, 1);
});
```

- [ ] **Step 2: Run — FAIL** (fungsi belum ada).
- [ ] **Step 3: Implementasi** (append `lib/feed/hashtags.ts`):

```ts
/** Subset TransactionClient yang dipakai — injectable untuk unit test. */
export type HashtagTx = {
  hashtag: {
    upsert: (args: {
      where: { name: string };
      create: { name: string; postCount: number };
      update: { postCount: { increment: number } };
    }) => Promise<{ id: string }>;
    updateMany: (args: {
      where: { id: { in: string[] }; postCount: { gt: number } };
      data: { postCount: { decrement: number } };
    }) => Promise<unknown>;
  };
  feedPostHashtag: {
    createMany: (args: {
      data: { feedPostId: string; hashtagId: string }[];
    }) => Promise<unknown>;
    findMany: (args: {
      where: { feedPostId: string };
      select: { hashtagId: true };
    }) => Promise<{ hashtagId: string }[]>;
  };
};

/**
 * Panggil DI DALAM $transaction create post (foto & video — dua-duanya jalur
 * client DAN admin; tidak ada route create lain). captionText = gabungan
 * `${title} ${description ?? ""}` — sumber yang sama dengan gate mention.
 */
export async function syncPostHashtags(
  tx: HashtagTx,
  feedPostId: string,
  captionText: string,
): Promise<void> {
  const names = extractHashtags(captionText);
  if (names.length === 0) return;
  const rows: { feedPostId: string; hashtagId: string }[] = [];
  for (const name of names) {
    const tag = await tx.hashtag.upsert({
      where: { name },
      create: { name, postCount: 1 },
      update: { postCount: { increment: 1 } },
    });
    rows.push({ feedPostId, hashtagId: tag.id });
  }
  await tx.feedPostHashtag.createMany({ data: rows });
}

/**
 * HANYA untuk jalur HARD delete (admin ?hard=1). Soft delete (deletedAt)
 * TIDAK men-decrement — postCount memang aproksimatif (spec §1), halaman
 * hashtag ter-filter PUBLIC_FEED_POST_WHERE jadi tetap benar.
 * Panggil SEBELUM prisma.feedPost.delete (cascade menghapus junction-nya).
 */
export async function decrementHashtagCounts(
  tx: HashtagTx,
  feedPostId: string,
): Promise<void> {
  const rows = await tx.feedPostHashtag.findMany({
    where: { feedPostId },
    select: { hashtagId: true },
  });
  if (rows.length === 0) return;
  await tx.hashtag.updateMany({
    where: { id: { in: rows.map((r) => r.hashtagId) }, postCount: { gt: 0 } },
    data: { postCount: { decrement: 1 } },
  });
}
```

- [ ] **Step 4: Run — PASS** + `npx tsc --noEmit`.
- [ ] **Step 5: Commit** — `git commit -m "feat(feed): syncPostHashtags + decrementHashtagCounts (Spec C)"`

---

### Task 4: Wire route create FOTO (`app/api/feed/posts/route.ts`)

**Files:**
- Modify: `app/api/feed/posts/route.ts` (gate ±baris 195-203; tx ±baris 532-643)

**Interfaces:**
- Consumes: `extractHashtags`, `MAX_HASHTAGS_PER_POST`, `HASHTAG_LIMIT_MESSAGE`, `syncPostHashtags` (Task 2-3).

- [ ] **Step 1: Import** — di blok import route: `import { extractHashtags, MAX_HASHTAGS_PER_POST, HASHTAG_LIMIT_MESSAGE, syncPostHashtags } from "@/lib/feed/hashtags";` (samakan gaya alias import file itu — kalau route pakai relative `../../..`, ikuti).
- [ ] **Step 2: Gate 400** — TEPAT di bawah gate mention existing (±baris 195-203, `captionMentions`):

```ts
// Spec C: max 5 hashtag unik per post (caption = title + description,
// sumber yang sama dengan gate mention di atas).
const captionHashtags = extractHashtags(`${title} ${description ?? ""}`);
if (captionHashtags.length > MAX_HASHTAGS_PER_POST) {
  return NextResponse.json({ error: HASHTAG_LIMIT_MESSAGE }, { status: 400 });
}
```

(Pakai bentuk response error yang SAMA dengan gate mention persis di atasnya — kalau di sana `NextResponse.json({ error }, { status: 400 })`, ikuti verbatim.)
- [ ] **Step 3: Sync dalam tx** — di dalam `prisma.$transaction` (±baris 532), SETELAH `tx.feedTaggedUser.createMany` (±baris 638), sebelum transaksi selesai:

```ts
// Spec C: tulis relasi hashtag dalam transaksi yang sama dengan create post.
await syncPostHashtags(tx, post.id, `${title} ${description ?? ""}`);
```

(`post` = hasil `tx.feedPost.create` baris 533 — pakai nama variabel persis yang ada di file.)
- [ ] **Step 4: Verifikasi** — `npx tsc --noEmit` bersih; `npx tsx --test tests/feed-hashtags.test.ts tests/feed-tagged-users.test.ts` hijau (regresi tetangga).
- [ ] **Step 5: Commit** — `git commit -m "feat(feed): parse+simpan hashtag di create foto (Spec C)"`

---

### Task 5: Wire route create VIDEO (`app/api/feed/bunny/upload-url/route.ts`)

**Files:**
- Modify: `app/api/feed/bunny/upload-url/route.ts` (tx ±baris 323-380; caption = `title` + `description`, lihat komentar baris 140-143)

- [ ] **Step 1: Import** sama Task 4.
- [ ] **Step 2: Gate 400** — sebelum `$transaction` (setelah parsing body caption/title): kode identik Task 4 Step 2 (gunakan variabel title/description milik route ini).
- [ ] **Step 3: Sync dalam tx** — di dalam `$transaction` (baris 323), setelah `tx.feedTaggedUser.createMany` (±baris 380): `await syncPostHashtags(tx, post.id, \`${title} ${description ?? ""}\`);` — nama variabel post/title/description ikut file.
- [ ] **Step 4: Verifikasi** — `npx tsc --noEmit`; test suite hashtags tetap hijau. CATATAN: junction video ditulis saat provision (encodingStatus "uploading") — itu BENAR; halaman hashtag ter-filter `encodingStatus: "ready"` via `PUBLIC_FEED_POST_WHERE`, jadi post video baru tampil setelah playable (spec §1). JANGAN menunda sync ke hook ready.
- [ ] **Step 5: Commit** — `git commit -m "feat(feed): parse+simpan hashtag di create video (Spec C)"`

---

### Task 6: Decrement saat HARD delete admin

**Files:**
- Modify: `app/api/admin/feed/posts/[id]/route.ts` (cabang hard ±baris 301: `prisma.feedPost.delete`)

- [ ] **Step 1: Import** `decrementHashtagCounts` dari `@/lib/feed/hashtags` (ikuti gaya import file).
- [ ] **Step 2: Bungkus hard delete** — cabang `?hard=1` (±baris 301) jadi transaksi: decrement dulu (junction masih ada), lalu delete (cascade):

```ts
await prisma.$transaction(async (tx) => {
  // Spec C: kurangi postCount sebelum cascade menghapus junction.
  await decrementHashtagCounts(tx, postId);
  await tx.feedPost.delete({ where: { id: postId } });
});
```

(Kalau cabang hard sudah punya operasi lain di sekitarnya — mis. hapus aset Bunny — pertahankan urutan existing, hanya pindahkan delete ke dalam tx bersama decrement.) Soft delete (default, `deletedAt`) TIDAK disentuh.
- [ ] **Step 3: Verifikasi** — `npx tsc --noEmit` bersih.
- [ ] **Step 4: Commit** — `git commit -m "feat(admin): decrement postCount hashtag saat hard delete (Spec C)"`

---

### Task 7: Endpoint halaman hashtag `GET /api/feed/hashtags/[name]`

**Files:**
- Create: `app/api/feed/hashtags/[name]/route.ts`
- Modify: `lib/feed/hashtags.ts` (append query helper injectable)
- Test: `tests/feed-hashtags.test.ts` (append)

**Interfaces:**
- Consumes: `isValidHashtagName` (Task 2); `PUBLIC_FEED_POST_WHERE` + serializer feed dari `lib/feed/queries.ts` (`listFeedPosts` menerima `db` injectable — baca file itu dan REUSE serializer/select yang sama, jangan menyalin field-by-field baru).
- Produces: response `{ name: string, postCount: number, posts: FeedPostJson[], nextCursor: string | null }` — dipakai Flutter Task 10/11. `postCount` di response = **hitungan akurat** query (BUKAN kolom cache).

- [ ] **Step 1: Failing test untuk builder where** (append; pure):

```ts
import { hashtagPostsWhere } from "../lib/feed/hashtags";

test("hashtagPostsWhere: gabungkan PUBLIC_FEED_POST_WHERE + relasi tag", () => {
  const where = hashtagPostsWhere("kucing");
  assert.equal(where.status, "ACTIVE");
  assert.equal(where.deletedAt, null);
  assert.equal(where.encodingStatus, "ready");
  assert.deepEqual(where.hashtags, {
    some: { hashtag: { name: "kucing" } },
  });
});
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implementasi helper** (append `lib/feed/hashtags.ts`):

```ts
import { PUBLIC_FEED_POST_WHERE } from "./queries";

/** Where-clause halaman hashtag: visibilitas feed penuh + relasi tag. */
export function hashtagPostsWhere(name: string) {
  return {
    ...PUBLIC_FEED_POST_WHERE,
    hashtags: { some: { hashtag: { name } } },
  };
}
```

(Kalau `PUBLIC_FEED_POST_WHERE` belum di-export dari `lib/feed/queries.ts`, export-kan — satu kata kunci `export`, tanpa mengubah isinya.)
- [ ] **Step 4: Run — PASS.**
- [ ] **Step 5: Route handler** (`app/api/feed/hashtags/[name]/route.ts`) — pola route feed existing (lihat `app/api/feed/posts/[id]/route.ts` utk gaya params/response/error):

```ts
import { NextResponse } from "next/server";
import { prisma } from "@/lib/db"; // ikuti path import db yang dipakai route feed lain
import {
  isValidHashtagName,
  hashtagPostsWhere,
} from "@/lib/feed/hashtags";
// REUSE select + serializer feed dari lib/feed/queries.ts — pakai fungsi/const
// yang sama dengan listFeedPosts (mis. FEED_POST_SELECT + serializeFeedPost;
// nama persis lihat file — JANGAN menulis serializer baru).

const PAGE_SIZE = 24;

export async function GET(
  req: Request,
  { params }: { params: Promise<{ name: string }> },
) {
  const { name: raw } = await params;
  const name = raw.toLowerCase();
  if (!isValidHashtagName(name)) {
    return NextResponse.json({ error: "Tag tidak valid." }, { status: 400 });
  }
  const cursor = new URL(req.url).searchParams.get("cursor");
  const where = hashtagPostsWhere(name);

  const [total, rows] = await Promise.all([
    prisma.feedPost.count({ where }),
    prisma.feedPost.findMany({
      where,
      orderBy: { createdAt: "desc" },
      take: PAGE_SIZE + 1,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      select: FEED_POST_SELECT, // select feed existing (bawa brand-safety)
    }),
  ]);

  const hasMore = rows.length > PAGE_SIZE;
  const page = hasMore ? rows.slice(0, PAGE_SIZE) : rows;
  return NextResponse.json({
    name,
    postCount: total, // hitungan AKURAT dari query — bukan kolom cache
    posts: page.map((row) => serializeFeedPost(row /* + arg lain sesuai signature existing */)),
    nextCursor: hasMore ? page[page.length - 1].id : null,
  });
}
```

Sesuaikan `FEED_POST_SELECT`/`serializeFeedPost` dengan nama konkret di `lib/feed/queries.ts` (implementer WAJIB baca file itu dulu; serializer existing sudah brand-safe + bawa taggedUsers).
- [ ] **Step 6: Verifikasi** — `npx tsc --noEmit` bersih; `npx tsx --test tests/feed-hashtags.test.ts` hijau.
- [ ] **Step 7: Commit** — `git commit -m "feat(api): GET /api/feed/hashtags/[name] (Spec C)"`

---

### Task 8: Endpoint autocomplete `GET /api/feed/hashtags/search`

**Files:**
- Create: `app/api/feed/hashtags/search/route.ts`
- Modify: `lib/feed/hashtags.ts` (append)
- Test: `tests/feed-hashtags.test.ts` (append)

**Interfaces:**
- Produces: response `{ hashtags: { name: string, postCount: number }[] }` (maks 8, urut postCount desc) — dipakai `HashtagPickerController` Task 12.

- [ ] **Step 1: Failing test** (append; fake db):

```ts
import { searchHashtags } from "../lib/feed/hashtags";

test("searchHashtags: prefix lowercase, urut postCount desc, maks 8", async () => {
  const captured: unknown[] = [];
  const fakeDb = {
    hashtag: {
      findMany: async (args: unknown) => {
        captured.push(args);
        return [{ name: "kucing", postCount: 24 }];
      },
    },
  };
  const rows = await searchHashtags(fakeDb, "Ku");
  assert.deepEqual(rows, [{ name: "kucing", postCount: 24 }]);
  const args = captured[0] as {
    where: { name: { startsWith: string } };
    orderBy: { postCount: "desc" };
    take: number;
  };
  assert.equal(args.where.name.startsWith, "ku"); // di-lowercase
  assert.equal(args.orderBy.postCount, "desc");
  assert.equal(args.take, 8);
});

test("searchHashtags: q kosong/whitespace → [] tanpa sentuh db", async () => {
  const fakeDb = {
    hashtag: {
      findMany: async () => {
        throw new Error("tidak boleh dipanggil");
      },
    },
  };
  assert.deepEqual(await searchHashtags(fakeDb, "  "), []);
});
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implementasi** (append `lib/feed/hashtags.ts`):

```ts
export type HashtagSearchDb = {
  hashtag: {
    findMany: (args: {
      where: { name: { startsWith: string } };
      orderBy: { postCount: "desc" };
      take: number;
      select: { name: true; postCount: true };
    }) => Promise<{ name: string; postCount: number }[]>;
  };
};

/** Autocomplete: prefix match lowercase, urut postCount desc, maks 8. */
export async function searchHashtags(
  db: HashtagSearchDb,
  q: string,
): Promise<{ name: string; postCount: number }[]> {
  const prefix = q.trim().toLowerCase();
  if (prefix.length === 0) return [];
  return db.hashtag.findMany({
    where: { name: { startsWith: prefix } },
    orderBy: { postCount: "desc" },
    take: 8,
    select: { name: true, postCount: true },
  });
}
```

- [ ] **Step 4: Run — PASS** + `npx tsc --noEmit`.
- [ ] **Step 5: Route handler** (`app/api/feed/hashtags/search/route.ts`):

```ts
import { NextResponse } from "next/server";
import { prisma } from "@/lib/db"; // ikuti path db route feed lain
import { searchHashtags } from "@/lib/feed/hashtags";

export async function GET(req: Request) {
  const q = new URL(req.url).searchParams.get("q") ?? "";
  const hashtags = await searchHashtags(prisma, q);
  return NextResponse.json({ hashtags });
}
```

(Auth: samakan dengan `/api/users/search` — kalau route itu pakai `getSession`, pakai gate yang sama di sini.)
- [ ] **Step 6: Verifikasi + Commit** — `npx tsc --noEmit`; `git commit -m "feat(api): autocomplete hashtag search (Spec C)"`

---

### Task 9: Flutter — parser bersama di `mention_text.dart`

**Files:**
- Modify: `flutter_app/lib/utils/mention_text.dart`
- Test: `flutter_app/test/utils/mention_text_hashtag_test.dart` (BARU)

**Interfaces:**
- Consumes: `buildMentionSpans` existing (signature di baris 23: params `text`, `onMentionTap`, `defaultStyle`, `mentionStyle`, `collectRecognizers`, `officialHandles`).
- Produces: parameter baru **opsional** `void Function(String name)? onHashtagTap` + `TextStyle? hashtagStyle` di `buildMentionSpans` DAN di widget `MentionText`. `MentionText.build` sudah memanggil `buildMentionSpans` (baris 149-156) — meneruskan parameter baru = SEMUA permukaan (caption feed via FeedExpandableCaption, komentar, detail post) otomatis kebagian. Callback menerima nama **lowercase tanpa '#'**.

- [ ] **Step 1: Failing test** (`flutter_app/test/utils/mention_text_hashtag_test.dart`) — kasus MIRROR persis server (Task 2):

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/mention_text.dart';

List<InlineSpan> spansOf(
  String text, {
  void Function(String)? onHashtagTap,
}) =>
    buildMentionSpans(
      text,
      onMentionTap: (_) {},
      onHashtagTap: onHashtagTap,
    );

String? hashtagOf(InlineSpan s) =>
    (s is TextSpan && s.text != null && s.text!.startsWith('#'))
        ? s.text
        : null;

void main() {
  test('hashtag jadi span tersendiri, biru w600, tap kirim lowercase', () {
    String? tapped;
    final spans = spansOf('Halo #KucingLucu!', onHashtagTap: (n) => tapped = n);
    final tagSpan = spans
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == '#KucingLucu');
    expect(tagSpan.style!.color, const Color(0xFF0B7FEA));
    expect(tagSpan.style!.fontWeight, FontWeight.w600);
    (tagSpan.recognizer as TapGestureRecognizer).onTap!();
    expect(tapped, 'kucinglucu');
  });

  test('boundary mirror server: mid-word & URL fragment TIDAK tappable', () {
    for (final text in ['harga#promo', 'cek natalo.com/#promo']) {
      final spans = spansOf(text, onHashtagTap: (_) {});
      expect(spans.whereType<TextSpan>().any((s) => hashtagOf(s) != null),
          isFalse, reason: text);
    }
  });

  test('panjang mirror server: #a plain, #ab tappable', () {
    final spans = spansOf('#a #ab', onHashtagTap: (_) {});
    final tags = spans
        .whereType<TextSpan>()
        .where((s) => s.recognizer != null && s.text!.startsWith('#'))
        .map((s) => s.text)
        .toList();
    expect(tags, ['#ab']);
  });

  test('mention + hashtag satu teks: keduanya utuh', () {
    String? mention;
    String? tag;
    final spans = buildMentionSpans(
      'Sama @budi_petshop di #grooming',
      onMentionTap: (h) => mention = h,
      onHashtagTap: (n) => tag = n,
    );
    final all = spans.whereType<TextSpan>().map((s) => s.text).join();
    expect(all, 'Sama @budi_petshop di #grooming');
    expect(spans.whereType<TextSpan>().where((s) => s.recognizer != null).length, 2);
    // fire keduanya utk memastikan routing benar
    for (final s in spans.whereType<TextSpan>()) {
      (s.recognizer as TapGestureRecognizer?)?.onTap?.call();
    }
    expect(mention, 'budi_petshop');
    expect(tag, 'grooming');
  });

  test('onHashtagTap null → hashtag tetap teks polos (tanpa recognizer)', () {
    final spans = spansOf('#kucing');
    expect(
      spans.whereType<TextSpan>().any(
          (s) => s.text == '#kucing' && s.recognizer != null),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run — FAIL**: `flutter test test/utils/mention_text_hashtag_test.dart` (param belum ada).
- [ ] **Step 3: Implementasi** — di `mention_text.dart`:
  1. Tambah konstanta regex hashtag di sebelah `_kMentionPattern` (baris 9-12):

```dart
/// MIRROR persis lib/feed/hashtags.ts (server). Boundary: '#' hanya valid
/// di awal teks atau setelah whitespace. Panjang 2-50 di-filter di kode
/// (bukan regex) — sama seperti server. Ubah di sini ⇒ ubah di sana.
final RegExp _kHashtagPattern = RegExp(
  r'(^|\s)#([a-z0-9_]+)',
  caseSensitive: false,
);
const int _kHashtagMinLength = 2;
const int _kHashtagMaxLength = 50;

/// Style hashtag: biru sama mention, w600 (mention w800) — topik lebih
/// ringan dari orang (spec §3).
const TextStyle _kDefaultHashtagStyle = TextStyle(
  color: Color(0xFF0B7FEA),
  fontWeight: FontWeight.w600,
);
```

  2. `buildMentionSpans`: tambah param `void Function(String name)? onHashtagTap` dan `TextStyle? hashtagStyle`. Ubah algoritma jadi dua fase: kumpulkan SEMUA match (mention + hashtag) sebagai list `(start, end, builder)` — utk hashtag, `start` = posisi `#` (grup 1 whitespace TIDAK ikut di-span, tetap teks biasa), filter panjang 2-50, skip kalau `onHashtagTap == null`; sort by start; render berselang-seling dengan teks polos di antaranya (pola loop existing diperluas — mention span builder existing TIDAK berubah, termasuk brand-override official). Hashtag span:

```dart
TextSpan(
  text: matchedText, // '#KucingLucu' apa adanya (display as typed)
  style: (defaultStyle ?? const TextStyle())
      .merge(hashtagStyle ?? _kDefaultHashtagStyle),
  recognizer: recognizer, // TapGestureRecognizer, register ke collectRecognizers
  semanticsLabel: 'Tag ${name}', // §3b Semantics
)
```

  dengan `onTap: () => onHashtagTap(name.toLowerCase())`.
  3. Widget `MentionText` (baris 101): tambah field `final void Function(String name)? onHashtagTap;` (+ konstruktor), teruskan ke `buildMentionSpans` di build (baris 149-156). Lifecycle recognizer sudah ditangani `collectRecognizers` existing — recognizer hashtag ikut mekanisme yang sama.
- [ ] **Step 4: Run — PASS** + regresi test mention existing: `flutter test test/utils/` (semua file utils) → hijau; `flutter analyze lib/utils/mention_text.dart` bersih.
- [ ] **Step 5: Commit** — `git commit -m "feat(app): parser hashtag di buildMentionSpans + MentionText (Spec C)"`

---

### Task 10: Flutter — route `'/hashtag'`, service fetcher, wiring call sites

**Files:**
- Modify: `flutter_app/lib/main.dart` (switch `onGenerateRoute` ±baris 328-450)
- Modify: `flutter_app/lib/services/feed_service.dart`
- Modify: `flutter_app/lib/features/feed/widgets/feed_creator_overlay.dart` (`FeedExpandableCaption` → `buildMentionSpans` call ±baris 396-402)
- Modify: `flutter_app/lib/widgets/feed_comment_sheet.dart` (`MentionText` baris 2756, 2934)
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart` (`MentionText` baris 2960)
- Test: `flutter_app/test/services/feed_service_hashtag_test.dart` (BARU)

**Interfaces:**
- Consumes: `onHashtagTap` (Task 9); response Task 7/8.
- Produces: `FeedService.fetchHashtagPosts(String name, {String? cursor})` → `HashtagPageResult { name, postCount, posts(List<FeedPost>), nextCursor }`; `FeedService.searchHashtags(String q)` → `List<HashtagSuggestion { name, postCount }>`; route `'/hashtag'` (arguments String nama lowercase) → `HashtagScreen` (dibuat Task 11 — Task 10 mendaftarkan route dengan import; kerjakan Task 10 SETELAH Task 11 kalau eksekusi berurutan, ATAU pakai placeholder screen minimal di Task 10 lalu Task 11 mengisinya — pilih urutan 11→10 saat eksekusi agar tanpa placeholder).

**CATATAN URUTAN:** kerjakan **Task 11 dulu, lalu Task 10** (plan ditulis 10-sebelum-11 hanya untuk kejelasan interface).

- [ ] **Step 1: Failing test service** (`flutter_app/test/services/feed_service_hashtag_test.dart`) — pola test service existing (fetcher injectable; lihat `feed_service.dart` utk gaya inject `apiClient`/fetcher):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';

void main() {
  test('fetchHashtagPosts parse name+postCount+posts+cursor', () async {
    final result = HashtagPageResult.fromJson({
      'name': 'kucing',
      'postCount': 3,
      'posts': [
        {
          'id': 'p1',
          'slug': 'p1',
          'kind': 'PHOTO_CAROUSEL',
          'author': {'id': 'u1', 'name': 'Budi'},
          'createdAt': '2026-07-23T00:00:00.000Z',
        }
      ],
      'nextCursor': 'p1',
    });
    expect(result.name, 'kucing');
    expect(result.postCount, 3);
    expect(result.posts.single.id, 'p1');
    expect(result.nextCursor, 'p1');
  });

  test('HashtagSuggestion parse + list kosong aman', () {
    final s = HashtagSuggestion.fromJson({'name': 'kucing', 'postCount': 24});
    expect(s.name, 'kucing');
    expect(s.postCount, 24);
  });
}
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implementasi service** — di `feed_service.dart` tambah class + methods (pola method existing di file itu — `apiClient.getJson`):

```dart
class HashtagSuggestion {
  final String name;
  final int postCount;
  const HashtagSuggestion({required this.name, required this.postCount});
  factory HashtagSuggestion.fromJson(Map<String, dynamic> json) =>
      HashtagSuggestion(
        name: (json['name'] as String?) ?? '',
        postCount: (json['postCount'] as num?)?.toInt() ?? 0,
      );
}

class HashtagPageResult {
  final String name;
  final int postCount;
  final List<FeedPost> posts;
  final String? nextCursor;
  const HashtagPageResult({
    required this.name,
    required this.postCount,
    required this.posts,
    this.nextCursor,
  });
  factory HashtagPageResult.fromJson(Map<String, dynamic> json) =>
      HashtagPageResult(
        name: (json['name'] as String?) ?? '',
        postCount: (json['postCount'] as num?)?.toInt() ?? 0,
        posts: ((json['posts'] as List?) ?? const [])
            .whereType<Map>()
            .map((raw) => FeedPost.fromJson(Map<String, dynamic>.from(raw)))
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}
```

Methods di `FeedService`:

```dart
Future<HashtagPageResult> fetchHashtagPosts(String name, {String? cursor}) async {
  final data = await apiClient.getJson(
    '/api/feed/hashtags/${Uri.encodeComponent(name)}',
    query: cursor == null ? null : {'cursor': cursor},
  );
  return HashtagPageResult.fromJson(Map<String, dynamic>.from(data as Map));
}

Future<List<HashtagSuggestion>> searchHashtags(String q) async {
  final data = await apiClient.getJson(
    '/api/feed/hashtags/search',
    query: {'q': q},
  );
  final rows = (data is Map ? data['hashtags'] as List? : null) ?? const [];
  return rows
      .whereType<Map>()
      .map((r) => HashtagSuggestion.fromJson(Map<String, dynamic>.from(r)))
      .toList();
}
```

(Signature `apiClient.getJson` ikuti pemakaian existing di file yang sama.)
- [ ] **Step 4: Run — PASS.**
- [ ] **Step 5: Route** — di switch `onGenerateRoute` `main.dart`, pola persis `'/u'` (baris 419-420):

```dart
'/hashtag' when settings.arguments is String =>
    HashtagScreen(name: settings.arguments as String),
```

(+ import `screens/hashtag_screen.dart`.)
- [ ] **Step 6: Wiring call sites** — helper navigasi kecil di `mention_text.dart` ATAU langsung di tiap call site:

```dart
void _openHashtag(BuildContext context, String name) {
  Navigator.of(context, rootNavigator: true)
      .pushNamed('/hashtag', arguments: name);
}
```

  - `feed_creator_overlay.dart`: `FeedExpandableCaption` tambah field `final void Function(String name)? onHashtagTap;`, teruskan ke `buildMentionSpans` (±baris 396-402). Kedua pemakainya (`feed_screen.dart:2224-2228`, `feed_video_post_view.dart:3671-3679`) isi `onHashtagTap: (name) => Navigator.of(context).pushNamed('/hashtag', arguments: name)`.
  - `feed_comment_sheet.dart` baris 2756 & 2934: tambah `onHashtagTap` pada `MentionText` — dari sheet, pakai `rootNavigator: true` supaya halaman push di atas sheet-context yang benar.
  - `member_post_detail_screen.dart` baris 2960: sama.
- [ ] **Step 7: Verifikasi** — `flutter analyze` pada file-file yang diubah bersih; `flutter test test/utils/mention_text_hashtag_test.dart test/services/feed_service_hashtag_test.dart` hijau; regresi widget caption existing (`flutter test test/features/feed/ test/screens/feed_photo_tag_pill_toggle_test.dart`) hijau.
- [ ] **Step 8: Commit** — `git commit -m "feat(app): route /hashtag + service + wiring onHashtagTap semua permukaan (Spec C)"`

---

### Task 11: Flutter — `HashtagScreen`

**Files:**
- Create: `flutter_app/lib/screens/hashtag_screen.dart`
- Test: `flutter_app/test/screens/hashtag_screen_test.dart` (BARU)

**Interfaces:**
- Consumes: `FeedService.fetchHashtagPosts` (Task 10 — utk test, screen menerima fetcher injectable `Future<HashtagPageResult> Function(String name, {String? cursor})` default ke feedService), `GalleryPostTile` (`flutter_app/lib/features/feed/widgets/gallery_post_tile.dart`), mixin `PostGalleryOpener` (`flutter_app/lib/features/feed/widgets/post_gallery_opener.dart` — pola pemakaian lihat `saved_posts_screen.dart`, TERMASUK `authorPerPost`).
- Produces: `HashtagScreen({required String name, fetcher})`.

**Requirement perilaku (dari spec §3 + §3b):**
- AppBar judul `#<name>` (lowercase kanonik) + `Semantics` header; subjudul "N postingan" dari `postCount` response (akurat).
- Grid reuse `GalleryPostTile` + buka post via `PostGalleryOpener` dengan **`authorPerPost => true`** (multi-author — pola `saved_posts_screen.dart`).
- State: loading awal (pola loading grid `saved_posts_screen.dart`); **error pakai error view + tombol coba-lagi standar app** (widget yang sama dipakai `saved_posts_screen.dart`/hasil unify PR #46 — BUKAN empty state); empty: teks persis `"Belum ada postingan dengan tag ini."`; paginasi cursor + indikator footer saat load-more.
- Tanpa animasi baru (kalau menambahkan, wajib `MotionPrefs.effective`).

- [ ] **Step 1: Failing test** (`flutter_app/test/screens/hashtag_screen_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/hashtag_screen.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';

FeedPost post(String id, String author) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'PHOTO_CAROUSEL',
      'thumbnailUrl': 'placeholder-$id',
      'author': {'id': 'u-$author', 'name': author},
      'createdAt': '2026-07-23T00:00:00.000Z',
    });

Future<void> pump(
  WidgetTester tester,
  Future<HashtagPageResult> Function(String, {String? cursor}) fetcher,
) async {
  await tester.pumpWidget(MaterialApp(
    home: HashtagScreen(name: 'kucing', fetcher: fetcher),
  ));
  await tester.pump(); // resolve future
  await tester.pump();
}

void main() {
  testWidgets('judul #kucing + hitungan + grid multi-author', (tester) async {
    await pump(
      tester,
      (name, {cursor}) async => HashtagPageResult(
        name: name,
        postCount: 2,
        posts: [post('p1', 'Budi'), post('p2', 'Sari')],
        nextCursor: null,
      ),
    );
    expect(find.text('#kucing'), findsOneWidget);
    expect(find.textContaining('2 postingan'), findsOneWidget);
  });

  testWidgets('kosong → copy empty state persis spec', (tester) async {
    await pump(
      tester,
      (name, {cursor}) async => HashtagPageResult(
          name: name, postCount: 0, posts: const [], nextCursor: null),
    );
    expect(find.text('Belum ada postingan dengan tag ini.'), findsOneWidget);
  });

  testWidgets('error → BUKAN empty state; ada tombol coba lagi yang retry',
      (tester) async {
    var calls = 0;
    await pump(tester, (name, {cursor}) async {
      calls++;
      if (calls == 1) throw Exception('network');
      return HashtagPageResult(
          name: name, postCount: 1, posts: [post('p1', 'Budi')], nextCursor: null);
    });
    expect(find.text('Belum ada postingan dengan tag ini.'), findsNothing);
    final retry = find.textContaining('oba lagi'); // "Coba lagi"/"Coba Lagi" sesuai widget standar
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('1 postingan'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — FAIL** (screen belum ada).
- [ ] **Step 3: Implementasi** — `HashtagScreen` StatefulWidget dengan mixin `PostGalleryOpener`; struktur mengikuti `saved_posts_screen.dart` (baca file itu SEBELUM menulis): state `_loading/_error/_result/_loadingMore`, `initState` → fetch, `_retry`, grid `GridView.builder`/`SliverGrid` ber-`GalleryPostTile` + `ScrollController` utk load-more saat mendekati bawah (pola file acuan), `authorPerPost => true`, error view standar app (widget sama dgn file acuan), empty copy persis. Subjudul via `Text('$postCount postingan')` di bawah judul (AppBar `centerTitle: true`, `title: Column` kecil ATAU title `#name` + subjudul di body atas — ikuti yang paling sederhana konsisten app).
- [ ] **Step 4: Run — PASS** + `flutter analyze lib/screens/hashtag_screen.dart` bersih.
- [ ] **Step 5: Commit** — `git commit -m "feat(app): HashtagScreen grid multi-author (Spec C)"`

---

### Task 12: Flutter — `HashtagPicker` + wiring editor caption + validasi limit

**Files:**
- Create: `flutter_app/lib/widgets/hashtag_picker.dart`
- Modify: `flutter_app/lib/screens/feed_caption_edit_screen.dart` (controller baris 42-50, panel baris 186-187, tombol Simpan)
- Modify: `flutter_app/lib/utils/mention_text.dart` (export `extractHashtags` Dart — lihat Step 3)
- Test: `flutter_app/test/widgets/hashtag_picker_test.dart` (BARU)

**Interfaces:**
- Consumes: `FeedService.searchHashtags` (Task 10; injectable `Future<List<HashtagSuggestion>> Function(String q)`), pola `MentionPickerController` (`flutter_app/lib/widgets/mention_picker.dart` — BACA file itu dulu: trigger detect walk-back, debounce, `insertMention` baris 221, haptic baris 224-225, panel `MentionSuggestionsPanel` baris 243).
- Produces: `HashtagPickerController({required TextEditingController textController, searchFn})` dengan getter `suggestions/isActive/isLoading`, method `insertHashtag(HashtagSuggestion s)`, `dispose()`; widget `HashtagSuggestionsPanel(controller: ...)`; fungsi Dart `extractHashtagsFromText(String text) → List<String>` di `mention_text.dart` (mirror `extractHashtags` server — REUSE `_kHashtagPattern` + filter yang SAMA dengan Task 9, jangan regex ketiga).

**Requirement perilaku:**
- Trigger: kursor setelah `#` + ≥1 char kata; char sebelum `#` wajib awal-teks/whitespace (mirror boundary — analog anti-email mention baris 136-141).
- Debounce **300ms** (Global Constraints — sadar beda dari mention 200ms).
- Pilih saran → ganti `#partial` jadi `#nama` + spasi, kursor setelah spasi; haptic `AppHaptics.tap()` + `HapticFeedback.selectionClick()` (paritas `insertMention`).
- Tanpa hasil → `isActive` false → panel tersembunyi (tanpa overlay kosong).
- Baris panel: ListTile ≥48dp, teks `#nama` + subtitle `N postingan`, `Semantics` label `"Tag nama, N postingan"`.
- Validasi Simpan: `extractHashtagsFromText(text).length > 5` → blokir simpan + pesan inline merah persis `"Maksimal 5 hashtag per postingan."` (pola pesan error yang sudah ada di layar itu; kalau belum ada, `Text` merah `NataloColors.danger` di bawah field).
- Animasi panel (jika ada) lewat `MotionPrefs.effective`.

- [ ] **Step 1: Failing test** (`flutter_app/test/widgets/hashtag_picker_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';
import 'package:natalo_petshop_flutter/utils/mention_text.dart';
import 'package:natalo_petshop_flutter/widgets/hashtag_picker.dart';

void main() {
  Future<List<HashtagSuggestion>> fakeSearch(String q) async =>
      [const HashtagSuggestion(name: 'kucing', postCount: 24)];

  test('trigger # + huruf → aktif; boundary harga#promo → TIDAK aktif',
      () async {
    final text = TextEditingController();
    final ctrl =
        HashtagPickerController(textController: text, searchFn: fakeSearch);
    text.value = const TextEditingValue(
      text: 'halo #ku',
      selection: TextSelection.collapsed(offset: 8),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(ctrl.isActive, isTrue);
    expect(ctrl.suggestions.single.name, 'kucing');

    text.value = const TextEditingValue(
      text: 'harga#pro',
      selection: TextSelection.collapsed(offset: 9),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(ctrl.isActive, isFalse);
    ctrl.dispose();
    text.dispose();
  });

  test('insertHashtag: ganti #partial jadi #nama + spasi, kursor di akhir',
      () async {
    final text = TextEditingController();
    final ctrl =
        HashtagPickerController(textController: text, searchFn: fakeSearch);
    text.value = const TextEditingValue(
      text: 'halo #ku',
      selection: TextSelection.collapsed(offset: 8),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    ctrl.insertHashtag(const HashtagSuggestion(name: 'kucing', postCount: 24));
    expect(text.text, 'halo #kucing ');
    expect(text.selection.baseOffset, 'halo #kucing '.length);
    ctrl.dispose();
    text.dispose();
  });

  test('extractHashtagsFromText: mirror server (dedup, boundary, 2-50)', () {
    expect(extractHashtagsFromText('#Kucing #kucing #a harga#promo #ab_2'),
        ['kucing', 'ab_2']);
  });
}
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implementasi**:
  1. `mention_text.dart`: tambah `List<String> extractHashtagsFromText(String text)` — loop `_kHashtagPattern.allMatches`, lowercase, filter 2-50, dedup urutan kemunculan (kode cermin `extractHashtags` server; REUSE konstanta Task 9).
  2. `hashtag_picker.dart`: salin struktur `mention_picker.dart` lalu sesuaikan — `HashtagPickerController extends ChangeNotifier` (listener textController; `_detect()` walk-back dari kursor ke `#`, cek char sebelum `#` whitespace/awal, partial = potongan setelah `#` di-lowercase; kosong → inactive), debounce `Timer(const Duration(milliseconds: 300))` → `searchFn(partial)`; hasil kosong → `isActive=false`. `insertHashtag`: `text.replaceRange(hashPos, cursor, '#${s.name} ')`, set selection, `AppHaptics.tap(); HapticFeedback.selectionClick();`, deactivate. `HashtagSuggestionsPanel`: pola `MentionSuggestionsPanel` (auto-hide `!isActive`), ListTile per saran dengan `Semantics(label: 'Tag ${s.name}, ${s.postCount} postingan', button: true, child: ...)`, subtitle `'${s.postCount} postingan'`.
  3. `feed_caption_edit_screen.dart`: `late final HashtagPickerController _hashtagCtrl = HashtagPickerController(textController: _controller);` (dispose ikut), render `HashtagSuggestionsPanel(controller: _hashtagCtrl)` tepat di sebelah `MentionSuggestionsPanel` (baris 186-187 — tumpuk Column; hanya satu yang aktif pada satu waktu karena trigger char beda). Validasi di handler tombol Simpan: 

```dart
if (extractHashtagsFromText(_controller.text).length > 5) {
  setState(() => _hashtagLimitError = 'Maksimal 5 hashtag per postingan.');
  return;
}
```

  + `Text(_hashtagLimitError!, style: const TextStyle(color: NataloColors.danger, fontSize: 13))` di bawah field saat non-null; reset error saat teks berubah.
- [ ] **Step 4: Run — PASS**: `flutter test test/widgets/hashtag_picker_test.dart` + regresi `flutter test test/` subset caption/composer existing; `flutter analyze` file yang diubah bersih.
- [ ] **Step 5: Commit** — `git commit -m "feat(app): HashtagPicker + validasi limit 5 di editor caption (Spec C)"`

---

### Task 13: Regresi penuh

- [ ] **Step 1: Backend** — `npx tsc --noEmit` bersih; `npx tsx --test tests/*.test.ts` → baseline yang sama dengan sebelum Spec C (6 file vitest legacy pre-existing fail = known, BUKAN regresi).
- [ ] **Step 2: Flutter** — `flutter analyze` (bandingkan jumlah issue dengan main sebelum branch — tidak boleh ada issue baru dari file Spec C); `flutter test` penuh → hanya failure pre-existing yang sama (1 known).
- [ ] **Step 3: Commit sisa** bila ada, siapkan ringkasan utk PR (jangan buka PR tanpa instruksi user).

---

## Self-Review (sudah dijalankan)

- **Spec coverage:** §1 data/API → Task 1-8; §2 composer → Task 12; §3 render+halaman → Task 9-11; §3b UI premium → tersebar sebagai requirement Task 9/11/12 + Global Constraints; §4 testing → test per task + Task 13. Admin route = route sama (fakta terverifikasi) — tercakup Task 4-5. Soft/hard delete → Task 6 + Global Constraints. Parser bersama `MentionText` → fakta terverifikasi: `MentionText` MEMANGGIL `buildMentionSpans`, jadi Task 9 otomatis mengcover semua permukaan; call sites tinggal meneruskan callback (Task 10).
- **Placeholder scan:** nama `FEED_POST_SELECT`/`serializeFeedPost` (Task 7) dan signature `apiClient.getJson` (Task 10) sengaja dirujuk ke file konkret yang WAJIB dibaca implementer — bukan TBD, melainkan "pakai nama persis di file X" dengan file dan baris disebut. Selain itu tidak ada TBD/TODO.
- **Type consistency:** `HashtagSuggestion{name,postCount}` konsisten Task 8↔10↔12; `HashtagPageResult` Task 7 response ↔ Task 10 fromJson ↔ Task 11 fetcher; `extractHashtags` (TS) ↔ `extractHashtagsFromText` (Dart) dua nama sadar-beda-bahasa dengan aturan identik (kasus test mirror sama persis); `onHashtagTap(String name-lowercase)` konsisten Task 9↔10.
- **Urutan eksekusi:** 1→2→3→4→5→6→7→8→9→**11→10**→12→13 (catatan di Task 10).
