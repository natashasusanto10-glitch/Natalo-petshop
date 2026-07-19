# Notifikasi — Routing Presisi + Avatar Aktor + Thumbnail Produk

**Date:** 2026-07-19
**Scope:** Backend web (Next.js `lib/`, `app/api/`, `prisma/`) + client Flutter (`flutter_app/lib/screens/notifications_screen.dart`, model, services)
**Status:** Draft for review
**Depends on:** Redesign notifikasi premium (PR #189, merged) — baris memakai `NotificationRow` dgn slot identitas kiri + thumbnail kanan; model `AppNotification.imageUrl` parse `thumbnailUrl`.

## Latar & Temuan Audit

Model persisten backend bernama **`Announcement`** (`prisma/schema.prisma:1122-1156`), disajikan ke app oleh `app/api/notifications/me/route.ts` (mapper `mapAnnouncement` :38-73). Field yang sampai ke app: `id,title,body,url,segment,type,category,source,eventType,feedPostId,videoId,thumbnailUrl,status,ctaLabel,createdAt,read,reviewSummary`. **Tidak ada** `imageUrl`, field aktor, atau `orderId`. Client Flutter mem-parse `imageUrl` dari `imageUrl|image_url|thumbnailUrl`, jadi `thumbnailUrl` yang dikirim backend SUDAH tampil sebagai thumbnail kanan.

Konsekuensi & gap (semua terverifikasi ke kode):

1. **Feed publish** ("Feed kamu sudah tayang / dibagikan / menunggu review") — `sendFeedPublishPush` (`lib/feed/publish-push.ts:120-138`) membuat baris `Announcement` TANPA `feedPostId` dan TANPA `thumbnailUrl` (beda dari notif aktivitas feed yang selalu set keduanya, mis. `lib/feed/activity-notifications.ts:76-77`). Akibat: routing tap jatuh ke `/feed` generik (bukan post itu) + tak ada thumbnail.
2. **Pesanan** — tak ada kolom `orderId`; `sendOrderStatusPush` (`lib/push.ts:218-345`) menaruh `order_id`/`order_number` hanya di `data` push (transien). Baris `Announcement` cuma punya `url` = `buildOrderDetailPath(orderNumber, ...)`. Client `_navigateForNotification` mengarahkan ke `/member/orders` (daftar), bukan detail pesanan. Pola fetch-by-number sudah ada: `orderService.fetchOrderDetail(orderNumber)` (`lib/services/order_service.dart:14`) dipakai push deep-link `_openOrderByNumber` (`lib/services/deep_link_service.dart:273-290`) → `/member/order-detail`.
3. **Avatar aktor** — notif sosial komentar/mention/like TIDAK mengirim foto aktor (slot `thumbnailUrl` diisi foto POST via `createFeedNotification` `lib/feed/notification-center.ts:170`; `:143` = `imageUrl` push transien). Follow (`sendFollowNotification` `lib/social/notifications.ts:25-118`) mengisi `thumbnailUrl` = foto follower (brand-safe via `lib/social/brand-user.ts`), sehingga di redesign foto follower muncul di KANAN (slot thumbnail) — sisi yang salah untuk avatar.
4. **Foto produk** untuk notif pesanan/keranjang/promo tidak disimpan (push punya `imageUrl` transien di `lib/push-marketing.ts:52,137`, tak masuk baris `Announcement`).

Aturan brand WAJIB (`lib/social/brand-user.ts`): aktor akun admin → identitas "Natalo Petshop" (nama & foto), bukan nama/foto asli pemilik. Setiap field aktor baru WAJIB brand-guard.

---

## P0 — Backend: feed-publish set `feedPostId` + `thumbnailUrl`

**Tujuan:** notif "Feed kamu sudah tayang/dibagikan" tap → buka post itu (bukan `/feed` generik) + tampil thumbnail post. Deploy tanpa rilis app (client redesign sudah membaca `feedPostId` untuk routing & `thumbnailUrl` untuk gambar).

**Perubahan (backend saja):**
- `sendFeedPublishPush` (`lib/feed/publish-push.ts`): **tambah `thumbnailUrl: true` ke `select` FeedPost** (baris ~85-98; saat ini select TIDAK mengambil thumbnail — kolom ada di `FeedPost`, dipakai `activity-notifications.ts:53`). Lalu saat membuat baris `Announcement` (baris 127-138) set `feedPostId: post.id` dan `thumbnailUrl: post.thumbnailUrl`. Selaras dengan notif aktivitas feed lain. Koreksi audit: thumbnail BUKAN bagian pembentukan push saat ini (`buildFeedPushPayload` hanya pakai title/description), jadi select-nya wajib ditambah.
- Verifikasi post PHOTO_CAROUSEL admin benar-benar mengisi `thumbnailUrl` (kalau tidak, test "non-null untuk foto" gagal untuk foto).
- `type`/`eventType` biarkan (saat ini `type:"announcement"`) agar tak mengubah pengelompokan tab; menambah `feedPostId` tidak menyentuh `isFeed` logic (`route.ts:54`) — aman.

**Client:** tak ada perubahan kode. `_navigateForNotification` sudah mengutamakan `feedPostId` → `_openFeedPostInApp` (branch ini ada bahkan di app pra-#189), jadi **tap→post benar tanpa rilis app**.

**Catatan deploy jujur:** routing tap ke post berlaku tanpa rilis app. TAPI **thumbnail post baru tampil setelah app redesign #189 dirilis** (slot thumbnail kanan hanya ada di `NotificationRow` #189). Jangan konflasikan keduanya.

**Test:** unit builder — baris hasil `sendFeedPublishPush` mengandung `feedPostId` + `thumbnailUrl` non-null untuk foto/video. Regresi: notif publish existing tetap terkirim.

---

## P1 — Client: routing pesanan presisi + avatar follow ke kiri

Rilis app; tanpa backend.

### P1a — Pesanan → detail pesanan itu
- URL notif pesanan berformat **`/pesanan/{orderNumber}`** (`buildOrderDetailPath` `lib/order-detail.ts:65`, + optional `?token=` trackingToken; DELIVERED menambah `?review=1` `push.ts:241`) — **bukan** query `orderNumber=`. `orderNumber` berpola `ORD-...`.
- Di `_navigateForNotification` (`flutter_app/lib/screens/notifications_screen.dart`), sebelum cabang list pesanan (yang sekarang match via `haystack.contains('pesanan')`, bukan URL `/orders`): ekstrak `orderNumber` dari `url`, tampilkan spinner, `await orderService.fetchOrderDetail(orderNumber, trackingToken: token)`, lalu `Navigator.pushNamed('/member/order-detail', arguments: order)`. Gagal fetch → fallback `/member/orders` (persis pola `_openOrderByNumber` `deep_link_service.dart:273-290` + spinner pola `_openFeedPostInApp`). Sertakan `trackingToken` dari query `?token=` bila ada (konsisten dgn deep-link).
- Ekstraksi: helper murni `String? extractOrderNumber(String url)` — pakai regex `ORD-[A-Z0-9-]+` (mirror server `extractOrderNumberFromNotification` `app/api/notifications/me/route.ts:34`), yang bisa diuji.

### P1b — Avatar follow di kiri
- `NotificationRow`/`_IdentityAvatar`: untuk notif follow (`eventType == 'user_followed'`), render `thumbnailUrl` (foto follower) sebagai **avatar kiri** (lingkaran), dan JANGAN tampilkan di slot thumbnail kanan. Untuk notif feed/aktivitas, `thumbnailUrl` tetap di kanan (foto post).
- Aturan: bila notif ber-aktor-manusia sosial (follow) → `thumbnailUrl` = avatar → kiri. Selain itu → `thumbnailUrl` = konten → kanan. (Sampai P2 menambah field aktor terpisah, follow adalah satu-satunya kasus avatar-di-thumbnail; heuristik `eventType == 'user_followed'`.)

**Test:** unit `extractOrderNumber` (beberapa format url); widget — notif follow menaruh avatar di kiri & TIDAK di kanan; notif komentar tetap thumbnail di kanan; routing pesanan memanggil `fetchOrderDetail` lalu push order-detail (fake service), fallback saat gagal.

---

## P2 — Backend + client + migration: avatar aktor terstruktur untuk semua notif sosial

**Tujuan:** "A follow B → foto A; user komentar/mention/like/share di post B → foto user itu", di sisi KIRI, brand-safe. Butuh migration DB + rilis app.

### P2a — Backend
- **Migration Prisma**: tambah kolom `Announcement.actorAvatarUrl String?`, `actorName String?` (`prisma/schema.prisma` model `Announcement`, ~:1122). Buat migration SQL sungguhan (bukan `db push`) — lihat gotcha product-video schema drift + hati-hati DB Neon divergen. (`actorUsername` DIDROP — YAGNI: follow sudah route via `/u/{username}` dari `url`; tambah nanti bila fitur tap-aktor butuh.) `mapAnnouncement` pakai `findMany` tanpa `select` eksplisit → kolom baru auto-tersedia; hanya output mapper + tipe param yang perlu diedit.
- **`createFeedNotification`** (`lib/feed/notification-center.ts:87-181`): tambah param opsional `actor?: { avatarUrl, name }`; tulis ke dua kolom baru. `thumbnailUrl` TETAP foto post (kanan) — baris bisa punya keduanya: avatar aktor (kiri) + thumbnail post (kanan).
- **Builder sosial — enumerasi LENGKAP** (semua yang menulis aktor WAJIB brand-guard via `brandPhotoUrl(role,photo)` + `brandDisplayName(role,name)`, `lib/social/brand-user.ts`; select `profilePhotoUrl,name,role` aktor):
  - Komentar (`activity-notifications.ts:69-83`), reply (:121-136), mention (:195-217) → via `createFeedNotification.actor`.
  - Like single (`sendLikeNotification` create :339 **dan update branch :317-330** yang panggil `prisma.announcement.update` LANGSUNG — wajib ikut set kolom aktor, kalau tidak baris like batch tampil avatar basi/kosong).
  - Comment-like (`sendCommentLikeNotification` create :407 **dan update branch :396-405**) — sama, jangan terlewat.
  - Follow (`lib/social/notifications.ts`) — lihat bawah.
  - **Agregat tanpa aktor tunggal — SENGAJA tidak dapat avatar** (pakai brand/ikon fallback): `sendLikeMilestoneNotification` (:245) dan **share** (`sendShareNotification` :428 — signature `{postId,shareCount}`, TIDAK punya `actorUserId`; menambah avatar butuh ubah signature + call-site → **DIDESCOPE** dari P2, tetap agregat "Feed kamu dibagikan").
- **Follow** (`lib/social/notifications.ts`): set `actorAvatarUrl` = foto follower (+ `actorName`). **Transisi aman:** JANGAN kosongkan `thumbnailUrl` follow sampai versi app minimum sudah membaca `actorAvatarUrl` — kalau backend P2 deploy saat app masih di P1b (yang baca avatar follow dari `thumbnailUrl`), follow kehilangan avatar. Aturan: isi `actorAvatarUrl` DAN pertahankan `thumbnailUrl`=foto follower untuk follow selama masa transisi; hapus `thumbnailUrl` follow di rilis backend berikutnya setelah adopsi app P2 memadai (atau biarkan — client P2 mengutamakan `actorAvatarUrl` dan follow tak punya konten kanan, jadi thumbnailNya bisa diabaikan client saat `eventType=='user_followed'`). Brand-guard sudah ada.
- **API** `mapAnnouncement` (`app/api/notifications/me/route.ts:38-73`): expose `actorAvatarUrl,actorName`.

### P2b — Client
- `AppNotification`: tambah `actorAvatarUrl,actorName` (parse + copyWith).
- `NotificationRow`/`_IdentityAvatar`: bila `actorAvatarUrl` ada → avatar kiri = foto aktor (badge kategori mini tetap); else brand "NL"/ikon kategori seperti sekarang. Hapus heuristik follow P1b (digantikan field eksplisit). Ganti `Image.network` → widget cached (`AppProductImage`/pola cached app) untuk avatar & thumbnail (menuntaskan minor non-cached).

**Test:** backend unit — builder komentar/mention/follow mengisi `actorAvatarUrl` brand-safe (admin → brand foto/null + nama "Natalo Petshop"; user biasa → foto asli). API mengembalikan field. Client widget — avatar kiri = foto aktor saat ada; brand fallback saat null.

---

## P3 — Foto produk untuk notif pesanan/keranjang/promo (nice-to-have)

Rilis app + backend (bisa nunggu P2 migration).

- **Backend**: saat notif pesanan/keranjang/back-in-stock dibuat, simpan foto produk ke `thumbnailUrl` baris `Announcement` (kolom sudah ada; saat ini hanya diisi feed). Sumber: line item pertama / `topItem.imageUrl` (`lib/push-marketing.ts:52`), order line item (`lib/push.ts`).
- **Client**: tak ada (thumbnail kanan sudah render `thumbnailUrl`). Otomatis muncul begitu backend mengisi.

**Test:** backend unit — baris notif pesanan/keranjang punya `thumbnailUrl` produk.

---

## Catatan Implementasi (WAJIB)

- **Branch dari `origin/main`** (yang sudah memuat redesign #189: `NotificationRow` :769, `_IdentityAvatar` :918, `AppNotification.imageUrl` parse `thumbnailUrl` :72). Worktree brainstorming ini di HEAD terlepas PRA-#189 — jangan implement di sini.
- Semua nomor baris client di spec merujuk versi `origin/main` pasca-#189.

## Urutan & Dependensi

1. **P0** (backend, kecil, aman) → deploy; keluhan routing feed selesai tanpa rilis app.
2. **P1** (client, kecil-sedang) → rilis app; routing pesanan + avatar follow.
3. **P2** (backend+migration+client, besar) → migration deploy dulu (backward compatible), lalu rilis app.
4. **P3** (backend, kecil) → kapan saja setelah P0; client sudah siap.

P0, P1, P3 independen. P2 menggantikan heuristik P1b dengan field eksplisit (P1b sengaja sebagai jembatan agar follow tak salah-sisi sebelum P2).

## Out of Scope

- Agregasi sosial ("A & 3 lainnya menyukai") — desain terpisah.
- Realtime/websocket.
- Perubahan visual redesign yang sudah merged (hanya sisi avatar & data).
- Halaman preferensi notifikasi.

## Acceptance Criteria

1. P0: tap "Feed kamu sudah tayang/dibagikan" → buka post itu (bukan feed generik) + thumbnail post tampil; tanpa rilis app.
2. P1a: tap notif pesanan → detail pesanan yang dimaksud (fetch by orderNumber), fallback ke daftar bila gagal.
3. P1b: notif follow menampilkan foto follower di KIRI, tidak di kanan.
4. P2: notif komentar/mention/like(single)/follow menampilkan foto aktor (brand-safe) di kiri; admin → identitas Natalo Petshop, bukan pemilik asli. Share & like-milestone tetap agregat (brand/ikon, tanpa avatar aktor — didescope). Semua call-site penulis-aktor (termасuk update-branch like/comment-like) brand-guard.
5. P3: notif pesanan/keranjang/promo menampilkan foto produk di kanan.
6. Semua field aktor/gambar baru brand-guard; tak ada kebocoran nama/foto pemilik admin.
7. Perilaku non-terkait (mark-read, fetch, pull-refresh, hero header) tak berubah.
</content>
