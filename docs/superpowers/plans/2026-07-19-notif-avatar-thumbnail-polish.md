# Notifikasi — Avatar Brand + Thumbnail Feed + Avatar Bertumpuk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notifikasi lonceng menampilkan logo brand asli (bukan teks "NL"), thumbnail post yang benar (video signed + foto FeedMedia), avatar aktor untuk notif post-user-lain, dan avatar bertumpuk untuk like agregat — semua brand-safe.

**Architecture:** Backend mengisi data yang benar (helper thumbnail bersama, kolom array avatar liker, avatar aktor brand-safe) dan men-sign URL Bunny saat baca di API. Client Flutter merender logo brand (`OfficialBrandAvatar`), avatar bertumpuk (`StackedActorAvatars`), dan membuang kotak abu saat gambar gagal.

**Tech Stack:** Next.js (server), Prisma (migration SQL tulis-tangan), Node test runner (`tsx --test`), Flutter (`flutter test`/`flutter analyze`).

## Global Constraints

- Setiap avatar/foto aktor baru WAJIB brand-safe: liker/aktor akun ADMIN → foto=null (klien render logo brand), nama → "Natalo Petshop Official". Pakai `brandPhotoUrl(role, photo)` / `notificationActorFields(role, name, photo)` dari `lib/social/brand-user.ts`.
- Avatar bertumpuk maksimal **3** foto liker; judul agregat tetap **"N orang menyukai…"** (tanpa nama).
- URL Bunny di-sign **saat baca** di `mapAnnouncement` (`signBunnyUrl`, sync) — JANGAN simpan URL bertanda-tangan (expiry 6 jam).
- Migration SQL pakai `ADD COLUMN IF NOT EXISTS`; folder timestamp > `20260719140000`.
- Client memprioritaskan render avatar: `actorAvatarUrls.length >= 2` (bertumpuk) → `actorAvatarUrl` (tunggal) → `brandIdentity` (logo) → ikon kategori.

---

### Task 1: Migration + schema — kolom actorAvatarUrls

**Files:**
- Modify: `prisma/schema.prisma` (model `Announcement`, ~:1122, setelah `actorName String?`)
- Create: `prisma/migrations/20260719150000_add_announcement_actor_avatar_urls/migration.sql`

**Interfaces:**
- Produces: kolom `Announcement.actorAvatarUrls String[] @default([])`.

- [ ] **Step 1: Tambah field ke model Announcement**

Di `prisma/schema.prisma`, di model `Announcement`, setelah baris `actorName String?`, tambahkan:

```prisma
  actorAvatarUrls   String[]  @default([])
```

- [ ] **Step 2: Tulis migration SQL**

Buat `prisma/migrations/20260719150000_add_announcement_actor_avatar_urls/migration.sql`:

```sql
ALTER TABLE "Announcement"
ADD COLUMN IF NOT EXISTS "actorAvatarUrls" TEXT[] NOT NULL DEFAULT '{}';
```

- [ ] **Step 3: Regenerasi client**

Run: `npx prisma generate`
Expected: "Generated Prisma Client" tanpa error.

- [ ] **Step 4: Verifikasi tsc**

Run: `npx tsc --noEmit 2>&1 | grep -i "actorAvatarUrls" || echo OK`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add prisma/schema.prisma prisma/migrations/20260719150000_add_announcement_actor_avatar_urls/migration.sql
git commit -m "feat(notif-polish): kolom Announcement.actorAvatarUrls (avatar bertumpuk)"
```

---

### Task 2: Helper murni — feedNotificationThumbnail + topLikerAvatars

**Files:**
- Create: `lib/feed/notification-thumbnail.ts`
- Modify: `lib/social/brand-user.ts` (tambah `topLikerAvatars`)
- Test: `tests/notification-thumbnail.test.ts`
- Test: `tests/notification-actor-fields.test.ts` (tambah kasus `topLikerAvatars`)

**Interfaces:**
- Consumes: `brandPhotoUrl(role, photo)` dari `lib/social/brand-user.ts`.
- Produces:
  - `feedNotificationThumbnail(post: { thumbnailUrl: string | null; media?: Array<{ url: string }> | null }): string | null`
  - `topLikerAvatars(likers: Array<{ role: string | null; profilePhotoUrl: string | null }>): string[]`

- [ ] **Step 1: Tulis test feedNotificationThumbnail**

Buat `tests/notification-thumbnail.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { feedNotificationThumbnail } from "../lib/feed/notification-thumbnail";

test("video: pakai thumbnailUrl", () => {
  assert.equal(
    feedNotificationThumbnail({ thumbnailUrl: "https://cdn/v.jpg", media: [] }),
    "https://cdn/v.jpg",
  );
});

test("foto: thumbnailUrl null → media pertama", () => {
  assert.equal(
    feedNotificationThumbnail({
      thumbnailUrl: null,
      media: [{ url: "https://cdn/a.jpg" }, { url: "https://cdn/b.jpg" }],
    }),
    "https://cdn/a.jpg",
  );
});

test("tanpa thumbnail & tanpa media → null", () => {
  assert.equal(feedNotificationThumbnail({ thumbnailUrl: null, media: [] }), null);
  assert.equal(feedNotificationThumbnail({ thumbnailUrl: null }), null);
});
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `npx tsx --test tests/notification-thumbnail.test.ts`
Expected: FAIL "Cannot find module '../lib/feed/notification-thumbnail'".

- [ ] **Step 3: Tulis feedNotificationThumbnail**

Buat `lib/feed/notification-thumbnail.ts`:

```ts
/**
 * Thumbnail untuk baris notifikasi feed. Video → thumbnailUrl (URL Bunny;
 * di-sign saat baca di mapAnnouncement). Foto → URL FeedMedia pertama
 * (sortOrder asc). Null bila post tak punya keduanya.
 */
export function feedNotificationThumbnail(post: {
  thumbnailUrl: string | null;
  media?: Array<{ url: string }> | null;
}): string | null {
  return post.thumbnailUrl ?? post.media?.[0]?.url ?? null;
}
```

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run: `npx tsx --test tests/notification-thumbnail.test.ts`
Expected: PASS (3 test).

- [ ] **Step 5: Tulis topLikerAvatars di brand-user.ts**

Di `lib/social/brand-user.ts`, setelah fungsi `likeRowActorFields`, tambahkan:

```ts
/**
 * Foto avatar untuk baris notif LIKE agregat (avatar bertumpuk ala IG).
 * Brand-safe: liker akun ADMIN → foto null (di-DROP dari array, tak bocor;
 * array cuma berisi foto asli non-admin). Maks 3.
 */
export function topLikerAvatars(
  likers: Array<{ role: string | null | undefined; profilePhotoUrl: string | null | undefined }>,
): string[] {
  const out: string[] = [];
  for (const l of likers) {
    const photo = brandPhotoUrl(l.role, l.profilePhotoUrl);
    if (photo && photo.trim()) out.push(photo);
    if (out.length >= 3) break;
  }
  return out;
}
```

- [ ] **Step 6: Tambah test topLikerAvatars**

Di `tests/notification-actor-fields.test.ts`, tambahkan import `topLikerAvatars` ke baris import dari `"../lib/social/brand-user"`, lalu tambahkan:

```ts
test("topLikerAvatars: foto non-admin, admin di-drop, maks 3", () => {
  const r = topLikerAvatars([
    { role: "USER", profilePhotoUrl: "https://cdn/1.jpg" },
    { role: "ADMIN", profilePhotoUrl: "https://cdn/owner.jpg" }, // admin → drop
    { role: "USER", profilePhotoUrl: "https://cdn/2.jpg" },
    { role: "USER", profilePhotoUrl: "https://cdn/3.jpg" },
    { role: "USER", profilePhotoUrl: "https://cdn/4.jpg" }, // > 3 → dibuang
  ]);
  assert.deepEqual(r, ["https://cdn/1.jpg", "https://cdn/2.jpg", "https://cdn/3.jpg"]);
});

test("topLikerAvatars: null/empty foto dibuang", () => {
  assert.deepEqual(
    topLikerAvatars([
      { role: "USER", profilePhotoUrl: null },
      { role: "USER", profilePhotoUrl: "  " },
      { role: "USER", profilePhotoUrl: "https://cdn/x.jpg" },
    ]),
    ["https://cdn/x.jpg"],
  );
});
```

- [ ] **Step 7: Jalankan kedua test — pastikan LULUS**

Run: `npx tsx --test tests/notification-thumbnail.test.ts tests/notification-actor-fields.test.ts`
Expected: semua PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/feed/notification-thumbnail.ts lib/social/brand-user.ts tests/notification-thumbnail.test.ts tests/notification-actor-fields.test.ts
git commit -m "feat(notif-polish): helper feedNotificationThumbnail + topLikerAvatars (brand-safe, teruji)"
```

---

### Task 3: API mapper — sign thumbnail + expose actorAvatarUrls

**Files:**
- Modify: `app/api/notifications/me/route.ts` (`mapAnnouncement` :38-77)

**Interfaces:**
- Consumes: `signBunnyUrl` dari `lib/feed/bunny.ts` (sync, no-op untuk host non-Bunny); kolom `actorAvatarUrls` (Task 1).

- [ ] **Step 1: Import signBunnyUrl**

Di `app/api/notifications/me/route.ts`, tambahkan import (dekat import lain):

```ts
import { signBunnyUrl } from "@/lib/feed/bunny";
```

- [ ] **Step 2: Tambah actorAvatarUrls ke tipe param + sign thumbnail di return**

Di `mapAnnouncement`, pada tipe parameter object tambahkan field:

```ts
  actorAvatarUrls: string[];
```

(letakkan setelah `actorName: string | null;`).

Lalu di objek return, ubah baris `thumbnailUrl: a.thumbnailUrl,` menjadi:

```ts
    thumbnailUrl: signBunnyUrl(a.thumbnailUrl) ?? null,
```

dan tambahkan setelah baris `actorName: a.actorName,`:

```ts
    actorAvatarUrls: a.actorAvatarUrls,
```

- [ ] **Step 3: Verifikasi tsc**

Run: `npx tsc --noEmit 2>&1 | grep -i "notifications/me" || echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add "app/api/notifications/me/route.ts"
git commit -m "feat(notif-polish): mapper sign thumbnail Bunny saat baca + expose actorAvatarUrls"
```

---

### Task 4: Wiring feedNotificationThumbnail ke semua builder notif feed

**Files:**
- Modify: `lib/feed/activity-notifications.ts` (7 builder: `sendCommentNotification` :87, `sendReplyNotification` :146, `sendMentionNotifications` :234, `sendLikeMilestoneNotification` :308, `sendLikeNotification` :320, `sendCommentLikeNotification` :407, `sendShareNotification` :495+)
- Modify: `lib/feed/publish-push.ts` (`buildFeedPublishAnnouncementData` + `sendFeedPublishPush` query)
- Modify: `lib/social/notifications.ts` (`sendNewPostToFollowersNotification` thumb)

**Interfaces:**
- Consumes: `feedNotificationThumbnail` dari `lib/feed/notification-thumbnail.ts` (Task 2).

**Catatan pola (berlaku untuk SEMUA edit di task ini):**
1. Import di tiap file: `import { feedNotificationThumbnail } from "@/lib/feed/notification-thumbnail";`
2. Di setiap `prisma.feedPost.findUnique({ select: {...} })` yang menjadi sumber thumbnail, tambahkan ke `select`:
   ```ts
   media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
   ```
3. Ganti setiap penggunaan `post.thumbnailUrl` (saat menulis field `thumbnailUrl` Announcement/push) menjadi `feedNotificationThumbnail(post)`. Simpan hasilnya di satu `const thumb = feedNotificationThumbnail(post);` di awal bila dipakai berkali-kali (mis. di `sendLikeNotification` yang memakainya di cabang agregat + create).

- [ ] **Step 1: activity-notifications.ts — tambah media select + pakai helper (7 builder)**

Untuk MASING-MASING dari 7 builder, baca kode saat ini, lalu: (a) tambah `media` ke `select` query post-nya, (b) ganti `thumbnailUrl: post.thumbnailUrl` / `post?.thumbnailUrl ?? null` menjadi `thumbnailUrl: feedNotificationThumbnail(post)` (untuk post nullable pakai `post ? feedNotificationThumbnail(post) : null`). Tambahkan import helper di atas file.

Contoh untuk `sendLikeNotification` (`:320`) — query jadi:

```ts
    const post = await prisma.feedPost.findUnique({
      where: { id: params.postId },
      select: {
        id: true,
        authorId: true,
        authorRole: true,
        title: true,
        thumbnailUrl: true,
        media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } },
      },
    });
```

lalu di awal (setelah guard `post`) `const thumb = feedNotificationThumbnail(post);`, dan kedua tempat `thumbnailUrl: post.thumbnailUrl` → `thumbnailUrl: thumb`.

Untuk `sendCommentLikeNotification` (`:407`) query post-nya `select: { thumbnailUrl: true }` → tambah `media: {...}`, dan `thumbnailUrl: post?.thumbnailUrl ?? null` → `thumbnailUrl: post ? feedNotificationThumbnail(post) : null`.

- [ ] **Step 2: publish-push.ts — lebarkan param + query media + helper**

Di `sendFeedPublishPush`, tambahkan `media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } }` ke `select` post (`:112-125`).

Di `buildFeedPublishAnnouncementData` (`:89`), ubah tipe param `post` dari `{ id: string; thumbnailUrl: string | null }` menjadi:

```ts
  post: { id: string; thumbnailUrl: string | null; media?: Array<{ url: string }> | null };
```

dan ubah baris `thumbnailUrl: input.post.thumbnailUrl,` menjadi `thumbnailUrl: feedNotificationThumbnail(input.post),` (import helper). Di call site (`:156-162`) teruskan `media`: `post: { id: post.id, thumbnailUrl: post.thumbnailUrl, media: post.media }`.

- [ ] **Step 3: social/notifications.ts — thumb helper di new-post**

Di `sendNewPostToFollowersNotification` (`:135`), tambah `media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } }` ke `select` post, dan ganti `const thumb = post.thumbnailUrl ?? null;` menjadi `const thumb = feedNotificationThumbnail(post);` (import helper). (`thumb` sudah dipakai di payload + createMany rows.)

- [ ] **Step 4: Verifikasi tsc + test existing**

Run: `npx tsc --noEmit 2>&1 | grep -iE "activity-notifications|publish-push|social/notifications" || echo OK`
Expected: `OK`
Run: `npx tsx --test tests/feed-publish-push.test.ts`
Expected: PASS (test existing tetap hijau; `buildFeedPublishAnnouncementData` dgn post tanpa media tetap valid).

- [ ] **Step 5: Commit**

```bash
git add lib/feed/activity-notifications.ts lib/feed/publish-push.ts lib/social/notifications.ts
git commit -m "feat(notif-polish): semua builder notif feed pakai feedNotificationThumbnail (foto dapat thumbnail)"
```

---

### Task 5: Avatar bertumpuk — like agregat isi actorAvatarUrls

**Files:**
- Modify: `lib/feed/activity-notifications.ts` (cabang agregat `sendLikeNotification` + `sendCommentLikeNotification`)

**Interfaces:**
- Consumes: `topLikerAvatars` dari `lib/social/brand-user.ts` (Task 2).

- [ ] **Step 1: Import topLikerAvatars**

Di `lib/feed/activity-notifications.ts`, tambahkan `topLikerAvatars` ke import existing dari `"@/lib/social/brand-user"` (yang sudah mengimpor `notificationActorFields`, `likeRowActorFields`).

- [ ] **Step 2: sendLikeNotification agregat — query 3 liker + set actorAvatarUrls**

Di cabang `if (recentUnread)` `sendLikeNotification` (`:366-377`), SEBELUM `prisma.announcement.update`, tambahkan query liker teratas:

```ts
      const topLikers = await prisma.feedLike.findMany({
        where: { postId: post.id },
        orderBy: { createdAt: "desc" },
        take: 3,
        select: { user: { select: { role: true, profilePhotoUrl: true } } },
      });
      const avatarUrls = topLikerAvatars(topLikers.map((l) => l.user));
```

lalu di `data` update, tambahkan setelah `...likeRowActorFields(true, actorFields),`:

```ts
          actorAvatarUrls: avatarUrls,
```

- [ ] **Step 3: sendCommentLikeNotification agregat — query 3 liker komentar + set**

Di cabang `if (recentUnread)` `sendCommentLikeNotification` (`:456-467`), SEBELUM `prisma.announcement.update`, tambahkan:

```ts
      const topLikers = await prisma.feedCommentLike.findMany({
        where: { commentId: params.commentId },
        orderBy: { createdAt: "desc" },
        take: 3,
        select: { user: { select: { role: true, profilePhotoUrl: true } } },
      });
      const avatarUrls = topLikerAvatars(topLikers.map((l) => l.user));
```

lalu di `data` update tambahkan setelah `...likeRowActorFields(true, actorFields),`:

```ts
          actorAvatarUrls: avatarUrls,
```

- [ ] **Step 4: Verifikasi tsc**

Run: `npx tsc --noEmit 2>&1 | grep -i "activity-notifications" || echo OK`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add lib/feed/activity-notifications.ts
git commit -m "feat(notif-polish): like agregat isi actorAvatarUrls (3 liker teratas, brand-safe)"
```

---

### Task 6: Avatar aktor — notif postingan baru dari user yang diikuti

**Files:**
- Modify: `lib/social/notifications.ts` (`sendNewPostToFollowersNotification` :135)

**Interfaces:**
- Consumes: `notificationActorFields` dari `lib/social/brand-user.ts`.

- [ ] **Step 1: Import + tambah profilePhotoUrl ke select author**

Di `lib/social/notifications.ts`, pastikan `notificationActorFields` di-import dari `"./brand-user"` (tambah bila belum). Di query post `sendNewPostToFollowersNotification` (`:144-151`), pada `author.select` tambahkan `profilePhotoUrl: true,` (setelah `role: true,`).

- [ ] **Step 2: Hitung actorFields + tulis ke tiap row createMany**

Setelah `const thumb = feedNotificationThumbnail(post);` (Task 4), tambahkan:

```ts
    const actorFields = notificationActorFields(
      post.author.role,
      post.author.name,
      post.author.profilePhotoUrl,
    );
```

Lalu di `prisma.announcement.createMany` (`:213`), pada objek row (di dalam `.map`), tambahkan setelah `targetUserId: fid,`:

```ts
        actorAvatarUrl: actorFields.actorAvatarUrl,
        actorName: actorFields.actorName,
```

- [ ] **Step 3: Verifikasi tsc**

Run: `npx tsc --noEmit 2>&1 | grep -i "social/notifications" || echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add lib/social/notifications.ts
git commit -m "feat(notif-polish): notif postingan-baru isi avatar poster (brand-safe)"
```

---

### Task 7: Client Flutter — logo brand + avatar bertumpuk + kotak abu

**Files:**
- Modify: `flutter_app/lib/models/app_notification.dart` (field `actorAvatarUrls`)
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (`_IdentityAvatar`, avatar-selection, thumb block, widget `StackedActorAvatars`)
- Test: `flutter_app/test/notifications_redesign_widget_test.dart`

**Interfaces:**
- Consumes: `OfficialBrandAvatar` dari `../widgets/official_brand_avatar.dart` (param `size`); `AppNotification.actorAvatarUrls`.

- [ ] **Step 1: Tambah actorAvatarUrls ke AppNotification**

Di `flutter_app/lib/models/app_notification.dart`:
- Tambah field: setelah `final String? actorName;` → `final List<String> actorAvatarUrls;`
- Di konstruktor: setelah `this.actorName,` → `this.actorAvatarUrls = const [],`
- Di `fromApiJson`: setelah baris `actorName: ...,` tambahkan:

```dart
      actorAvatarUrls: ((json['actorAvatarUrls'] ?? json['actor_avatar_urls'])
                  as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
```

- Di `copyWith`: setelah `actorName: actorName,` → `actorAvatarUrls: actorAvatarUrls,`

- [ ] **Step 2: Tambah widget StackedActorAvatars**

Di `flutter_app/lib/screens/notifications_screen.dart`, tambahkan import di atas: `import '../widgets/official_brand_avatar.dart';` lalu tambahkan widget baru (dekat `_IdentityAvatar`):

```dart
/// Avatar bertumpuk ala IG untuk notif like agregat (2 foto liker teratas
/// saling tumpang-tindih). Ukuran total 42 supaya sejajar avatar lain.
class StackedActorAvatars extends StatelessWidget {
  final List<String> urls;
  final _NotificationVisual visual;
  const StackedActorAvatars({super.key, required this.urls, required this.visual});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = urls.take(2).toList();
    Widget circle(String url, double size) => Container(
          height: size,
          width: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: visual.color.withValues(alpha: 0.12),
            border: Border.all(color: cs.surface, width: 2),
          ),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Icon(visual.icon, color: visual.color, size: 16),
          ),
        );
    return SizedBox(
      key: const ValueKey('notification-stacked-avatars'),
      height: 42,
      width: 42,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (shown.length > 1)
            Positioned(left: 0, top: 0, child: circle(shown[1], 30)),
          Positioned(right: 0, bottom: 0, child: circle(shown[0], 30)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Pilih avatar bertumpuk di build (sebelum _IdentityAvatar)**

Di `NotificationRow.build`, di tempat memanggil `_IdentityAvatar(...)` (`:915-919`), bungkus dengan pilihan bertumpuk:

```dart
                if (notification.actorAvatarUrls.length >= 2)
                  StackedActorAvatars(
                    urls: notification.actorAvatarUrls,
                    visual: visual,
                  )
                else
                  _IdentityAvatar(
                    visual: visual,
                    brandIdentity: _isBrandIdentity,
                    avatarUrl: actorAvatarUrl,
                  ),
```

- [ ] **Step 4: Ganti Text('NL') → OfficialBrandAvatar**

Di `_IdentityAvatar.build`, pada cabang `brandIdentity` (`core = brandIdentity ? Container(...Text('NL')...)`), ganti seluruh `Container(... child: const Text('NL', ...))` menjadi:

```dart
        ? const OfficialBrandAvatar(size: 42)
```

(biarkan cabang `else` ikon kategori + Stack badge tetap.)

- [ ] **Step 5: Buang kotak abu saat gambar gagal (thumb block)**

Di thumb block (`:986-1009`, `key: ValueKey('notification-thumb')`), hapus warna+border permanen dari `Container` luar: hapus `color: cs.surfaceContainerHighest,` dan `border: Border.all(...)` dari `decoration`. Latar abu hanya saat loading — ubah `Image.network` menjadi:

```dart
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : Container(color: cs.surfaceContainerHighest),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
```

(decoration Container tinggal `borderRadius: BorderRadius.circular(12)`.)

- [ ] **Step 6: Tulis widget test**

Tambahkan ke `flutter_app/test/notifications_redesign_widget_test.dart` (dalam `main()`):

```dart
  testWidgets('brand notif → OfficialBrandAvatar (bukan teks NL)', (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'b1', 'title': 'Feed kamu sudah tayang', 'body': 'disetujui',
      'type': 'feed', 'eventType': 'feed_published',
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.text('NL'), findsNothing);
    expect(find.byType(OfficialBrandAvatar), findsOneWidget);
  });

  testWidgets('like agregat (actorAvatarUrls ≥2) → avatar bertumpuk', (tester) async {
    final n = AppNotification.fromApiJson({
      'id': 'agg1', 'title': '3 orang menyukai Feed kamu', 'body': '',
      'type': 'feed', 'eventType': 'feed_new_like',
      'actorAvatarUrls': ['https://cdn/1.jpg', 'https://cdn/2.jpg'],
      'createdAt': DateTime.now().toIso8601String(), 'read': false,
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
    ));
    expect(find.byKey(const ValueKey('notification-stacked-avatars')),
        findsOneWidget);
  });
```

- [ ] **Step 7: Jalankan analyze + test**

Run: `cd flutter_app && flutter analyze lib/screens/notifications_screen.dart lib/models/app_notification.dart`
Expected: "No issues found" (atau hanya info pre-existing).
Run: `cd flutter_app && flutter test test/notifications_redesign_widget_test.dart`
Expected: semua PASS.

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/models/app_notification.dart flutter_app/lib/screens/notifications_screen.dart flutter_app/test/notifications_redesign_widget_test.dart
git commit -m "feat(notif-polish): logo brand OfficialBrandAvatar + avatar bertumpuk + kotak abu hilang saat error"
```

---

## Self-Review

**Spec coverage:**
- Kolom actorAvatarUrls + migration → Task 1 ✅
- Helper thumbnail + topLikerAvatars (teruji) → Task 2 ✅
- Mapper sign Bunny + expose array → Task 3 ✅
- Thumbnail benar di semua builder → Task 4 ✅
- Avatar bertumpuk like agregat → Task 5 ✅
- Avatar poster followed_user_posted → Task 6 ✅
- Flutter logo + bertumpuk + kotak abu → Task 7 ✅
- Acceptance 1-7 tercakup ✅

**Placeholder scan:** tak ada TBD; tiap step ada kode konkret.

**Type consistency:** `feedNotificationThumbnail(post)` (Task 2) dipakai Task 4 & 6 dengan bentuk `post` yang punya `thumbnailUrl` + `media`. `topLikerAvatars(likers)` (Task 2) dipakai Task 5 dengan `{role, profilePhotoUrl}`. `actorAvatarUrls` (Task 1) di-set Task 5, di-expose Task 3, di-parse Task 7. `OfficialBrandAvatar(size:42)` cocok konstruktor. Dependensi Task 5 & 6 pada Task 4 (edit file sama, sekuensial — implementer baca state terkini).

**Catatan deploy:** migration deploy dulu (Task 1). Client (Task 7) butuh rilis app. Nomor baris client bergeser pasca-#197 — implementer lokasikan via simbol, bukan baris.
