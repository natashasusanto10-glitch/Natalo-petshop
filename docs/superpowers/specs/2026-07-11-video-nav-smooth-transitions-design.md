# Video nav smooth transitions — desain

Status: disetujui (mockup + koreksi perilaku profil ala IG) — siap masuk writing-plans.

## Latar belakang

Dua entry point dengan perilaku target BERBEDA (koreksi dari revisi pertama —
user menunjukkan screenshot IG sebagai referensi perilaku profil):

1. **"Postingan Terkait"** (`product_detail_screen.dart` → `_CustomerPostCard._openPost`):
   saat ini tap video membuka `MemberPostDetailScreen` (kartu terang, video muted,
   slide-push standar). Target: **langsung** ke feed video imersif scoped.
2. **Grid profil** (`public_profile_screen.dart` `_openPost` + `member_screen.dart`
   `_openPostDetail`, 3 tab Semua/Video/Ditandai): saat ini tap thumbnail membuka
   `MemberPostDetailScreen` (daftar post user, video autoplay inline muted) — ini
   TETAP. Yang kurang: tap videonya seharusnya mengembang ke fullscreen imersif
   (kode `_FullScreenVideoRoute` ada tapi dead — tidak pernah dipanggil), ala IG:
   grid → daftar Posts → tap video → fullscreen Reels, video lanjut tanpa restart.

Foto/carousel TIDAK berubah di mana pun (Hero `post-thumb-${post.id}` existing
sudah mulus).

## Tujuan

### A. Postingan Terkait → langsung feed imersif

1. Tap thumbnail **video** → thumbnail membesar & menyatu (scale/morph ~440ms
   ease-out, gaya "Membesar dari thumbnail" yang dipilih dari mockup) menjadi
   tampilan **video feed asli** — reuse komponen `FeedScreen` (gelap,
   autoplay+suara, rail like/comment/share/more, identitas kreator+badge official,
   caption, chip produk, progress bar), bukan replikasi.
2. Swipe vertikal = antar **video terkait produk itu saja** (scoped), bukan feed
   komunitas global.
3. Tap **foto** → tetap `MemberPostDetailScreen` seperti sekarang.

### B. Grid profil → daftar Postingan (tetap) → tap video → fullscreen mulus

1. Tap thumbnail di grid → `MemberPostDetailScreen` **tetap seperti sekarang**
   (daftar post user itu sendiri, tema existing, video autoplay inline muted,
   Hero foto existing). Tidak ada perubahan visual di level ini.
2. Tap **video yang sedang bermain** di daftar itu → video **mengembang mulus ke
   fullscreen imersif** ala IG Reels:
   - **Video TIDAK restart** — controller video yang sama dipakai terus
     (syarat teknis keras); yang berubah hanya chrome: kartu → fullscreen
     (rail aksi kanan, caption expandable, back kiri-atas, unmute).
   - Back (chevron / swipe-down) → menyusut kembali ke posisi kartu di daftar,
     video tetap lanjut (kembali muted mengikuti preferensi inline).
3. Fullscreen dari profil menampilkan **video itu sendiri** (bukan PageView
   scoped) — konteks daftarnya sudah di `MemberPostDetailScreen`; swipe
   antar-post terjadi dengan scroll daftar, bukan di dalam fullscreen.

## Pendekatan

### 1. Extract `_FeedPostView` jadi widget shared (untuk A)

`_FeedPostView` (private di `feed_screen.dart:1881`) di-extract jadi
`FeedVideoPostView` publik di `lib/features/feed/widgets/feed_video_post_view.dart`
dengan kontrak sama (`post`, `isActive`, `preloadedController`,
`onOverlayStateChanged`, `onMediaZoomChanged`, `preloadedCachedPlayer`) + callback
aksi (like/comment/share/more/follow/product-tap) supaya tidak depend ke state
private `_FeedScreenState`. `FeedScreen` di-refactor memakai widget shared ini
(satu implementasi, tidak drift).

### 2. Layar baru `ScopedVideoFeedScreen` (untuk A)

`lib/screens/scoped_video_feed_screen.dart`:

```dart
class ScopedVideoFeedScreen extends StatefulWidget {
  final List<FeedPost> posts;   // video-only, caller yang filter
  final int initialIndex;
  const ScopedVideoFeedScreen({required this.posts, required this.initialIndex});
}
```

- `PageView.builder` vertical (pola `FeedScreen`, `PageController(initialPage:
  initialIndex)`), item → `FeedVideoPostView`, preload window ±1 direplikasi dari
  `FeedScreen._managePreloadWindow`.
- Like/comment/share/follow via `feedService`/`feedStore` (sinkron lintas layar).
- Full immersive, back chevron overlay kiri-atas.
- `posts.length == 1` → render normal, swipe tidak berpindah.

### 3. Transisi masuk A: scale/morph dari thumbnail

Custom `PageRouteBuilder` (bukan `Hero` — `VideoPlayer` bukan Hero destination
yang valid, alasan yang sama kenapa Hero video di-skip di kode existing):

- Ambil rect thumbnail asal (`RenderBox`) saat tap.
- Route masuk: `Transform` rect-thumbnail → fullscreen, `borderRadius` 14 → 0,
  ~440ms `Curves.easeOutCubic`.
- Selama scale berjalan tampilkan **snapshot thumbnail** yang di-scale; video
  mulai render/autoplay setelah animasi selesai (hindari video "mengambang" saat
  kecil + beri waktu buffer MP4/HLS).
- Dibungkus helper `pushScaledVideoFeed(context, {required GlobalKey thumbnailKey,
  required List<FeedPost> posts, required int initialIndex})`.

### 4. Transisi fullscreen B: expand in-place tanpa restart

Di `member_post_detail_screen.dart`:

- `_InlineVideoPlayer` diberi `onTap` (area video, selain tombol mute) →
  mengembang ke fullscreen.
- **Controller di-share**: fullscreen menerima `CachedVideoPlayerPlus`/
  `VideoPlayerController` yang SAMA dari inline player (bukan init baru) —
  posisi playback lanjut persis. Inline player menandai controller sedang
  "dipinjam" supaya `VisibilityDetector`-nya tidak mem-pause saat kartu keluar
  viewport di belakang overlay.
- Transisi: rect kartu video → fullscreen (scale/morph sama gaya A, ~440ms),
  `PageRouteBuilder` transparan (`opaque: false`) supaya daftar tetap terlihat
  di belakang selama animasi.
- Masuk fullscreen: unmute (independen dari `appSettingsStore.feedMuted`,
  perilaku sama seperti niat `_FullScreenVideoRoute` lama); keluar: kembalikan
  volume mengikuti preferensi inline.
- Chrome fullscreen: reuse `FeedVideoPostView` bila memungkinkan TANPA PageView
  (single post), atau minimal komponen shared-nya (rail `FeedActionRail`,
  `FeedCreatorIdentity`, `FeedExpandableCaption` dari `features/feed/widgets/`)
  supaya visual identik feed.
- Back: chevron + swipe-down → reverse morph ke rect kartu, kembalikan
  controller ke inline player.
- `_FullScreenVideoRoute` lama (dead code, init controller sendiri = restart)
  dihapus/diganti implementasi baru ini.

### 5. Perubahan entry point

- **`product_detail_screen.dart`** (`_CustomerPostCard._openPost`): setelah fetch
  `fetchPostById` (loading dialog existing tetap), `post.isVideo` → kumpulkan
  video-only dari `_ProductCustomerPost` section itu → fetch/mapping ke `FeedPost`
  → `pushScaledVideoFeed`; foto → `MemberPostDetailScreen` seperti sekarang.
- **`public_profile_screen.dart`** & **`member_screen.dart`**: TIDAK berubah —
  tetap push `MemberPostDetailScreen` seperti sekarang (perilaku baru B ada di
  dalam `MemberPostDetailScreen` sendiri).

Catatan index (A): `initialIndex` relatif ke sub-list video-only
(`posts.where((p) => p.isVideo)`), bukan index list campuran.

## Yang TIDAK berubah

- `MemberPostDetailScreen`: tetap tujuan tap grid profil & tujuan foto Postingan
  Terkait; tema/layout-nya tidak berubah.
- `FeedScreen` (tab utama): perilaku user sama; hanya sumber widget item jadi
  shared.
- Foto/carousel: Hero existing dipertahankan di semua path.

## Error handling

- A: `fetchPostById` gagal/null → `AppToast` warning, tidak push (existing).
- B: kalau controller inline belum siap (video masih buffering) saat di-tap →
  fullscreen tetap terbuka dengan poster/thumbnail + spinner, lanjut play begitu
  siap (controller tetap yang sama).
- B: route fullscreen di-pop paksa (mis. deep link) → controller wajib
  dikembalikan ke inline player (jangan dispose ganda / bocor).

## Testing

- Widget test A: tap video di Postingan Terkait → `ScopedVideoFeedScreen`
  termount, `initialIndex` benar (foto ter-exclude, tidak error); tap foto →
  `MemberPostDetailScreen` (regresi).
- Widget test B: tap area video inline di `MemberPostDetailScreen` → route
  fullscreen muncul; pop → kembali tanpa exception; controller tidak di-dispose
  ganda (tidak ada error "used after dispose").
- Manual/device-verify: transisi scale halus dua arah, video B tidak restart
  (posisi playback lanjut), unmute/mute benar saat masuk/keluar fullscreen,
  like/comment sinkron lintas layar (feedStore), swipe scope A tidak bocor ke
  video luar konteks.
