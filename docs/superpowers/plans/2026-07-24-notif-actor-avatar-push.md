# Notif Foto Aktor di Push + Real-time List — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Push notifikasi sosial menampilkan foto si aktor — Android avatar bulat (largeIcon, semua kondisi), iOS thumbnail kotak (NSE) — plus ikon "Ditandai" in-app dan auto-refresh layar notifikasi.

**Architecture:** Backend menandai 5 event sosial beraktor sebagai `renderClientSide` (allowlist) dan mengirim FCM **per-kapabilitas-token**: token app baru → Android data-only (app render sendiri, avatar bulat) + iOS alert+mutable-content; token lama → notification-message seperti sekarang (nol notifikasi hilang, review A3). Order/promo/status TIDAK berubah (review D2). Flutter menambah renderer lokal (background+foreground) dengan crop avatar bulat, dedup id deterministik, timeout+fallback. NSE iOS melampirkan `actor_avatar_url`. Spec: `docs/superpowers/specs/2026-07-24-notif-actor-avatar-push-design.md` (ENG CLEARED).

**Tech Stack:** Next.js + Prisma + firebase-admin (`lib/fcm.ts`), Flutter (`firebase_messaging`, `flutter_local_notifications`, `dart:ui`), Swift NSE.

## Global Constraints

- Event allowlist render-klien (PERSIS 5): `feed_new_comment`, `feed_new_like`, `feed_mention`, `feed_tagged`, `user_followed`. Event lain (order/promo/status/`feed_encoding_failed`/moderasi admin) TETAP notification-message — jangan sentuh shape-nya.
- Capability gate per-token WAJIB: hanya token dengan `clientRenderVersion != null` yang menerima data-only. Token lama → shape lama. (Review A3 — mencegah notifikasi hilang di app lama.)
- FCM token disimpan di `PushSubscription` dengan `endpoint = "fcm:<token>"` (BUKAN model FcmToken); `p256dh`/`auth` NOT NULL diisi `""` untuk baris FCM. Register route: `app/api/push/subscribe-fcm/route.ts`.
- `lib/fcm.ts` TIDAK mengimpor `PushPayload` — ia punya `FcmPayload` sendiri (baris 79–102). Field baru ditambahkan ke KEDUA type (`FcmPayload` + `PushPayload` di `lib/push.ts`) agar caller tetap kompatibel struktural.
- Satu pesan FCM melayani Android+iOS sekaligus. Saat blok `notification` top-level dihapus (grup capable), WAJIB set `apns.payload.aps.alert = {title, body}` + `mutable-content: 1` supaya iOS tetap tampil. iOS TIDAK PERNAH data-only.
- Hardening (spec, WAJIB): dedup id deterministik dari `tag`; `DartPluginRegistrant.ensureInitialized()` + null-safe `RootIsolateToken` di background isolate; download avatar timeout ≤5s + downscale ±192px + gagal→notifikasi TETAP tampil tanpa largeIcon; TIDAK ada gating prefs di jalur render klien (backend sudah gate); channel background identik `_channelId='natalo_default'` (first-definition-wins); debounce tick 500ms di layar notifikasi; `_load()` tidak menaikkan tick.
- Test backend: node:test di `tests/` via `npx tsx --test tests/<file>.test.ts` (BUKAN jest). Flutter test: package `natalo_petshop_flutter`.
- Migration idempotent (`ADD COLUMN IF NOT EXISTS`). Kerja di branch `claude/notif-actor-avatar-push`; PR di akhir; JANGAN merge tanpa perintah user.

---

## File Structure

- Modify: `prisma/schema.prisma` (+ migration baru) — `PushSubscription.clientRenderVersion Int?`.
- Modify: `app/api/push/subscribe-fcm/route.ts` — terima + simpan `clientRender`.
- Modify: `lib/fcm.ts` — `FcmPayload` + `buildFcmMulticastMessage()` (diekstrak, pure, testable) + split per-kapabilitas di `sendFcmToUser`.
- Modify: `lib/push.ts` — `PushPayload` + field baru (passthrough).
- Modify: `lib/feed/notification-center.ts` — `RENDER_CLIENT_EVENTS` + `actor_avatar_url` + `renderClientSide`.
- Modify: `lib/social/notifications.ts` — `user_followed` ikut renderClientSide + avatar.
- Create: `tests/fcm-message-shape.test.ts`.
- Modify: `flutter_app/lib/services/push_notification_service.dart` — capability report, renderer data-only, `_circleAvatarBitmap`, `shouldDisplayLocally` baru.
- Create: `flutter_app/test/push_render_rules_test.dart`.
- Modify: `flutter_app/ios/NotificationService/NotificationService.swift` — attach `actor_avatar_url`.
- Modify: `flutter_app/lib/screens/notifications_screen.dart` — visual `feed_tagged`, listener tick + debounce + dispose.
- Modify: `flutter_app/lib/screens/feed_new_post_screen.dart` — hapus komentar stub basi (baris 221–223).

---

## Task 1: Prisma — kolom kapabilitas token

**Files:** Modify `prisma/schema.prisma` (model `PushSubscription`, baris ~858-865); Create `prisma/migrations/20260724100000_add_push_client_render/migration.sql`.

**Interfaces — Produces:** `PushSubscription.clientRenderVersion Int?` (null = app lama/belum lapor).

- [ ] **Step 1:** Di `model PushSubscription`, tambah setelah `userId String?`:
```prisma
  clientRenderVersion Int?
```
- [ ] **Step 2:** Migration:
```sql
ALTER TABLE "PushSubscription" ADD COLUMN IF NOT EXISTS "clientRenderVersion" INTEGER;
```
- [ ] **Step 3:** `npx prisma generate` (atau `validate` bila tanpa DATABASE_URL) → no errors.
- [ ] **Step 4:** Commit `feat(db): PushSubscription.clientRenderVersion utk capability gate push`.

## Task 2: Register route — simpan kapabilitas

**Files:** Modify `app/api/push/subscribe-fcm/route.ts` (handler POST, baris 13–43).

**Interfaces — Consumes:** kolom Task 1. **Produces:** body `{token, clientRender?}` → kolom terisi.

- [ ] **Step 1:** Setelah validasi token, parse:
```ts
  const clientRender =
    typeof body.clientRender === "number" && Number.isInteger(body.clientRender)
      ? body.clientRender
      : null;
```
- [ ] **Step 2:** Tambah `clientRenderVersion: clientRender,` ke KEDUA blok `update:` dan `create:` upsert. (Selalu tulis — app lama tanpa field → null, benar me-reset kapabilitas bila user downgrade.)
- [ ] **Step 3:** `npx tsc --noEmit` → no new errors. Commit `feat(api): subscribe-fcm terima clientRender capability`.

## Task 3: FCM shaping — ekstrak builder pure + split per-kapabilitas (TDD)

**Files:** Modify `lib/fcm.ts`; Modify `lib/push.ts` (type saja); Test `tests/fcm-message-shape.test.ts`.

**Interfaces — Produces:**
- `FcmPayload` + `renderClientSide?: boolean` + `actorAvatarUrl?: string | null`; `PushPayload` idem.
- `export function buildFcmMulticastMessage(payload: FcmPayload, opts: { clientRender: boolean }): object` — pure, testable: mengembalikan objek pesan TANPA `tokens`.
- `sendFcmToUser` membagi subscription jadi 2 grup dan mengirim ≤2 multicast.

- [ ] **Step 1 (failing test):** Create `tests/fcm-message-shape.test.ts`:
```ts
import assert from "node:assert/strict";
import test, { describe } from "node:test";
import { buildFcmMulticastMessage } from "@/lib/fcm";

const base = {
  title: "Budi menandai Anda dalam postingan",
  body: "Lihat postingannya sekarang.",
  url: "/feed/p1",
  tag: "feed-tagged-p1-u1",
  data: { type: "feed_tagged", url: "/feed/p1" },
  imageUrl: "https://cdn/img.jpg",
  prefCategory: "feed" as const,
};

describe("buildFcmMulticastMessage", () => {
  test("sosial + token capable → Android data-only, iOS alert+mutable", () => {
    const m: any = buildFcmMulticastMessage(
      { ...base, renderClientSide: true, actorAvatarUrl: "https://cdn/ava.jpg" },
      { clientRender: true },
    );
    assert.equal(m.notification, undefined);
    assert.equal(m.android.notification, undefined);
    assert.equal(m.android.priority, "high");
    assert.equal(m.data.title, base.title);
    assert.equal(m.data.actor_avatar_url, "https://cdn/ava.jpg");
    assert.deepEqual(m.apns.payload.aps.alert, { title: base.title, body: base.body });
    assert.equal(m.apns.payload.aps["mutable-content"], 1);
  });
  test("sosial + token LAMA → shape lama utuh (notification block ada)", () => {
    const m: any = buildFcmMulticastMessage(
      { ...base, renderClientSide: true, actorAvatarUrl: "https://cdn/ava.jpg" },
      { clientRender: false },
    );
    assert.equal(m.notification.title, base.title);
    assert.equal(m.android.notification.clickAction, "FCM_PLUGIN_ACTIVITY");
    assert.equal(m.apns.payload.aps.alert, undefined);
  });
  test("non-sosial → shape lama apapun kapabilitasnya", () => {
    const m: any = buildFcmMulticastMessage(base, { clientRender: true });
    assert.equal(m.notification.title, base.title);
    assert.equal(m.data.actor_avatar_url, undefined);
  });
});
```
- [ ] **Step 2:** `npx tsx --test tests/fcm-message-shape.test.ts` → FAIL (builder belum diexport).
- [ ] **Step 3:** Di `lib/fcm.ts`: tambah ke `FcmPayload`: `renderClientSide?: boolean;` + `actorAvatarUrl?: string | null;`. Ekstrak isi objek pesan (baris 150–208, TANPA `tokens`) menjadi:
```ts
export function buildFcmMulticastMessage(
  payload: FcmPayload,
  opts: { clientRender: boolean },
) {
  const dataPayload: Record<string, string> = {
    title: payload.title,
    body: payload.body,
    ...(payload.url ? { url: payload.url } : {}),
    ...(payload.tag ? { tag: payload.tag } : {}),
    ...(payload.data ?? {}),
  };
  const clientRender = payload.renderClientSide === true && opts.clientRender;
  if (clientRender && payload.actorAvatarUrl) {
    dataPayload.actor_avatar_url = payload.actorAvatarUrl;
  }
  if (clientRender) {
    // Android data-only: app render sendiri (avatar bulat). iOS TETAP alert
    // via aps.alert + mutable-content (iOS tidak pernah data-only) — spec §2.
    return {
      data: dataPayload,
      android: { priority: "high" as const },
      apns: {
        headers: { "apns-priority": "10", "apns-push-type": "alert" },
        payload: {
          aps: {
            alert: { title: payload.title, body: payload.body },
            sound: "default",
            badge: 1,
            "mutable-content": 1,
            ...(payload.category ? { category: payload.category } : {}),
          },
        },
        ...(payload.imageUrl ? { fcmOptions: { imageUrl: payload.imageUrl } } : {}),
      },
    };
  }
  return { /* shape LAMA persis: notification/android/apns spt baris 150–208 sekarang */ };
}
```
(Blok "shape LAMA" = pindahkan literal objek yang ada sekarang, tanpa perubahan.) Lalu `sendFcnToUser` → ganti: ambil `subs` DENGAN `select` tambahan `clientRenderVersion`, bagi:
```ts
  const wantsClientRender = payload.renderClientSide === true;
  const capable = wantsClientRender
    ? subs.filter((s) => s.clientRenderVersion != null)
    : [];
  const legacy = wantsClientRender
    ? subs.filter((s) => s.clientRenderVersion == null)
    : subs;
  const groups = [
    { subs: capable, clientRender: true },
    { subs: legacy, clientRender: false },
  ].filter((g) => g.subs.length > 0);
  for (const g of groups) {
    const res = await messaging.sendEachForMulticast({
      tokens: g.subs.map((s) => s.endpoint.replace(/^fcm:/, "")),
      ...buildFcmMulticastMessage(payload, { clientRender: g.clientRender }),
    });
    // invalid-token cleanup existing per grup (pakai g.subs utk mapping index)
  }
```
Di `lib/push.ts`: tambah `renderClientSide?: boolean;` + `actorAvatarUrl?: string | null;` ke `PushPayload` (passthrough — web push tak berubah perilaku).
- [ ] **Step 4:** Test PASS + `npx tsc --noEmit` bersih + `npm test` (pets/pet-care/push tests tetap hijau; 6 kegagalan vitest pre-existing boleh).
- [ ] **Step 5:** Commit `feat(push): FCM shaping per-kapabilitas (data-only sosial utk token capable)`.

## Task 4: Dispatcher — allowlist + actor avatar

**Files:** Modify `lib/feed/notification-center.ts`; Modify `lib/social/notifications.ts`.

**Interfaces — Consumes:** field Task 3. **Produces:** payload event sosial membawa `renderClientSide: true` + `actorAvatarUrl`.

- [ ] **Step 1:** Di `notification-center.ts`, atas file:
```ts
/** Event beraktor yang dirender klien (avatar bulat) — spec §2, review A2.
 *  JANGAN pakai kategori: feed_encoding_failed dkk harus tetap andal. */
const RENDER_CLIENT_EVENTS = new Set([
  "feed_new_comment",
  "feed_new_like",
  "feed_mention",
  "feed_tagged",
]);
```
Pada konstruksi `payload` (baris ~181-196) tambah:
```ts
      renderClientSide: RENDER_CLIENT_EVENTS.has(params.eventType),
      actorAvatarUrl: params.actor?.avatarUrl ?? null,
```
- [ ] **Step 2:** Di `lib/social/notifications.ts`, pada payload `user_followed` (dispatcher follow) tambah `renderClientSide: true` + `actorAvatarUrl` dari data aktor yang sudah ada (brand-safe helper yang sudah dipakai). `followed_user_posted` TIDAK (bukan interaksi personal beraktor-ke-kamu; biarkan notification-message).
- [ ] **Step 3:** `npx tsc --noEmit` bersih. Tambah 1 kasus di `tests/fcm-message-shape.test.ts` bila perlu meng-cover `user_followed`. Commit `feat(push): event sosial beraktor kirim renderClientSide + actor_avatar_url`.

## Task 5: Flutter — lapor kapabilitas saat register token

**Files:** Modify `flutter_app/lib/services/push_notification_service.dart` (registerWithServer, baris ~386-389).

- [ ] **Step 1:** Ganti body POST:
```dart
          await apiClient.postJson(
            '/api/push/subscribe-fcm',
            body: {'token': fcmToken, 'clientRender': 1},
          );
```
(`clientRender: 1` = versi protokol render-klien pertama; naikkan bila format berubah.)
- [ ] **Step 2:** `flutter analyze lib/services/push_notification_service.dart` bersih. Commit `feat(app): lapor kapabilitas client-render saat register token FCM`.

## Task 6: Flutter — renderer data-only + avatar bulat (TDD helper murni)

**Files:** Modify `flutter_app/lib/services/push_notification_service.dart`; Test `flutter_app/test/push_render_rules_test.dart`.

**Interfaces — Produces:**
- `static bool shouldRenderDataMessage({required bool hasNotificationPayload, required bool hasDataTitle})` → true hanya bila TANPA notification payload DAN ada `data['title']` (pesan sosial data-only). Menggantikan peran lama `hasNotificationPayload` di alur baru; `shouldDisplayLocally` lama tetap untuk pesan notification-message di foreground.
- `static int notificationIdFromTag(String? tag, int fallback)` → id deterministik: `tag == null ? fallback : tag.hashCode & 0x7fffffff`.
- `Future<void> renderDataMessage(RemoteMessage message)` — dipakai background handler + foreground.
- `_circleAvatarBitmap(String url)` — download ≤5s → decode → downscale ≤192 → crop lingkaran (`dart:ui`) → PNG bytes; null bila gagal (JANGAN throw keluar).

- [ ] **Step 1 (failing test):** Create `flutter_app/test/push_render_rules_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/push_notification_service.dart';

void main() {
  group('shouldRenderDataMessage', () {
    test('data-only sosial → render', () {
      expect(PushNotificationService.shouldRenderDataMessage(
        hasNotificationPayload: false, hasDataTitle: true), isTrue);
    });
    test('notification-message (order/promo) → JANGAN render (OS gambar)', () {
      expect(PushNotificationService.shouldRenderDataMessage(
        hasNotificationPayload: true, hasDataTitle: true), isFalse);
    });
    test('data tanpa title (silent/data lain) → jangan render', () {
      expect(PushNotificationService.shouldRenderDataMessage(
        hasNotificationPayload: false, hasDataTitle: false), isFalse);
    });
  });
  group('notificationIdFromTag', () {
    test('deterministik + non-negatif', () {
      final a = PushNotificationService.notificationIdFromTag('feed-tagged-p1-u1', 7);
      final b = PushNotificationService.notificationIdFromTag('feed-tagged-p1-u1', 9);
      expect(a, b);
      expect(a >= 0, isTrue);
    });
    test('null tag → fallback', () {
      expect(PushNotificationService.notificationIdFromTag(null, 42), 42);
    });
  });
}
```
- [ ] **Step 2:** Jalankan → FAIL. Lalu implement di service:
  - Kedua static helper di atas (`@visibleForTesting` tidak wajib — dipakai produksi juga).
  - `renderDataMessage(message)`: baca `data['title']/'body'/'url'/'tag'/'thumbnail_url'/'actor_avatar_url'`; `largeIcon` dari `_circleAvatarBitmap` (try/catch → null); `styleInformation` dari `_buildBigPictureStyle(thumbnail)` bila ada; `id = notificationIdFromTag(tag, message.hashCode)`; channel SAMA `_channelId` (parity); `payload: url` untuk tap-routing existing (`onDidReceiveNotificationResponse` → `_handleDeepLink`). TANPA cek prefs (backend sudah gate — spec Hardening).
  - `_circleAvatarBitmap`: reuse fetch `HttpClient` pola `_buildBigPictureStyle` (timeout 5s) → `ui.instantiateImageCodec(bytes, targetWidth: 192, targetHeight: 192)` → gambar ke canvas dgn `clipPath(Path()..addOval(...))` → `toByteData(format: ui.ImageByteFormat.png)`. Semua error → return null.
  - **Background handler** (baris 32–41): setelah `Firebase.initializeApp`, tambah:
```dart
  try {
    DartPluginRegistrant.ensureInitialized();
    final token = RootIsolateToken.instance;
    if (token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }
    if (PushNotificationService.shouldRenderDataMessage(
      hasNotificationPayload: message.notification != null,
      hasDataTitle: (message.data['title'] as String?)?.isNotEmpty == true,
    )) {
      await pushNotificationService.renderDataMessageInBackground(message);
    }
  } catch (_) {
    // Jangan crash isolate background — notifikasi lain tak boleh terganggu.
  }
```
  (`renderDataMessageInBackground` = init `FlutterLocalNotificationsPlugin` lokal isolate + channel `_channelId` identik + panggil renderer; bila init/plugin gagal → diamkan.)
  - **Foreground** (`_onForegroundMessage`): di awal, bila `shouldRenderDataMessage(...)` true → `await renderDataMessage(message); notificationRefreshTick.value++; return;` (jalur lama untuk notification-message tetap).
- [ ] **Step 3:** `flutter test test/push_render_rules_test.dart` PASS; `flutter analyze lib/services/push_notification_service.dart` bersih.
- [ ] **Step 4:** Commit `feat(app): render lokal push sosial data-only + avatar bulat largeIcon`.

## Task 7: Cold-start arbiter tap

**Files:** Modify `flutter_app/lib/services/push_notification_service.dart` (init, dekat `getInitialMessage` baris ~258-265).

- [ ] **Step 1:** Setelah cek `getInitialMessage`, tambah cek `getNotificationAppLaunchDetails`:
```dart
      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      final localPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          localPayload != null && localPayload.isNotEmpty) {
        launchedFromColdPush = true;
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          _handleDeepLink(localPayload);
        });
      }
```
  Arbiter: pesan sosial (app-rendered) TIDAK muncul di `getInitialMessage` (notifikasinya lokal), jadi dua sumber tak pernah tumpang-tindih untuk pesan yang sama; guard `launchedFromColdPush` cegah dobel bila keduanya ada di kasus aneh — bila `getInitialMessage` sudah menang, skip blok lokal.
- [ ] **Step 2:** `flutter analyze` file bersih. Commit `feat(app): cold-start tap routing utk notifikasi app-rendered`.

## Task 8: iOS NSE — lampirkan foto aktor

**Files:** Modify `flutter_app/ios/NotificationService/NotificationService.swift` (47 baris — lihat isi sekarang di laporan telusur).

- [ ] **Step 1:** Ganti isi `didReceive` (pertahankan guard + `serviceExtensionTimeWillExpire`):
```swift
    if let avatarUrlString = request.content.userInfo["actor_avatar_url"] as? String,
       let avatarUrl = URL(string: avatarUrlString) {
      let task = URLSession.shared.downloadTask(with: avatarUrl) { tempUrl, _, _ in
        defer { contentHandler(bestAttemptContent) }
        guard let tempUrl = tempUrl else { return }
        let target = FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString)
          .appendingPathExtension(avatarUrl.pathExtension.isEmpty ? "jpg" : avatarUrl.pathExtension)
        do {
          try FileManager.default.moveItem(at: tempUrl, to: target)
          let attachment = try UNNotificationAttachment(identifier: "actor-avatar", url: target)
          bestAttemptContent.attachments = [attachment]
        } catch {
          // Gagal attach → notifikasi tetap tampil polos (contentHandler di defer).
        }
      }
      task.resume()
      return
    }
    // Tanpa avatar → perilaku lama: Firebase helper attach fcm_options.image.
    FIRMessagingExtensionHelper().populateNotificationContent(
      bestAttemptContent, withContentHandler: contentHandler)
```
  (`UNNotificationAttachment` memindahkan file ke store internal — tak perlu cleanup manual; timeout NSE ditangani `serviceExtensionTimeWillExpire` yang sudah ada.)
- [ ] **Step 2:** Tidak bisa dikompilasi di Windows — verifikasi sintaks manual + device-verify nanti. Commit `feat(ios): NSE lampirkan foto aktor dari actor_avatar_url`.

## Task 9: In-app — visual "Ditandai" + real-time list + cleanup

**Files:** Modify `flutter_app/lib/screens/notifications_screen.dart`; Modify `flutter_app/lib/screens/feed_new_post_screen.dart`.

- [ ] **Step 1:** Di `_NotificationVisual.from()` SEBELUM case `feed_new_comment` (baris ~1865):
```dart
    if (ev == 'feed_tagged') {
      return const _NotificationVisual(
        icon: Icons.person_pin_rounded,
        color: NataloColors.primary,
        label: 'Ditandai',
      );
    }
```
  (Import NataloColors bila belum; bila file pakai literal Color, pakai `Color(0xFF1E5FBF)` konsisten gaya file.) Verifikasi `feed_tagged` masuk tab Aktivitas (filter feed match via haystack `type=feed`); bila tidak, tambah match eksplisit `item.eventType == 'feed_tagged'` di `_NotificationFilter.feed.matches`.
- [ ] **Step 2:** Real-time (#2) di `_NotificationsScreenState`:
```dart
  Timer? _tickDebounce;
  late final VoidCallback _tickListener = () {
    _tickDebounce?.cancel();
    _tickDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _load(silent: true);
    });
  };

  @override
  void initState() {
    super.initState();
    _load();
    pushNotificationService.notificationRefreshTick.addListener(_tickListener);
  }

  @override
  void dispose() {
    pushNotificationService.notificationRefreshTick.removeListener(_tickListener);
    _tickDebounce?.cancel();
    super.dispose();
  }
```
  (`dispose()` BELUM ada di state ini — tambah baru. `_load(silent:true)` sudah tanpa spinner; list pendek (cap 50) jadi anchor-scroll tidak kritis, tapi JANGAN reset scroll controller.) Import `dart:async` + service bila belum.
- [ ] **Step 3:** Hapus 2 baris komentar basi di `feed_new_post_screen.dart` baris 222–223 ("Kedua layar saat ini masih stub … sampai Task 9/10 diisi.") — sisakan baris 221 ("Buka layar penempatan Tag People — foto atau video.").
- [ ] **Step 4:** `flutter analyze` kedua file bersih; `flutter test test/notifications_redesign_widget_test.dart` (suite layar notif existing) tetap hijau. Commit `feat(app): visual Ditandai + auto-refresh layar notifikasi + hapus komentar stub`.

## Task 10: Verifikasi penuh + PR

- [ ] **Step 1:** Backend: `npx tsx --test tests/fcm-message-shape.test.ts tests/push-notifications.test.ts tests/feed-publish-push.test.ts` hijau; `npx tsc --noEmit` (hanya 6 error vitest pre-existing); `npm test` 458+ pass.
- [ ] **Step 2:** Flutter: `flutter analyze` 0 issue di file yang disentuh; `flutter test` — kegagalan hanya 6 pre-existing yang sudah terdokumentasi.
- [ ] **Step 3:** Push branch + `gh pr create` — body merangkum: capability gate (A3), scope sosial-only (D2), allowlist (A2), hardening, matriks device-verify dari spec (Android fg/bg/terminated sosial+order, iOS attach, prefs backend-gate, in-app). Catat: NSE tak terkompilasi di Windows → wajib build Xcode; migration apply di deploy berikutnya; TestFlight/APK baru untuk device-verify.
- [ ] **Step 4 (catatan, jangan auto-run):** setelah merge: apply migration, rilis app, jalankan matriks device-verify spec.

---

## Self-Review

- Spec coverage: §1 data contract → T3/T4; §2 shaping → T3; §2b capability gate → T1/T2/T3/T5; §3 Android render → T6/T7; §4 NSE → T8; §5 in-app → T9; §6 realtime → T9; §7 cleanup → T9; Hardening semua terpetakan (dedup id T6, isolate init T6, timeout/fallback T6, no-client-gating T6, payload iOS T3, arbiter T7, channel parity T6, kuota→tanpa perubahan volume, debounce T9). ✓
- Konsistensi type: `renderClientSide`/`actorAvatarUrl` identik di FcmPayload/PushPayload/call site; `shouldRenderDataMessage`/`notificationIdFromTag`/`renderDataMessage` konsisten T6↔T7. ✓
- Catatan sadar: `RENDER_CLIENT_EVENTS` di notification-center hanya 4 event feed; `user_followed` di-set manual di social/notifications.ts (T4 Step 2) karena melalui helper social, bukan feed — total tetap 5 sesuai allowlist.
