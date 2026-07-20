# Notifikasi — Aksi Inline "♡ + Balas" pada Notif Komentar (ala IG)

**Date:** 2026-07-20
**Scope:** Backend web (`prisma/`, `lib/feed/`, `app/api/`) + client Flutter (`flutter_app/`)
**Status:** Draft for review
**Depends on:** Redesign notifikasi (#189), P2 actor fields (#195), format komentar IG-style + lencana like (#203), pill follow-back (#207 — pola seam injeksi & aksi-inline pertama di layar ini).

## Latar

Studi screenshot IG (sinarpetstore): di bawah tiap notif komentar ada baris aksi **♡ Reply**. Tap ♡ → like komentar itu langsung di tempat. Tap Reply → **composer balas ringan** muncul di atas daftar notifikasi (bar input + baris emoji cepat + keyboard, "Replying to {user}", input terisi `@username `) — BUKAN pindah layar / buka sheet komentar penuh; daftar notifikasi tetap terlihat di belakang.

Audit kode (terverifikasi):

- **Like komentar**: backend `app/api/feed/comments/[id]/like/route.ts` — `PUT` (set liked) / `DELETE` (set unliked), **idempotent** (`reconcileFeedLikeState` upsert/deleteMany; PUT saat sudah liked = no-op, respons tetap `{ok, liked, likeCount}`). Flutter `feedService.setCommentLiked(commentId, {required liked})` (`feed_service.dart:344`) sudah memanggil persis ini.
- **Kirim balasan**: `POST /api/feed/posts/{id}/comments` body `{content, parentCommentId?}` — threading satu level (reply-ke-reply di-reparent ke root, `route.ts:239-250`). Flutter `feedService.postComment(postId, {required content, parentCommentId})` (`feed_service.dart:291`) sudah dipakai sheet komentar.
- **BLOCKER tunggal**: `commentId` pemicu notif TIDAK pernah sampai ke app — builder menaruh `data.comment_id` yang hanya masuk push toast OS (`notification-center.ts:136-147`); baris `Announcement` tak punya kolomnya (`schema.prisma` model Announcement tanpa kolom data/commentId); mapper `/api/notifications/me` tak meneruskannya.
- **Tak ada API ambil-satu-komentar** (`app/api/feed/comments/[id]/route.ts` hanya `DELETE`) — padahal composer butuh **username** author (notif hanya simpan `actorName` = nama tampilan, bukan username) + validasi komentar masih ada.
- Status like per komentar tersedia di list komentar (`viewerLiked`, `queries.ts:710`) tapi TIDAK tersedia per notifikasi.

## Keputusan produk (disepakati)

1. Dua aksi sekaligus: **♡ (toggle like inline)** + **"Balas"**.
2. Balas = **composer ringan overlay** ala screenshot IG (tetap di layar notifikasi), BUKAN sheet komentar penuh.
3. Hati default **outline** (tanpa fetch status per baris — hemat; N baris = N request kalau difetch). Setelah tap, status akurat dari server (idempotent). Kompromi sadar vs IG yang tahu status awal; bisa di-upgrade nanti.
4. Visual pakai **token Natalo** (w400/w600, biru brand `NataloColors`), bukan jiplakan visual IG mentah.

## Desain

### D1. Backend — migration `commentId` + expose

- **Migration** (SQL tulis-tangan, `ADD COLUMN IF NOT EXISTS`, timestamp > terbaru): `Announcement.commentId String?` + field Prisma di model `Announcement`.
- **Builder** yang mengisi (semuanya SUDAH memegang commentId di scope):
  - `createFeedNotification` (`lib/feed/notification-center.ts`): param opsional baru `commentId?: string | null` → tulis ke kolom saat `prisma.announcement.create`.
  - `sendCommentNotification` (`lib/feed/activity-notifications.ts`): teruskan `commentId: params.commentId` (field ini sudah ada persis di signature-nya).
  - `sendReplyNotification` (`lib/feed/activity-notifications.ts`): signature-nya **tidak punya field `commentId`** (params: `parentCommentId`, `replyCommentId`, `postId`, `actorUserId`, `content`) — teruskan `commentId: params.replyCommentId` (balasan yang baru dibuat = target reply yang benar). Menulis `params.commentId` di sini adalah error kompilasi TypeScript (properti tak ada) — verifikasi ulang saat implementasi.
  - `sendCommentLikeNotification`: teruskan `commentId: params.commentId` (create path; cabang agregat `announcement.update` TIDAK perlu menyentuh commentId — nilai dari create tetap benar utk komentar yang sama).
- **Mapper** `/api/notifications/me` (`mapAnnouncement`): expose `commentId` (findMany tanpa select → kolom auto-tersedia; hanya tipe param + return).
- **Client model** `AppNotification`: field `commentId` (parse dual-key `commentId`/`comment_id`, copyWith).

### D2. Backend — endpoint `GET /api/feed/comments/{id}`

- File existing `app/api/feed/comments/[id]/route.ts` (saat ini hanya `DELETE`) — tambah handler `GET`.
- **Pra-syarat**: `mapFeedComment` (dan helper `resolveOfficialMentionHandles`) di `lib/feed/queries.ts` saat ini **module-private** (tanpa `export`), dipakai hanya oleh `listFeedComments` internal. Tambahkan `export` ke keduanya (tanda tangan tak berubah) supaya endpoint baru bisa reuse tanpa menulis mapping baru. Caller (handler GET) membangun sendiri argumen `viewerLikedIds`/`officialHandles` yang diminta mapper — pola sama seperti `listFeedComments` membangunnya sekarang, hanya untuk satu komentar.
- Respons: satu komentar ter-map **via mapper brand-safe existing** (`mapFeedComment`, kini exported — WAJIB reuse, jangan tulis mapping baru; admin → identitas brand, foto null) + `viewerLiked` bila session ada + `postId` induk.
- **Dua alasan 404, dua pesan berbeda** (dibedakan di respons agar D4 bisa menampilkan pesan tepat):
  - Komentar tak ada / soft-deleted → 404 `{error: "Komentar tidak ditemukan"}`.
  - **Post induk sudah dihapus/tak aktif** (`deletedAt` non-null ATAU `status !== "ACTIVE"`) → 404 `{error: "Postingan sudah dihapus"}`. Guard ini WAJIB ada (pola sama seperti like-route `app/api/feed/comments/[id]/like/route.ts:66-69,81-90`) — comment routes lain (DELETE existing) tidak melakukan cascade ke comment saat post dihapus, jadi tanpa guard ini `fetchCommentById` akan sukses untuk post yang sudah tak ada dan composer (D4) akan terbuka untuk balasan yang tak mungkin terkirim.
- Tanpa auth wajib (komentar publik; `viewerLiked` false bila anonim) — konsisten kebijakan list komentar.
- Flutter: method service baru `feedService.fetchCommentById(String commentId)` → `FeedComment` (+ `postId`); harus membedakan kedua alasan 404 di atas (mis. lewat pesan error dari body atau exception type terpisah) supaya D4 bisa memilih snackbar yang tepat.

### D3. Client — baris aksi ♡ + Balas di notif komentar

- **Gate**: baris aksi baru dirender HANYA bila `eventType == 'feed_new_comment'` DAN `notification.commentId` non-empty DAN `feedPostId` non-empty. Notif komentar LAMA (pra-migration, commentId null) → fallback pill "Lihat Komentar" existing, tak berubah. (Notif comment-like ikut gate yang sama bila eventType-nya `feed_new_like` — TIDAK dapat aksi ini; scope hanya notif komentar/balasan.)
- **Layout** (menggantikan blok pill generik utk baris yang lolos gate, pola if/else-if sama pill follow-back #207): `[♡ ikon 18px, tap-target 44px]` + `[pill "Balas" gaya CTA existing]` + waktu relatif.
- **♡ toggle**: state lokal widget (idle outline → tap → optimistik ❤️ merah `Color(0xFFE11D48)` + `setCommentLiked(commentId, liked: true)`; tap lagi → outline + `liked: false`). Gagal → rollback + snackbar "Gagal menyukai komentar." `AppHaptics.tap()` saat tap. `if (!mounted) return;` setelah await. Busy-guard (abaikan tap saat request in-flight).
- Tap area baris lain → navigasi existing (buka post) tak berubah.

### D4. Client — composer balas ringan (widget baru)

- Widget baru `NotificationReplyComposer` (file terpisah `flutter_app/lib/widgets/notification_reply_composer.dart` — layar notifikasi sudah besar), dibuka via `showModalBottomSheet` (transparan, daftar notif tetap terlihat di belakang barrier).
- **Wajib keyboard-safe** — codebase ini sudah pernah kena bug persis ini: `home_screen.dart:591-595` mencatat `showModalBottomSheet` transparan dulu dipakai lalu dibuang karena "blur abu-abu, input susah dilihat, layout rusak saat keyboard muncul". Composer ini WAJIB `isScrollControlled: true` + hitung `MediaQuery.viewInsetsOf(context).bottom` eksplisit sebagai bottom padding (pola yang sudah terbukti jalan di `feed_video_post_view.dart:2089-2093`), BUKAN mengandalkan default `showModalBottomSheet`/`resizeToAvoidBottomInset` implisit.
- **Alur tap "Balas"**: pill → spinner-di-pill → `fetchCommentById(commentId)`:
  - Sukses → buka composer: label "Membalas @{username}" (username dari comment author; author tanpa username → fallback nama tampilan tanpa `@`), input ter-prefill `@{username} ` + fokus otomatis, **baris emoji cepat** (❤️ 🙌 🔥 👏 😢 😍 😮 😂 — tap menyisipkan ke input), tombol kirim bulat biru brand (disabled saat input kosong/hanya whitespace).
  - 404 komentar dihapus → snackbar "Komentar sudah dihapus." — composer tak dibuka; pill balik normal.
  - 404 postingan dihapus (guard D2) → snackbar "Postingan sudah dihapus." — composer tak dibuka; pill balik normal.
  - Error lain → snackbar "Gagal memuat komentar. Coba lagi."
- **Kirim** → `postComment(feedPostId, content: text, parentCommentId: commentId)` → tutup composer + snackbar "Balasan terkirim". Gagal krn validasi/network biasa → composer TETAP terbuka + snackbar error (draf tak hilang). Gagal krn 404 "post tidak ditemukan" (race kecil: post terhapus tepat di antara buka-composer dan kirim, celah yang guard D2 tak menutup 100%) → composer DITUTUP + snackbar "Postingan sudah dihapus." (draf komentar utk post yang sudah tak ada tak berguna dipertahankan). `if (!mounted) return;` setelah tiap await.
- Threading: `parentCommentId` = commentId notif; bila komentar itu sendiri sebuah balasan, server otomatis reparent ke root (perilaku existing `route.ts:239-250`) — composer tak perlu tahu.
- Brand-safety: username/nama author dari endpoint D2 sudah brand-safe (mapper existing).

### Testabilitas

- Seam injeksi pola #207: `NotificationRow` param opsional tambahan (mis. `FeedService?`/fetcher typedef) default ke global — widget test menyuntik fake (like sukses/gagal, fetch 404, kirim sukses/gagal).
- Backend unit (`tsx --test`): builder mengisi `commentId` (komentar/reply/comment-like create); mapper expose; endpoint GET single-comment — 404, brand-safe admin author, `viewerLiked`.
- Widget test: gate (commentId null → pill lama; non-komentar → tak ada aksi); ♡ optimistik + rollback saat gagal; Balas → 404 → snackbar tanpa composer; composer kirim → `postComment` terpanggil dgn `parentCommentId` benar; tombol kirim disabled saat kosong.

## Out of Scope

- Status like awal per notifikasi (fetch per baris / kolom denormalized) — hati mulai outline.
- Scroll-to-comment / highlight di sheet komentar penuh.
- Aksi inline utk notif comment-like/mention/share.
- Mention autocomplete penuh di composer (input teks polos + prefill @username; mention tetap terparse server-side seperti komentar biasa).

## Urutan Deploy

1. **Migration deploy** (`commentId`, backward compatible).
2. Backend deploy (builder isi kolom + mapper + endpoint GET) — notif komentar BARU mulai membawa commentId; app lama abaikan field (aman).
3. Rilis app Flutter → aksi ♡/Balas muncul utk notif komentar baru; notif lama tetap pill "Lihat Komentar".

## Acceptance Criteria

1. Notif komentar baru menampilkan ♡ + "Balas"; notif komentar lama (tanpa commentId) tetap pill "Lihat Komentar"; notif non-komentar tak berubah.
2. Tap ♡ → komentar ter-like (optimistik, rollback saat gagal); tap lagi → unlike. Idempotent — tak pernah salah state setelah respons server.
3. Tap "Balas" → composer ringan muncul di atas daftar notifikasi (tak pindah layar): "Membalas @username", input ter-prefill, emoji cepat, kirim → balasan masuk thread yang benar (`parentCommentId`).
4. Komentar sudah dihapus ATAU postingan induknya sudah dihapus → pesan jelas sesuai penyebab, tanpa crash/composer kosong; bila postingan terhapus tepat saat proses kirim (celah race), composer tertutup otomatis dgn pesan jelas (bukan dibiarkan terbuka kosong).
5. Author admin di composer tampil sebagai identitas brand (brand-safe, tanpa bocor nama pemilik).
6. Perilaku non-terkait (routing tap baris, pill follow-back, lencana like, mark-read) tak berubah.
