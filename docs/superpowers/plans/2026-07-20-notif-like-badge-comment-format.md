# Notifikasi — Lencana ❤️ Like + Format Komentar IG-style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notif like menampilkan lencana ❤️ merah kecil di sudut avatar berfoto/agregat (ala IG), dan notif komentar diformat ringkas (nama aktor + isi komentar langsung).

**Architecture:** Feature A (client-only Flutter): overlay badge ❤️ di cabang foto `_IdentityAvatar` + `StackedActorAvatars`, digate `eventType == 'feed_new_like'`. Feature B (backend-only): helper murni `buildCommentNotificationText` + wire ke `sendCommentNotification`. Dua task independen.

**Tech Stack:** Flutter (`flutter test`/`flutter analyze`), Node built-in test runner (`npx tsx --test`), TypeScript.

## Global Constraints

- Lencana ❤️ HANYA untuk `eventType == 'feed_new_like'` (like-post & like-komentar). Komentar/share/follow/mention TIDAK dapat lencana.
- Lencana ditambahkan HANYA di cabang foto (`_IdentityAvatar` photo branch) + `StackedActorAvatars`. Cabang `brandIdentity` (like tanpa foto → logo brand + badge kategori existing) TIDAK disentuh — cegah badge dobel.
- Lencana: lingkaran `Color(0xFFE11D48)` diameter 17, `Icon(Icons.favorite_rounded, Colors.white, size: 9)`, `Border.all(color: colorScheme.surface, width: 2)`, `Positioned(right: -3, bottom: -3)`, `key: ValueKey('notification-like-badge')`.
- Judul komentar `"{actorName} berkomentar"` WAJIB memuat substring "komentar" (filter tab Feed match keyword "komentar" — "ber**komentar**" memenuhi). Jangan ganti ke bentuk tanpa "komentar".
- `actorName` di builder komentar sudah brand-safe (admin → `OFFICIAL_BRAND_NAME`); helper tak mengubah nama.

---

### Task 1: Backend — format komentar IG-style (helper + wire)

**Files:**
- Modify: `lib/feed/notification-center.ts` (tambah `buildCommentNotificationText` setelah `truncateFeedText` ~:76-80)
- Modify: `lib/feed/activity-notifications.ts` (`sendCommentNotification` :82-100 + import :28-34)
- Test: `tests/comment-notification-text.test.ts` (baru)

**Interfaces:**
- Consumes: `truncateFeedText(input, limit=80)` dari `notification-center.ts`.
- Produces: `buildCommentNotificationText(actorName: string, content: string): { title: string; body: string }`.

- [ ] **Step 1: Tulis test helper**

Buat `tests/comment-notification-text.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { buildCommentNotificationText } from "../lib/feed/notification-center";

test("judul = nama + 'berkomentar' (memuat 'komentar'), body = isi", () => {
  const r = buildCommentNotificationText("Andi", "Done ✅");
  assert.equal(r.title, "Andi berkomentar");
  assert.match(r.title, /komentar/); // load-bearing utk filter tab Feed
  assert.equal(r.body, "Done ✅");
});

test("isi panjang → body ter-truncate (limit 80, akhiran …)", () => {
  const long = "a".repeat(200);
  const r = buildCommentNotificationText("Budi", long);
  assert.equal(r.body.length, 80); // 79 char + '…'
  assert.ok(r.body.endsWith("…"));
});

test("nama brand admin diteruskan apa adanya (brand-safety di call-site)", () => {
  const r = buildCommentNotificationText("Natalo Petshop Official", "halo");
  assert.equal(r.title, "Natalo Petshop Official berkomentar");
});

test("isi kosong/whitespace → body kosong (truncateFeedText trim)", () => {
  assert.equal(buildCommentNotificationText("Andi", "   ").body, "");
});
```

- [ ] **Step 2: Jalankan test — pastikan GAGAL**

Run: `npx tsx --test tests/comment-notification-text.test.ts`
Expected: FAIL "buildCommentNotificationText is not a function" / export not found.

- [ ] **Step 3: Tulis helper di notification-center.ts**

Di `lib/feed/notification-center.ts`, tepat SETELAH fungsi `truncateFeedText` (yang berakhir ~:80, sebelum `quoteFeedTitle`), tambahkan:

```ts
/**
 * Teks notif komentar ringkas ala IG: nama aktor jadi judul + isi komentar
 * langsung (tanpa judul generik / judul post — thumbnail kanan sudah
 * menunjukkan post-nya). "berkomentar" WAJIB memuat "komentar" karena filter
 * tab Feed di client mencocokkan keyword itu.
 */
export function buildCommentNotificationText(
  actorName: string,
  content: string,
): { title: string; body: string } {
  return {
    title: `${actorName} berkomentar`,
    body: truncateFeedText(content),
  };
}
```

- [ ] **Step 4: Jalankan test — pastikan LULUS**

Run: `npx tsx --test tests/comment-notification-text.test.ts`
Expected: PASS (4 test).

- [ ] **Step 5: Wire ke sendCommentNotification**

Di `lib/feed/activity-notifications.ts`:

(a) Tambah `buildCommentNotificationText` ke import dari `"@/lib/feed/notification-center"` (blok :28-34, yang sudah mengimpor `createFeedNotification`, `quoteFeedTitle`, `truncateFeedText`):

```ts
import {
  buildCommentNotificationText,
  createFeedNotification,
  feedPostOwnerUrl,
  quoteFeedTitle,
  SOCIAL_NOTIFICATION_SOURCE,
  truncateFeedText,
} from "@/lib/feed/notification-center";
```

(b) Di `sendCommentNotification`, GANTI blok `createFeedNotification` bagian title+message (`:82-88`). Sebelum `await createFeedNotification({`, hitung teks; lalu pakai:

```ts
    const commentText = buildCommentNotificationText(actorName, params.content);

    await createFeedNotification({
      userId: post.authorId,
      eventType: "feed_new_comment",
      title: commentText.title,
      message: commentText.body,
      feedPostId: post.id,
      thumbnailUrl: feedNotificationThumbnail(post),
      url: feedPostOwnerUrl(post.id),
      ctaLabel: "Lihat Komentar",
      tag: `feed-comment-${post.id}`,
      data: { comment_id: params.commentId },
      surface: SOCIAL_NOTIFICATION_SOURCE,
      actor: {
        avatarUrl: actorFields.actorAvatarUrl,
        name: actorFields.actorName,
      },
    });
```

(`quoteFeedTitle` dan `truncateFeedText` tetap dipakai builder LAIN di file ini, jadi importnya tak dihapus. `quoteFeedTitle` kini tak dipakai di `sendCommentNotification` sendiri — itu wajar, tak perlu diubah.)

- [ ] **Step 6: Verifikasi tsc + test existing**

Run: `npx tsc --noEmit 2>&1 | grep -iE "activity-notifications|notification-center" || echo OK`
Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add lib/feed/notification-center.ts lib/feed/activity-notifications.ts tests/comment-notification-text.test.ts
git commit -m "feat(notifikasi): format komentar ringkas IG-style (nama + isi komentar, teruji)"
```

---

### Task 2: Client — lencana ❤️ pada notif like

**Files:**
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (helper `_likeBadge` baru; `_IdentityAvatar` :1072-1139; `StackedActorAvatars` :1027-1069; call site `NotificationRow.build` :917-926)
- Test: `flutter_app/test/notifications_redesign_widget_test.dart` (tambah grup baru)

**Interfaces:**
- Consumes: `notification.eventType`, `notification.actorAvatarUrls`, `_NotificationVisual`.
- Produces: badge dgn `key: ValueKey('notification-like-badge')`.

- [ ] **Step 1: Tambah helper _likeBadge**

Di `flutter_app/lib/screens/notifications_screen.dart`, tepat SEBELUM `class StackedActorAvatars` (~:1027), tambahkan fungsi top-level:

```dart
/// Lencana ❤️ kecil utk notif LIKE — ditempel di sudut kanan-bawah avatar
/// BERFOTO (persis pola badge kategori brand). Hanya utk feed_new_like.
/// Return Positioned → WAJIB dipakai sebagai child langsung sebuah Stack.
Positioned _likeBadge(BuildContext context) => Positioned(
      right: -3,
      bottom: -3,
      child: Container(
        key: const ValueKey('notification-like-badge'),
        height: 17,
        width: 17,
        decoration: BoxDecoration(
          color: const Color(0xFFE11D48),
          shape: BoxShape.circle,
          border: Border.all(
              color: Theme.of(context).colorScheme.surface, width: 2),
        ),
        child: const Icon(Icons.favorite_rounded,
            color: Colors.white, size: 9),
      ),
    );
```

- [ ] **Step 2: Tambah param likeBadge ke StackedActorAvatars + overlay**

Di `StackedActorAvatars` (:1027-1032), tambah field + param:

```dart
class StackedActorAvatars extends StatelessWidget {
  final List<String> urls;
  final _NotificationVisual visual;
  final bool likeBadge;
  const StackedActorAvatars(
      {super.key,
      required this.urls,
      required this.visual,
      this.likeBadge = false});
```

Lalu di `Stack.children` dalam `build` (:1057-1064), tambahkan badge di akhir:

```dart
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (shown.length > 1)
            Positioned(left: 0, top: 0, child: circle(shown[1], 30)),
          Positioned(right: 0, bottom: 0, child: circle(shown[0], 30)),
          if (likeBadge) _likeBadge(context),
        ],
      ),
```

- [ ] **Step 3: Tambah param likeBadge ke _IdentityAvatar + overlay di cabang foto**

Di `_IdentityAvatar` (:1072-1081), tambah field + param:

```dart
class _IdentityAvatar extends StatelessWidget {
  final _NotificationVisual visual;
  final bool brandIdentity;
  final String? avatarUrl;
  final bool likeBadge;

  const _IdentityAvatar({
    required this.visual,
    required this.brandIdentity,
    this.avatarUrl,
    this.likeBadge = false,
  });
```

Lalu di `build`, GANTI cabang foto (`:1085-1103`, blok `if (url != null && url.trim().isNotEmpty) { return Container(...); }`) menjadi:

```dart
    final url = avatarUrl;
    if (url != null && url.trim().isNotEmpty) {
      final photo = Container(
        key: const ValueKey('notification-actor-avatar'),
        height: 42,
        width: 42,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: visual.color.withValues(alpha: 0.12),
        ),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(visual.icon, color: visual.color, size: 20),
        ),
      );
      if (!likeBadge) return photo;
      return Stack(
        clipBehavior: Clip.none,
        children: [photo, _likeBadge(context)],
      );
    }
```

(Cabang `brandIdentity`/ikon di bawahnya TIDAK diubah — like tanpa foto tetap logo brand + badge kategori existing.)

- [ ] **Step 4: Gate di call site NotificationRow.build**

Di `NotificationRow.build`, sebelum `Padding(` avatar (~:912) atau di dekat deklarasi `visual`/`actorAvatarUrl`, tambahkan:

```dart
    final showLikeBadge =
        notification.eventType?.trim().toLowerCase() == 'feed_new_like';
```

Lalu di blok avatar (:917-926), teruskan flag ke KEDUA widget:

```dart
                if (notification.actorAvatarUrls.length >= 2)
                  StackedActorAvatars(
                    urls: notification.actorAvatarUrls,
                    visual: visual,
                    likeBadge: showLikeBadge,
                  )
                else
                  _IdentityAvatar(
                    visual: visual,
                    brandIdentity: _isBrandIdentity,
                    avatarUrl: actorAvatarUrl,
                    likeBadge: showLikeBadge,
                  ),
```

- [ ] **Step 5: Tulis widget test**

Tambahkan ke `flutter_app/test/notifications_redesign_widget_test.dart` (dalam `main()`):

```dart
  group('lencana like', () {
    testWidgets('like berfoto → lencana ❤️ di sudut avatar', (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'lk1', 'title': 'Andi menyukai postinganmu', 'body': '',
        'type': 'feed', 'eventType': 'feed_new_like',
        'actorAvatarUrl': 'https://cdn/andi.jpg',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byKey(const ValueKey('notification-like-badge')),
          findsOneWidget);
    });

    testWidgets('like agregat (stacked) → lencana ❤️ di atas tumpukan',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'lk2', 'title': '3 orang menyukai Feed kamu', 'body': '',
        'type': 'feed', 'eventType': 'feed_new_like',
        'actorAvatarUrls': ['https://cdn/1.jpg', 'https://cdn/2.jpg'],
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byKey(const ValueKey('notification-stacked-avatars')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('notification-like-badge')),
          findsOneWidget);
    });

    testWidgets('like TANPA foto → tak ada lencana baru (cabang brand tak disentuh)',
        (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'lk3', 'title': 'Feed kamu mendapat like baru', 'body': '',
        'type': 'feed', 'eventType': 'feed_new_like',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byKey(const ValueKey('notification-like-badge')),
          findsNothing);
    });

    testWidgets('komentar berfoto → TIDAK dapat lencana like', (tester) async {
      final n = AppNotification.fromApiJson({
        'id': 'lk4', 'title': 'Andi berkomentar', 'body': 'keren!',
        'type': 'feed', 'eventType': 'feed_new_comment',
        'actorAvatarUrl': 'https://cdn/andi.jpg',
        'createdAt': DateTime.now().toIso8601String(), 'read': false,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotificationRow(notification: n, onTap: () {})),
      ));
      expect(find.byKey(const ValueKey('notification-like-badge')),
          findsNothing);
    });
  });
```

- [ ] **Step 6: Jalankan analyze + test**

Run: `cd flutter_app && flutter analyze lib/screens/notifications_screen.dart`
Expected: "No issues found" (atau hanya 2 info `library_private_types_in_public_api` pre-existing di :1029/:1031).
Run: `cd flutter_app && flutter test test/notifications_redesign_widget_test.dart`
Expected: semua PASS.

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/screens/notifications_screen.dart flutter_app/test/notifications_redesign_widget_test.dart
git commit -m "feat(notifikasi): lencana ❤️ di notif like berfoto/agregat (ala IG)"
```

---

## Self-Review

**Spec coverage:**
- Feature A (lencana like foto+stacked, gate feed_new_like, cabang brand tak disentuh) → Task 2 ✅
- Feature B (helper buildCommentNotificationText + wire sendCommentNotification) → Task 1 ✅
- Acceptance 1-5 tercakup ✅

**Placeholder scan:** tak ada TBD; tiap step ada kode konkret.

**Type consistency:** `buildCommentNotificationText(actorName, content): {title, body}` (Task 1) konsisten dari helper→call site. `_likeBadge(context): Positioned` (Task 2) dipakai sebagai child Stack di `_IdentityAvatar` (Stack baru) + `StackedActorAvatars` (Stack existing) — keduanya Stack, valid. `likeBadge: bool` default false konsisten di kedua widget + call site. `ValueKey('notification-like-badge')` konsisten helper↔test.

**Catatan deploy:** Task 1 backend-only (notif komentar baru langsung ringkas, tanpa migration). Task 2 client-only (butuh rilis app). Independen — urutan bebas.
