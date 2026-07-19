# P2 — Avatar Aktor Terstruktur (brand-safe) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps pakai checkbox (`- [ ]`).

**Goal:** Notif sosial (komentar, reply, mention, like single, comment-like single, follow) menyimpan `actorAvatarUrl` + `actorName` terstruktur & brand-safe, dan app menampilkan foto aktor di KIRI. Menggantikan heuristik follow P1.

**Architecture:** Kolom baru `Announcement.actorAvatarUrl/actorName` (migration Prisma). Semua penulisan aktor lewat helper murni brand-safe `notificationActorFields`. Builder yang lewat `createFeedNotification` mengirim `actor`; builder follow + batched-like update menulis kolom langsung. API `mapAnnouncement` expose kolom. Client parse + render avatar kiri.

**Tech Stack:** TypeScript, Prisma (Postgres/Neon), Node test runner (`tsx --test`), Flutter/`flutter_test`.

## Global Constraints

- **Brand-safety WAJIB**: setiap penulisan `actorName`/`actorAvatarUrl` lewat `brandDisplayName(role,name)` + `brandPhotoUrl(role,photo)` (`lib/social/brand-user.ts`). Admin → name="Natalo Petshop Official", avatar=null (client render logo brand). JANGAN pernah persist nama/foto asli pemilik admin.
- **Migration**: SQL sungguhan di `prisma/migrations/` (bukan `db push`) — gotcha schema-drift Neon; kolom nullable (backward compatible).
- **Batched-like semantics**: baris agregat (update branch "N orang menyukai") → `actorAvatarUrl=null, actorName=null` (aktor ambigu). Hanya like TUNGGAL (create pertama) yang bawa aktor.
- **Deploy order**: backend + migration boleh deploy sebelum app P2 rilis (kolom nullable, client lama abaikan). Follow: pertahankan `thumbnailUrl`=foto follower selama transisi (jangan null-kan) + isi `actorAvatarUrl` (spec transisi).
- Font client w400/w600; token `NataloColors.*`.
- Branch `claude/notification-p2-actor-avatar` (off origin/main). Perintah backend dari repo root worktree; flutter dari `flutter_app/`.

---

### Task 1: Migration + schema — kolom `actorAvatarUrl` + `actorName`

**Files:**
- Create: `prisma/migrations/20260719130000_add_announcement_actor_fields/migration.sql`
- Modify: `prisma/schema.prisma` (model `Announcement`, setelah `targetUserId`)

- [ ] **Step 1: Tulis migration SQL**

Buat `prisma/migrations/20260719130000_add_announcement_actor_fields/migration.sql`:

```sql
-- Kolom identitas aktor terstruktur untuk notifikasi sosial (komentar,
-- mention, like tunggal, follow). Memungkinkan app menampilkan foto + nama
-- aktor di kiri baris notifikasi, brand-safe (admin → null avatar + nama
-- brand, di-guard di layer aplikasi via lib/social/brand-user.ts).
-- Nullable: baris lama & notif non-aktor (sistem/pesanan/promo) tetap null.

ALTER TABLE "Announcement"
ADD COLUMN "actorAvatarUrl" TEXT,
ADD COLUMN "actorName" TEXT;
```

- [ ] **Step 2: Tambah kolom di schema**

Di `prisma/schema.prisma`, model `Announcement`, setelah baris `targetUserId String?`:

```prisma
  /// Identitas aktor notifikasi sosial (follow/komentar/mention/like tunggal).
  /// Brand-safe: admin → actorName brand + actorAvatarUrl null. Null untuk
  /// notif non-aktor / agregat.
  actorAvatarUrl String?
  actorName      String?
```

- [ ] **Step 3: Generate client + verify migrasi konsisten**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx prisma generate && npx prisma migrate status 2>&1 | tail -20`
Expected: `prisma generate` sukses; migrate status TIDAK menunjukkan drift/error parse (kalau DB env tak tersambung di lokal, minimal `generate` sukses + schema valid — `npx prisma validate` bersih).

- [ ] **Step 4: Commit**

```bash
git add prisma/schema.prisma prisma/migrations/20260719130000_add_announcement_actor_fields/
git commit -m "feat(notifikasi): kolom Announcement.actorAvatarUrl + actorName (migration)"
```

---

### Task 2: Helper murni `notificationActorFields` (brand-safe) + test

**Files:**
- Modify: `lib/social/brand-user.ts`
- Test: `tests/notification-actor-fields.test.ts` (baru)

**Interfaces:**
- Produces: `notificationActorFields(role, name, profilePhotoUrl): { actorName: string | null; actorAvatarUrl: string | null }` — admin → `{ actorName: OFFICIAL_BRAND_NAME, actorAvatarUrl: null }`; user biasa → `{ actorName: name ?? null, actorAvatarUrl: profilePhotoUrl ?? null }`.

- [ ] **Step 1: Tulis test yang gagal**

Buat `tests/notification-actor-fields.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  notificationActorFields,
  OFFICIAL_BRAND_NAME,
} from "../lib/social/brand-user";

test("admin actor → nama brand, avatar null (tak bocor foto/nama pemilik)", () => {
  const r = notificationActorFields("ADMIN", "Natasha", "https://cdn/natasha.jpg");
  assert.equal(r.actorName, OFFICIAL_BRAND_NAME);
  assert.equal(r.actorAvatarUrl, null);
});

test("user biasa → nama & foto asli", () => {
  const r = notificationActorFields("USER", "Andi", "https://cdn/andi.jpg");
  assert.equal(r.actorName, "Andi");
  assert.equal(r.actorAvatarUrl, "https://cdn/andi.jpg");
});

test("user tanpa foto/nama → null", () => {
  const r = notificationActorFields("USER", null, null);
  assert.equal(r.actorName, null);
  assert.equal(r.actorAvatarUrl, null);
});
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx tsx --test tests/notification-actor-fields.test.ts`
Expected: FAIL — `notificationActorFields` belum diekspор.

- [ ] **Step 3: Implementasi helper**

Di `lib/social/brand-user.ts`, tambahkan di akhir:

```ts
/**
 * Field aktor terstruktur untuk baris notifikasi (Announcement.actorName/
 * actorAvatarUrl), brand-safe. Admin → nama brand + avatar null (client render
 * logo). User biasa → nama & foto asli.
 */
export function notificationActorFields(
  role: string | null | undefined,
  name: string | null | undefined,
  profilePhotoUrl: string | null | undefined,
): { actorName: string | null; actorAvatarUrl: string | null } {
  return {
    actorName: isAdminRole(role) ? OFFICIAL_BRAND_NAME : (name ?? null),
    actorAvatarUrl: brandPhotoUrl(role, profilePhotoUrl),
  };
}
```

- [ ] **Step 4: Test + typecheck**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx tsx --test tests/notification-actor-fields.test.ts && npx tsc --noEmit 2>&1 | grep -i "brand-user" || echo "no brand-user type errors"`
Expected: PASS; tak ada type error.

- [ ] **Step 5: Commit**

```bash
git add lib/social/brand-user.ts tests/notification-actor-fields.test.ts
git commit -m "feat(notifikasi): helper murni notificationActorFields (brand-safe)"
```

---

### Task 3: `createFeedNotification` menerima + menulis `actor`

**Files:**
- Modify: `lib/feed/notification-center.ts`

**Interfaces:**
- Consumes: helper Task 2 (dipakai pemanggil, bukan di sini).
- Produces: param baru `actor?: { avatarUrl?: string | null; name?: string | null }` pada `createFeedNotification`; ditulis ke `announcement.create.data.actorAvatarUrl/actorName`.

- [ ] **Step 1: Tambah param ke signature**

Di `createFeedNotification` params type (`lib/feed/notification-center.ts:87-101`), tambahkan sebelum `dedupeByEvent`:

```ts
  actor?: { avatarUrl?: string | null; name?: string | null };
```

- [ ] **Step 2: Tulis kolom di announcement.create**

Di blok `prisma.announcement.create({ data: { ... } })` (`:160-176`), tambahkan sebelum `publishedAt`:

```ts
          actorAvatarUrl: params.actor?.avatarUrl ?? null,
          actorName: params.actor?.name ?? null,
```

(Opsional: tambahkan juga ke `pushData` bila ingin push membawa actor — tidak wajib untuk P2; lewati agar minimal.)

- [ ] **Step 3: Typecheck**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx tsc --noEmit 2>&1 | grep -i "notification-center" || echo "no type errors"`
Expected: bersih (kolom sudah ada dari Task 1 `prisma generate`).

- [ ] **Step 4: Commit**

```bash
git add lib/feed/notification-center.ts
git commit -m "feat(notifikasi): createFeedNotification menulis actorAvatarUrl/actorName"
```

---

### Task 4: Builder komentar / reply / mention — kirim actor brand-safe

**Files:**
- Modify: `lib/feed/activity-notifications.ts` (3 builder: `sendCommentNotification`, `sendReplyNotification`, `sendMentionNotifications`)

**Interfaces:**
- Consumes: `notificationActorFields` (Task 2), param `actor` di `createFeedNotification` (Task 3).

Untuk KETIGA builder, pola edit sama:
1. Widen `prisma.user.findUnique` select aktor → tambahkan `profilePhotoUrl: true` (comment `:60-63`, reply `:108-111`, mention `:163-166`).
2. Setelah actor di-fetch, hitung: `const actorFields = notificationActorFields(actor?.role, actor?.name, actor?.profilePhotoUrl);` (import `notificationActorFields` dari `@/lib/social/brand-user`). Pertahankan komputasi `actorName` string yang sudah ada untuk teks (atau ganti pakai `actorFields.actorName ?? "Seseorang"`).
3. Di panggilan `createFeedNotification`, tambahkan: `actor: { avatarUrl: actorFields.actorAvatarUrl, name: actorFields.actorName },`.

- [ ] **Step 1: Edit `sendCommentNotification`** — widen select (+profilePhotoUrl), hitung `actorFields`, tambah `actor:` di createFeedNotification call (`:69-83`).

- [ ] **Step 2: Edit `sendReplyNotification`** — sama (select `:108-111`, call `:121-136`).

- [ ] **Step 3: Edit `sendMentionNotifications`** — sama (select `:163-166`, call `:193-219`; `actorFields` dihitung sekali sebelum `recipients.map`).

- [ ] **Step 4: Typecheck + import**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx tsc --noEmit 2>&1 | grep -i "activity-notifications" || echo "no type errors"`
Expected: bersih; `notificationActorFields` terimpor.

- [ ] **Step 5: Commit**

```bash
git add lib/feed/activity-notifications.ts
git commit -m "feat(notifikasi): komentar/reply/mention kirim actor brand-safe"
```

---

### Task 5: Like tunggal + comment-like — actor bernama; batched agregat null

**Files:**
- Modify: `lib/feed/activity-notifications.ts` (`sendLikeNotification`, `sendCommentLikeNotification`)

**Interfaces:**
- Consumes: `notificationActorFields` (Task 2), `actor` param (Task 3).

- [ ] **Step 1: `sendLikeNotification` — tambah lookup aktor + actor pada create**

Tambahkan lookup aktor (belum ada). Setelah `post` di-fetch (`:289-298`), tambah:

```ts
    const actor = await prisma.user.findUnique({
      where: { id: params.actorUserId },
      select: { name: true, role: true, profilePhotoUrl: true },
    });
    const actorFields = notificationActorFields(
      actor?.role,
      actor?.name,
      actor?.profilePhotoUrl,
    );
    const likerName = actorFields.actorName ?? "Seseorang";
```

Ubah create path (`:332-346`): pesan single jadi bernama + kirim actor:

```ts
    await createFeedNotification({
      userId: post.authorId,
      eventType: "feed_new_like",
      title: "Feed kamu mendapat like baru",
      message: `${likerName} menyukai postingan ${quoteFeedTitle(post.title)}.`,
      feedPostId: post.id,
      thumbnailUrl: post.thumbnailUrl,
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Postingan",
      tag: `feed-like-${post.id}`,
      data: { like_count: String(params.likeCount) },
      actor: { avatarUrl: actorFields.actorAvatarUrl, name: actorFields.actorName },
      surface: SOCIAL_NOTIFICATION_SOURCE,
    });
```

Di batched update branch (`:317-329`), TAMBAHKAN ke `data`: `actorAvatarUrl: null, actorName: null,` (agregat → aktor ambigu, jangan tampilkan satu wajah).

- [ ] **Step 2: `sendCommentLikeNotification` — sama**

Tambah lookup aktor (belum ada; ada lookup `author`=recipient di `:370-374`, tambah lookup aktor terpisah). Hitung `actorFields` + `likerName`. Create path (`:407-422`): `message: `${likerName} menyukai komentarmu di Feed.`` + `actor: {...}`. Batched update (`:396-404`) `data`: tambah `actorAvatarUrl: null, actorName: null`.

- [ ] **Step 3: Typecheck**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx tsc --noEmit 2>&1 | grep -i "activity-notifications" || echo "no type errors"`
Expected: bersih.

- [ ] **Step 4: Commit**

```bash
git add lib/feed/activity-notifications.ts
git commit -m "feat(notifikasi): like tunggal bernama+avatar; batched tetap agregat (null actor)"
```

---

### Task 6: Follow — persist `actorName`/`actorAvatarUrl` (transisi aman)

**Files:**
- Modify: `lib/social/notifications.ts` (`sendFollowNotification`)

- [ ] **Step 1: Tulis kolom aktor di announcement.create**

Di `sendFollowNotification`, komputasi brand-safe sudah ada (`actorName` `:46-48`, `actorPhoto` `:49`). Di `prisma.announcement.create({ data: {...} })` (`:99-113`), tambahkan sebelum `publishedAt`:

```ts
          actorName,
          actorAvatarUrl: actorPhoto,
```

PERTAHANKAN `thumbnailUrl: actorPhoto` yang sudah ada (transisi: app P1 lama masih baca avatar follow dari thumbnailUrl; jangan hapus di P2).

- [ ] **Step 2: Typecheck**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx tsc --noEmit 2>&1 | grep -i "social/notifications" || echo "no type errors"`
Expected: bersih.

- [ ] **Step 3: Commit**

```bash
git add lib/social/notifications.ts
git commit -m "feat(notifikasi): follow persist actorName/actorAvatarUrl (thumbnailUrl dipertahankan utk transisi)"
```

---

### Task 7: API — expose `actorAvatarUrl`/`actorName` di `mapAnnouncement`

**Files:**
- Modify: `app/api/notifications/me/route.ts`

- [ ] **Step 1: Tambah field di tipe + return `mapAnnouncement`**

Di tipe param `mapAnnouncement` (`:38-52`), tambahkan setelah `thumbnailUrl`:

```ts
  actorAvatarUrl: string | null;
  actorName: string | null;
```

Di objek return (`:53-72`), tambahkan setelah `thumbnailUrl: a.thumbnailUrl,`:

```ts
    actorAvatarUrl: a.actorAvatarUrl,
    actorName: a.actorName,
```

(Kedua `findMany` tak pakai `select` sempit → kolom baru auto-tersedia; tak perlu ubah query.)

- [ ] **Step 2: Typecheck**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx tsc --noEmit 2>&1 | grep -i "notifications/me" || echo "no type errors"`
Expected: bersih.

- [ ] **Step 3: Commit**

```bash
git add app/api/notifications/me/route.ts
git commit -m "feat(notifikasi): API expose actorAvatarUrl/actorName"
```

---

### Task 8: Client — parse actor + render avatar kiri (gantikan heuristik follow P1)

**Files:**
- Modify: `flutter_app/lib/models/app_notification.dart`
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (`NotificationRow`, `_IdentityAvatar`)
- Test: `flutter_app/test/models/app_notification_actor_test.dart` (baru) + tambah widget test di `test/notifications_redesign_widget_test.dart`

**Interfaces:**
- `AppNotification.actorAvatarUrl` (`String?`), `actorName` (`String?`) — parse `actorAvatarUrl`/`actor_avatar_url` & `actorName`/`actor_name`; copyWith preserve.
- `NotificationRow`: avatar kiri = `notification.actorAvatarUrl` bila ada (semua notif ber-aktor, tak lagi cuma follow); thumbnail kanan disembunyikan hanya bila avatar berasal dari media aktor tanpa konten (follow). 

- [ ] **Step 1: Model test (gagal)**

Buat `flutter_app/test/models/app_notification_actor_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/app_notification.dart';

void main() {
  Map<String, dynamic> base() => {
        'id': 'n', 'title': 'T', 'body': 'B', 'type': 'info',
        'createdAt': '2026-07-19T00:00:00.000Z', 'read': false,
      };
  test('parse actorAvatarUrl + actorName (camel & snake)', () {
    final a = AppNotification.fromApiJson(
        {...base(), 'actorAvatarUrl': 'https://cdn/a.jpg', 'actorName': 'Andi'});
    expect(a.actorAvatarUrl, 'https://cdn/a.jpg');
    expect(a.actorName, 'Andi');
    final b = AppNotification.fromApiJson(
        {...base(), 'actor_avatar_url': 'https://cdn/b.jpg', 'actor_name': 'Budi'});
    expect(b.actorAvatarUrl, 'https://cdn/b.jpg');
    expect(b.actorName, 'Budi');
  });
  test('null saat absent, survive copyWith', () {
    final a = AppNotification.fromApiJson(base());
    expect(a.actorAvatarUrl, isNull);
    final c = AppNotification.fromApiJson(
        {...base(), 'actorAvatarUrl': 'https://cdn/a.jpg'});
    expect(c.copyWith(read: true).actorAvatarUrl, 'https://cdn/a.jpg');
  });
}
```

- [ ] **Step 2: Jalankan, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/models/app_notification_actor_test.dart`
Expected: FAIL — getter `actorAvatarUrl` belum ada.

- [ ] **Step 3: Tambah field di `AppNotification`**

Tambah field `final String? actorAvatarUrl;` + `final String? actorName;`, param konstruktor, parsing di `fromApiJson`:

```dart
      actorAvatarUrl:
          (json['actorAvatarUrl'] ?? json['actor_avatar_url'])?.toString(),
      actorName: (json['actorName'] ?? json['actor_name'])?.toString(),
```

dan teruskan di `copyWith`.

- [ ] **Step 4: Widget test (gagal) — avatar aktor untuk komentar**

Tambah di `test/notifications_redesign_widget_test.dart`:

```dart
  testWidgets('actorAvatarUrl → avatar aktor di kiri (mis. komentar)',
      (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'c1', 'title': 'Andi mengomentari postinganmu', 'body': 'keren!',
      'type': 'info', 'eventType': 'feed_new_comment',
      'actorAvatarUrl': 'https://cdn/andi.jpg',
      'thumbnailUrl': 'https://cdn/post.jpg',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.byKey(const ValueKey('notification-actor-avatar')),
        findsOneWidget);
    // Komentar tetap punya thumbnail POST di kanan (beda dari follow).
    expect(find.byKey(const ValueKey('notification-thumb')), findsOneWidget);
  });
```

- [ ] **Step 5: Update `NotificationRow` + `_IdentityAvatar`**

Di `NotificationRow.build`, ganti logika follow-heuristik P1:

```dart
    final actorAvatarUrl = notification.actorAvatarUrl;
    final isFollow =
        notification.eventType?.toLowerCase() == 'user_followed';
    // Avatar kiri dari field terstruktur (semua notif ber-aktor). Follow
    // tak punya konten post → sembunyikan thumbnail kanan; notif lain (mis.
    // komentar) tetap tampilkan thumbnail POST di kanan.
```

`_IdentityAvatar(avatarUrl: actorAvatarUrl != null && actorAvatarUrl.trim().isNotEmpty ? actorAvatarUrl : (isFollow ? imageUrl : null), ...)` — utamakan `actorAvatarUrl`; fallback `imageUrl` untuk follow (kompat notif follow lama pra-P2 yang cuma set thumbnailUrl).

Thumbnail kanan: `if (imageUrl != null && imageUrl.trim().isNotEmpty && !isFollow) ...`. (Ganti widget cached bila ada `AppProductImage`/CachedNetworkImage; kalau tidak, biarkan `Image.network` — di luar scope minor.)

- [ ] **Step 6: Test + analyze**

Run: `cd flutter_app && flutter test test/models/app_notification_actor_test.dart test/notifications_redesign_widget_test.dart test/notification_order_routing_test.dart && flutter analyze lib/screens/notifications_screen.dart lib/models/app_notification.dart`
Expected: semua PASS; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/models/app_notification.dart flutter_app/lib/screens/notifications_screen.dart flutter_app/test/models/app_notification_actor_test.dart flutter_app/test/notifications_redesign_widget_test.dart
git commit -m "feat(notifikasi): app render avatar aktor dari actorAvatarUrl (gantikan heuristik follow)"
```

---

### Task 9: Regresi backend + client + analyze

- [ ] **Step 1: Backend tests + typecheck**

Run: `cd .claude/worktrees/flutter-feed-ui-design-f74eb8 && npx tsx --test tests/notification-actor-fields.test.ts tests/feed-publish-push.test.ts && npx tsc --noEmit 2>&1 | grep -iE "notification|activity|social/notifications|brand-user" || echo "no type errors in touched files"`
Expected: test PASS; tak ada type error di file yang disentuh.

- [ ] **Step 2: Client tests + analyze**

Run: `cd flutter_app && flutter test test/models/ test/notifications_redesign_widget_test.dart test/notifications_redesign_logic_test.dart test/notification_order_routing_test.dart && flutter analyze lib/screens/notifications_screen.dart lib/models/app_notification.dart`
Expected: `All tests passed!`; `No issues found!`

- [ ] **Step 3: Commit penutup (bila ada penyesuaian)** — lewati bila bersih.

---

## Verifikasi manual (staging + device)

- Migration ter-deploy (`prisma migrate deploy`).
- Komentar/mention/like/follow dari user biasa → baris notif punya `actorAvatarUrl`+`actorName`; app tampil foto user di kiri.
- Aktor ADMIN → `actorAvatarUrl` null + `actorName` "Natalo Petshop Official"; app tampil logo brand "NL" (TIDAK bocor foto/nama pemilik).
- Batched like ("N orang") → tak ada satu avatar (ikon kategori).
- Follow → foto follower kiri; app P1 lama tetap jalan (thumbnailUrl dipertahankan).

## Catatan

Setelah adopsi app P2 memadai, `thumbnailUrl` follow bisa dibersihkan (follow-up). P3 (thumbnail produk pesanan/keranjang) menyusul.
</content>
