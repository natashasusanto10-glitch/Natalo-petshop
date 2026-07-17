# Detail Produk — reverse-target parity untuk morph video (spec #1)

Tanggal: 2026-07-17
Status: disetujui (menunggu review spec)

## Masalah

Di **Postingan Terkait** (Detail Produk), tap thumbnail video membuka viewer
fullscreen (`ScopedVideoFeedScreen`) lewat `pushScaledVideoFeed`
(`product_detail_screen.dart:2766`). Pemanggilan ini **tidak** meneruskan
`reverseTarget`/`reverseMorphEnabled` (berbeda dengan jalur
`member_post_detail_screen.dart:966` yang lengkap).

Akibatnya, saat user swipe ke video lain lalu menutup viewer, **morph tutup
selalu mengecil balik ke thumbnail pertama yang di-tap** — bukan ke post yang
sedang tampil. Ini "meleset" dan tidak seperti Instagram, yang selalu morph
kembali ke sel yang sedang dilihat dan menggeser grid ke sel itu.

## Non-tujuan

- **Warm handoff / pre-warm sesi video** — TIDAK dikerjakan. Rail Postingan
  Terkait menampilkan thumbnail statis (`_CustomerPostCard`, gambar diam), tak
  ada `VideoPlayerSession` inline untuk di-handoff. "Video load sebentar saat
  dibuka" adalah perilaku normal (IG pun begitu). `coordinator: null`.
- Durasi/kurva morph (260/220ms) — bagian batch #2–6, bukan di sini.
- Tampilan kartu, thumbnail, jalur tap-foto (non-video), fetch siblings — tak
  berubah.

## Perilaku target (paritas IG)

1. Tap thumbnail video → viewer fullscreen (seperti sekarang).
2. User swipe antar video di viewer.
3. Tutup viewer → morph mengecil balik ke **thumbnail post yang sedang tampil**,
   dan rail **auto-scroll** agar thumbnail itu terlihat sebelum morph mendarat.

## Arsitektur

### Komponen baru: `_RelatedPostsRail` (controller kecil, plain object)

Dimiliki oleh masing-masing permukaan yang me-render kartu. Tanggung jawab
tunggal: memetakan `postId → posisi/rect thumbnail` dan menyediakan target
morph-balik.

Antarmuka:

- `final ScrollController scroll` — dipasang ke `ListView`/grid permukaan.
- `GlobalKey keyFor(String postId)` — registry key **stabil per-post**
  (memoized dalam `Map<String, GlobalKey>`). Menggantikan `_thumbnailKey` lokal
  di `_CustomerPostCard`. Ini yang membuat kartu-yang-di-tap bisa menemukan rect
  kartu **mana pun** (termasuk saudara).
- `Future<ScaledVideoFeedReverseTarget?> resolveReturnTarget(String postId)`:
  1. Jika key belum terdaftar → return `null` (morph fallback aman).
  2. `Scrollable.ensureVisible(context, duration: ...)` ke context key tsb.
  3. Tunggu satu post-frame (`WidgetsBinding.addPostFrameCallback`).
  4. Ukur `RenderBox` via key → `rect = localToGlobal(Offset.zero) & size`.
  5. Return `ScaledVideoFeedReverseTarget(rect: rect, imageUrl:
     post.thumbnailUrl, borderRadius: 14)`.
  6. Jika box null / tak `hasSize` → return `null`.

### Perubahan wiring (mirror pola `member_post_detail`)

- **`_ProductCustomerPostsSection`** (rail utama di halaman) → ubah dari
  `StatelessWidget` menjadi `StatefulWidget`. State memiliki satu instance
  `_RelatedPostsRail`, memasang `scroll` ke `ListView.separated`, dan meneruskan
  controller ke tiap `_CustomerPostCard`.
- **`_ProductCustomerPostsScreen`** ("Lihat semua", sudah Stateful) → wiring
  controller yang sama (bug & kartu identik; murah sekalian, logika terpusat di
  controller).
- **`_CustomerPostCard`**:
  - Gunakan `controller.keyFor(post.id)` untuk `key` thumbnail (buang field
    `_thumbnailKey` lokal).
  - Jalur video di `_openPost` memanggil
    `pushScaledVideoFeed<ScopedVideoFeedResult>` dengan:
    - `thumbnailKey: controller.keyFor(post.id)`
    - `thumbnailImageUrl: post.thumbnailUrl`, `thumbnailBorderRadius: 14`
    - `reverseMorphEnabled` + `reverseTarget` (dua `ValueNotifier` lokal)
    - `onActivePostChanged: (id) => reverseMorphEnabled.value = (id == post.id)`
    - `onPrepareClose: (result, _) async { reverseTarget.value = await
      controller.resolveReturnTarget(result.postId); reverseMorphEnabled.value =
      true; }`
    - `coordinator: null`, `originPostId: null`
  - `finally`: `dispose()` kedua notifier.

## Aliran data

```
tap kartu A ──> _openPost (video) ──> pushScaledVideoFeed<Result>
                                        │  (reverseTarget notifier = null awal)
viewer swipe ke C ──> onActivePostChanged('C')
                        └─> reverseMorphEnabled = (C==A) = false
user tutup ──> onPrepareClose(result=C)
                └─> controller.resolveReturnTarget('C')
                      ├─ ensureVisible(keyFor C)
                      ├─ ukur rect C
                      └─> reverseTarget = rect C ; reverseMorphEnabled = true
route reverse-morph ──> mengecil ke rect thumbnail C
```

## Penanganan error / edge case

- `resolveReturnTarget` mengembalikan `null` bila post tak ada di registry
  (mis. hasil viewer berisi post dari `loadMore` yang belum ter-render di rail)
  → route jatuh ke morph default (kembali ke origin) — aman, tidak crash.
- Notifier selalu di-dispose di `finally`, konsisten dengan pola post-detail.
- `reverseMorphEnabled=false` saat active≠origin mencegah morph-balik ke rect
  usang selama swipe (mengikuti `member_post_detail_screen.dart:985`).

## Testing

Perluas `flutter_app/test/screens/product_detail_screen_related_posts_test.dart`:

- **Test baru**: buka viewer dari kartu index 0, simulasikan
  `onActivePostChanged` ke post index 2 lalu `onPrepareClose` dengan
  `result.postId` = post 2 → verifikasi `reverseTarget.value.rect` cocok dengan
  rect thumbnail post 2 (bukan post 0), dan `reverseMorphEnabled.value == true`.
- **Regresi**: tap-foto (non-video) tetap push `MemberPostDetailScreen` seperti
  semula.

## Berkas tersentuh

- `flutter_app/lib/screens/product_detail_screen.dart`
  (`_ProductCustomerPostsSection`, `_ProductCustomerPostsScreen`,
  `_CustomerPostCard`, + kelas controller `_RelatedPostsRail`).
- `flutter_app/test/screens/product_detail_screen_related_posts_test.dart`.
