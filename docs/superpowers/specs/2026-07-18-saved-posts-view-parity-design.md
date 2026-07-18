# Halaman Postingan Tersimpan — Parity dengan View Halaman Postingan

Tanggal: 2026-07-18
Branch: `claude/saved-posts-page-8d400c`

## Tujuan

Halaman **Postingan Tersimpan** (`/member/saved`) harus memakai **kembali** view halaman
Postingan (`member_posts_screen.dart`): grid full-bleed → tap tile → viewer vertikal yang
bisa di-swipe antar post, dengan animasi origin-expansion, warm video handoff, dan load-more.
Yang membedakan hanya **cakupan datanya**: daftar post yang di-simpan (bookmark) user,
**lintas akun** (foto / carousel / video dari akun mana pun), bukan post milik sendiri.

Referensi visual: halaman **Saved** Instagram — grid "Reels and posts", tap → viewer
vertikal per post.

## Kondisi sekarang (yang perlu diperbaiki)

`saved_posts_screen.dart` **belum** memakai view halaman Postingan:

| Aspek | Halaman Postingan (`member_posts_screen`) | Saved sekarang (`saved_posts_screen`) |
|---|---|---|
| Grid tile | `_GalleryPostTile` — `RepaintBoundary` + `originKey`, warm video-prep di `onTapDown` | `_SavedPostTile` — polos, tanpa originKey / warm-prep |
| Grid delegate | `profileGridDelegate()` (shared, gap 1.5) | `SliverGridDelegateWithFixedCrossAxisCount` (gap 2) |
| Transisi buka | `pushOriginExpansion` (origin-expansion) | `MaterialPageRoute` biasa |
| Daftar post | daftar penuh + `initialIndex` → swipe antar post | `posts: [post]` — 1 post, tak bisa swipe |
| Warm video handoff | ada (`warmVideoHandoff`) | tidak ada |
| Load-more | `loadMoreScopedPosts: fetchMyPosts` | tidak ada |
| Tab | — (filter foto/video/review) | Tab Semua/Belanja (akan dibuang) |

## Blocker penting: viewer sekarang single-author

`MemberPostDetailScreen` me-resolve author dari **satu** parameter top-level
(`authorName`/`authorPhotoUrl`/`authorInitial`/`isOwner`) untuk **seluruh** pager, lewat
`_postWithResolvedAuthor` (member_post_detail_screen.dart:615). Saat `!isOwner` dan
`authorName` null, `_memberName` mengembalikan literal **"Pengguna"** (member_post_detail_screen.dart:525)
dan menimpa `post.author.name`.

Ini benar untuk caller sekarang (public profile → post satu user, semua author sama), tapi
**salah** untuk saved feed yang **lintas akun** — setiap post punya pemilik berbeda. Kalau
di-reuse apa adanya, **semua post tersimpan akan tampil "Pengguna"** dengan avatar kosong.

## Desain

### 1. Halaman grid — `saved_posts_screen.dart`

- **Buang** `TabController` + tab "Semua/Belanja" + logika filter belanja + prefetch belanja.
  Satu grid saja (mirip IG Saved).
- **Tanpa subjudul.** Header hanya judul "Postingan Tersimpan" (18px, `NataloWeight.strong`)
  + tombol back, AppBar `cs.surface` (tema terang — konsisten halaman Postingan).
- **Grid delegate** ganti ke `profileGridDelegate()` (identik halaman Postingan, gap 1.5,
  full-bleed).
- **Tile** ganti `_SavedPostTile` → tile bersama (lihat §3): cover + badge tipe media
  (▶ video / ⧉ carousel), `originKey`, warm video-prep. **Tanpa status badge** (status
  pending/active urusan pemilik; tak relevan lintas-akun).
- **Empty / error state, pull-to-refresh paw, load-more grid** dipertahankan apa adanya.
- **Data lintas-akun**: isi grid = semua post `viewerSaved == true` dari endpoint
  `fetchSavedPosts` (sudah ada, feed_service.dart:153), tipe foto / carousel / video, dari
  akun mana pun. Identitas pemilik **tidak** ditampilkan di tile (bersih ala IG) — muncul di
  header viewer.

### 2. Buka post → reuse view halaman Postingan

Ganti pembukaan single-post menjadi meniru `_openPostDetail` (member_posts_screen.dart:441):

```
pushOriginExpansion<void>(
  context,
  originKey: tileKey,
  destinationBuilder: (_) => MemberPostDetailScreen(
    post: post,
    posts: <seluruh daftar saved>,
    initialIndex: index,
    isOwner: false,                 // sembunyikan edit/hapus
    authorPerPost: true,            // NEW — lihat §4
    warmVideoHandoff: handoff,
    initialNextCursor: _nextCursor,
    loadMoreScopedPosts: (cursor) => feedService.fetchSavedPosts(cursor: cursor),
  ),
);
```

Efeknya: bisa **swipe atas/bawah** antar post tersimpan, animasi origin-expansion, video
instan (warm handoff), dan infinite scroll scoped ke daftar tersimpan.

**Fullscreen video otomatis ikut.** `MemberPostDetailScreen` sudah punya fullscreen player
("Tap video → open fullscreen player", member_post_detail_screen.dart:70) beserta handoff
playback-nya. Karena viewer di-reuse seutuhnya, tap video di Saved membuka fullscreen
**sama persis** dengan halaman Postingan — tanpa kode tambahan.

### 3. Ekstrak `_GalleryPostTile` jadi widget bersama

`_GalleryPostTile` sekarang privat di `member_posts_screen.dart` (1564 baris). Ekstrak ke
`lib/features/feed/widgets/gallery_post_tile.dart` sebagai `GalleryPostTile` publik dengan
opsi `bool showStatusBadge`:

- Halaman Postingan: `showStatusBadge: true` (perilaku sekarang, tak berubah).
- Halaman Saved: `showStatusBadge: false`.

`member_posts_screen.dart` memakai versi ekstrak (mengganti referensi `_GalleryPostTile` →
`GalleryPostTile`). Sub-widget internal yang dipakainya (`_PostThumbnail`,
`_PostMediaTypeIcon`, `_StatusBadge`, `_thumbnailUrlForPost`, `_PostThumbnailFallback`) ikut
dipindah/di-share seperlunya. Tujuan: **satu sumber kode** → dua halaman selalu identik.

### 4. Perbaikan viewer: mode `authorPerPost`

Tambah field `bool authorPerPost = false` di `MemberPostDetailScreen`. Saat `true`:

- `_postWithResolvedAuthor(post)` **mengembalikan `post` apa adanya** — nama / foto /
  username / badge official diambil dari `post.author` masing-masing (server sudah mengisi
  lengkap via brand-user helper), **tanpa** menimpa dengan override top-level maupun
  "Pengguna".
- Getter `_memberName` / `_memberPhotoUrl` / `_memberInitial` (dipakai di luar per-post
  render) membaca dari post yang sedang aktif, bukan konstanta "Pengguna".

Caller lama (public profile, my-posts) memakai default `authorPerPost: false` → **zero
regression**.

### 5. Perilaku unsave

Bookmark di viewer = unsave. Grid me-listen `feedStore` dan `_allSavedPosts` difilter
`viewerSaved == true` (saved_posts_screen.dart:69) → tile **otomatis hilang** dari grid saat
kembali. Perilaku ini sudah jalan; dipertahankan.

## File tersentuh

1. `lib/screens/saved_posts_screen.dart` — buang tab/subjudul; pakai `profileGridDelegate()`
   + `GalleryPostTile` (showStatusBadge:false); buka viewer full-list + origin-expansion +
   warm handoff + load-more; `isOwner:false`, `authorPerPost:true`.
2. `lib/screens/member_post_detail_screen.dart` — tambah flag `authorPerPost` + cabang
   resolusi author per-post.
3. `lib/features/feed/widgets/gallery_post_tile.dart` (baru) — ekstrak `GalleryPostTile`
   (+ sub-widget pendukung); `member_posts_screen.dart` memakainya.

## Yang TIDAK berubah

- Endpoint/service `fetchSavedPosts` (sudah ada).
- Route `/member/saved` (main.dart:411).
- Caller `MemberPostDetailScreen` yang lain (default `authorPerPost:false`).
- Empty/error/refresh/load-more grid.

## Testing

- Widget test halaman Saved: grid render dari fetcher fake; tap tile membuka
  `MemberPostDetailScreen` dengan `posts` = daftar penuh + `initialIndex` benar,
  `isOwner:false`, `authorPerPost:true`.
- Test viewer: `authorPerPost:true` + daftar multi-author → header tiap post memakai
  `post.author` masing-masing (bukan "Pengguna"); edit/hapus tersembunyi.
- Regresi: caller lama (`authorPerPost:false`) tetap memakai override single-author.
- `flutter analyze` bersih; hindari hang shimmer di widget test (bounded pump-loop, mock
  prefs, clear cartStore) sesuai catatan repo.
