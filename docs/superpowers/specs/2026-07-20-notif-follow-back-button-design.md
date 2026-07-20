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

**Alur tap (langkah demi langkah):**
1. `AppHaptics.tap()` (pola existing `post_likers_sheet.dart:129`).
2. Set state `loading`.
3. `username = _extractProfileUsername(notification.url)`. Bila null → langsung state error (kasus data korup, jarang terjadi) → kembali `idle`.
4. `profile = await profileService.fetchPublicProfile(username: username, limit: 1)` (limit kecil — cuma butuh `user.id`+`isFollowing`, bukan daftar postingan).
5. Bila `profile.isFollowing == true` (sudah follow duluan, mis. user follow manual sebelum tap notif ini) → set state `following` langsung, **tanpa** memanggil follow API lagi.
6. Bila belum: `state = await followService.follow(profile.id)` (reuse `FollowService`, otomatis dpt `optimistic override` + coalescing existing).
7. Sukses → state `following`. Gagal (`ApiException`/error lain) → `ScaffoldMessenger.of(context).showSnackBar(...)` + state balik `idle`.
8. `FollowSessionChangedException` (user ganti sesi login di tengah proses, kasus tepi) → diamkan, state balik `idle` tanpa snackbar (pola sama `post_likers_sheet.dart:150-151`).

**Gate tap terpisah dari baris:** pill dibungkus `InkWell` sendiri dengan `onTap` KHUSUS (bukan `onTap` baris yang diteruskan) — Flutter gesture arena otomatis mencegah tap pill diteruskan ke `InkWell` baris di luarnya (pola nested-InkWell yang sudah lazim di Flutter, tak perlu `GestureDetector.absorbing` tambahan).

**State tak persisten:** murni state lokal widget (StatefulWidget di dalam `NotificationRow`, bukan disimpan ke `AppNotification`/list state global). Kalau baris di-scroll jauh sampai widget di-dispose lalu dibangun ulang, tombol kembali ke `idle` — dapat diterima (sepadan IG: cek ulang follow-state saat re-render, bukan bug).

**Visual:** gaya pill sama persis dengan CTA lain (`NataloColors.primarySoft` bg, `NataloColors.primary` teks, radius 999, padding sama) — hanya isi & `onTap`-nya beda utk notif follow.

## Testing

- Widget test: notif follow → pill awal tampil "Ikuti"; tap pill TIDAK memicu navigasi row (mock `onTap` baris, pastikan tak terpanggil); state loading→following via fake `ProfileService`/`FollowService` (perlu constructor test-seam atau service injection — ikuti pola `FollowService.forTesting` yang sudah ada, `follow_service.dart:187-193`).
- Widget test: `profile.isFollowing==true` → langsung "Mengikuti" tanpa panggil `followService.follow`.
- Widget test: error dari `followService.follow` → pill balik "Ikuti" + snackbar tampil.
- Regression: notif non-follow tetap pakai pill generik existing (`ctaLabel` apa adanya, `onTap` = navigasi baris) — tak berubah.

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
