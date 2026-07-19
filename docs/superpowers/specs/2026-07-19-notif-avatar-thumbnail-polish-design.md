# Notifikasi — Avatar Brand, Thumbnail Feed, Avatar Bertumpuk (like agregat)

**Date:** 2026-07-19
**Scope:** Backend web (Next.js `lib/`, `app/api/`, `prisma/`) + client Flutter (`flutter_app/`)
**Status:** Draft for review
**Depends on:** Redesign notifikasi (#189), P0–P3 routing/thumbnail/actor (#190/#192/#195/#196). Membangun di atas field aktor P2 (`Announcement.actorAvatarUrl/actorName`) & brand-safety `lib/social/brand-user.ts`.

## Latar (temuan audit, terverifikasi ke kode)

Dari screenshot lonceng in-app, tiga masalah "gambar di notifikasi":

1. **Avatar "NL" ≠ logo brand asli.** `_IdentityAvatar` (`notifications_screen.dart:1055-1071`) menggambar lingkaran teks hardcoded `Text('NL')` untuk notif brand-identity, alih-alih memakai aset logo resmi `assets/native/icon-only.png` lewat widget `OfficialBrandAvatar` (`official_brand_avatar.dart:15`, param tunggal `size`) yang dipakai di feed/komentar/profil. Inkonsistensi kode, bukan notif lama.

2. **Thumbnail feed kosong/hilang.**
   - Post **video**: `thumbnailUrl` = URL Bunny **mentah** (`publish-push.ts` set `post.thumbnailUrl` tanpa sign). Feed men-sign via `signBunnyUrl` (`queries.ts:429`) tapi notif tidak → Bunny token-auth menolak → `Image.network` gagal → errorBuilder kosong TAPI Container abu tetap terlihat = **kotak abu hampa** (`notifications_screen.dart:986-1009`).
   - Post **foto**: `FeedPost.thumbnailUrl` **null** untuk foto (foto disimpan sebagai baris `FeedMedia`, `thumbnailUrl` hanya diisi untuk video Bunny) → `imageUrl` null → **tak ada kotak**.

3. **Avatar aktor salah / tidak bertumpuk.**
   - "Postingan baru — {user} posting" (`followed_user_posted`) menampilkan "NL" padahal aktornya user lain → harusnya foto poster (brand-safe). Gap P2.
   - Like agregat ("N orang menyukai") anonim (P2 `likeRowActorFields` nge-null-kan aktor) → tak ada foto. IG menampilkan **avatar bertumpuk** liker teratas.

Aturan brand WAJIB (`lib/social/brand-user.ts`): aktor akun admin → identitas "Natalo Petshop" (foto=null → klien render logo), bukan foto/nama asli pemilik. Setiap avatar liker baru WAJIB brand-guard.

---

## Keputusan produk (disepakati)

- Avatar **sistem/postingan sendiri** ("Feed kamu…") → logo brand (`OfficialBrandAvatar`).
- Avatar **aktor tunggal** (komentar/like-1/follow/post-user-lain) → foto aktor (`actorAvatarUrl`, brand-safe).
- Like **agregat (≥2)** → **avatar bertumpuk** (hingga 3 foto liker teratas, brand-safe). **Judul tetap "N orang menyukai…"** (Pilihan 1 — tanpa menyebut nama; menyimpan nama liker + brand-safety nama = di luar scope sekarang).
- Thumbnail feed diisi **gambar yang benar** (video signed + foto FeedMedia pertama); kotak disembunyikan penuh saat gambar gagal.

## Arsitektur & Perubahan

### P-A. Backend — thumbnail feed benar (helper bersama + sign saat baca)

- **Helper bersama** `feedNotificationThumbnail(post)` (baru, mis. `lib/feed/notification-thumbnail.ts`): `return post.thumbnailUrl ?? post.media?.[0]?.url ?? null`. Video → `thumbnailUrl` (Bunny mentah). Foto → URL `FeedMedia` pertama (`media` diurut `sortOrder asc`, ambil `.url`; `schema.prisma:1362-1388`).
- Terapkan di **semua builder notif feed** yang set `thumbnailUrl` (enumerasi terverifikasi, `activity-notifications.ts`): `sendCommentNotification` (:87), `sendReplyNotification` (:146), `sendMentionNotifications` (:234), `sendLikeMilestoneNotification` (:308), `sendLikeNotification` (:387 + agregat :374), `sendCommentLikeNotification` (:477), `sendShareNotification` (:517) — TAK SATU PUN query post-nya fetch `media` saat ini; masing-masing tambah `media: { orderBy: { sortOrder: "asc" }, take: 1, select: { url: true } }` ke select.
- `buildFeedPublishAnnouncementData` (`publish-push.ts:89`): param `post` saat ini `{id, thumbnailUrl}` → **lebarkan tipe param** jadi menerima `media` (atau langsung hasil helper), dan query `sendFeedPublishPush` (:112-125) tambah select `media` yang sama.
- **Sign saat baca** di `app/api/notifications/me/route.ts` `mapAnnouncement`: `thumbnailUrl: signBunnyUrl(a.thumbnailUrl) ?? null` (import `signBunnyUrl` dari `lib/feed/bunny`). `signBunnyUrl` hanya men-sign URL ber-host `BUNNY_CDN_HOSTNAME` (`bunny.ts:301`) → URL Bunny video di-sign segar (anti-kedaluwarsa; URL bertanda-tangan expiry 6 jam, jadi TIDAK boleh disimpan bertanda-tangan), URL non-Bunny (foto FeedMedia, produk P3) diteruskan apa adanya. Terpusat → semua notif ber-thumbnail Bunny ikut benar sekaligus.

### P-B. Backend — avatar aktor `followed_user_posted`

- **Lokasi (koreksi review):** builder-nya `sendNewPostToFollowersNotification` di **`lib/social/notifications.ts:135`** (eventType `:160`), BUKAN activity-notifications/notification-center. Bentuk insert-nya **`prisma.announcement.createMany` (:213)** — batch per follower — jadi fix-nya menambah `actorAvatarUrl`/`actorName` ke **tiap objek row** createMany (bukan param `actor:{}` ala `createFeedNotification`).
- Select author (`:144-151`) saat ini `{ id, name, username, role }` **tanpa `profilePhotoUrl`** → tambahkan. Lalu hitung sekali `notificationActorFields(author.role, author.name, author.profilePhotoUrl)` (brand-safe; poster admin → nama brand + avatar null) dan spread ke tiap row.

### P-C. Backend — avatar bertumpuk like agregat (migration)

- **Migration** (timestamp > `20260719140000`): `ALTER TABLE "Announcement" ADD COLUMN IF NOT EXISTS "actorAvatarUrls" TEXT[] NOT NULL DEFAULT '{}';` + field Prisma `actorAvatarUrls String[] @default([])` di model `Announcement` (`schema.prisma:1126`).
- **Helper murni teruji** `topLikerAvatars(likers): string[]` — input list `{ role, profilePhotoUrl }` (maks 3), output URL foto **brand-safe** via `brandPhotoUrl(role, photo)`, buang null/empty, maks 3. (Admin liker → di-drop dari array foto ATAU disertakan sebagai penanda-brand? Keputusan: **drop null** — array cuma berisi foto asli non-admin; slot brand ditangani klien bila perlu. Simpel + tak bocor.)
- `sendLikeNotification` & `sendCommentLikeNotification` cabang **agregat** (`announcement.update`, `activity-notifications.ts:366-377` & `456-467`): query 3 liker terbaru dari `FeedLike`/`FeedCommentLike` (`orderBy createdAt desc, take 3`, `user.select { profilePhotoUrl, role }`; tabel `schema.prisma:1496,1522`), set `actorAvatarUrls: topLikerAvatars(likers)`. Cabang **single create** tetap `actorAvatarUrl` (P2, tak berubah); `actorAvatarUrls` untuk single = `[]`.
- **API** `mapAnnouncement`: expose `actorAvatarUrls` (kolom auto-tersedia, `findMany` tanpa `select`; hanya tipe param + return mapper diedit).

### P-D. Client Flutter

- **Avatar brand** (`_IdentityAvatar`, cabang `brandIdentity` — `Text('NL')` di `notifications_screen.dart:1021`, blok :1012-1029): ganti lingkaran `Text('NL')` → `OfficialBrandAvatar(size: 42)` (badge kategori mini di-Stack tetap; aset `assets/native/` sudah terdaftar `pubspec.yaml:184`). Notif ber-`actorAvatarUrl` tetap foto aktor (jalur P2 existing, tak berubah). **Catatan cakupan:** `_isBrandIdentity` (:827-829) = feed **ATAU** pengumuman → notif pengumuman/promo broadcast juga berpindah dari "NL" ke logo (konsisten, memang diinginkan — set yang sama yang hari ini menampilkan "NL").
- **Avatar bertumpuk** (`AppNotification` + `_IdentityAvatar`): parse `actorAvatarUrls` (List<String>) dari JSON. Bila `actorAvatarUrls.length >= 2` → widget baru `StackedActorAvatars` (2 lingkaran `Image.network` bertumpuk, offset ~ -14px, ring putih tipis, 42px total + badge like kecil). Prioritas render kiri: `actorAvatarUrls≥2` (bertumpuk) → `actorAvatarUrl` (tunggal) → `brandIdentity` (logo) → ikon kategori.
- **Kotak abu thumbnail** (blok thumb `:944-966`): `errorBuilder` SUDAH mengembalikan `SizedBox.shrink()` (:964) — masalahnya `Container` luar punya `color: cs.surfaceContainerHighest` + border **permanen** (:955-959) yang tetap terlihat saat gambar gagal. Fix = **hapus warna/border permanen dari Container luar**; latar abu hanya muncul via `loadingBuilder` selama memuat; rounding via `ClipRRect` pada `Image` sendiri. Hasil: gambar gagal = slot kosong tanpa sisa kotak.
- `AppNotification.copyWith` + `fromApiJson` mengangkut `actorAvatarUrls` (default `[]`), gaya dual-key konsisten: `(json['actorAvatarUrls'] ?? json['actor_avatar_urls']) as List?)?.map((e) => e.toString()).toList() ?? const []`.
- Catatan web: halaman notifikasi web TIDAK merender thumbnail/avatar aktor (grep-terverifikasi) → sign-saat-baca cukup di API app; web tak terpengaruh kolom baru.

## Testing

- Backend unit (`tsx --test`): `feedNotificationThumbnail` (video→thumbnailUrl, foto→media[0].url, kosong→null); `topLikerAvatars` (brand-safe: admin liker foto di-drop; maks 3; null/empty dibuang); `notificationActorFields` untuk `followed_user_posted` (sudah teruji P2, tambah kasus post-builder bila perlu). Mapper: `signBunnyUrl` dipanggil untuk thumbnailUrl (URL Bunny di-sign, non-Bunny apa adanya) — uji via helper murni/predikat.
- Flutter widget: brand notif → `OfficialBrandAvatar` (aset, bukan `Text('NL')`); notif ber-`actorAvatarUrl` → foto tunggal; `actorAvatarUrls≥2` → StackedActorAvatars (2 lingkaran); thumbnail error → tak ada Container tersisa; foto post → thumbnail tampil.

## Out of Scope

- Judul agregat menyebut nama liker ("A, B dan N lainnya") — butuh simpan array nama + brand-safety nama. Pilihan 1 (jumlah) dipakai sekarang.
- Agregasi baru selain like (share/milestone) — tetap seperti sekarang.
- Realtime.

## Urutan Deploy

1. **Migration deploy** (`actorAvatarUrls`, backward compatible `DEFAULT '{}'`).
2. Backend deploy → thumbnail benar (sign saat baca) + avatar aktor `followed_user_posted` + array liker terisi. App lama: notif tetap jalan (avatar tunggal/logo, tanpa stack) — degradasi anggun.
3. Rilis app Flutter → logo brand `OfficialBrandAvatar` + avatar bertumpuk + kotak-abu hilang.

## Acceptance Criteria

1. Notif sistem "Feed kamu…" DAN notif pengumuman/promo broadcast (set brand-identity yang sama) menampilkan **logo brand asli** (bukan teks "NL").
2. Notif "postingan baru dari {user}" menampilkan **foto user** itu (brand-safe: admin → logo brand).
3. Notif feed (publish/komentar/like) menampilkan **thumbnail post yang benar**: video (Bunny signed, tak lagi kotak abu) & foto (FeedMedia pertama).
4. Like agregat (≥2) menampilkan **avatar bertumpuk** (≤3 foto liker teratas, brand-safe); judul tetap "N orang menyukai…".
5. Thumbnail yang gagal load **tidak menyisakan kotak abu**.
6. Semua avatar/foto baru brand-guard; tak ada kebocoran foto/nama pemilik admin.
7. Perilaku non-terkait (routing tap, mark-read, tab, hero header) tak berubah.
