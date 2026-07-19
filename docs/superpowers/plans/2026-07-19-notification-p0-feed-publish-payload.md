# P0 — Feed-Publish Notification: set feedPostId + thumbnailUrl — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Notif "Feed kamu sudah tayang/dibagikan" menyimpan `feedPostId` + `thumbnailUrl` di baris `Announcement`, supaya tap → buka post itu (bukan `/feed` generik) dan thumbnail post tampil di app redesign.

**Architecture:** Backend Next.js. Ekstrak pembentukan `data` untuk `announcement.create` di `sendFeedPublishPush` ke fungsi murni yang bisa diuji (repo menguji fungsi murni, tidak mem-mock prisma), lalu tambah `thumbnailUrl` ke `select` FeedPost + isi `feedPostId`/`thumbnailUrl`.

**Tech Stack:** TypeScript, Node built-in test runner (`tsx --test tests/*.test.ts`), Prisma.

## Global Constraints

- Hanya sentuh `lib/feed/publish-push.ts` + test baru. Jangan ubah logika guard/klaim atomik/daily-cap/push dispatch.
- `type` tetap `"announcement"`, `ctaLabel` tetap `"Lihat Post"` (jangan ubah — di luar scope).
- Backend tidak terpengaruh redesign #189; boleh dikerjakan di branch `claude/notification-routing-audit` (sudah off `origin/main`).
- Jalankan test dari repo root `C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/flutter-feed-ui-design-f74eb8`.

---

### Task 1: Ekstrak builder murni `buildFeedPublishAnnouncementData` + set feedPostId/thumbnailUrl

**Files:**
- Modify: `lib/feed/publish-push.ts`
- Test: `tests/feed-publish-push.test.ts` (tambah kasus)

**Interfaces:**
- Produces: fungsi murni `export function buildFeedPublishAnnouncementData(input: { post: { id: string; thumbnailUrl: string | null }; title: string; body: string; url: string; segment: PushSegment }): Prisma.AnnouncementCreateInput`-shaped object — mengembalikan objek `data` yang identik dengan sebelumnya PLUS `feedPostId: input.post.id` dan `thumbnailUrl: input.post.thumbnailUrl`.

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan di `tests/feed-publish-push.test.ts` (import builder baru di atas):

```ts
import { buildFeedPublishAnnouncementData } from "../lib/feed/publish-push";

test("buildFeedPublishAnnouncementData: menyertakan feedPostId + thumbnailUrl", () => {
  const data = buildFeedPublishAnnouncementData({
    post: { id: "post-1", thumbnailUrl: "https://cdn/thumb.jpg" },
    title: "Judul",
    body: "Isi",
    url: "/feed/post-1",
    segment: "members",
  });
  assert.equal(data.feedPostId, "post-1");
  assert.equal(data.thumbnailUrl, "https://cdn/thumb.jpg");
  assert.equal(data.type, "announcement");
  assert.equal(data.ctaLabel, "Lihat Post");
  assert.equal(data.url, "/feed/post-1");
});

test("buildFeedPublishAnnouncementData: thumbnailUrl null tetap valid", () => {
  const data = buildFeedPublishAnnouncementData({
    post: { id: "p2", thumbnailUrl: null },
    title: "J",
    body: "B",
    url: "/feed/p2",
    segment: "members",
  });
  assert.equal(data.feedPostId, "p2");
  assert.equal(data.thumbnailUrl, null);
});
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx tsx --test tests/feed-publish-push.test.ts`
Expected: FAIL — `buildFeedPublishAnnouncementData` belum diekspор.

- [ ] **Step 3: Implementasi builder + wiring**

Di `lib/feed/publish-push.ts`:

1. Tambah `thumbnailUrl: true` ke `select` di `prisma.feedPost.findUnique` (blok baris ~87-98).

2. Tambah fungsi murni (dekat `sendFeedPublishPush`, level modul):

```ts
export function buildFeedPublishAnnouncementData(input: {
  post: { id: string; thumbnailUrl: string | null };
  title: string;
  body: string;
  url: string;
  segment: PushSegment;
}) {
  return {
    title: input.title,
    body: input.body,
    url: input.url,
    segment: input.segment,
    type: "announcement" as const,
    feedPostId: input.post.id,
    thumbnailUrl: input.post.thumbnailUrl,
    ctaLabel: "Lihat Post",
    publishedAt: new Date(),
    status: "PUBLISHED" as const,
  };
}
```

3. Ganti blok `await prisma.announcement.create({ data: { ... } })` menjadi:

```ts
    await prisma.announcement.create({
      data: buildFeedPublishAnnouncementData({
        post: { id: post.id, thumbnailUrl: post.thumbnailUrl },
        title,
        body,
        url,
        segment,
      }),
    });
```

(`title`, `body`, `url` sudah ada dari `buildFeedPushPayload`; `segment` sudah dihitung.)

- [ ] **Step 4: Jalankan test + typecheck**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx tsx --test tests/feed-publish-push.test.ts && npx tsc --noEmit 2>&1 | grep -i "publish-push" || echo "no publish-push type errors"`
Expected: semua test PASS; tidak ada type error di publish-push.

- [ ] **Step 5: Commit**

```bash
git add lib/feed/publish-push.ts tests/feed-publish-push.test.ts
git commit -m "feat(notifikasi): feed-publish set feedPostId + thumbnailUrl di Announcement"
```

---

## Verifikasi manual (staging — di luar test)

Publikasikan satu post baru → cek baris `Announcement` (via admin/DB) punya `feedPostId` + `thumbnailUrl` terisi → di app (build redesign) tap notif "sudah tayang" membuka post itu + thumbnail tampil. Cek PHOTO_CAROUSEL admin punya `thumbnailUrl` (kalau null, thumbnail memang tak ada — routing tetap benar).

## Catatan lanjutan (bukan bagian P0)

Setelah P0 merge & deploy: lanjut P1 (client — routing pesanan + avatar follow), lalu P2 (avatar aktor + migration), P3 (thumbnail produk). Lihat spec `2026-07-19-notification-routing-and-actor-avatar-design.md`.
