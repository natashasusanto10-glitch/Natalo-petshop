# Design — Double-tap like di halaman Postingan (video)

Tanggal: 2026-07-17
Status: Disetujui (menunggu review spec)

## Masalah

Di halaman detail postingan (`MemberPostDetailScreen`), video berperilaku beda dari feed dan dari Instagram:

- **Single tap pada video → langsung buka fullscreen** (scoped feed). Tidak ada jeda.
- **Double tap pada video TIDAK melakukan like** — gesture double-tap sengaja dimatikan untuk video (`onDoubleTap: post.isVideo ? null : ...` di widget konten detail).

Akar teknis: single-tap→fullscreen dipegang oleh `GestureDetector` **dalam** milik `_InlineVideoPlayer` (`onTap: _openFullscreen`), sedangkan double-tap-like ada di `GestureDetector` **luar** yang membungkus media. Karena keduanya detector terpisah, tap dalam menang di gesture arena dan langsung membuka fullscreen — window double-tap tak pernah sempat dievaluasi.

Foto di halaman yang sama SUDAH punya double-tap-like + heart burst; hanya video yang belum.

## Tujuan

Samakan perilaku video di halaman Postingan dengan Instagram / feed:

1. **Single tap** tidak lagi langsung fullscreen — dibuka **setelah** window double-tap lewat (~300 ms).
2. **Double tap** = like (Instagram behavior: hanya like, tidak un-like) + animasi heart.
3. **Animasi heart "fly-to"** — heart merah muncul di titik jari lalu terbang ke tombol like di action row, seperti feed. Foto ikut di-upgrade ke gaya fly-to agar seragam dalam satu layar.

## Non-tujuan

- Tidak menambah play/pause inline pada video di halaman Postingan (single tap tetap = buka fullscreen, bukan pause). Berbeda dari feed yang single-tap = play/pause.
- Tidak mengubah feed (`FeedVideoPostView`) — hanya jadi acuan pola.
- Tidak mengubah transisi morph fullscreen, logika like optimistic, atau alur scoped feed.

## Pendekatan

Kunci: **satukan single-tap dan double-tap ke SATU `GestureDetector`.** Saat `onTap` dan `onDoubleTap` berada di detector yang sama, framework Flutter menunda `onTap` sampai timeout double-tap lewat tanpa tap kedua — inilah "single tap tidak langsung" yang diminta, sekaligus memberi kesempatan double-tap terdeteksi.

### Perubahan (semua di `lib/screens/member_post_detail_screen.dart`)

1. **Detector luar pembungkus media** (di widget konten detail, saat ini sekitar baris 1400):
   - `onTap`: untuk video → picu buka fullscreen. Untuk foto → tetap null (single tap foto tidak melakukan apa-apa, seperti sekarang).
   - `onDoubleTapDown` + `onDoubleTap`: **aktifkan untuk video maupun foto** (buang gate `post.isVideo ? null`).
   - Saat `dormant` (fullscreen sedang terbuka) → tap dinonaktifkan.

2. **`_InlineVideoPlayer` melepas kepemilikan tap fullscreen** — hapus `onTap: _openFullscreen` dari `GestureDetector` dalam. Anchor key untuk transisi morph tetap dilaporkan ke atas lewat mekanisme yang sudah ada (`onVideoAnchorReady` / `onExpandRequested`), sehingga detector luar memicu `onOpenScopedFeed` dengan `(postId, anchorKey)` yang sama. Tombol **mute** (pojok kanan bawah) tetap punya `GestureDetector` sendiri sebagai hit-target terpisah — tidak terpengaruh.

3. **Heart fly-to bersama** — ganti overlay burst-di-tempat yang sekarang dengan helper bersama `feedPostBuildFlyingBurstHeart(...)` + `FeedPostBurstHeart` dari `lib/features/feed/widgets/feed_post_shared_widgets.dart`. Target terbang = pusat tombol like di action row, di-resolve via `GlobalKey` pada tombol like (pola sama seperti `_resolveLikeCenter()` di feed). Overlay tetap `IgnorePointer` agar tidak mengganggu tap berikutnya. Diterapkan ke video **dan** foto.

### Alur gesture setelah perubahan (video)

- 1 tap → framework tunggu ~300 ms → tidak ada tap kedua → `onTap` → buka fullscreen.
- 2 tap cepat → `onDoubleTap` → like (jika belum) + burst heart terbang ke tombol like; `onTap` tidak fire.
- Double-tap saat sudah liked → tidak un-like, tapi burst tetap tampil (feedback "sudah suka").
- Tap pada tombol mute → toggle mute (detector anak menang di regionnya).

## Trade-off (diterima)

Menambah `onTap` berdampingan dengan `onDoubleTap` membuat buka fullscreen tertunda ~300 ms (menunggu kepastian bukan double-tap). Ini konsekuensi wajib agar double-tap bisa dideteksi, dan sudah disepakati.

## Testing

Widget test pada halaman/komponen detail:

- Double-tap video → `onLike` terpanggil sekali + overlay burst muncul (opacity > 0).
- Double-tap video saat sudah liked → `onLike` TIDAK terpanggil, burst tetap muncul.
- Single-tap video → callback buka fullscreen terpanggil (via fake `onOpenScopedFeed` / `onExpandRequested`); dan TIDAK terpanggil saat masih dalam window double-tap.
- Foto: double-tap tetap like + burst (regresi tidak berubah selain gaya fly-to).
- Tombol mute tetap toggle mute, tidak memicu fullscreen.

## Yang tidak berubah

Swipe horizontal carousel foto, tombol mute, transisi morph fullscreen, logika like optimistic + like count, dan perilaku video (tidak di-pause).
