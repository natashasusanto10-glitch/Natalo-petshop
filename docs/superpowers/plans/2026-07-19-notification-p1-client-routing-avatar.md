# P1 — Client: Routing Pesanan Presisi + Avatar Follow ke Kiri — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development atau executing-plans. Steps pakai checkbox (`- [ ]`).

**Goal:** (P1a) tap notif pesanan → buka detail pesanan itu (bukan daftar); (P1b) notif follow tampilkan foto follower di KIRI (identitas), bukan di kanan (slot konten).

**Architecture:** Semua di client Flutter `flutter_app/lib/screens/notifications_screen.dart`. Routing pesanan meniru pola `_openFeedPostInApp` (spinner → fetch-by-id → push, fallback). Avatar follow: `_IdentityAvatar` dapat param `avatarUrl` opsional; `NotificationRow` mendeteksi follow dan mengarahkan `imageUrl` (foto follower) ke kiri + menyembunyikan thumbnail kanan.

**Tech Stack:** Flutter, `flutter_test`.

## Global Constraints

- Branch dari `origin/main` (sudah memuat #189 + P0). Worktree `claude/notification-p1-client` sudah di sana.
- Bobot font hanya w400/w600. Warna dari token `NataloColors.*`.
- JANGAN ubah cabang routing lain (`_openFeedPostInApp`, review, follow-profile, promo, voucher, refund, loyalty, cart) — hanya SISIPKAN cabang pesanan-spesifik sebelum cabang daftar pesanan.
- Jalankan test dari `flutter_app/`. Tiap task: `flutter analyze` bersih di file + test hijau → commit.

---

### Task 1: Helper murni `extractOrderNumber` + `extractOrderTrackingToken`

**Files:**
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (tambah 2 fungsi top-level `@visibleForTesting`, dekat `_notificationHaystack`)
- Test: `flutter_app/test/notification_order_routing_test.dart` (baru)

**Interfaces:**
- Produces: `String? extractOrderNumber(String? url)` — kembalikan `ORD-...` pertama dari url (regex `RegExp(r'ORD-[A-Z0-9-]+', caseSensitive: false)`), else null. `String? extractOrderTrackingToken(String? url)` — nilai query `token`, else null.

- [ ] **Step 1: Tulis test yang gagal**

Buat `flutter_app/test/notification_order_routing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/notifications_screen.dart';

void main() {
  group('extractOrderNumber', () {
    test('ambil ORD- dari path /pesanan/{orderNumber}', () {
      expect(extractOrderNumber('/pesanan/ORD-20260719-abc'), 'ORD-20260719-abc');
    });
    test('abaikan query & suffix review', () {
      expect(extractOrderNumber('/pesanan/ORD-123?review=1'), 'ORD-123');
    });
    test('null saat tak ada ORD-', () {
      expect(extractOrderNumber('/member/orders'), isNull);
      expect(extractOrderNumber(null), isNull);
      expect(extractOrderNumber(''), isNull);
    });
  });

  group('extractOrderTrackingToken', () {
    test('ambil token dari query', () {
      expect(extractOrderTrackingToken('/pesanan/ORD-1?token=xyz'), 'xyz');
    });
    test('null saat tak ada token', () {
      expect(extractOrderTrackingToken('/pesanan/ORD-1'), isNull);
      expect(extractOrderTrackingToken(null), isNull);
    });
  });
}
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/notification_order_routing_test.dart`
Expected: FAIL — `extractOrderNumber` tidak terdefinisi.

- [ ] **Step 3: Implementasi helper**

Di `lib/screens/notifications_screen.dart`, tambahkan setelah `_notificationHaystack` (top-level):

```dart
/// Ekstrak nomor pesanan (`ORD-...`) dari url notifikasi pesanan
/// (`/pesanan/{orderNumber}`, mirror server `extractOrderNumberFromNotification`).
@visibleForTesting
String? extractOrderNumber(String? url) {
  if (url == null || url.isEmpty) return null;
  final match = RegExp(r'ORD-[A-Z0-9-]+', caseSensitive: false).firstMatch(url);
  return match?.group(0);
}

/// Ekstrak trackingToken dari query `?token=` (akses order guest/non-login).
@visibleForTesting
String? extractOrderTrackingToken(String? url) {
  if (url == null || url.isEmpty) return null;
  final token = Uri.tryParse(url)?.queryParameters['token']?.trim();
  return (token == null || token.isEmpty) ? null : token;
}
```

- [ ] **Step 4: Jalankan test + analyze**

Run: `cd flutter_app && flutter test test/notification_order_routing_test.dart && flutter analyze lib/screens/notifications_screen.dart`
Expected: PASS; `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/notifications_screen.dart flutter_app/test/notification_order_routing_test.dart
git commit -m "feat(notifikasi): helper extractOrderNumber + trackingToken"
```

---

### Task 2: Routing pesanan → detail pesanan itu (`_openOrderInApp`)

**Files:**
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (import `order_service`; tambah `_openOrderInApp`; sisipkan cabang di `_navigateForNotification`)

**Interfaces:**
- Consumes: `extractOrderNumber`/`extractOrderTrackingToken` (Task 1); `orderService.fetchOrderDetail(orderNumber, trackingToken:)` (`lib/services/order_service.dart:14`) → `OrderSummary`; rute `/member/order-detail` (arg `OrderSummary`, `main.dart:426`).

- [ ] **Step 1: Tambah import**

Di daftar import `lib/screens/notifications_screen.dart`, tambahkan:

```dart
import '../services/order_service.dart';
```

- [ ] **Step 2: Tambah `_openOrderInApp` (mirror `_openFeedPostInApp`)**

Di dalam `_NotificationsScreenState`, dekat `_openFeedPostInApp`:

```dart
  /// Fetch pesanan by orderNumber lalu buka detail pesanan itu. Spinner saat
  /// fetch; fallback ke daftar pesanan kalau gagal (pesanan tidak ada / token
  /// invalid). Mirror pola _openFeedPostInApp + deep_link _openOrderByNumber.
  Future<void> _openOrderInApp(String orderNumber, String? trackingToken) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );

    OrderSummary? order;
    try {
      order = await orderService.fetchOrderDetail(
        orderNumber,
        trackingToken: trackingToken,
      );
    } catch (_) {
      order = null;
    }

    rootNav.pop(); // tutup loading dialog
    if (!mounted) return;

    if (order == null) {
      await Navigator.pushNamed(context, '/member/orders');
      return;
    }
    await Navigator.pushNamed(context, '/member/order-detail', arguments: order);
  }
```

- [ ] **Step 3: Sisipkan cabang di `_navigateForNotification`**

Tepat SEBELUM blok daftar pesanan yang ada (`if (url.contains('/member/orders') || ... haystack.contains('pesanan') ...)`), sisipkan:

```dart
    // Pesanan spesifik: url `/pesanan/{orderNumber}` → buka detail pesanan itu
    // (bukan daftar). Fallback ke daftar di dalam _openOrderInApp bila fetch gagal.
    final orderNumber = extractOrderNumber(url);
    if (orderNumber != null) {
      await _openOrderInApp(orderNumber, extractOrderTrackingToken(url));
      return;
    }
```

(Blok daftar pesanan lama TETAP sebagai fallback untuk notif pesanan tanpa `ORD-` di url, mis. yang cuma match `haystack.contains('pesanan')`.)

- [ ] **Step 4: Analyze + test regresi**

Run: `cd flutter_app && flutter analyze lib/screens/notifications_screen.dart && flutter test test/notification_order_routing_test.dart test/notifications_redesign_widget_test.dart test/notifications_redesign_logic_test.dart`
Expected: `No issues found!`; semua PASS. (Navigasi+fetch diverifikasi manual — pola sama dgn `_openFeedPostInApp` yang juga tak di-unit-test; seam service singleton.)

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/notifications_screen.dart
git commit -m "feat(notifikasi): routing pesanan buka detail pesanan itu (fetch by orderNumber)"
```

---

### Task 3: Avatar follow ke kiri (P1b)

**Files:**
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (`_IdentityAvatar` + `NotificationRow`)
- Test: `flutter_app/test/notifications_redesign_widget_test.dart` (tambah group)

**Interfaces:**
- `_IdentityAvatar` dapat param baru `final String? avatarUrl;` — bila non-null/non-empty → render foto lingkaran (network, fallback ke core saat error), keyed `ValueKey('notification-actor-avatar')`.
- `NotificationRow`: follow (`eventType == 'user_followed'`) → `imageUrl` diarahkan ke avatar kiri; thumbnail kanan disembunyikan untuk follow.

- [ ] **Step 1: Tulis widget test yang gagal**

Tambahkan di `test/notifications_redesign_widget_test.dart` (pola `_pumpRow` sudah ada di file itu; buat notif follow):

```dart
  group('NotificationRow follow avatar', () {
    AppNotification followNotif() => AppNotification.fromApiJson({
          'id': 'f1',
          'title': 'Andi mulai mengikuti kamu',
          'body': '',
          'type': 'info',
          'eventType': 'user_followed',
          'imageUrl': 'https://cdn/andi.jpg',
          'createdAt':
              DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
          'read': false,
        });

    testWidgets('follow → avatar aktor di KIRI, thumbnail kanan disembunyikan',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(notification: followNotif(), onTap: () {}),
        ),
      ));
      expect(find.byKey(const ValueKey('notification-actor-avatar')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('notification-thumb')), findsNothing,
          reason: 'foto follower tampil di kiri, bukan slot thumbnail kanan');
    });
  });
```

- [ ] **Step 2: Jalankan test, pastikan GAGAL**

Run: `cd flutter_app && flutter test test/notifications_redesign_widget_test.dart --plain-name "follow"`
Expected: FAIL — key `notification-actor-avatar` tidak ada (avatar follow masih di kanan / brand icon).

- [ ] **Step 3: Tambah `avatarUrl` ke `_IdentityAvatar`**

Ubah `_IdentityAvatar`:

```dart
class _IdentityAvatar extends StatelessWidget {
  final _NotificationVisual visual;
  final bool brandIdentity;
  final String? avatarUrl;

  const _IdentityAvatar({
    required this.visual,
    required this.brandIdentity,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    if (url != null && url.trim().isNotEmpty) {
      return Container(
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
    }
    // ... sisa kode brand/icon EKSISTING tidak berubah ...
```

(Biarkan blok `final core = brandIdentity ? ... : ...` dan badge yang sudah ada; hanya tambahkan cabang avatar di atasnya.)

- [ ] **Step 4: Deteksi follow di `NotificationRow`**

Di `NotificationRow.build`, setelah `final imageUrl = notification.imageUrl;`:

```dart
    final isFollow =
        notification.eventType?.toLowerCase() == 'user_followed';
    final actorAvatarUrl = isFollow ? imageUrl : null;
```

Ubah pemanggilan `_IdentityAvatar`:

```dart
                _IdentityAvatar(
                  visual: visual,
                  brandIdentity: _isBrandIdentity,
                  avatarUrl: actorAvatarUrl,
                ),
```

Ubah kondisi thumbnail kanan supaya follow tidak menampilkannya:

```dart
                if (imageUrl != null &&
                    imageUrl.trim().isNotEmpty &&
                    !isFollow) ...[
```

- [ ] **Step 5: Jalankan test + analyze**

Run: `cd flutter_app && flutter test test/notifications_redesign_widget_test.dart && flutter analyze lib/screens/notifications_screen.dart`
Expected: PASS semua (termasuk test lama: non-follow ber-imageUrl tetap tampil thumbnail kanan); `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/notifications_screen.dart flutter_app/test/notifications_redesign_widget_test.dart
git commit -m "feat(notifikasi): notif follow tampilkan foto follower di kiri (bukan thumbnail kanan)"
```

---

### Task 4: Regresi penuh + analyze

- [ ] **Step 1: Suite notifikasi**

Run:
```bash
cd flutter_app && flutter test \
  test/notification_order_routing_test.dart \
  test/notifications_redesign_widget_test.dart \
  test/notifications_redesign_logic_test.dart \
  test/models/app_notification_image_url_test.dart \
  && flutter analyze lib/screens/notifications_screen.dart
```
Expected: `All tests passed!`; `No issues found!`

- [ ] **Step 2: Commit penutup (bila ada penyesuaian)** — lewati bila bersih.

---

## Verifikasi manual (device — di luar test)

- Notif pesanan (dikirim/dibayar) → tap → buka **detail pesanan itu** (spinner sebentar), fallback ke daftar bila pesanan tak ada.
- Notif follow → foto follower tampil di **kiri** sebagai avatar bulat; tak ada thumbnail di kanan; tap → profil follower.
- Notif feed/komentar (punya thumbnail post) → thumbnail tetap di kanan seperti sebelumnya.

## Catatan

P1b heuristik `eventType=='user_followed'` bersifat jembatan; P2 (avatar aktor terstruktur `actorAvatarUrl`) akan menggantikannya + memperluas ke komentar/mention/like. Lihat spec `2026-07-19-notification-routing-and-actor-avatar-design.md`.
</content>
