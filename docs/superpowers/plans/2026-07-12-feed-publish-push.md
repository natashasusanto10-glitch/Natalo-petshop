# Feed Publish Push — judul post → notifikasi user saat tayang

## Tujuan
Saat admin publish post feed dengan opsi "Beri tahu pelanggan" ON, kirim push ke segmen user terpilih (judul = headline, caption = body, tap → `/feed/{postId}`) + simpan Announcement untuk lonceng notifikasi. Post video dikirim saat encoding Bunny selesai (webhook ready), bukan saat upload.

## Keputusan terkunci (user-approved via mockup v2)
- Opt-in per post: toggle default **OFF**.
- Segmen: `all` / `members` / `active30d`, default **members**.
- Rate cap: maks **2 push feed per 24 jam** (rolling window) — push ke-3 di-skip diam-diam (log saja).
- Tombol "Tes ke HP saya dulu" → kirim payload sama hanya ke admin yang login.
- Idempoten: `publishPushSentAt` — set atomik sebelum kirim; webhook retry tidak dobel-blast.
- Hanya post `authorRole=ADMIN` + `status=ACTIVE` + `encodingStatus=ready`.

## Global Constraints
- **Migration WAJIB di PR yang sama** dengan perubahan schema.prisma (insiden PR #71: schema tanpa migration → storefront 0 produk). Pakai SQL idempoten `ADD COLUMN IF NOT EXISTS`, pola persis `prisma/migrations/20260710000000_add_product_video_columns/migration.sql`.
- Reuse dispatch push existing: `sendPushToUser` (lib/push.ts), `sendApnsToUser` (lib/apns.ts), `sendFcmToUser` (lib/fcm.ts). Batch 50, `Promise.allSettled`, pola persis `app/api/admin/push/broadcast/route.ts:208-236`.
- Resolusi segmen COPY pola broadcast route (baris 100-141): `all` = distinct userId di PushSubscription; `members` = Order PAID distinct userId ∩ PushSubscription; `active30d` = sama + `createdAt >= now-30d`.
- Notifikasi tidak boleh memblok/menggagalkan alur utama — semua fire-and-forget `void` + try/catch telan error dengan `console.warn` (pola lib/feed/notifications.ts).
- Bahasa UI & komentar: Indonesia, gaya file sekitarnya.
- Verifikasi per task: `npx tsc --noEmit` + `npx eslint <file>` hijau. Test node ada di `tests/*.test.ts` (node:test + node:assert, jalankan `npm test`).
- JANGAN commit di main checkout; kerja di worktree ini, branch `claude/feed-publish-push`.

## Task 1 — Schema + migration
`prisma/schema.prisma` model FeedPost (setelah `encodingStatus`):
```prisma
  // Publish-push: opsi "Beri tahu pelanggan" saat admin publish.
  notifyOnPublish   Boolean   @default(false)
  pushSegment       String?   // "all" | "members" | "active30d"
  publishPushSentAt DateTime? // guard idempoten — set saat push terkirim
```
Migration baru `prisma/migrations/20260712000000_add_feed_publish_push/migration.sql` (idempoten):
```sql
ALTER TABLE "FeedPost" ADD COLUMN IF NOT EXISTS "notifyOnPublish" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "FeedPost" ADD COLUMN IF NOT EXISTS "pushSegment" TEXT;
ALTER TABLE "FeedPost" ADD COLUMN IF NOT EXISTS "publishPushSentAt" TIMESTAMP(3);
```
Jalankan `npx prisma generate` setelahnya. Verify: tsc hijau.

## Task 2 — lib/feed/publish-push.ts
Export:
- `type PushSegment = "all" | "members" | "active30d"`
- `resolveSegmentUserIds(segment: PushSegment): Promise<string[]>` — copy pola broadcast route.
- `countRecentPublishPush(): Promise<number>` — `prisma.feedPost.count({ where: { publishPushSentAt: { gte: new Date(Date.now() - 24*60*60*1000) } } })`.
- `FEED_PUSH_DAILY_CAP = 2`.
- `sendFeedPublishPush(postId: string): Promise<void>` — SEMUA guard di dalam, aman dipanggil dari mana pun:
  1. Ambil post (select id, authorRole, status, encodingStatus, title, description, notifyOnPublish, pushSegment, publishPushSentAt, thumbnailUrl). Return diam kalau: tidak ada / authorRole!=="ADMIN" / status!=="ACTIVE" / encodingStatus!=="ready" / !notifyOnPublish / publishPushSentAt!=null.
  2. Cap: `countRecentPublishPush() >= FEED_PUSH_DAILY_CAP` → `console.warn("[feed-push] daily cap tercapai, skip", postId)` + return.
  3. Klaim atomik: `prisma.feedPost.updateMany({ where: { id, publishPushSentAt: null }, data: { publishPushSentAt: new Date() } })` — kalau `count===0` return (race/retry).
  4. Payload: `title` = post.title dipotong 60 char; `body` = post.description dipotong 120 char, fallback `"Ada konten baru di Natalo 🎥"`; `url` = `/feed/${postId}`; `tag` = `feed-publish-${postId}`.
  5. Buat `prisma.announcement.create` (pola broadcast route baris 160-174): title, body, url, `segment` = pushSegment ?? "members", `type: "announcement"`, `ctaLabel: "Lihat Post"`, `publishedAt: new Date()`, `status: "PUBLISHED"`.
  6. Fan-out batch 50 × 3 channel (copy broadcast 208-236). Seluruh fungsi dibungkus try/catch → `console.warn("[feed-push] failed:", err)`.
- `sendFeedPublishTestPush(params: { userId: string; title: string; description: string | null }): Promise<void>` — payload sama (tanpa post/Announcement/guard), kirim 3 channel ke 1 user, url `/feed`.
Test `tests/feed-publish-push.test.ts` untuk helper murni pemotong payload — ekstrak `buildFeedPushPayload(postId, title, description)` pure + test truncation 60/120 + fallback body + url.

## Task 3 — Wiring trigger + terima field dari client
- `app/api/feed/posts/route.ts`: body type + parse `notifyOnPublish?: boolean`, `pushSegment?: string` — HANYA dihormati kalau `isAdmin` (customer diabaikan). Validasi pushSegment ∈ {all,members,active30d}, default "members" saat notifyOnPublish true. Simpan ke `tx.feedPost.create` data. Setelah transaction (dekat baris 537): `void import("@/lib/feed/publish-push").then(({ sendFeedPublishPush }) => sendFeedPublishPush(post.id));` — guard internal helper yang memutuskan (post video admin masih `uploading` → no-op; kalau suatu saat ada post admin non-video ready → langsung kirim).
- `app/api/feed/bunny/webhook/route.ts`: setelah update `encodingStatus: "ready"` (baris ~174, sebelah `sendFeedPendingReviewNotification`): `void import("@/lib/feed/publish-push").then(({ sendFeedPublishPush }) => sendFeedPublishPush(post.id));`.

## Task 4 — Endpoint info + tes
`app/api/admin/feed/push-info/route.ts`:
- `GET` — admin-auth (`getSession("ADMIN")`). Return `{ counts: { all, members, active30d }, quota: { used, cap } }`. Counts pakai `resolveSegmentUserIds` (3 panggilan paralel `Promise.all`, return `.length`); quota.used = `countRecentPublishPush()`, cap = `FEED_PUSH_DAILY_CAP`.
- `POST` — admin-auth + `assertSameOrigin` (lib/csrf). Body `{ title: string, description?: string | null }` (validasi title non-empty ≤200). Panggil `sendFeedPublishTestPush({ userId: session.sub, ... })`. Return `{ ok: true }`.

## Task 5 — UI AdminFeedCreateClient
`components/admin/feed/AdminFeedCreateClient.tsx`, section baru "Beri tahu pelanggan" ANTARA section Title+description dan Product picker, gaya section existing (`rounded-2xl border border-gray-100 bg-white p-3`):
- State: `notifyOnPublish` (false), `pushSegment` ("members"), `pushInfo` (null), `testState` ("idle"|"sending"|"sent").
- Saat toggle pertama ON → fetch GET `/api/admin/feed/push-info` sekali (cache di state) untuk counts + quota.
- Toggle switch (button role=switch, styling tailwind, biru natalo saat ON) + subline dinamis: OFF "Post tayang tanpa notifikasi" / ON "Push dikirim saat post ini tayang".
- Saat ON tampil: baris kuota "Kuota push hari ini: X dari 2 tersisa" (hijau kalau sisa>0, merah + toggle disabled-OFF paksa kalau habis); 3 radio-card segmen (Semua pelanggan / Member [badge "Disarankan"] / Aktif 30 hari) dengan deskripsi 1 baris + count dari pushInfo (fallback "–" saat belum load); tombol "Tes ke HP saya dulu" → POST push-info (butuh title terisi ≥3; error toast/inline kalau kosong), label berubah "Terkirim ✓" 2 detik.
- Submit: sertakan `notifyOnPublish` + `pushSegment` di kedua payload POST `/api/feed/posts` (jalur Bunny ~baris 333 dan jalur non-Bunny ~baris 492).
- Copy Indonesia persis mockup v2. Kuota habis: kirim tetap di-skip server-side (cap) — UI hanya informatif, jangan blok publish post-nya.

## Task 6 — Final review whole-branch (opus)
