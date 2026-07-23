# Spec B — Tandai Orang (Tag People) ala Instagram

**Tanggal:** 2026-07-23
**Status:** Draft — menunggu review user
**Bagian dari:** rencana 5 bagian (A–E) mengganti tag belanja dengan Tag People + Hashtag + Lokasi. Spec A (tutup tag belanja + tab Ditandai shell) selesai di PR #245.

## Tujuan

User bisa menandai user lain di post feed — titik interaktif di foto (persis IG), daftar nama untuk video. Yang ditandai dapat notifikasi, post-nya masuk tab **Ditandai** di profil (cangkang kosong dari Spec A diisi data sungguhan), dan yang ditandai punya kendali: hapus tag dirinya atau sembunyikan dari profilnya.

Referensi perilaku: IG versi 2025–awal 2026 (riset web + screenshot user).

## Cakupan

**Masuk Spec B:**
1. Layar khusus "Tandai Orang" di composer (foto: tanam titik; video: daftar).
2. Penyimpanan tag (tabel `FeedTaggedUser`) + API create/read/remove/hide.
3. Viewer: badge ikon orang + pill tap-to-reveal (foto) + sheet "Ditandai dalam video ini" (video).
4. Notifikasi `feed_tagged` ke yang ditandai.
5. Tab Ditandai terisi data sungguhan (profil sendiri & publik).
6. Tag Options untuk yang ditandai: **Hapus saya dari post** + **Sembunyikan dari profil saya**.

**DILUAR cakupan (spec lanjutan):**
- Edit tag setelah post terbit (app belum punya edit post sama sekali).
- Manually approve tags / tombol "Manage" / bulk hide-remove.
- Setting "siapa boleh menandai saya" (Semua/Follow/Tidak ada) — Spec B: semua user terdaftar bisa ditandai.
- Sheet "Di Foto Ini" untuk post foto (tap badge = tap foto saja).
- Invite collaborators, Add music (tidak akan dibuat).
- Auto-fade badge ala IG — badge kita selalu tampil (lebih sederhana, aman saat scroll cepat).

## 1. Data & API

### Tabel baru `FeedTaggedUser` (Prisma)

Meniru pola `FeedPostProduct`:
- `id`, `feedPostId` (FK → FeedPost, **onDelete: Cascade**), `mediaId` (FK → FeedMedia, nullable — null untuk video, Cascade), `taggedUserId` (FK → User), `x`, `y` (Float nullable, pecahan 0–1 dari lebar/tinggi foto; null untuk video), `hidden` (Boolean default false), `createdAt`.
- Unik `(feedPostId, taggedUserId)` — satu orang satu tag per post (sesuai IG).
- Index `taggedUserId` (query tab Ditandai).
- **Migration file sungguhan + apply ke kedua database Neon — BUKAN `db push`** (insiden schema-drift product-video).

### API

- **`POST /api/feed/posts`** (existing) — body tambah `taggedUsers: [{userId, mediaIndex, x, y}]` (video: tanpa mediaIndex/x/y). Server: validasi user ada, `mediaIndex` menunjuk foto yang benar-benar ada, maks **20 tag per post**, koordinat 0–1. Mapping `mediaIndex`→`mediaId` dalam transaksi yang sama dengan `feedMedia.createMany`. Setelah simpan → kirim notifikasi (lihat §4).
- **`DELETE /api/feed/posts/[id]/tags/me`** — Hapus saya dari post. Hanya boleh oleh user yang ditandai (hapus baris miliknya sendiri).
- **`PATCH /api/feed/posts/[id]/tags/me`** `{hidden: bool}` — Sembunyikan/tampilkan dari profil. Hanya user yang ditandai.
- **`GET /api/u/[username]?content=tagged`** (perluasan endpoint profil publik) — post yang menandai user itu, terbaru dulu, **exclude `hidden=true`**. Jalur setara untuk profil sendiri (my-posts filter tagged atau endpoint saudara).
- Semua response post feed (feed, single post, profil, my-posts) ikut membawa `taggedUsers[]`: `{userId, username, name, profilePhotoUrl, mediaId/mediaIndex, x, y}` — pill dirender tanpa request tambahan.
- **WAJIB `lib/social/brand-user.ts`** di setiap endpoint di atas: identitas akun official tampil sebagai brand "Natalo Petshop", bukan data asli pemilik.

### Model Flutter

`FeedPost` dapat `List<FeedTaggedUser> taggedUsers` (kelas kecil: userId, username, name, photoUrl, mediaIndex?, x?, y?, `isSelf`-able via memberStore). Ikut `fromJson` **dan `toJson` (lossless — aturan repo)**.

## 2. Composer — layar "Tandai Orang"

- **Entry:** baris "Tandai Orang" di layar Buat Post (area bekas "Tag Produk Pernah Dibeli"), ikon orang-dalam-bingkai + chevron. Kalau sudah ada tag → subtitle ringkasan ("2 orang" / nama).
- **Layar (foto):** judul tengah "Tandai Orang", tombol selesai lingkaran biru brand + centang di kanan atas, foto di tengah, hint "Ketuk foto untuk menandai orang" di bawah.
  - Tap titik mana pun di foto → panel pencarian fullscreen (search bar "Cari akun" + Batal; endpoint `/api/users/search` existing; UI meniru picker cari-akun/mention yang ada).
  - Pilih akun → pill gelap (username putih + panah pointer) tertanam **tepat di koordinat tap user** (bebas, bukan grid).
  - Pill **bisa di-drag** untuk digeser; posisi akhir yang disimpan. Haptic ringan saat mulai drag.
  - Tap pill → tombol X untuk hapus.
  - **Carousel:** swipe antar foto di layar ini, tanam titik per-foto, indikator halaman. Limit 20 total → snackbar saat penuh.
  - Animasi pill muncul: pop scale-fade `easeOutCubic` (konsisten Spec A).
- **Layar (video):** daftar sederhana — cari → tambah ke list → bisa hapus. Tanpa titik.
- **Kirim:** array tag ikut jalur upload existing (`startPhotoUpload`/`startVideoUpload`). Draft video: tag ikut tersimpan & dipulihkan seperti caption (mekanisme draft Fase 2).
- Semua teks bahasa Indonesia.

## 3. Viewer di feed

- **Badge:** ikon orang kecil (siluet putih, lingkaran semi-transparan) pojok kiri-bawah media ber-tag. Selalu tampil (tanpa auto-fade).
- **Foto — tap sekali di foto atau badge:** toggle pill untuk slide yang sedang dilihat; muncul pop-fade `easeOutCubic`, tap lagi → hilang. Ganti slide carousel → pill ikut ganti. **Tidak boleh merusak double-tap like** (`onTap` + `onDoubleTap` GestureDetector — Flutter menunda single-tap otomatis).
- **Tap pill (orang lain):** navigasi profil publik `/u/username`.
- **Tap pill (nama sendiri):** sheet **"Opsi Tag"** — "Hapus saya dari post" (merah, konfirmasi ringan) + "Sembunyikan dari profil saya" / "Tampilkan di profil saya" (toggle) + Batal.
- **Video — tap badge:** sheet **"Ditandai dalam video ini"** — daftar avatar+nama+username, tap → profil; baris nama sendiri → pintu Opsi Tag yang sama. (Ini satu-satunya surface tag utk video — wajib ada.)
- Setelah "Hapus saya": pill/baris hilang seketika (optimistic) + post keluar dari tab Ditandai user itu.

## 4. Notifikasi

- Event baru **`feed_tagged`** di `FeedNotificationEventType` + fungsi `sendTaggedUserNotifications` di `lib/feed/activity-notifications.ts` (template: `sendMentionNotifications`), dipanggil dari POST create setelah transaksi sukses.
- Teks: **"[Nama] menandai Anda dalam postingan"**. Penandai official → nama brand.
- `prefCategory: "feed"` (mengikuti toggle "Aktivitas Feed" existing). Push via `sendPushToUser` + `sendFcmToUser` (JANGAN + sendApnsToUser — gotcha iOS dobel).
- Deep-link: `/feed/<postId>`.
- Tidak ada notifikasi ke diri sendiri (kalau menandai diri sendiri, boleh, tapi tanpa notif).

## 5. Tab Ditandai (mengisi cangkang Spec A)

- **Profil publik:** hapus short-circuit `_shortCircuitTaggedContent` di `public_profile_screen.dart`; filter `shoppable` (label Ditandai) fetch `content=tagged` sungguhan.
- **Profil sendiri (MemberScreen):** `_taggedPosts => const []` diganti fetch nyata (endpoint tagged-of-me).
- Grid & buka post: reuse persis widget tab Postingan/Video.
- Post `hidden` oleh user itu tidak tampil (di kedua layar; profil publik juga exclude hidden — hidden berlaku global untuk profil user tsb).
- Empty state: teks Spec A tetap ("Belum ada postingan yang menandaimu" / versi orang-ketiga di profil publik).

## 6. Testing

- Backend: unit/route test — validasi limit 20, mediaIndex, unik per user, remove/hide hanya oleh yang ditandai, brand-user di response, `content=tagged` exclude hidden.
- Flutter: widget test layar Tandai Orang (tanam/geser/hapus pill, limit), overlay pill viewer (toggle, tak ganggu double-tap like), sheet video, Opsi Tag (remove optimistic), tab Ditandai terisi & kosong.
- `FeedPost.toJson` round-trip taggedUsers.
- Golden bila layout profil berubah (kemungkinan tidak — grid reuse).

## Keputusan & trade-off tercatat

- Semua user terdaftar bisa ditandai (tanpa gate follow) — pengaman: Remove me + Hide.
- Badge selalu tampil ≠ IG (auto-fade) — disengaja, lebih sederhana.
- Sheet "Di Foto Ini" foto ditunda; versi video wajib (satu-satunya surface).
- Edit tag pasca-post, approve manual, setting siapa-boleh-menandai → spec lanjutan.
