# Video nav smooth transitions — desain

Status: disetujui (mockup) — siap masuk writing-plans.

## Latar belakang

Saat ini, tap thumbnail **video** di tiga tempat:

1. "Postingan Terkait" (`product_detail_screen.dart` → `_CustomerPostCard._openPost`)
2. Grid post di halaman profil orang lain (`public_profile_screen.dart` → `_openPost`)
3. Grid "Postingan Saya" (`member_screen.dart` → `_openPostDetail`, 3 tab: Semua/Video/Ditandai)

...semuanya membuka `MemberPostDetailScreen`: halaman kartu bertema **terang** (app bar putih "Postingan / <author>"), video **auto-play tanpa suara**, transisi `MaterialPageRoute` slide-push standar. Ini terasa seperti "pindah ke halaman lain", bukan menonton video, dan berbeda total dari pengalaman `FeedScreen` (Reels-style: gelap, immersive, autoplay+suara, rail aksi kanan).

Foto/carousel di layar yang sama SUDAH punya transisi mulus (Hero `post-thumb-${post.id}`) — jadi masalahnya spesifik ke video (Hero sengaja dilewati untuk `VideoPlayer`, sesuai komentar existing di kode).

## Tujuan

Saat tap thumbnail **video** dari ketiga entry point di atas:

1. Thumbnail membesar & menyatu (scale/morph transition, ~440ms ease-out) menjadi tampilan **video feed asli** — reuse komponen `FeedScreen` (gelap, autoplay+suara, rail like/comment/share/more, identitas kreator+badge official, caption, chip produk, progress bar), bukan replikasi terpisah.
2. Vertical swipe di dalamnya berpindah antar video **dalam konteks entry point**, bukan seluruh feed komunitas global:
   - Dari Postingan Terkait → video-video terkait produk itu saja.
   - Dari grid profil (orang lain ATAU "Postingan Saya" sendiri) → video-video milik user itu saja.
3. Foto/carousel TIDAK berubah — tetap Hero ke `MemberPostDetailScreen` seperti sekarang.
4. `MemberPostDetailScreen` sendiri tetap ada (masih dipakai kalau post-nya foto), tapi tidak lagi jadi tujuan tap untuk **video** di ketiga entry point.

## Pendekatan

### 1. Extract `_FeedPostView` jadi widget shared

`_FeedPostView` (dan dependensinya: preload/visibility/autoplay logic, `_managePreloadWindow` sliding-window controller) saat ini private di `feed_screen.dart:1881`. Extract jadi `FeedVideoPostView` publik di `lib/features/feed/widgets/feed_video_post_view.dart`, dengan kontrak yang sama seperti sekarang (`post`, `isActive`, `preloadedController`, `onOverlayStateChanged`, `onMediaZoomChanged`, `preloadedCachedPlayer`) ditambah callback untuk aksi (like/comment/share/more/follow/product-tap) supaya bisa dipakai di luar `_FeedScreenState` tanpa depend ke state privatenya.

`FeedScreen` sendiri di-refactor untuk memakai `FeedVideoPostView` yang baru (bukan duplikat) — supaya tidak ada 2 implementasi visual yang bisa drift.

### 2. Layar baru: `ScopedVideoFeedScreen`

Layar baru `lib/screens/scoped_video_feed_screen.dart`:

```dart
class ScopedVideoFeedScreen extends StatefulWidget {
  final List<FeedPost> posts;       // hanya video (caller filter foto)
  final int initialIndex;
  final bool isOwner;               // true → tampilkan menu edit/hapus di rail (parity MemberPostDetailScreen)
  const ScopedVideoFeedScreen({
    required this.posts,
    required this.initialIndex,
    this.isOwner = false,
  });
}
```

- Isi: `PageView.builder` vertical (persis pola `FeedScreen`, `PageController(initialPage: initialIndex)`), item builder → `FeedVideoPostView` per index, preload window ±1 direplikasi dari `FeedScreen._managePreloadWindow`.
- Like/comment/share/follow: panggil `feedService`/`feedStore` langsung (sama seperti `FeedScreen` dan `MemberPostDetailScreen` sekarang) — state like/comment count tetap sinkron lintas layar karena semua baca/tulis `feedStore`.
- `isOwner`: saat true, rail "..." menampilkan Edit caption/Hapus (reuse action existing dari `MemberPostDetailScreen`, dipindah ke helper bersama bila perlu).
- Tidak ada app bar terang — full immersive, tombol back (chevron) overlay kiri-atas seperti mockup.

### 3. Transisi masuk: scale/morph dari thumbnail

Custom `PageRouteBuilder` (bukan `Hero`, karena `VideoPlayer` tidak valid sebagai Hero destination — masalah yang sama seperti kenapa Hero video dilewati sebelumnya):

- Ambil `RenderBox` thumbnail asal (posisi + ukuran di layar) saat tap.
- Route baru masuk dengan `child` di-`Transform` dari rect-thumbnail → full-screen, `borderRadius` dari radius kartu (14) → 0, durasi ~440ms `Curves.easeOutCubic` (sama seperti mockup yang disetujui).
- Selama animasi scale berjalan, tampilkan **snapshot gambar thumbnail** (bukan video-nya langsung) yang di-scale — video asli baru mulai render/autoplay begitu animasi scale selesai (~menghindari video "mengambang" aneh saat masih kecil, dan support MP4/HLS yang butuh waktu buffer awal).
- Pola ini dibungkus helper reusable `pushScaledVideoFeed(context, {required GlobalKey thumbnailKey, required List<FeedPost> posts, required int initialIndex, bool isOwner})` supaya 1 implementasi dipakai oleh ketiga entry point (product detail, public profile, member screen tab manapun).

### 4. Perubahan di 3 entry point

- **`product_detail_screen.dart`** (`_CustomerPostCard._openPost`): setelah fetch `FeedPost` by id (logic existing tetap, termasuk loading dialog), cek `post.isVideo` — kalau true, panggil `pushScaledVideoFeed` dengan `posts` = daftar video di antara `_ProductCustomerPost` yang sama (yang sudah di-fetch sebagai preview di section itu; foto di-exclude dari list ini tapi index tetap dihitung relatif ke video-only list); kalau false (foto), tetap `Navigator.push(MemberPostDetailScreen(...))` seperti sekarang.
- **`public_profile_screen.dart`** (`_openPost`): filter `_posts` jadi video-only, hitung `initialIndex` relatif ke situ, panggil `pushScaledVideoFeed`. Kalau tap-nya foto, tetap ke `MemberPostDetailScreen` seperti sekarang (path existing tidak berubah untuk foto).
- **`member_screen.dart`** (`_openPostDetail`, dipanggil dari 3 grid: Semua/Video/Ditandai): sama pola — video → `pushScaledVideoFeed(isOwner: true)`; foto → `MemberPostDetailScreen` existing.

Catatan index: karena `ScopedVideoFeedScreen` cuma menerima video, `initialIndex` yang dikirim adalah index post itu di dalam **sub-list video**, bukan index di grid campuran asli. Helper filter kecil (`posts.where((p) => p.isVideo).toList()` + cari index post yang di-tap di dalamnya) dipakai di ketiga caller.

## Yang TIDAK berubah

- `MemberPostDetailScreen` tetap ada dan tetap jadi tujuan untuk **foto/carousel** di ketiga entry point (Hero existing dipertahankan).
- `FeedScreen` (tab Feed utama) tetap sama perilakunya untuk user — cuma sumber `_FeedPostView`-nya sekarang dari widget shared, bukan definisi privatenya sendiri.
- `_FullScreenVideoRoute` (dead code di `member_post_detail_screen.dart`) tidak disentuh/dipakai — di luar cakupan ini.

## Error handling

- Sama seperti alur `_openPost` existing di product detail: kalau `feedService.fetchPostById` gagal/null, tampilkan `AppToast` warning, tidak lanjut push.
- Kalau video di-tap ternyata satu-satunya di scope (`posts.length == 1`), `ScopedVideoFeedScreen` tetap render normal, cuma swipe atas/bawah tidak berpindah (sama seperti Reels saat feed cuma 1 item).

## Testing

- Widget test: tap video thumbnail di masing-masing 3 entry point → `ScopedVideoFeedScreen` termount dengan `initialIndex` benar (posts video-only, foto ter-exclude dari list tapi tidak error).
- Widget test: tap foto di ketiga entry point tetap ke `MemberPostDetailScreen` (regresi existing).
- Manual/device-verify: rasakan transisi scale (durasi, tidak ada frame video "telanjang" sebelum animasi selesai), swipe scope benar (tidak bocor ke video luar konteks), like/comment count sinkron antara `ScopedVideoFeedScreen` dan `FeedScreen`/`MemberPostDetailScreen` lain.
