# Notifikasi — Tombol "Follow Back" Inline

**Date:** 2026-07-20
**Scope:** Client Flutter (`flutter_app/lib/screens/notifications_screen.dart`) — **tanpa perubahan backend**.
**Status:** Draft for review
**Depends on:** Redesign notifikasi (#189), avatar/thumbnail polish (#200), ikon kategori (#201), lencana like + avatar netral (#203/#204).

## Latar

Studi pola IG (item C dari sesi lalu): notifikasi follow di IG punya tombol "Follow back" inline — tap langsung follow-balik tanpa keluar dari layar notifikasi. Audit kode mengonfirmasi **semua yang dibutuhkan sudah ada**:

- API follow: `POST/DELETE /social/users/{userId}/follow`, sudah dibungkus `FollowService` (`flutter_app/lib/services/follow_service.dart:418`, instance singleton `followService`) — dipakai `post_likers_sheet.dart:141-142` dgn pola optimistic-update + rollback yang matang (coalescing tap ganda, `FollowSessionChangedException`, `setFollowOverride`).
- Resolusi username→userId + status follow saat ini: `ProfileService.fetchPublicProfile({username})` (`flutter_app/lib/services/profile_service.dart:27-60`) memanggil `GET /api/u/{username}` yang **sudah** mengembalikan `user.id` **dan** `isFollowing` dalam satu response (`app/api/u/[username]/route.ts:272,292`).
- Username aktor sudah bisa diekstrak dari `item.url` via helper existing `_extractProfileUsername` (dipakai routing follow yang sudah ada).
- Notif follow **sudah** punya slot CTA pill: `ctaLabel: "Lihat Profil"` (`lib/social/notifications.ts:113`), tapi ini **redundan** — tap di bagian baris mana pun (bukan cuma pill) sudah navigasi ke profil via `_navigateForNotification`, karena CTA pill hari ini pakai `onTap` yang SAMA dengan `onTap` baris (`notifications_screen.dart:962`, `InkWell(onTap: onTap, ...)`).

**Kesimpulan: fitur ini 100% client-only.** Tidak ada endpoint baru, tidak ada migration.

## Desain

**Ganti isi pill CTA khusus notif follow** (`eventType == 'user_followed'`): dari teks statis "Lihat Profil" (yang cuma navigasi) menjadi **widget interaktif** `"Ikuti"` / `"Mengikuti"` yang melakukan aksi follow, BUKAN navigasi. Tap di bagian baris lain (di luar pill) tetap membuka profil seperti sekarang (tak berubah).

**Widget baru:** `_NotificationFollowBackPill` (StatefulWidget kecil, satu file `notifications_screen.dart`) menggantikan blok pill generik (`:961-981`) KHUSUS saat `notification.eventType == 'user_followed'`; untuk semua notif lain, blok pill generik existing tetap dipakai apa adanya.

**State widget:** `idle` ("Ikuti") → tap → `loading` (spinner kecil, gaya sama dgn pill: latar `NataloColors.primarySoft`, ukuran pill tak berubah) → `following` ("Mengikuti", non-tappable) ATAU balik ke `idle` + `ScaffoldMessenger` snackbar error singkat ("Gagal follow, coba lagi").

**Gate render pill follow-back (KOREKSI review #2):** pill "Ikuti" HANYA dirender bila `_extractProfileUsername(notification.url) != null` (url berpola `/u/{username}`). Follower **tanpa username** adalah kasus SAH (bukan data korup): server menulis `url: "/notifications"` untuk mereka (`lib/social/notifications.ts:52-53`) → ekstraksi null → **fallback ke pill generik existing** ("Lihat Profil", navigasi) alih-alih tombol yang tak akan pernah bisa sukses.

**Alur tap (langkah demi langkah):**
1. `AppHaptics.tap()` (pola existing `post_likers_sheet.dart:129`).
2. Set state `loading`.
3. `final result = await profileService.fetchPublicProfile(username: username, limit: 1)` — **KOREKSI review #7:** return type-nya `PublicProfileResult`, jadi akses via `result.profile.id` / `result.profile.isFollowing` (BUKAN `profile.id` langsung). `if (!mounted) return;` setelah await (WAJIB — StatefulWidget).
4. Guard diri sendiri: bila `result.profile.isOwner == true` → state balik `idle` diam-diam (jangan coba follow diri sendiri; kasus tepi, notif self-follow normalnya tak ada).
5. Bila `result.profile.isFollowing == true` (sudah follow duluan) → state `following` langsung, tanpa panggil follow API.
6. Bila belum: `await followService.follow(result.profile.id)`. `if (!mounted) return;` setelah await. **Catatan (review #4):** pola likers-sheet memanggil `setFollowOverride` manual SEBELUM await untuk optimistic update lintas-widget; pill ini SENGAJA melewatkannya (state pill lokal saja, tak baca override store) — `follow()` sendiri sudah `confirmFollowMutation` saat sukses dan `setFollowOverride` rollback saat gagal, jadi konsistensi lintas-widget tetap terjaga pasca-selesai.
7. Sukses → state `following`. Gagal (`ApiException`/error lain) → `ScaffoldMessenger.of(context).showSnackBar(...)` + state balik `idle`.
8. `FollowSessionChangedException` (user ganti sesi login di tengah proses) → diamkan, state balik `idle` tanpa snackbar (pola `post_likers_sheet.dart:150-151`).

**Penggantian pill (review #6):** cabang `eventType == 'user_followed'` (dan username terekstrak) **menggantikan seluruh blok pill generik** (`if (ctaLabel != null) ...`), bukan menambah pill kedua — kalau tidak, dua pill tampil berdampingan.

**Gate tap terpisah dari baris:** pill dibungkus `InkWell` sendiri dengan `onTap` KHUSUS (bukan `onTap` baris yang diteruskan) — Flutter gesture arena otomatis mencegah tap pill diteruskan ke `InkWell` baris di luarnya (pola nested-InkWell yang sudah lazim di Flutter, tak perlu `GestureDetector.absorbing` tambahan).

**State tak persisten:** murni state lokal widget (StatefulWidget di dalam `NotificationRow`, bukan disimpan ke `AppNotification`/list state global). Kalau baris di-scroll jauh sampai widget di-dispose lalu dibangun ulang, tombol kembali ke `idle` — dapat diterima (sepadan IG: cek ulang follow-state saat re-render, bukan bug).

**Visual:** gaya pill sama persis dengan CTA lain (`NataloColors.primarySoft` bg, `NataloColors.primary` teks, radius 999, padding sama) — hanya isi & `onTap`-nya beda utk notif follow.

## Testing

**Seam injeksi (KOREKSI review #8 — blocker asli):** `followService`/`profileService` adalah **global final** (`follow_service.dart:418`, `profile_service.dart:97`) yang TIDAK bisa di-swap di test; `FollowService.forTesting` membuat instance terpisah, bukan mengganti global. Maka `NotificationRow` WAJIB diberi param injeksi opsional — `NotificationRow({..., FollowService? followService, ProfileService? profileService})` default ke global — dan diteruskan ke `_NotificationFollowBackPill`. Widget test menyuntik fake lewat param ini (fake `FollowService` via `FollowService.forTesting(mutationRequest: ...)`; fake `ProfileService` butuh seam serupa — tambahkan `ProfileService.forTesting(fetcher)` kecil atau terima `Future<PublicProfileResult> Function(String username)` langsung sebagai param pill).

- Widget test: notif follow ber-url `/u/{username}` → pill awal "Ikuti"; tap pill TIDAK memicu `onTap` baris (callback baris tak terpanggil); loading→"Mengikuti" via fake.
- Widget test: `result.profile.isFollowing==true` → langsung "Mengikuti" tanpa panggil `follow()` (fake mencatat panggilan).
- Widget test: error dari `follow()` → pill balik "Ikuti" + snackbar tampil.
- Widget test: notif follow TANPA username di url (`url: "/notifications"`) → fallback pill generik "Lihat Profil" (navigasi), BUKAN tombol Ikuti.
- Regression: notif non-follow tetap pill generik existing — tak berubah. (Catatan review: test existing follow-row hanya assert layout avatar, tak ada assert pill "Lihat Profil" → penggantian pill tak merusaknya.)

## Out of Scope

- Cek follow-state proaktif untuk semua baris follow yang terlihat di layar (biar hemat request — cukup lazy-check saat tap).
- Tombol "Unfollow" dari notifikasi (follow-back cuma satu arah: follow, bukan toggle).
- Reply komentar inline (Feature D) — spec terpisah, tertunda (butuh migration `commentId` ke `Announcement`).

## Acceptance Criteria

1. Notif follow menampilkan pill "Ikuti"; tap → follow user tsb tanpa keluar dari layar notifikasi.
2. Kalau user ternyata sudah follow duluan → pill langsung "Mengikuti" tanpa panggilan follow ganda.
3. Gagal follow → pill balik "Ikuti" + pesan error singkat; tak ada state macet di "loading".
4. Tap di bagian baris lain (bukan pill) tetap membuka profil seperti sekarang.
5. Notif non-follow sama sekali tak berubah perilaku/tampilannya.
6. Tanpa perubahan backend/migration.
