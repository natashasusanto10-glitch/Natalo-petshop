# Notifikasi — Aksi Inline "♡ + Balas" pada Notif Komentar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tambah baris aksi ♡ (like komentar inline) + "Balas" (composer ringan overlay ala IG) di bawah notifikasi komentar, tanpa pindah layar.

**Architecture:** Backend menambah kolom `Announcement.commentId` supaya app tahu komentar mana yang memicu notif, meng-expose-nya lewat mapper `/api/notifications/me`, dan menyediakan endpoint baru `GET /api/feed/comments/{id}` (brand-safe, reuse mapper existing lewat fungsi query baru) agar composer bisa ambil username author + validasi komentar/post masih ada. Client menambah gate + widget aksi di `NotificationRow` (♡ optimistik idempotent via `setCommentLiked`, pill "Balas") dan widget composer baru (`NotificationReplyComposer`) yang dibuka sebagai bottom sheet keyboard-safe dan kirim via `postComment(parentCommentId)`.

**Tech Stack:** Next.js API routes + Prisma (Postgres/Neon), TypeScript unit test via `tsx --test` (node:test), Flutter/Dart client + `flutter_test`.

## Global Constraints

- **Brand-safety (hard rule):** identitas akun admin/official TIDAK boleh bocor nama/foto asli pemilik. Nama brand persis string `"Natalo Petshop Official"`. Semua serialisasi author WAJIB lewat mapper brand-safe existing (`mapFeedComment`/`brandDisplayName`/`brandPhotoUrl`) — jangan tulis mapping author baru.
- **Working dir isolasi:** kerja HANYA di worktree `C:\Users\USER\Desktop\natalopetshopflutter\.claude\worktrees\notif-inline-reply` (branch `claude/notif-inline-reply-like`). JANGAN pernah commit di checkout utama `C:\Users\USER\Desktop\natalopetshopflutter` (dipakai sesi lain). Tiap perintah `cd` ke worktree; verifikasi `git branch --show-current` = `claude/notif-inline-reply-like` sebelum commit.
- **Migration idempotent:** SQL tulis-tangan pakai `ADD COLUMN IF NOT EXISTS`; timestamp folder > migration terbaru (`20260719150000_add_announcement_actor_avatar_urls`). Migration TIDAK di-deploy di plan ini (deploy = langkah terpisah, gated user).
- **Idempotent like:** like komentar pakai `setCommentLiked(id, liked:)` (PUT liked / DELETE unliked) — aman untuk optimistik + retry, jangan pakai toggle legacy.
- **Font weight:** teks baru ikut skala Natalo — body `w400`, penekanan/pill `w600`. Jangan `w700+`.
- **Warna:** pill CTA pakai `NataloColors.primarySoft` (bg) + `NataloColors.primary` (teks); hati aktif merah `Color(0xFFE11D48)` (sama dengan lencana like existing). Radius pill 999, padding pill `h14 v6`, fontSize 12 `w600`.
- **`if (!mounted) return;` setelah SETIAP await** di widget State; busy-guard di aksi async (abaikan tap saat request in-flight).
- **Gate aksi komentar:** render HANYA bila `eventType == 'feed_new_comment'` DAN `commentId` non-empty DAN `feedPostId` non-empty. Selain itu → perilaku lama (pill `ctaLabel`).
- **Testabilitas seam:** widget baru terima param opsional (typedef fetcher/setter/poster) default ke global `feedService`; query backend baru terima `db = prisma` (pola `listFeedComments`).

---

## File Structure

**Backend (dibuat/diubah):**
- `prisma/migrations/20260720000000_add_announcement_comment_id/migration.sql` (create) — kolom `commentId`.
- `prisma/schema.prisma` (modify) — field `commentId String?` di model `Announcement`.
- `lib/feed/notification-center.ts` (modify) — param `commentId?` di `createFeedNotification` + tulis ke `announcement.create`.
- `lib/feed/activity-notifications.ts` (modify) — 3 builder isi `commentId`.
- `app/api/notifications/me/route.ts` (modify) — mapper expose `commentId`.
- `lib/feed/queries.ts` (modify) — fungsi baru exported `getFeedCommentDetail` (reuse `mapFeedComment` privat).
- `app/api/feed/comments/[id]/route.ts` (modify) — tambah handler `GET`.
- `tests/feed-comment-detail.test.ts` (create) — unit test `getFeedCommentDetail`.

**Client Flutter (dibuat/diubah):**
- `flutter_app/lib/models/app_notification.dart` (modify) — field `commentId`.
- `flutter_app/lib/services/feed_service.dart` (modify) — `fetchCommentById` + exception typed.
- `flutter_app/lib/widgets/notification_reply_composer.dart` (create) — composer + helper `showNotificationReplyComposer` + typedef `CommentReplyPoster`.
- `flutter_app/lib/screens/notifications_screen.dart` (modify) — gate + `_NotificationCommentActions` + typedef seam di `NotificationRow`.
- `flutter_app/test/app_notification_comment_id_test.dart` (create) — parse/copyWith.
- `flutter_app/test/notification_reply_composer_test.dart` (create) — composer isolasi.
- `flutter_app/test/notifications_redesign_widget_test.dart` (modify) — group aksi komentar.

**Catatan deviasi dari spec:** spec D2 menyebut "export `mapFeedComment`". Rencana ini malah menambah fungsi baru `getFeedCommentDetail` di `queries.ts` yang me-reuse `mapFeedComment` privat di file yang sama — lebih terkapsul (tidak membocorkan 3 internal ke route) sekaligus tetap memenuhi syarat "reuse mapper brand-safe existing". Semua logika brand-safe tetap di `queries.ts`.

---

### Task 1: Migration + schema kolom `Announcement.commentId`

**Files:**
- Create: `prisma/migrations/20260720000000_add_announcement_comment_id/migration.sql`
- Modify: `prisma/schema.prisma:1160` (model `Announcement`, setelah `feedStatus String?`)

**Interfaces:**
- Produces: kolom `Announcement.commentId` (nullable TEXT) + field Prisma `commentId String?` — dipakai Task 2 (`announcement.create`) & Task 3 (mapper).

- [ ] **Step 1: Buat file migration**

Create `prisma/migrations/20260720000000_add_announcement_comment_id/migration.sql`:

```sql
ALTER TABLE "Announcement"
ADD COLUMN IF NOT EXISTS "commentId" TEXT;
```

- [ ] **Step 2: Tambah field ke schema Prisma**

Di `prisma/schema.prisma`, model `Announcement`, sisipkan tepat setelah baris `feedStatus       String?` (baris ~1160):

```prisma
  feedStatus   String?
  /// Komentar pemicu notif (feed_new_comment / reply / comment-like).
  /// Dipakai app untuk aksi inline ♡/Balas. Null utk notif non-komentar
  /// & notif komentar lama (pra-migration).
  commentId    String?
```

- [ ] **Step 3: Validasi schema + regenerasi client**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && npx prisma validate && npx prisma generate`
Expected: `The schema at prisma/schema.prisma is valid` lalu `Generated Prisma Client`. (Regenerasi WAJIB supaya Task 2 typecheck mengenal `commentId`.)

- [ ] **Step 4: Commit**

```bash
cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && git add prisma/migrations/20260720000000_add_announcement_comment_id/migration.sql prisma/schema.prisma && git commit -m "feat(notif): kolom Announcement.commentId (migration + schema)"
```

---

### Task 2: Builder isi `commentId` + `createFeedNotification` teruskan ke DB

**Files:**
- Modify: `lib/feed/notification-center.ts:103-118` (params `createFeedNotification`) + `:177-195` (`announcement.create` data)
- Modify: `lib/feed/activity-notifications.ts` — `sendCommentNotification` (:85), `sendReplyNotification` (:149), `sendCommentLikeNotification` (:510)

**Interfaces:**
- Consumes: field Prisma `Announcement.commentId` (Task 1).
- Produces: notif `feed_new_comment` (komentar & reply) + `feed_new_like` (comment-like) kini menyimpan `commentId` di baris Announcement.

- [ ] **Step 1: Tambah param `commentId?` ke `createFeedNotification`**

Di `lib/feed/notification-center.ts`, dalam objek params `createFeedNotification` (setelah `tag?: string | null;`, baris ~113):

```ts
    tag?: string | null;
    commentId?: string | null;
    data?: Record<string, string | null | undefined>;
```

- [ ] **Step 2: Tulis `commentId` ke `announcement.create`**

Di `lib/feed/notification-center.ts`, dalam `data:` objek `prisma.announcement.create` (setelah `feedStatus: params.status ?? null,`, baris ~188):

```ts
          feedStatus: params.status ?? null,
          commentId: params.commentId ?? null,
          ctaLabel: params.ctaLabel ?? "Lihat Postingan",
```

- [ ] **Step 3: `sendCommentNotification` teruskan commentId**

Di `lib/feed/activity-notifications.ts`, dalam call `createFeedNotification` di `sendCommentNotification` (setelah `tag: \`feed-comment-${post.id}\`,`, baris ~94):

```ts
      tag: `feed-comment-${post.id}`,
      commentId: params.commentId,
      data: { comment_id: params.commentId },
```

- [ ] **Step 4: `sendReplyNotification` teruskan `replyCommentId`**

Di `lib/feed/activity-notifications.ts`, dalam call `createFeedNotification` di `sendReplyNotification` (setelah `tag: \`feed-reply-${params.parentCommentId}\`,`, baris ~158). CATATAN: signature `sendReplyNotification` TIDAK punya `params.commentId` — pakai `params.replyCommentId` (balasan yang baru dibuat = target reply yang benar; menulis `params.commentId` di sini = error kompilasi):

```ts
      tag: `feed-reply-${params.parentCommentId}`,
      commentId: params.replyCommentId,
      data: {
        parent_comment_id: params.parentCommentId,
        reply_comment_id: params.replyCommentId,
      },
```

- [ ] **Step 5: `sendCommentLikeNotification` teruskan commentId (create path)**

Di `lib/feed/activity-notifications.ts`, dalam call `createFeedNotification` di `sendCommentLikeNotification` (setelah `tag: \`feed-comment-like-${params.commentId}\`,`, baris ~519). Cabang agregat `announcement.update` (baris ~494-506) TIDAK disentuh — nilai commentId dari create tetap benar untuk komentar yang sama:

```ts
      tag: `feed-comment-like-${params.commentId}`,
      commentId: params.commentId,
      data: {
        comment_id: params.commentId,
        like_count: String(params.likeCount),
      },
```

- [ ] **Step 6: Typecheck**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && npx tsc --noEmit 2>&1 | grep -E "notification-center|activity-notifications" | head`
Expected: tidak ada baris error dari kedua file (output kosong). (Jika `commentId` tak dikenal Prisma type → Task 1 `prisma generate` belum jalan.)

- [ ] **Step 7: Commit**

```bash
cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && git add lib/feed/notification-center.ts lib/feed/activity-notifications.ts && git commit -m "feat(notif): builder komentar/reply/comment-like isi commentId"
```

---

### Task 3: Mapper `/api/notifications/me` expose `commentId`

**Files:**
- Modify: `app/api/notifications/me/route.ts:39-56` (param type `mapAnnouncement`) + `:59-79` (return object)

**Interfaces:**
- Consumes: kolom `Announcement.commentId` (Task 1). `findMany` tanpa `select` → kolom auto-tersedia; hanya tipe param + return yang diubah.
- Produces: field `commentId` di JSON item `/api/notifications/me` — dipakai client `AppNotification` (Task 6).

- [ ] **Step 1: Tambah `commentId` ke tipe param `mapAnnouncement`**

Di `app/api/notifications/me/route.ts`, dalam tipe inline param `mapAnnouncement` (setelah `feedStatus: string | null;`, baris ~53):

```ts
  feedStatus: string | null;
  commentId: string | null;
  ctaLabel: string | null;
```

- [ ] **Step 2: Tambah `commentId` ke return `mapAnnouncement`**

Di return object (setelah `status: a.feedStatus,`, baris ~75):

```ts
    status: a.feedStatus,
    commentId: a.commentId,
    ctaLabel: a.ctaLabel,
```

- [ ] **Step 3: Typecheck**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && npx tsc --noEmit 2>&1 | grep "notifications/me" | head`
Expected: output kosong (tak ada error).

- [ ] **Step 4: Commit**

```bash
cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && git add app/api/notifications/me/route.ts && git commit -m "feat(notif): expose commentId di mapper notifications/me"
```

---

### Task 4: Query `getFeedCommentDetail` (brand-safe, reuse mapper) + unit test

**Files:**
- Modify: `lib/feed/queries.ts` (tambah fungsi exported setelah `listFeedComments`, ~baris 840+)
- Test: `tests/feed-comment-detail.test.ts` (create)

**Interfaces:**
- Consumes: privat `mapFeedComment`, `resolveOfficialMentionHandles`, `FEED_COMMENT_THREAD_INCLUDE` (semua di file yang sama); tipe `FeedCommentItem` (sudah di-import dari `./types`).
- Produces: `getFeedCommentDetail({ commentId, viewerUserId?, db? }): Promise<FeedCommentDetailResult>` di mana `FeedCommentDetailResult = { status: "not-found" } | { status: "post-gone" } | { status: "ok"; comment: FeedCommentItem }`. Dipakai Task 5 (route GET).

- [ ] **Step 1: Tulis test dulu (gagal)**

Create `tests/feed-comment-detail.test.ts`:

```ts
import assert from "node:assert/strict";
import test from "node:test";
import { getFeedCommentDetail } from "@/lib/feed/queries";

function baseComment(overrides: Record<string, unknown> = {}) {
  return {
    id: "c1",
    postId: "p1",
    parentCommentId: null,
    content: "halo",
    deletedAt: null,
    isAdminOfficial: false,
    isHidden: false,
    likeCount: 2,
    createdAt: new Date("2026-07-20T00:00:00Z"),
    author: {
      id: "u1",
      name: "Asiong",
      username: "asiong",
      role: "CUSTOMER",
      profilePhotoUrl: "https://cdn/asiong.jpg",
    },
    replies: [],
    post: { status: "ACTIVE", deletedAt: null },
    ...overrides,
  };
}

function makeDb(comment: unknown, likes: Array<{ commentId: string }> = []) {
  return {
    feedComment: { async findUnique() { return comment; } },
    feedCommentLike: { async findMany() { return likes; } },
    user: { async findMany() { return []; } },
  } as never;
}

test("ok: komentar customer + viewerLiked dari likes", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    viewerUserId: "viewer",
    db: makeDb(baseComment(), [{ commentId: "c1" }]),
  });
  assert.equal(res.status, "ok");
  if (res.status !== "ok") return;
  assert.equal(res.comment.id, "c1");
  assert.equal(res.comment.postId, "p1");
  assert.equal(res.comment.author.username, "asiong");
  assert.equal(res.comment.author.name, "Asiong");
  assert.equal(res.comment.viewerLiked, true);
});

test("ok: viewerLiked false saat anonim (tanpa viewerUserId)", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(baseComment()),
  });
  assert.equal(res.status, "ok");
  if (res.status !== "ok") return;
  assert.equal(res.comment.viewerLiked, false);
});

test("brand-safe: author admin → nama brand + foto null", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(
      baseComment({
        author: {
          id: "admin1",
          name: "Private Owner",
          username: "natalopetshop",
          role: "ADMIN",
          profilePhotoUrl: "https://cdn/private.jpg",
        },
      }),
    ),
  });
  assert.equal(res.status, "ok");
  if (res.status !== "ok") return;
  assert.equal(res.comment.author.name, "Natalo Petshop Official");
  assert.equal(res.comment.author.profilePhotoUrl, null);
});

test("not-found: komentar tidak ada", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(null),
  });
  assert.equal(res.status, "not-found");
});

test("not-found: komentar soft-deleted", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(baseComment({ deletedAt: new Date() })),
  });
  assert.equal(res.status, "not-found");
});

test("not-found: komentar hidden (moderasi)", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(baseComment({ isHidden: true })),
  });
  assert.equal(res.status, "not-found");
});

test("post-gone: post induk deletedAt", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(baseComment({ post: { status: "ACTIVE", deletedAt: new Date() } })),
  });
  assert.equal(res.status, "post-gone");
});

test("post-gone: post status bukan ACTIVE", async () => {
  const res = await getFeedCommentDetail({
    commentId: "c1",
    db: makeDb(baseComment({ post: { status: "PENDING_REVIEW", deletedAt: null } })),
  });
  assert.equal(res.status, "post-gone");
});
```

- [ ] **Step 2: Jalankan test → gagal**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && npx tsx --test tests/feed-comment-detail.test.ts 2>&1 | tail -20`
Expected: FAIL — `getFeedCommentDetail` belum di-export (error import / not a function).

- [ ] **Step 3: Implement `getFeedCommentDetail`**

Di `lib/feed/queries.ts`, tambahkan tepat SETELAH akhir fungsi `listFeedComments` (cari `}` penutupnya, ~baris 840). Fungsi ini me-reuse `mapFeedComment`, `resolveOfficialMentionHandles`, dan `FEED_COMMENT_THREAD_INCLUDE` yang semuanya privat di file ini:

```ts
export type FeedCommentDetailResult =
  | { status: "not-found" }
  | { status: "post-gone" }
  | { status: "ok"; comment: FeedCommentItem };

/**
 * Ambil satu komentar (utk composer balas dari notifikasi). Brand-safe via
 * mapFeedComment (admin → identitas brand, foto null). Bedakan "komentar
 * hilang" vs "post induk hilang" supaya client bisa pesan yang tepat —
 * comment routes tak cascade-delete komentar saat post dihapus, jadi guard
 * post WAJIB (pola sama seperti like-route).
 */
export async function getFeedCommentDetail({
  commentId,
  viewerUserId,
  db = prisma,
}: {
  commentId: string;
  viewerUserId?: string | null;
  db?: Pick<
    Prisma.TransactionClient,
    "feedComment" | "feedCommentLike" | "user"
  >;
}): Promise<FeedCommentDetailResult> {
  const comment = await db.feedComment.findUnique({
    where: { id: commentId },
    include: {
      ...FEED_COMMENT_THREAD_INCLUDE,
      post: { select: { status: true, deletedAt: true } },
    },
  });
  if (!comment || comment.deletedAt !== null || comment.isHidden) {
    return { status: "not-found" };
  }
  if (
    !comment.post ||
    comment.post.status !== "ACTIVE" ||
    comment.post.deletedAt !== null
  ) {
    return { status: "post-gone" };
  }

  let viewerLikedIds = new Set<string>();
  if (viewerUserId) {
    const commentIds = [comment.id, ...comment.replies.map((r) => r.id)];
    const likes = await db.feedCommentLike.findMany({
      where: { userId: viewerUserId, commentId: { in: commentIds } },
      select: { commentId: true },
    });
    viewerLikedIds = new Set(likes.map((l) => l.commentId));
  }

  const officialHandles = await resolveOfficialMentionHandles(
    [comment.content, ...comment.replies.map((r) => r.content)],
    db,
  );

  return {
    status: "ok",
    comment: mapFeedComment(comment, viewerLikedIds, officialHandles),
  };
}
```

- [ ] **Step 4: Jalankan test → lulus**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && npx tsx --test tests/feed-comment-detail.test.ts 2>&1 | tail -6`
Expected: `# pass 8` `# fail 0`.

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && git add lib/feed/queries.ts tests/feed-comment-detail.test.ts && git commit -m "feat(feed): getFeedCommentDetail brand-safe single-comment query + test"
```

---

### Task 5: Endpoint `GET /api/feed/comments/{id}`

**Files:**
- Modify: `app/api/feed/comments/[id]/route.ts` (tambah handler `GET` + import)

**Interfaces:**
- Consumes: `getFeedCommentDetail` (Task 4), `getSession` (existing import).
- Produces: `GET /api/feed/comments/{id}` → 200 `{ ok, comment, postId }` | 404 `{ error, reason: "comment_deleted" | "post_deleted" }` | 400. Dipakai Task 7 (`fetchCommentById`).

- [ ] **Step 1: Tambah import `getFeedCommentDetail`**

Di `app/api/feed/comments/[id]/route.ts`, tambahkan import (setelah import `comment-sync` di baris ~15):

```ts
import { getFeedCommentDetail } from "@/lib/feed/queries";
```

- [ ] **Step 2: Tambah handler `GET`**

Di `app/api/feed/comments/[id]/route.ts`, tambahkan fungsi baru SEBELUM `export async function DELETE` (baris ~17). GET publik (read-only, tanpa CSRF); pakai session bila ada utk `viewerLiked`:

```ts
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: commentId } = await params;
  if (!commentId) {
    return NextResponse.json({ error: "Comment ID kosong." }, { status: 400 });
  }

  const session = await getSession();
  const result = await getFeedCommentDetail({
    commentId,
    viewerUserId: session?.sub ?? null,
  });

  if (result.status === "not-found") {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan", reason: "comment_deleted" },
      { status: 404 }
    );
  }
  if (result.status === "post-gone") {
    return NextResponse.json(
      { error: "Postingan sudah dihapus", reason: "post_deleted" },
      { status: 404 }
    );
  }
  return NextResponse.json({
    ok: true,
    comment: result.comment,
    postId: result.comment.postId,
  });
}
```

- [ ] **Step 3: Typecheck**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && npx tsc --noEmit 2>&1 | grep "feed/comments" | head`
Expected: output kosong.

- [ ] **Step 4: Jalankan test backend penuh (tak ada regresi)**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && npm test 2>&1 | tail -8`
Expected: semua test pass (termasuk `feed-comment-detail`).

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && git add app/api/feed/comments/\[id\]/route.ts && git commit -m "feat(feed): GET /api/feed/comments/[id] single-comment (brand-safe, guard post)"
```

---

### Task 6: Client model `AppNotification.commentId`

**Files:**
- Modify: `flutter_app/lib/models/app_notification.dart`
- Test: `flutter_app/test/app_notification_comment_id_test.dart` (create)

**Interfaces:**
- Consumes: JSON field `commentId` dari `/api/notifications/me` (Task 3).
- Produces: `AppNotification.commentId` (`String?`) — dipakai Task 9 (gate aksi).

- [ ] **Step 1: Tulis test dulu (gagal)**

Create `flutter_app/test/app_notification_comment_id_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/app_notification.dart';

void main() {
  test('parse commentId (camelCase)', () {
    final n = AppNotification.fromApiJson({
      'id': 'n1', 'title': 'x', 'body': 'y', 'type': 'feed',
      'eventType': 'feed_new_comment', 'feedPostId': 'p1',
      'commentId': 'c123',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    expect(n.commentId, 'c123');
  });

  test('parse comment_id (snake_case fallback)', () {
    final n = AppNotification.fromApiJson({
      'id': 'n1', 'title': 'x', 'body': 'y', 'type': 'feed',
      'comment_id': 'c456',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    expect(n.commentId, 'c456');
  });

  test('commentId null saat absen', () {
    final n = AppNotification.fromApiJson({
      'id': 'n1', 'title': 'x', 'body': 'y', 'type': 'feed',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    expect(n.commentId, isNull);
  });

  test('copyWith(read:) mempertahankan commentId', () {
    final n = AppNotification.fromApiJson({
      'id': 'n1', 'title': 'x', 'body': 'y', 'type': 'feed',
      'commentId': 'c789',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    expect(n.copyWith(read: true).commentId, 'c789');
  });
}
```

- [ ] **Step 2: Jalankan test → gagal**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply/flutter_app" && flutter test test/app_notification_comment_id_test.dart 2>&1 | tail -12`
Expected: FAIL — `commentId` getter belum ada (compile error).

- [ ] **Step 3: Tambah field + constructor + parse + copyWith**

Di `flutter_app/lib/models/app_notification.dart`:

(a) Field — setelah `final String? feedPostId;` (baris ~11):
```dart
  final String? feedPostId;
  final String? commentId;
```

(b) Constructor — setelah `this.feedPostId,` (baris ~35):
```dart
    this.feedPostId,
    this.commentId,
```

(c) Parse dalam `fromApiJson` — setelah baris `feedPostId: (json['feedPostId'] ?? json['videoId'])?.toString(),` (~baris 67):
```dart
      feedPostId: (json['feedPostId'] ?? json['videoId'])?.toString(),
      commentId: (json['commentId'] ?? json['comment_id'])?.toString(),
```

(d) `copyWith` — setelah `feedPostId: feedPostId,` (~baris 107) supaya nilai tidak hilang saat mark-read:
```dart
      feedPostId: feedPostId,
      commentId: commentId,
```

- [ ] **Step 4: Jalankan test → lulus**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply/flutter_app" && flutter test test/app_notification_comment_id_test.dart 2>&1 | tail -6`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && git add flutter_app/lib/models/app_notification.dart flutter_app/test/app_notification_comment_id_test.dart && git commit -m "feat(notif): AppNotification.commentId (parse dual-key + copyWith)"
```

---

### Task 7: Client service `fetchCommentById` + exception typed

**Files:**
- Modify: `flutter_app/lib/services/feed_service.dart` (typedef/enum/exception top-level + method di class `FeedService`)

**Interfaces:**
- Consumes: endpoint `GET /api/feed/comments/{id}` (Task 5); `FeedComment.fromApiJson` (existing).
- Produces: `feedService.fetchCommentById(String commentId): Future<FeedComment>` (throw `FeedCommentUnavailableException(reason)` saat 404); enum `FeedCommentUnavailableReason { commentDeleted, postDeleted }`. Dipakai Task 9 (default fetcher) & Task 8/9 (composer flow).

Catatan: method HTTP ini tak di-unit-test langsung (feed_service pakai `http` global tanpa seam — konsisten dgn method HTTP lain di file yang juga tak di-test). Diverifikasi lewat typecheck/analyze; alur konsumennya di-test dengan fake di Task 9. Wajib disebut di laporan.

- [ ] **Step 1: Tambah enum + exception top-level**

Di `flutter_app/lib/services/feed_service.dart`, setelah `FeedDesiredStateVerb feedDesiredStateVerb(...)` (baris ~27, sebelum `Map<String, dynamic> buildFeedCommentsQuery`):

```dart
/// Alasan komentar tak bisa diambil (utk composer balas dari notifikasi).
enum FeedCommentUnavailableReason { commentDeleted, postDeleted }

class FeedCommentUnavailableException implements Exception {
  final FeedCommentUnavailableReason reason;
  const FeedCommentUnavailableException(this.reason);
  @override
  String toString() => 'FeedCommentUnavailableException($reason)';
}
```

- [ ] **Step 2: Tambah method `fetchCommentById`**

Di dalam class `FeedService`, tambahkan tepat SEBELUM `postComment` (baris ~289):

```dart
  /// Ambil satu komentar by id (utk composer balas dari notifikasi).
  /// 404 → [FeedCommentUnavailableException] dgn reason (komentar vs post
  /// dihapus) supaya caller bisa tampilkan pesan yang tepat.
  Future<FeedComment> fetchCommentById(String commentId) async {
    final uri = ApiConfig.uri(
      '/api/feed/comments/${Uri.encodeComponent(commentId)}',
    );
    try {
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 404) {
        String? reason;
        try {
          final body = jsonDecode(res.body);
          if (body is Map<String, dynamic>) {
            reason = body['reason']?.toString();
          }
        } catch (_) {}
        throw FeedCommentUnavailableException(
          reason == 'post_deleted'
              ? FeedCommentUnavailableReason.postDeleted
              : FeedCommentUnavailableReason.commentDeleted,
        );
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException('fetch comment failed', statusCode: res.statusCode);
      }
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        final commentJson = body['comment'] is Map<String, dynamic>
            ? body['comment'] as Map<String, dynamic>
            : body;
        return FeedComment.fromApiJson(commentJson);
      }
      throw const ApiException('invalid response');
    } catch (e) {
      if (e is FeedCommentUnavailableException) rethrow;
      if (e is ApiException) rethrow;
      throw ApiException(e.toString(), cause: e);
    }
  }
```

- [ ] **Step 3: Analyze**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply/flutter_app" && flutter analyze lib/services/feed_service.dart 2>&1 | tail -8`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && git add flutter_app/lib/services/feed_service.dart && git commit -m "feat(feed): feedService.fetchCommentById + FeedCommentUnavailableException"
```

---

### Task 8: Widget `NotificationReplyComposer` (composer ringan keyboard-safe)

**Files:**
- Create: `flutter_app/lib/widgets/notification_reply_composer.dart`
- Test: `flutter_app/test/notification_reply_composer_test.dart` (create)

**Interfaces:**
- Consumes: `FeedComment` (author.username/displayName), `feedService.postComment` (default poster), `ApiException` (statusCode 404), `AppHaptics`, `NataloColors`.
- Produces: `showNotificationReplyComposer(context, {required FeedComment comment, required String feedPostId, CommentReplyPoster? poster}): Future<void>`; typedef `CommentReplyPoster = Future<void> Function(String postId, {required String content, String? parentCommentId})`; widget `NotificationReplyComposer`. Dipakai Task 9.

- [ ] **Step 1: Tulis test dulu (gagal)**

Create `flutter_app/test/notification_reply_composer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_comment.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/services/api_client.dart';
import 'package:natalo_petshop_flutter/widgets/notification_reply_composer.dart';

FeedComment _comment({String? username = 'asiong'}) => FeedComment(
      id: 'c1',
      postId: 'p1',
      content: 'halo',
      isAdminOfficial: false,
      isHidden: false,
      likeCount: 0,
      createdAt: DateTime.now(),
      viewerLiked: false,
      author: FeedAuthor(id: 'u1', name: 'Asiong', username: username),
    );

Future<void> _open(
  WidgetTester tester, {
  required FeedComment comment,
  required CommentReplyPoster poster,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showNotificationReplyComposer(
              context,
              comment: comment,
              feedPostId: 'p1',
              poster: poster,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('prefill @username + label Membalas', (tester) async {
    await _open(
      tester,
      comment: _comment(),
      poster: (_, {required content, parentCommentId}) async {},
    );
    expect(find.text('Membalas @asiong'), findsOneWidget);
    expect(find.text('@asiong '), findsOneWidget); // isi TextField
  });

  testWidgets('kirim memanggil poster dgn parentCommentId benar + pop',
      (tester) async {
    String? gotPost;
    String? gotParent;
    String? gotContent;
    await _open(
      tester,
      comment: _comment(),
      poster: (postId, {required content, parentCommentId}) async {
        gotPost = postId;
        gotContent = content;
        gotParent = parentCommentId;
      },
    );
    await tester.enterText(find.byType(TextField), '@asiong mantap');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();
    expect(gotPost, 'p1');
    expect(gotParent, 'c1');
    expect(gotContent, '@asiong mantap');
    expect(find.text('Balasan terkirim'), findsOneWidget);
    expect(find.byType(NotificationReplyComposer), findsNothing); // sudah pop
  });

  testWidgets('kirim gagal (bukan 404) → composer tetap terbuka + snackbar',
      (tester) async {
    await _open(
      tester,
      comment: _comment(),
      poster: (_, {required content, parentCommentId}) async =>
          throw const ApiException('boom', statusCode: 500),
    );
    await tester.enterText(find.byType(TextField), 'coba');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationReplyComposer), findsOneWidget); // masih ada
    expect(find.text('Gagal mengirim balasan. Coba lagi.'), findsOneWidget);
  });

  testWidgets('kirim 404 (post dihapus saat kirim) → composer ditutup',
      (tester) async {
    await _open(
      tester,
      comment: _comment(),
      poster: (_, {required content, parentCommentId}) async =>
          throw const ApiException('gone', statusCode: 404),
    );
    await tester.enterText(find.byType(TextField), 'coba');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationReplyComposer), findsNothing); // ditutup
    expect(find.text('Postingan sudah dihapus.'), findsOneWidget);
  });

  testWidgets('tombol kirim disabled saat kosong', (tester) async {
    await _open(
      tester,
      comment: _comment(username: null), // tanpa username → prefill kosong
      poster: (_, {required content, parentCommentId}) async {},
    );
    // Tap send saat kosong tidak crash / tidak memanggil poster (tak ada snackbar terkirim).
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();
    expect(find.text('Balasan terkirim'), findsNothing);
    expect(find.text('Membalas Asiong'), findsOneWidget); // fallback tanpa @
  });
}
```

- [ ] **Step 2: Jalankan test → gagal**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply/flutter_app" && flutter test test/notification_reply_composer_test.dart 2>&1 | tail -12`
Expected: FAIL — file `notification_reply_composer.dart` belum ada (compile error).

- [ ] **Step 3: Implement composer**

Create `flutter_app/lib/widgets/notification_reply_composer.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/feed_comment.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Seam kirim balasan — default ke [feedService.postComment].
typedef CommentReplyPoster = Future<void> Function(
  String postId, {
  required String content,
  String? parentCommentId,
});

const List<String> _kQuickEmojis = [
  '❤️', '🙌', '🔥', '👏', '😢', '😍', '😮', '😂',
];

/// Buka composer balas ringan (overlay ala IG) di atas daftar notifikasi.
/// Daftar notif tetap terlihat di belakang barrier transparan; sheet
/// menempel keyboard (keyboard-safe: isScrollControlled + viewInsets).
Future<void> showNotificationReplyComposer(
  BuildContext context, {
  required FeedComment comment,
  required String feedPostId,
  CommentReplyPoster? poster,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => NotificationReplyComposer(
      comment: comment,
      feedPostId: feedPostId,
      poster: poster,
    ),
  );
}

class NotificationReplyComposer extends StatefulWidget {
  final FeedComment comment;
  final String feedPostId;
  final CommentReplyPoster? poster;

  const NotificationReplyComposer({
    super.key,
    required this.comment,
    required this.feedPostId,
    this.poster,
  });

  @override
  State<NotificationReplyComposer> createState() =>
      _NotificationReplyComposerState();
}

class _NotificationReplyComposerState extends State<NotificationReplyComposer> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  bool _canSend = false;

  bool get _hasUsername {
    final u = widget.comment.author.username;
    return u != null && u.trim().isNotEmpty;
  }

  String get _handle {
    final u = widget.comment.author.username;
    return _hasUsername ? u!.trim() : widget.comment.author.displayName;
  }

  @override
  void initState() {
    super.initState();
    final prefill = _hasUsername ? '@$_handle ' : '';
    _controller = TextEditingController(text: prefill);
    _canSend = _controller.text.trim().isNotEmpty;
    _controller.addListener(() {
      final can = _controller.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _insertEmoji(String emoji) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final next = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _send() async {
    if (_sending || !_canSend) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    AppHaptics.tap();
    setState(() => _sending = true);
    final post = widget.poster ??
        (String postId, {required String content, String? parentCommentId}) =>
            feedService.postComment(
              postId,
              content: content,
              parentCommentId: parentCommentId,
            );
    try {
      await post(
        widget.feedPostId,
        content: text,
        parentCommentId: widget.comment.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Balasan terkirim')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        // Post terhapus tepat saat kirim (celah race) — draf tak berguna.
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Postingan sudah dihapus.')),
        );
        return;
      }
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengirim balasan. Coba lagi.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengirim balasan. Coba lagi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 6),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _hasUsername ? 'Membalas @$_handle' : 'Membalas $_handle',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _kQuickEmojis.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (_, i) => InkWell(
                    onTap: () => _insertEmoji(_kQuickEmojis[i]),
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        _kQuickEmojis[i],
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'Tulis balasan…',
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SendButton(
                      key: const ValueKey('composer-send'),
                      enabled: _canSend && !_sending,
                      sending: _sending,
                      onTap: _send,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final bool sending;
  final VoidCallback onTap;
  const _SendButton({
    super.key,
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? NataloColors.primary
              : cs.onSurfaceVariant.withValues(alpha: 0.25),
        ),
        child: sending
            ? const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
      ),
    );
  }
}
```

- [ ] **Step 4: Jalankan test → lulus**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply/flutter_app" && flutter test test/notification_reply_composer_test.dart 2>&1 | tail -8`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && git add flutter_app/lib/widgets/notification_reply_composer.dart flutter_app/test/notification_reply_composer_test.dart && git commit -m "feat(notif): NotificationReplyComposer (composer balas ringan keyboard-safe)"
```

---

### Task 9: Gate + `_NotificationCommentActions` di `NotificationRow`

**Files:**
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (import, typedef seam, `NotificationRow` params + gate + branch, widget `_NotificationCommentActions`)
- Test: `flutter_app/test/notifications_redesign_widget_test.dart` (tambah group)

**Interfaces:**
- Consumes: `AppNotification.commentId` (Task 6); `feedService.setCommentLiked` + `feedService.fetchCommentById` + `FeedCommentUnavailableException`/`Reason` (Task 7); `showNotificationReplyComposer` + `CommentReplyPoster` (Task 8); `AppHaptics`, `NataloColors`.
- Produces: `NotificationRow` param opsional `commentLikeSetter` / `commentByIdFetcher` / `commentReplyPoster`; typedef `CommentLikeSetter`, `CommentByIdFetcher`. Baris aksi ♡+Balas untuk notif komentar ber-`commentId`.

- [ ] **Step 1: Tulis test dulu (gagal)**

Di `flutter_app/test/notifications_redesign_widget_test.dart`, tambahkan import baru di atas + group baru sebelum `}` penutup `main()`:

Import (di blok import atas, setelah import `feed_service.dart` — tambahkan bila belum ada):
```dart
import 'package:natalo_petshop_flutter/models/feed_comment.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/services/feed_service.dart';
```

Group (sebelum baris terakhir `}` dari `main()`):
```dart
  group('aksi komentar (♡ + Balas)', () {
    AppNotification commentNotif({
      String? commentId = 'c1',
      String? feedPostId = 'p1',
      String eventType = 'feed_new_comment',
      String ctaLabel = 'Lihat Komentar',
    }) =>
        AppNotification.fromApiJson({
          'id': 'cm1', 'title': 'Asiong berkomentar', 'body': 'mantap',
          'type': 'feed', 'eventType': eventType,
          if (feedPostId != null) 'feedPostId': feedPostId,
          if (commentId != null) 'commentId': commentId,
          'ctaLabel': ctaLabel,
          'createdAt': DateTime.now().toIso8601String(), 'read': true,
        });

    FeedComment fakeComment() => FeedComment(
          id: 'c1', postId: 'p1', content: 'mantap',
          isAdminOfficial: false, isHidden: false, likeCount: 1,
          createdAt: DateTime.now(), viewerLiked: false,
          author: const FeedAuthor(id: 'u1', name: 'Asiong', username: 'asiong'),
        );

    testWidgets('notif komentar baru → aksi ♡ + Balas (bukan pill lama)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(
            notification: commentNotif(),
            onTap: () {},
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('notification-comment-like')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('notification-comment-reply')),
          findsOneWidget);
      expect(find.text('Lihat Komentar'), findsNothing);
    });

    testWidgets('notif komentar lama (tanpa commentId) → pill Lihat Komentar',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(
            notification: commentNotif(commentId: null),
            onTap: () {},
          ),
        ),
      ));
      expect(find.text('Lihat Komentar'), findsOneWidget);
      expect(find.byKey(const ValueKey('notification-comment-reply')),
          findsNothing);
    });

    testWidgets('♡ optimistik → merah + panggil setter; tap TIDAK navigasi baris',
        (tester) async {
      var rowTapped = false;
      String? likedId;
      bool? likedState;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(
            notification: commentNotif(),
            onTap: () => rowTapped = true,
            commentLikeSetter: (id, {required liked}) async {
              likedId = id;
              likedState = liked;
              return 2;
            },
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('notification-comment-like')));
      await tester.pumpAndSettle();
      expect(rowTapped, isFalse);
      expect(likedId, 'c1');
      expect(likedState, true);
      final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const ValueKey('notification-comment-like')),
        matching: find.byType(Icon),
      ));
      expect(icon.icon, Icons.favorite_rounded);
    });

    testWidgets('♡ gagal → rollback ke outline + snackbar', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(
            notification: commentNotif(),
            onTap: () {},
            commentLikeSetter: (id, {required liked}) async =>
                throw const ApiException('boom'),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('notification-comment-like')));
      await tester.pumpAndSettle();
      final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const ValueKey('notification-comment-like')),
        matching: find.byType(Icon),
      ));
      expect(icon.icon, Icons.favorite_border_rounded);
      expect(find.text('Gagal menyukai komentar.'), findsOneWidget);
    });

    testWidgets('Balas → 404 komentar dihapus → snackbar tanpa composer',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(
            notification: commentNotif(),
            onTap: () {},
            commentByIdFetcher: (_) async => throw
                const FeedCommentUnavailableException(
                    FeedCommentUnavailableReason.commentDeleted),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('notification-comment-reply')));
      await tester.pumpAndSettle();
      expect(find.text('Komentar sudah dihapus.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // composer tak dibuka
    });

    testWidgets('Balas → sukses buka composer → kirim panggil poster',
        (tester) async {
      String? gotParent;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(
            notification: commentNotif(),
            onTap: () {},
            commentByIdFetcher: (_) async => fakeComment(),
            commentReplyPoster: (postId, {required content, parentCommentId}) async {
              gotParent = parentCommentId;
            },
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('notification-comment-reply')));
      await tester.pumpAndSettle();
      expect(find.text('Membalas @asiong'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '@asiong keren');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pumpAndSettle();
      expect(gotParent, 'c1');
    });
  });
```

- [ ] **Step 2: Jalankan test → gagal**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply/flutter_app" && flutter test test/notifications_redesign_widget_test.dart 2>&1 | tail -15`
Expected: FAIL — param `commentLikeSetter`/`commentByIdFetcher`/`commentReplyPoster` belum ada + key `notification-comment-like` tak ditemukan.

- [ ] **Step 3: Tambah import di `notifications_screen.dart`**

Di `flutter_app/lib/screens/notifications_screen.dart`, tambahkan import (setelah `import '../models/feed_post.dart';`, baris ~7):
```dart
import '../models/feed_comment.dart';
```
dan (setelah `import '../widgets/profile_avatar.dart';`, baris ~23):
```dart
import '../widgets/notification_reply_composer.dart';
```

- [ ] **Step 4: Tambah typedef seam + params di `NotificationRow`**

Di `flutter_app/lib/screens/notifications_screen.dart`, setelah typedef `PublicProfileFetcher` (baris ~865):
```dart
/// Seam test aksi komentar. Default produksi memakai feedService.
typedef CommentLikeSetter = Future<int> Function(
  String commentId, {
  required bool liked,
});
typedef CommentByIdFetcher = Future<FeedComment> Function(String commentId);
```

Di class `NotificationRow`, tambah field (setelah `final PublicProfileFetcher? profileFetcher;`, baris ~874):
```dart
  final CommentLikeSetter? commentLikeSetter;
  final CommentByIdFetcher? commentByIdFetcher;
  final CommentReplyPoster? commentReplyPoster;
```
dan param constructor (setelah `this.profileFetcher,`, baris ~881):
```dart
    this.commentLikeSetter,
    this.commentByIdFetcher,
    this.commentReplyPoster,
```

- [ ] **Step 5: Hitung gate + sisipkan branch aksi**

Di `NotificationRow.build`, setelah blok `final followBackUsername = ...` (baris ~907-910), tambahkan:
```dart
    final feedPostIdTrim = notification.feedPostId?.trim() ?? '';
    final commentIdTrim = notification.commentId?.trim() ?? '';
    final showCommentActions =
        notification.eventType?.trim().toLowerCase() == 'feed_new_comment' &&
            commentIdTrim.isNotEmpty &&
            feedPostIdTrim.isNotEmpty;
```

Lalu di dalam `Row(children: [...])` aksi (baris ~977-1019), sisipkan branch BARU antara branch follow-back dan branch `ctaLabel`. Ubah bagian:
```dart
                          if (followBackUsername != null) ...[
                            _NotificationFollowBackPill(
                              username: followBackUsername,
                              followService: followService,
                              profileFetcher: profileFetcher,
                            ),
                            const SizedBox(width: 10),
                          ] else if (ctaLabel != null) ...[
```
menjadi:
```dart
                          if (followBackUsername != null) ...[
                            _NotificationFollowBackPill(
                              username: followBackUsername,
                              followService: followService,
                              profileFetcher: profileFetcher,
                            ),
                            const SizedBox(width: 10),
                          ] else if (showCommentActions) ...[
                            _NotificationCommentActions(
                              commentId: commentIdTrim,
                              feedPostId: feedPostIdTrim,
                              likeSetter: commentLikeSetter,
                              fetcher: commentByIdFetcher,
                              poster: commentReplyPoster,
                            ),
                            const SizedBox(width: 8),
                          ] else if (ctaLabel != null) ...[
```

- [ ] **Step 6: Tambah widget `_NotificationCommentActions`**

Di `flutter_app/lib/screens/notifications_screen.dart`, tambahkan SETELAH class `_NotificationFollowBackPillState` (setelah baris ~1153, sebelum `Positioned _likeBadge(...)`):
```dart
/// Baris aksi ♡ + Balas utk notif komentar (gate: feed_new_comment +
/// commentId + feedPostId). ♡ optimistik idempotent (setCommentLiked);
/// Balas → fetchCommentById → composer ringan. Nested InkWell: tap aksi
/// TIDAK memicu navigasi baris.
class _NotificationCommentActions extends StatefulWidget {
  final String commentId;
  final String feedPostId;
  final CommentLikeSetter? likeSetter;
  final CommentByIdFetcher? fetcher;
  final CommentReplyPoster? poster;

  const _NotificationCommentActions({
    required this.commentId,
    required this.feedPostId,
    this.likeSetter,
    this.fetcher,
    this.poster,
  });

  @override
  State<_NotificationCommentActions> createState() =>
      _NotificationCommentActionsState();
}

class _NotificationCommentActionsState
    extends State<_NotificationCommentActions> {
  bool _liked = false;
  bool _likeBusy = false;
  bool _replyLoading = false;

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    AppHaptics.tap();
    final next = !_liked;
    setState(() {
      _liked = next;
      _likeBusy = true;
    });
    final setLike = widget.likeSetter ??
        (String id, {required bool liked}) =>
            feedService.setCommentLiked(id, liked: liked);
    try {
      await setLike(widget.commentId, liked: next);
      if (!mounted) return;
      setState(() => _likeBusy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = !next; // rollback
        _likeBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menyukai komentar.')),
      );
    }
  }

  Future<void> _openReply() async {
    if (_replyLoading) return;
    AppHaptics.tap();
    setState(() => _replyLoading = true);
    final fetch =
        widget.fetcher ?? (String id) => feedService.fetchCommentById(id);
    try {
      final comment = await fetch(widget.commentId);
      if (!mounted) return;
      setState(() => _replyLoading = false);
      await showNotificationReplyComposer(
        context,
        comment: comment,
        feedPostId: widget.feedPostId,
        poster: widget.poster,
      );
    } on FeedCommentUnavailableException catch (e) {
      if (!mounted) return;
      setState(() => _replyLoading = false);
      final msg = e.reason == FeedCommentUnavailableReason.postDeleted
          ? 'Postingan sudah dihapus.'
          : 'Komentar sudah dihapus.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _replyLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal memuat komentar. Coba lagi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: const ValueKey('notification-comment-like'),
          onTap: _toggleLike,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 40,
            width: 44,
            child: Icon(
              _liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              size: 18,
              color: _liked
                  ? const Color(0xFFE11D48)
                  : cs.onSurfaceVariant,
            ),
          ),
        ),
        InkWell(
          key: const ValueKey('notification-comment-reply'),
          onTap: _replyLoading ? null : _openReply,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: NataloColors.primarySoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: _replyLoading
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: NataloColors.primary,
                    ),
                  )
                : const Text(
                    'Balas',
                    style: TextStyle(
                      color: NataloColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 7: Jalankan test → lulus**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply/flutter_app" && flutter test test/notifications_redesign_widget_test.dart 2>&1 | tail -8`
Expected: `All tests passed!`

- [ ] **Step 8: Analyze (file yang diubah)**

Run: `cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply/flutter_app" && flutter analyze lib/screens/notifications_screen.dart lib/widgets/notification_reply_composer.dart lib/services/feed_service.dart lib/models/app_notification.dart 2>&1 | tail -8`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
cd "C:/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/notif-inline-reply" && git add flutter_app/lib/screens/notifications_screen.dart flutter_app/test/notifications_redesign_widget_test.dart && git commit -m "feat(notif): baris aksi ♡ + Balas di notif komentar (gate commentId)"
```

---

## Self-Review

**1. Spec coverage:**
- D1 (migration commentId + expose): Task 1 (migration+schema), Task 2 (builders + createFeedNotification), Task 3 (mapper), Task 6 (AppNotification). ✅ — termasuk koreksi review: `sendReplyNotification` pakai `replyCommentId` (Task 2 Step 4).
- D2 (GET endpoint brand-safe + guard post): Task 4 (query+test), Task 5 (route), Task 7 (fetchCommentById). ✅ — dua alasan 404 (`comment_deleted`/`post_deleted`).
- D3 (baris aksi ♡ + Balas, gate): Task 9. ✅ — optimistik+rollback+busy-guard+haptics; nested InkWell; fallback pill lama.
- D4 (composer ringan keyboard-safe): Task 8. ✅ — isScrollControlled + viewInsets; prefill @username; emoji row; kirim parentCommentId; 404 saat kirim tutup composer.
- Deploy order (migration → backend → app): tercermin di urutan task + catatan migration tak di-deploy di plan (gated user).

**2. Placeholder scan:** Tak ada "TBD/TODO/handle edge cases" — semua step berisi kode lengkap + command + expected output. ✅

**3. Type consistency:**
- `getFeedCommentDetail` return `FeedCommentDetailResult` (Task 4) dikonsumsi Task 5 dengan status yang sama persis (`not-found`/`post-gone`/`ok`). ✅
- `CommentReplyPoster` didefinisikan di composer (Task 8) & dipakai `NotificationRow`/`_NotificationCommentActions` (Task 9) via import. ✅
- `FeedCommentUnavailableReason.postDeleted/commentDeleted` (Task 7) dipakai konsisten di Task 9 `_openReply`. ✅
- `commentLikeSetter` (`Future<int> Function(String, {required bool liked})`) cocok dgn `feedService.setCommentLiked` signature. ✅
- Key test (`notification-comment-like`/`notification-comment-reply`/`composer-send`) konsisten antara test (Task 8/9 Step 1) & implementasi. ✅

**Catatan verifikasi lemah (disebut eksplisit):** `feedService.fetchCommentById` (Task 7) tak punya unit test langsung (feed_service pakai `http` global tanpa seam, konsisten dgn method HTTP lain); dicover typecheck/analyze + konsumen di-test dgn fake (Task 9). Endpoint GET (Task 5) tipis di atas `getFeedCommentDetail` yang sudah di-unit-test penuh (Task 4).
