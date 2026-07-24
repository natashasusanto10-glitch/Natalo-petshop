# Agregasi Notifikasi ala IG — Design Spec

Tanggal: 2026-07-24. Lanjutan backlog audit notifikasi (spec `2026-07-24-notif-actor-avatar-push-design.md`, PR #267).

## Ringkasan

Tiru batas agregasi IG: **like** (sudah ada, dipoles) dan **follow** (baru) digabung jadi satu baris hidup per window; **komentar, mention, tag TIDAK diagregasi** (personal, tiap baris berdiri sendiri — persis IG). Push tray ikut ter-update via replace-by-tag dengan throttle 5 menit.

## Keputusan user

1. **Event yang diagregasi:** ikut pola IG — like + follow saja. Komentar/mention/tag tetap per-baris.
2. **Push agregat:** kirim ulang push dengan tag sama (replace di tray, bukan menumpuk), throttle maksimal 1 push per 5 menit per baris agregat. Berlaku untuk follow (baru) DAN like (perbaikan: sekarang angka tray basi karena update in-app tidak pernah re-push).
3. **Pill follow-back:** baris follow tunggal (1 orang dalam window) tetap punya pill "Ikuti" seperti sekarang. Baris agregat (≥2 orang) kehilangan pill; tap baris → daftar follower.
4. **Urutan nama:** follower terbaru di depan — "sinta dan 5 lainnya mulai mengikuti kamu" (ala IG).
5. **Window:** 30 menit, konstanta yang sama dengan like (`LIKE_BATCH_WINDOW_MS`) — seragam, tidak ada angka baru.

## Arsitektur

Tidak ada sistem baru. Perluas pola update-in-place yang sudah ada di jalur like (`lib/feed/activity-notifications.ts` — `sendLikeNotification`): satu `Announcement` belum-dibaca dalam window di-update judul/avatar-nya, kolom `actorAvatarUrls` + widget `StackedActorAvatars` (Flutter) sudah tersedia.

Tiga unit:

### 1. Follow aggregation (`lib/social/notifications.ts` — `sendFollowNotification`)

Alur baru saat B mem-follow A:

1. **Dedup 7 hari dicek PERTAMA** (sebelum agregasi): kalau B sudah pernah trigger notif follow ke A dalam 7 hari → skip total, tidak menambah agregat. Mencegah follow/unfollow berulang menggelembungkan angka. Angka agregat = jumlah ORANG, bukan aksi.
2. Cari baris agregat hidup: `Announcement` dengan `eventType: "user_followed"`, `targetUserId: A`, `tag: "follow-agg-<A>"` (tag agregat per-target, BUKAN url per-follower), `reads: none`, `createdAt >= now - 30m`.
3. **Ketemu** → update in-place:
   - Judul: `"{nama follower terbaru} dan {N-1} lainnya mulai mengikuti kamu"` — N dihitung dari **query count follower aktual dalam window** (bukan increment counter; kebal race dua follow paralel, sama seperti like yang query `feedLike`).
   - `actorAvatarUrls`: 3 avatar follower terbaru (pola `topLikerAvatars`).
   - `url` → daftar follower target; `publishedAt` refresh (naik ke atas); body ringkas non-kontradiktif.
   - Pill follow-back hilang (client: pill hanya dirender kalau baris tunggal — deteksi via jumlah aktor/field agregat).
4. **Tidak ketemu** → create baris tunggal seperti sekarang (judul "Pengikut baru", body "{nama} mulai mengikuti kamu", url profil follower, pill utuh) TAPI dengan `tag: "follow-agg-<A>"` supaya update berikutnya menemukannya.
5. Brand-safety dipertahankan: follower admin → nama brand + foto null (helper `brandPhotoUrl`/`notificationActorFields` existing).

### 2. Push-update ter-throttle (like + follow)

- Baris agregat menyimpan `lastPushedAt` (kolom baru nullable di `Announcement`, atau field JSON existing — diputuskan saat plan).
- Saat update agregat: kirim ulang push **hanya jika** `now - lastPushedAt >= 5 menit`; selain itu update in-app saja (real-time list PR #267 menangkapnya gratis).
- Push replace pakai `tag` yang sama → Android/iOS mengganti notifikasi di tray (dedup-id deterministik dari tag sudah dibangun PR #267). `actor_avatar_url` = avatar follower/liker terbaru (https-only filter existing tetap berlaku).
- Jalur like ikut dipasangi throttle yang sama (sekali kerja dua event).
- Push pertama (baris tunggal) tetap instan seperti sekarang.

### 3. In-app polish (Flutter `notifications_screen.dart`)

- Baris agregat follow render `StackedActorAvatars` (reuse dari like) + label follow.
- Pill "Ikuti" hanya di baris follow tunggal; baris agregat: tap → daftar follower.
- Tidak ada perubahan layar lain; real-time refresh existing sudah cukup.

## Contoh perilaku (window 30m, throttle 5m)

| Waktu | Kejadian | In-app | Push tray |
|---|---|---|---|
| 10:00 | Budi follow | baris tunggal + pill | push "Budi mulai mengikuti kamu" |
| 10:02 | Sinta follow | "sinta dan 1 lainnya…", pill hilang, avatar 2 | skip (<5m) |
| 10:06 | Rudi follow | "rudi dan 2 lainnya…" | push replace "rudi dan 2 lainnya…" |
| 13:00 | Rina follow (lewat window) | baris BARU tunggal + pill | push baru |

## Error handling

- Semua try/catch + `console.warn` — kegagalan notif tidak boleh menggagalkan aksi follow/like (pola existing).
- Race update paralel: angka selalu dari query count, bukan increment — hasil akhir konsisten.
- Follower tanpa username: url fallback `/notifications` (existing), tetap ikut agregasi via tag per-target.

## Di luar scope

Komentar/mention/tag aggregation (keputusan: tidak, ikut IG), badge count/dot bottom-nav, preferensi per-jenis-event, quiet hours — tetap backlog terpisah dari audit sebelumnya.

## Testing (backend `tsx --test` di `tests/`)

1. Follow pertama → baris tunggal + data pill.
2. Follow kedua dalam window → agregat: judul "…dan 1 lainnya", avatar 2, pill off.
3. Follow lewat window → baris baru terpisah.
4. Follow-unfollow-follow orang sama → dedup 7 hari, angka tidak naik.
5. Throttle: update <5m tidak re-push; ≥5m re-push dengan tag sama.
6. Admin follower → nama brand, foto null, di agregat maupun tunggal.
7. Like: update agregat kini re-push ter-throttle (regresi-guard shape existing).

## Verifikasi device (setelah rilis)

Android+iOS: push replace di tray (tidak menumpuk), baris agregat real-time, pill behavior, tap-target agregat vs tunggal.
