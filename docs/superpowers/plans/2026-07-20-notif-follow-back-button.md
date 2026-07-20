# Notifikasi — Tombol "Follow Back" Inline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notif follow menampilkan pill "Ikuti"/"Mengikuti" interaktif (follow-balik tanpa keluar layar), menggantikan pill "Lihat Profil" yang redundan.

**Architecture:** Client-only Flutter, satu file layar + satu file test. Widget `_NotificationFollowBackPill` (StatefulWidget, state lokal idle/loading/following) memakai `profileService.fetchPublicProfile` (resolusi username→id + isFollowing sekaligus) lalu `followService.follow`. Seam injeksi opsional di `NotificationRow` untuk testability (global final tak bisa di-swap).

**Tech Stack:** Flutter (`flutter analyze`, `flutter test`).

## Global Constraints

- Pill "Ikuti" HANYA dirender bila `eventType == 'user_followed'` DAN `extractProfileUsername(notification.url) != null`; selain itu (termasuk follower tanpa username, url `/notifications`) → pill generik existing tak berubah.
- Cabang follow **menggantikan seluruh** blok pill generik `if (ctaLabel != null)` — bukan menambah pill kedua.
- `fetchPublicProfile` return `PublicProfileResult` → akses `result.profile.id` / `result.profile.isFollowing` / `result.profile.isOwner`.
- `if (!mounted) return;` WAJIB setelah SETIAP await di pill.
- Guard `result.profile.isOwner == true` → kembali idle diam-diam (jangan follow diri sendiri).
- `FollowSessionChangedException` → idle tanpa snackbar. `ApiException`/error lain → idle + snackbar "Gagal mengikuti. Coba lagi."
- Pill sengaja TIDAK memanggil `setFollowOverride` pre-await (state lokal; `follow()` internal sudah confirm/rollback override).
- Gaya pill identik CTA existing: bg `NataloColors.primarySoft`, teks `NataloColors.primary`, radius 999, padding h14 v6, fontSize 12 w600.
- Tanpa perubahan backend/migration.

---

### Task 1: Pill follow-back + seam injeksi + test

**Files:**
- Modify: `flutter_app/lib/screens/notifications_screen.dart` (`NotificationRow` :861-869, blok pill :961-983, promosikan `_extractProfileUsername` :503-510 ke top-level, widget baru `_NotificationFollowBackPill`)
- Test: `flutter_app/test/notifications_redesign_widget_test.dart`

**Interfaces:**
- Consumes: `profileService`/`ProfileService.fetchPublicProfile({required username, limit})` → `PublicProfileResult{profile: PublicProfile{id, isFollowing, isOwner}}` (`services/profile_service.dart:28,85-95,97`); `followService`/`FollowService.follow(userId)` + `FollowService.forTesting({required FollowMutationRequest mutationRequest})` + `FollowSessionChangedException` (`services/follow_service.dart:174,187,203,418`); `AppHaptics.tap()`.
- Produces: `extractProfileUsername(String?)` top-level (`@visibleForTesting`), `NotificationRow` param baru `followService`/`profileFetcher`, key `ValueKey('notification-follow-back-pill')`.

- [ ] **Step 1: Promosikan _extractProfileUsername ke top-level**

Method `_extractProfileUsername` saat ini ada DI DALAM State class layar (`:503-510`) — pill/`NotificationRow` tak bisa memanggilnya. Pindahkan jadi fungsi top-level (dekat `extractOrderNumber` yang sudah top-level + `@visibleForTesting`):

```dart
/// Extract username dari URL pattern `/u/{username}` (deep link
/// public profile). Lowercase karena DB username always lowercase.
/// Top-level: dipakai routing layar DAN gate pill follow-back.
@visibleForTesting
String? extractProfileUsername(String? url) {
  if (url == null || url.isEmpty) return null;
  final match = RegExp(r'/u/([^/?#]+)').firstMatch(url);
  if (match == null) return null;
  final username = match.group(1)?.trim().toLowerCase() ?? '';
  if (username.isEmpty) return null;
  return Uri.decodeComponent(username);
}
```

Hapus method lama di State class; ganti pemanggil existing (`:155` `_extractProfileUsername(item.url)`) menjadi `extractProfileUsername(item.url)`.

- [ ] **Step 2: Tambah import + typedef + param injeksi di NotificationRow**

Tambah import di atas file:

```dart
import '../services/follow_service.dart';
import '../services/profile_service.dart';
```

Tepat sebelum `class NotificationRow` tambahkan typedef fetcher (seam test ProfileService tanpa mengubah service-nya):

```dart
/// Seam test: fetch profil publik by username. Default produksi memakai
/// [profileService.fetchPublicProfile]; widget test menyuntik fake.
typedef PublicProfileFetcher = Future<PublicProfileResult> Function(
    String username);
```

Ubah `NotificationRow` (`:861-869`):

```dart
class NotificationRow extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final FollowService? followService;
  final PublicProfileFetcher? profileFetcher;

  const NotificationRow({
    super.key,
    required this.notification,
    required this.onTap,
    this.followService,
    this.profileFetcher,
  });
```

- [ ] **Step 3: Ganti blok pill utk notif follow ber-username**

Di `build`, sebelum `Row(children: [ if (ctaLabel != null) ...` (blok `:960-983`), hitung:

```dart
    final followBackUsername =
        notification.eventType?.toLowerCase() == 'user_followed'
            ? extractProfileUsername(notification.url)
            : null;
```

Lalu ganti blok pill (`if (ctaLabel != null) ...[ InkWell(...), SizedBox(width: 10) ]`) menjadi:

```dart
                          if (followBackUsername != null) ...[
                            _NotificationFollowBackPill(
                              username: followBackUsername,
                              followService: followService,
                              profileFetcher: profileFetcher,
                            ),
                            const SizedBox(width: 10),
                          ] else if (ctaLabel != null) ...[
                            InkWell(
                              onTap: onTap,
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: NataloColors.primarySoft,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  ctaLabel,
                                  style: const TextStyle(
                                    color: NataloColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
```

(Follower tanpa username → `followBackUsername` null → jatuh ke cabang `ctaLabel` existing "Lihat Profil" — fallback sesuai spec.)

- [ ] **Step 4: Tulis widget _NotificationFollowBackPill**

Tambahkan setelah class `NotificationRow` (sebelum `StackedActorAvatars`):

```dart
enum _FollowBackState { idle, loading, following }

/// Pill follow-balik inline utk notif follow — tap men-follow tanpa keluar
/// layar (ala IG "Follow back"). State lokal saja: kalau widget di-dispose
/// (scroll jauh) lalu dibangun ulang, kembali "Ikuti" — dapat diterima.
/// SENGAJA tidak setFollowOverride pre-await (bukan optimistic lintas-widget;
/// follow() internal sudah confirm saat sukses + rollback override saat gagal).
class _NotificationFollowBackPill extends StatefulWidget {
  final String username;
  final FollowService? followService;
  final PublicProfileFetcher? profileFetcher;

  const _NotificationFollowBackPill({
    required this.username,
    this.followService,
    this.profileFetcher,
  });

  @override
  State<_NotificationFollowBackPill> createState() =>
      _NotificationFollowBackPillState();
}

class _NotificationFollowBackPillState
    extends State<_NotificationFollowBackPill> {
  _FollowBackState _state = _FollowBackState.idle;

  Future<void> _handleTap() async {
    if (_state != _FollowBackState.idle) return;
    AppHaptics.tap();
    setState(() => _state = _FollowBackState.loading);
    try {
      final fetch = widget.profileFetcher ??
          (String u) => profileService.fetchPublicProfile(
                username: u,
                limit: 1,
              );
      final result = await fetch(widget.username);
      if (!mounted) return;
      if (result.profile.isOwner) {
        setState(() => _state = _FollowBackState.idle);
        return;
      }
      if (result.profile.isFollowing) {
        setState(() => _state = _FollowBackState.following);
        return;
      }
      final service = widget.followService ?? followService;
      await service.follow(result.profile.id);
      if (!mounted) return;
      setState(() => _state = _FollowBackState.following);
    } on FollowSessionChangedException {
      if (mounted) setState(() => _state = _FollowBackState.idle);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _FollowBackState.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengikuti. Coba lagi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_state) {
      _FollowBackState.following => 'Mengikuti',
      _ => 'Ikuti',
    };
    return InkWell(
      key: const ValueKey('notification-follow-back-pill'),
      onTap: _state == _FollowBackState.idle ? _handleTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: NataloColors.primarySoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: _state == _FollowBackState.loading
            ? const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: NataloColors.primary,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: NataloColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
```

Catatan tipe: `widget.followService ?? followService` — nama global `followService` (`follow_service.dart:418`) tak bentrok dengan field karena field diakses via `widget.`.

- [ ] **Step 5: Jalankan analyze**

Run: `cd flutter_app && flutter analyze lib/screens/notifications_screen.dart`
Expected: "No issues found" atau hanya 2 info `library_private_types_in_public_api` pre-existing. (Param `FollowService?` di `NotificationRow` publik memakai tipe publik — tak menambah info baru.)

- [ ] **Step 6: Tulis widget test**

Di `flutter_app/test/notifications_redesign_widget_test.dart`, tambah import:

```dart
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/services/follow_service.dart';
import 'package:natalo_petshop_flutter/services/profile_service.dart';
```

Tambahkan grup dalam `main()`:

```dart
  group('pill follow-back', () {
    AppNotification followNotif({String url = '/u/andi'}) =>
        AppNotification.fromApiJson({
          'id': 'fb1', 'title': 'andi mulai mengikuti kamu', 'body': '',
          'type': 'info', 'eventType': 'user_followed', 'url': url,
          'ctaLabel': 'Lihat Profil',
          'createdAt': DateTime.now().toIso8601String(), 'read': false,
        });

    PublicProfileResult profileResult({
      bool isFollowing = false,
      bool isOwner = false,
    }) =>
        PublicProfileResult(
          profile: PublicProfile.fromJson(
            {'id': 'u-andi', 'name': 'Andi', 'username': 'andi'},
            isOwner: isOwner,
          ).copyWith(isFollowing: isFollowing),
          posts: const [],
        );

    testWidgets('notif follow ber-username → pill Ikuti; tap TIDAK navigasi baris',
        (tester) async {
      var rowTapped = false;
      var followCalls = 0;
      final fakeFollow = FollowService.forTesting(
        mutationRequest: (userId, following) async {
          followCalls++;
          return {'isFollowing': true, 'followersCount': 1, 'followingCount': 0};
        },
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(
            notification: followNotif(),
            onTap: () => rowTapped = true,
            followService: fakeFollow,
            profileFetcher: (_) async => profileResult(),
          ),
        ),
      ));
      expect(find.text('Ikuti'), findsOneWidget);
      expect(find.text('Lihat Profil'), findsNothing);

      await tester.tap(
          find.byKey(const ValueKey('notification-follow-back-pill')));
      await tester.pumpAndSettle();
      expect(rowTapped, isFalse);
      expect(followCalls, 1);
      expect(find.text('Mengikuti'), findsOneWidget);
    });

    testWidgets('sudah follow duluan → langsung Mengikuti tanpa panggil follow',
        (tester) async {
      var followCalls = 0;
      final fakeFollow = FollowService.forTesting(
        mutationRequest: (userId, following) async {
          followCalls++;
          return {'isFollowing': true};
        },
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(
            notification: followNotif(),
            onTap: () {},
            followService: fakeFollow,
            profileFetcher: (_) async => profileResult(isFollowing: true),
          ),
        ),
      ));
      await tester.tap(
          find.byKey(const ValueKey('notification-follow-back-pill')));
      await tester.pumpAndSettle();
      expect(followCalls, 0);
      expect(find.text('Mengikuti'), findsOneWidget);
    });

    testWidgets('gagal follow → balik Ikuti + snackbar', (tester) async {
      final fakeFollow = FollowService.forTesting(
        mutationRequest: (userId, following) async =>
            throw const ApiException('boom'),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(
            notification: followNotif(),
            onTap: () {},
            followService: fakeFollow,
            profileFetcher: (_) async => profileResult(),
          ),
        ),
      ));
      await tester.tap(
          find.byKey(const ValueKey('notification-follow-back-pill')));
      await tester.pumpAndSettle();
      expect(find.text('Ikuti'), findsOneWidget);
      expect(find.text('Gagal mengikuti. Coba lagi.'), findsOneWidget);
    });

    testWidgets('follower TANPA username (url /notifications) → fallback pill generik',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NotificationRow(
            notification: followNotif(url: '/notifications'),
            onTap: () {},
          ),
        ),
      ));
      expect(find.text('Lihat Profil'), findsOneWidget);
      expect(find.byKey(const ValueKey('notification-follow-back-pill')),
          findsNothing);
    });
  });
```

Catatan: `ApiException` diekspor dari `services/api_client.dart` via `profile_service.dart`/`follow_service.dart` — bila analyzer minta, tambah import `package:natalo_petshop_flutter/services/api_client.dart`. Bila `PublicProfile.fromJson`/`copyWith` signature beda dari asumsi (cek `models/public_profile.dart:97,147`), sesuaikan konstruksi fake seperlunya — nilai yang wajib: `id`, `isFollowing`, `isOwner`.

- [ ] **Step 7: Jalankan test — pastikan LULUS**

Run: `cd flutter_app && flutter test test/notifications_redesign_widget_test.dart`
Expected: semua PASS (existing + 4 baru).

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/screens/notifications_screen.dart flutter_app/test/notifications_redesign_widget_test.dart
git commit -m "feat(notifikasi): pill follow-back inline (Ikuti/Mengikuti) di notif follow"
```

---

## Self-Review

**Spec coverage:** gate username (fallback generik) ✅ S3; ganti-seluruh-blok bukan pill kedua ✅ S3; `result.profile.*` ✅ S4; mounted checks ✅ S4; guard isOwner ✅ S4; sudah-follow→Mengikuti tanpa API ✅ S4+test; error→idle+snackbar ✅ S4+test; FollowSessionChangedException senyap ✅ S4; skip setFollowOverride pre-await (dikomentari) ✅ S4; seam injeksi (blocker review #8) ✅ S2+S6; acceptance 1-6 tercakup.

**Placeholder scan:** bersih — satu penyesuaian kondisional (signature `PublicProfile.fromJson`) diberi instruksi konkret + lokasi file, bukan TBD.

**Type consistency:** `PublicProfileFetcher(String) → Future<PublicProfileResult>` konsisten S2↔S4↔S6; `FollowService.forTesting({required FollowMutationRequest mutationRequest})` cocok `follow_service.dart:187`; `extractProfileUsername` top-level dipakai S3 + caller lama S1; key `notification-follow-back-pill` konsisten S4↔S6.

**Catatan deploy:** client-only, butuh rilis app Flutter. Satu task — satu siklus test penuh.
