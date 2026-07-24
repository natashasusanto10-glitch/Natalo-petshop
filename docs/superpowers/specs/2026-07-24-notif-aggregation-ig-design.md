# Agregasi Notifikasi ala IG — Design Spec

Tanggal: 2026-07-24. Lanjutan backlog audit notifikasi (spec `2026-07-24-notif-actor-avatar-push-design.md`, PR #267). **Dependensi keras: PR #267 harus merge dulu** — spec ini memakai real-time list, dedup-tag client, `actorAvatarUrls`, dan filter https `actor_avatar_url` dari PR itu. Kerja di branch BARU di atas main pasca-merge.

## Ringkasan

Tiru batas agregasi IG: **like** (sudah ada, dipoles) dan **follow** (baru) digabung jadi satu baris hidup per window; **komentar, mention, tag TIDAK diagregasi** (personal, tiap baris berdiri sendiri — persis IG). Push tray ikut ter-update via replace (Android by tag, iOS by `apns-collapse-id`) dengan throttle 5 menit.

## Keputusan user (brainstorming + eng review D2–D9)

1. **Event yang diagregasi:** like + follow saja. Komentar/mention/tag tetap per-baris.
2. **Push agregat:** re-push dengan tag sama (replace di tray), throttle maks 1 push per 5 menit per baris. Berlaku follow (baru) DAN like. Disadari: ini MENAMBAH frekuensi push like vs sekarang (yang tak pernah re-push) — diputuskan sadar demi angka tray segar (review F6).
3. **Pill follow-back:** baris tunggal tetap ber-pill; baris agregat (≥2 orang) tanpa pill, tap → daftar follower sendiri.
4. **Urutan nama:** follower terbaru di depan.
5. **Window:** 30 menit (`LIKE_BATCH_WINDOW_MS`), sama dengan like.
6. **(D2/2A)** Angka agregat = count `UserFollow` (unique constraint `[followerId, followingId]` menjamin hitungan per-ORANG, follow-unfollow-follow tetap 1). Dedup 7-hari existing dipertahankan tapi diakui hanya efektif untuk baris TUNGGAL; refollow anggota agregat paling banter memicu update ter-throttle — residual diterima. Teks klaim "dedup mencegah gelembung angka" DIHAPUS (yang menjamin angka adalah unique constraint, bukan dedup — review F5).
7. **(D3/3A)** `apns-collapse-id: payload.tag` (dipotong ≤64 byte) ditambahkan ke headers apns di `buildFcmMulticastMessage` — KEDUA shape (capable + legacy), hanya saat tag ada. Tanpa ini iOS menumpuk, bukan replace. Efek samping disadari: semua notif ber-tag (termasuk order) ikut jadi replace di iOS — masuk matriks device-verify.
8. **(D4/4A)** Throttle state = kolom eksplisit `Announcement.lastPushedAt DateTime?` + migration idempotent (`ADD COLUMN IF NOT EXISTS`).
9. **(D5/5A + F2/F3)** Kontrak agregat = kolom/field eksplisit `aggregatedCount Int?` di `Announcement` (ikut migration yang sama), diekspos di read-path (`mapAnnouncement`/API) dan model Flutter (`AppNotification.aggregatedCount`). Client: `aggregatedCount != null && aggregatedCount > 1` → pill off + tap ke daftar follower. **Heuristik `actorAvatarUrls.length` DILARANG** sebagai penanda agregasi (follower tanpa foto membuat array kosong — `topLikerAvatars` men-drop foto null; review F2).
10. **(D8/8A)** N dihitung dengan patokan TETAP milik baris: `UserFollow.createdAt >= barisAgregat.createdAt` — BUKAN rolling `now-30m`. Mencegah satu orang terhitung di dua baris saat follow beruntun melewati batas window (review F1).
11. **(D9/9A)** Tap baris agregat → deep-link BARU daftar follower sendiri (mis. `/akun/followers`), wiring ke layar follower existing di area profil, urut terbaru-dulu. WAJIB tambah `case` di `_handle` deep-link service (gotcha PR #137: URL server baru tanpa case → nyasar ke /member).

## Arsitektur

Tidak ada sistem baru. Perluas pola update-in-place jalur like (`lib/feed/activity-notifications.ts` — `sendLikeNotification`); `actorAvatarUrls` + `StackedActorAvatars` (Flutter) sudah tersedia.

### 1. Follow aggregation (`lib/social/notifications.ts` — `sendFollowNotification`)

Alur saat B mem-follow A:

1. Dedup 7-hari existing dicek pertama (efektif untuk baris tunggal; lihat Keputusan 6).
2. Cari baris agregat hidup: `Announcement` `eventType: "user_followed"`, `targetUserId: A`, `tag: "follow-agg-<A>"`, `reads: none`, `createdAt >= now - 30m`.
3. **Ketemu** → update in-place:
   - `N` = count `UserFollow` where `followingId: A, createdAt >= baris.createdAt` (Keputusan 10) + follower pembuat baris (baseline 1).
   - Judul: `"{nama follower terbaru} dan {N-1} lainnya mulai mengikuti kamu"`.
   - `actorAvatarUrls`: ≤3 avatar follower terbaru (helper baru `topFollowerAvatars` meniru `topLikerAvatars` — join `UserFollow`→`user`, drop foto null, brand-safe).
   - `aggregatedCount: N`; `url` → `/akun/followers`; `publishedAt` refresh; body ringkas non-kontradiktif.
4. **Tidak ketemu** → create baris tunggal seperti sekarang (judul "Pengikut baru", url profil follower, pill utuh, `aggregatedCount: null`) dengan `tag: "follow-agg-<A>"`.
5. Brand-safety follower admin: nama brand + foto null (helper existing) — di tunggal maupun agregat.

### 2. Push-update ter-throttle (like + follow)

- Saat update baris agregat: re-push hanya jika `lastPushedAt == null || now - lastPushedAt >= 5 menit`; sukses kirim → tulis `lastPushedAt = now`. Selain itu update in-app saja (real-time list PR #267 menangkap gratis).
- Replace: Android legacy via `android.notification.tag` (existing), Android capable via dedup-id client dari tag (PR #267), iOS via `apns-collapse-id` (Keputusan 7).
- `actor_avatar_url` = avatar aktor terbaru (filter https existing tetap berlaku).
- Jalur like dipasangi throttle yang sama. Push pertama (baris baru) tetap instan.

### 3. In-app (Flutter `notifications_screen.dart` + deep link)

- Baris agregat: `StackedActorAvatars` + label follow; pill "Ikuti" hanya saat `aggregatedCount` absen/1; tap agregat → `/akun/followers` (case deep-link baru), tap tunggal → profil follower.
- Model `AppNotification` + parsing dapat field `aggregatedCount`.

## Contoh perilaku (window 30m, throttle 5m)

| Waktu | Kejadian | In-app | Push tray |
|---|---|---|---|
| 10:00 | Budi follow | baris tunggal + pill | push "Budi mulai mengikuti kamu" |
| 10:02 | Sinta follow | "sinta dan 1 lainnya…", pill off, avatar 2, aggregatedCount 2 | skip (<5m) |
| 10:06 | Rudi follow | "rudi dan 2 lainnya…" | push replace (Android tag / iOS collapse-id) |
| 13:00 | Rina follow (lewat window) | baris BARU tunggal + pill | push baru |

## Error handling & failure modes

- Semua try/catch + `console.warn` — kegagalan notif tidak menggagalkan follow/like (pola existing).
- Race update paralel: N dari query count berpatokan `baris.createdAt` — konsisten apapun urutan update. Throttle race (dua update baca `lastPushedAt` basi bersamaan) → maks 1 push ekstra, diterima.
- Follower tanpa foto / semua-admin: `actorAvatarUrls` bisa kosong — UI wajib tetap benar via `aggregatedCount`, bukan panjang array (Keputusan 9).
- `lastPushedAt` null di baris pra-migration → dianggap "boleh push" (kondisi `== null` eksplisit).
- Deep-link `/akun/followers` di app versi lama (tanpa case): jatuh ke fallback existing — dicatat, bukan blocker (fitur baru butuh rilis app baru bersamaan).

## Di luar scope

Agregasi komentar/mention/tag (keputusan: tidak — ikut IG), badge count/dot bottom-nav, preferensi per-jenis-event, quiet hours, soft-delete UserFollow (D2/2C ditolak), layar khusus "follower dalam window ini" (9A memakai daftar follower penuh urut terbaru — cukup, ala IG).

## Yang sudah ada (reuse, bukan bangun ulang)

Pola update-in-window + `topLikerAvatars` (jalur like), `actorAvatarUrls` + `StackedActorAvatars`, dedup-id client dari tag + real-time list + filter https (PR #267), `android.notification.tag` (legacy replace), helper brand-safe, index `UserFollow [followingId, createdAt]`, layar daftar follower area profil.

## Testing

Backend (`tsx --test` di `tests/`):
1. Follow pertama → baris tunggal, `aggregatedCount` null, data pill utuh.
2. Follow kedua dalam window → agregat: judul "…dan 1 lainnya", `aggregatedCount: 2`, avatar ≤3, pill-data off.
3. Follow lewat window → baris baru terpisah.
4. Follow-unfollow-follow orang sama → angka tidak naik (unique constraint); dedup baris tunggal tetap jalan.
5. Count anchor: follow beruntun melewati batas window → tidak dobel-hitung antar dua baris (patokan `baris.createdAt`).
6. Throttle: `<5m` skip; `>=5m` re-push; tepat 5m → re-push; `lastPushedAt` null → re-push.
7. Admin follower → nama brand, foto null (tunggal + agregat).
8. `buildFcmMulticastMessage`: `apns-collapse-id == tag` di kedua shape; tag >64 byte terpotong; tanpa tag → header absen.
9. Like: re-push ter-throttle + shape regresi-guard existing tetap hijau.
10. **Regresi (wajib):** baris follow tunggal — url profil, pill, dedup 7-hari — perilaku byte-identik dengan sekarang.

Flutter (widget test, suite notifikasi existing):
11. `aggregatedCount > 1` → pill hilang + tap-target daftar follower; absen/1 → pill + tap profil.
12. `aggregatedCount: 2` dengan `actorAvatarUrls` kosong (follower tanpa foto) → layout agregat tetap benar.
13. Deep-link `/akun/followers` → case `_handle` membuka layar follower.

## Verifikasi device (setelah rilis)

Android+iOS: push replace di tray (tidak menumpuk — cek juga notif ORDER ber-tag di iOS ikut replace, Keputusan 7), baris agregat real-time, pill on/off, tap agregat vs tunggal, follower tanpa foto.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | issues_found→folded | 6 (D2 dedup-source, D3 apns-collapse-id, D4 lastPushedAt, D5 kontrak agregat, D6 test gaps, perf clean) |
| Outside Voice | subagent (opus) | Independent 2nd opinion | 1 | issues_found→folded | 8 (F1 window-anchor→D8, F2/F3 wiring aggregatedCount, F4 tap-target→D9, F5 teks dedup, F6 diakui, F7 scope→7A tetap, F8 dependensi #267) |

- **CODEX:** tidak jalan (CLI tak terpasang) — outside voice via Claude subagent (opus).
- **CROSS-MODEL:** 1 tension nyata (F7 scope follow-aggregation) — diputuskan user 7A (bangun penuh; argumen trajektori sosial > snapshot follower hari ini). Temuan lain saling melengkapi, tidak bertentangan.
- **VERDICT:** ENG CLEARED — semua temuan kedua reviewer dilipat ke spec (Keputusan 6–11 + Testing 1–13). Siap ke writing-plans setelah PR #267 merge.

NO UNRESOLVED DECISIONS
