# Spec A — Tutup tag belanja + tab "Ditandai" (shell) — Design

Tanggal: 2026-07-22
Status: Disetujui — siap implementasi (subagent-driven)

Ini spec pertama dari rencana besar 5 bagian (A–E) untuk mengganti fitur tag belanja di alur posting dengan Tag People + Hashtag + Lokasi ala Instagram. Bagian lain (B: Tag People, C: Hashtag, D: Add Lokasi, E: sisa poles Profil seperti tombol "Pet Profile") dikerjakan sebagai spec terpisah, satu per satu, setelah Spec A ini selesai diimplementasi.

## Latar belakang

Saat ini pengguna bisa menandai produk yang pernah dibeli saat membuat postingan Feed ("Tag Produk Pernah Dibeli" di layar New Post), dan hasilnya muncul di tab ke-3 halaman Profil ("Belanja") sebagai kumpulan postingan yang terhubung ke produk Natalo. User ingin menutup dulu jalur input ini dan mengganti slot tab ke-3 profil menjadi "Ditandai" (Tagged), sebagai persiapan visual untuk fitur Tag People yang akan datang di Spec B.

## Tujuan

1. Sembunyikan section "Tag Produk Pernah Dibeli" di layar New Post — reversibel lewat satu flag, tanpa menghapus kode/data.
2. Ganti tab ke-3 Profil (ikon tas belanja + label "Belanja") menjadi ikon dua-orang + label **"Ditandai"**, dengan isi grid berupa *empty state* statis (belum ada query data — data asli menyusul di Spec B).
3. Terapkan gaya "tab aktif" yang lebih jelas & premium ke KETIGA tab (Postingan/Video/Ditandai), bukan cuma tab Ditandai — supaya konsisten: ikon outline→filled + warna abu→biru brand + gerak naik tipis (~3px), melebur mengikuti swipe (bukan snap instan). Ukuran ikon diseragamkan ke 24px (menyamai bottom nav). Treatment visual (warna/gerak/crossfade) memakai kurva `easeOutCubic` atas nilai `emphasis` supaya mengendap di ujung transisi, bukan tracking 1:1 jari (kesan premium). Indikator garis bawah TIDAK ikut kurva ini (mekanismenya sendiri, sudah mulus).
4. Matikan haptic saat ganti tab profil (permintaan user) — di kedua layar. `AppHaptics.tap` di aksi lain (buka post, edit profil, follow, share) TIDAK disentuh.
5. Hapus `Tooltip` pada tab profil supaya konsisten dengan kebijakan app-wide "Global Icon Clean Interaction" ([2026-07-22-global-icon-clean-interaction-design.md](2026-07-22-global-icon-clean-interaction-design.md)). Kebijakan itu secara teknis mengecualikan "tabs", tapi user memutuskan menyamakan tab profil juga demi kebersihan penuh. Aksesibilitas tetap terjaga lewat `Semantics(label:...)` yang sudah ada (tidak dihapus). Konsekuensi: test yang meng-anchor lewat `find.byTooltip(<label tab>)` harus pindah ke `find.byKey(public_tab_*_pill)`.
6. Perubahan berlaku di kedua permukaan yang memakai `PublicProfileContentTabBar`: profil sendiri (`MemberScreen`, mode selalu-expanded) dan profil publik (`PublicProfileScreen`, termasuk mode pill saat header collapse — lihat referensi di bawah).

**Catatan rebase:** branch ini sudah di-rebase ke `main` terkini (yang memuat kebijakan clean-icon + freeze-header profil sepi). Tab bar `public_profile_content_tab_bar.dart` identik dengan main (tabs dikecualikan dari clean-icon), sudah pakai `NoSplash`/overlay transparan. Perubahan `public_profile_screen.dart` di main (freeze header) TIDAK menyentuh region `_activateContent`/`_EmptyPosts` yang spec ini ubah.

## Non-tujuan

- Tidak membangun fitur Tag People sungguhan (pemilihan orang, penyimpanan, notifikasi) — itu Spec B. Tab "Ditandai" di sini murni cangkang visual kosong.
- Tidak mengubah backend/model sama sekali: `FeedPostProduct`, endpoint `app/api/feed/posts/route.ts`, dan `app/api/feed/pinnable-products/route.ts` tetap seperti sekarang.
- Tidak mengubah `FeedPost.products`/`taggedProducts` (model Flutter) atau logic pill produk di kartu feed (`FeedProductPill`, `showFeedProductLinksSheet`) — itu tetap tampil di postingan lama yang sudah punya produk tertaut, di luar konteks tab profil.
- **Trade-off yang disadari**: karena slot tab ke-3 sekarang permanen berisi "Ditandai" (bukan sekadar disembunyikan), membalikkan flag `kShopTagEnabled` ke `true` nanti HANYA menghidupkan lagi input di New Post — tab Profil TIDAK otomatis kembali jadi "Belanja". Kalau itu benar-benar diinginkan lagi, perlu perubahan manual terpisah.
- **Diputuskan dihapus**: badge kecil ikon tas belanja pada thumbnail grid "Postingan" untuk post lama yang punya produk tertaut ([member_screen.dart](../../../flutter_app/lib/screens/member_screen.dart), sekitar baris 960 pasca-rebase) — supaya tidak ada lagi jejak visual "tag belanja" di Profil. Badge play video (untuk post video) tetap ada.

## Pendekatan

### 1. Flag reversibel — file baru `flutter_app/lib/config/feature_flags.dart`

```dart
const kShopTagEnabled = false;
```

Konsisten dengan folder `lib/config/` yang sudah ada (`api_config.dart`, `natalo_store_config.dart`).

### 2. New Post — `flutter_app/lib/screens/feed_new_post_screen.dart`

- Section `_SectionTitle('Tag Produk Pernah Dibeli')` + `_PurchasedProductSearch` + `_PurchasedProducts` (sekitar baris 608) dibungkus `if (kShopTagEnabled)`.
- `_loadPurchasedProducts()` tidak dipanggil saat flag `false` (hemat 1 network call ke `/api/feed/pinnable-products`).
- State `_selectedProductIds`, `_toggleProduct`, `prefilledProductIds` **tetap ada di kode** — draft lama yang kebetulan masih punya `taggedProductIds` tetap submit apa adanya, cuma tidak ada UI untuk mengubahnya.

### 3. Tab bar bersama — `flutter_app/lib/widgets/public_profile_content_tab_bar.dart`

- Tab index 2: `icon: Icons.shopping_bag_outlined` → `Icons.people_outline_rounded` (non-aktif) / `Icons.people_rounded` (aktif); `label: 'Belanja'` → `'Ditandai'`.
- Ukuran ikon: turunkan dari `lerpDouble(27, 23, pillOpacity)` jadi tetap 24 di ketiga tab (match bottom nav `size: 25`, dibulatkan biar konsisten lintas komponen — detail final di plan implementasi).
- **Perbaiki gap yang ditemukan saat brainstorming**: saat ini di mode "selalu expanded" (`pillOpacity: 0`, dipakai `MemberScreen`), variabel `foreground` di `_PublicProfileTab` dihitung dari `Color.lerp(expandedForeground, collapsedForeground, pillOpacity)` — karena `pillOpacity` selalu 0 di mode ini, `foreground` selalu = `expandedForeground` (konstan), TIDAK PERNAH ikut nilai `emphasis`. Akibatnya tab aktif/nonaktif sama warnanya, cuma dibedakan garis bawah tipis. Ini perlu diperbaiki supaya warna ikon benar-benar melebur abu→biru brand mengikuti `emphasis`, di kedua mode (expanded icon-only maupun collapsed pill).
- Tambahkan swap ikon outline↔filled: dua `Icon` ditumpuk (`Stack`), opacity masing-masing = fungsi `emphasis` (crossfade, bukan snap), supaya transisi tetap mulus saat swipe antar tab (`controller.animation.value` kontinu, sama seperti indikator garis yang sudah ada).
- Tambahkan `Transform.translate(offset: Offset(0, lerp(0, -3, curvedEmphasis)))` pada ikon aktif (`curvedEmphasis` = `easeOutCubic` atas `emphasis`) — gerak naik tipis ~3px, dikombinasi dengan crossfade warna di atas. Ini BEDA dari animasi bounce-scale yang dipakai `bottom_nav.dart` (`_NavBounce`) — sengaja dipilih user supaya kesan tab profil lebih halus/kalem dibanding bottom nav yang lebih "pop".
- Perubahan ini otomatis berlaku untuk kedua pemakai (`MemberScreen` via `_AccountTabHeaderDelegate`, dan `PublicProfileScreen` termasuk mode pinned-pill — lihat `2026-07-17-public-profile-pinned-tabbar-design.md` untuk mekanisme `pillOpacity`/`labelOpacity` yang sudah ada dan TIDAK diubah oleh spec ini, hanya diisi treatment ikon baru di atasnya).

### 4. Konten tab "Ditandai" (empty state statis)

Kedua layar punya arsitektur data yang BEDA untuk tab ini — jangan disamakan:

- **`flutter_app/lib/screens/member_screen.dart`** (profil sendiri): `_taggedPosts` saat ini adalah getter client-side (`_allPosts.where((p) => p.productIds.isNotEmpty)`, baris ~422) — tidak ada network call terpisah. Cukup ganti isinya jadi selalu `const []` (atau getter yang sengaja mengembalikan list kosong) supaya `_PostGrid` ke-3 selalu jatuh ke cabang empty-state.
  - Ikon empty-state di `_EmptyState` (baris ~988) **TIDAK perlu diganti** — ikonnya sudah generik (`Icons.pets_rounded`, paw, dibungkus badge biru muda) dan SAMA untuk ketiga tab, bukan per-tab. Cukup ubah `emptyText`/`emptySubtext` di pemanggilan `_PostGrid` ke-3 (baris ~542-544): **"Belum ada postingan yang menandaimu"** / **"Saat orang lain menandaimu di sebuah postingan, itu akan muncul di sini."** (kata "menandaimu" valid di sini karena ini profil milik viewer sendiri).

- **`flutter_app/lib/screens/public_profile_screen.dart`** (profil orang lain): tab `PublicProfileContentFilter.shoppable` (baris ~48) memanggil **network call sungguhan** lewat `profileService.fetchPublicProfile(content: ..., cursor: ...)` di `_loadSelectedContent`/`_loadMore` (baris ~438-529) — bukan filter client-side. Perlu intercept: saat `content == shoppable` (Ditandai), `_activateContent` langsung menandai `contentState.loaded = true` dengan `posts: []` TANPA memanggil `_loadSelectedContent`/API sama sekali — supaya tidak ada network call sia-sia tiap kali viewer buka tab ini.
  - Ikon+teks empty-state di sini diatur widget `_EmptyPosts` (baris ~1412-1457) lewat `switch (content)` — **ikon PERLU diganti** (`Icons.shopping_bag_outlined` → `Icons.people_outline_rounded`, konsisten dengan ikon tab bar) di baris ~1431-1432.
  - **Teksnya HARUS beda dari versi profil sendiri** — ini profil milik ORANG LAIN, jadi "menandaimu" salah secara tata bahasa (menyiratkan menandai si penonton). Pakai orang ketiga, mis. **"Belum ada postingan yang menandai akun ini."** (baris ~1442-1443).
  - `_EmptyPosts` saat ini cuma render satu baris teks (tidak ada slot subteks, beda dari `_EmptyState` milik `member_screen.dart` yang dua baris) — usulan: tambah parameter subteks opsional supaya kesan premium konsisten di kedua layar. Kalau ingin tetap satu baris demi diff minimal, itu juga valid — keputusan kecil ini terbuka saat review.
  - `showCommerceBadge: content == PublicProfileContentFilter.shoppable` (baris ~1057-1058, badge harga/jumlah produk di tile grid) otomatis jadi kode mati (tidak pernah ke-trigger lagi karena tab ini selalu kosong) — aman dibiarkan apa adanya, tidak perlu dihapus, cukup dicatat supaya tidak disangka terlewat saat implementasi.

Jumlah tab tetap 3 di kedua layar — tidak perlu ubah `TabController(length: ...)` atau pembagian `/3` di perhitungan posisi indikator (sudah benar apa adanya).

## Testing

- Widget test `feed_new_post_screen_test.dart`: dengan `kShopTagEnabled = false` (default), section "Tag Produk Pernah Dibeli" tidak ditemukan di widget tree, dan `fetchPinnableProducts` tidak terpanggil (mock verify no-call).
- Widget test tab bar: label "Ditandai" + ikon baru muncul di index 2; assert warna & posisi ikon (`translateY`, opacity crossfade) berubah sesuai nilai `controller.animation` (sample 0.0, 0.5, 1.0) — termasuk kasus `pillOpacity: 0` (mode `MemberScreen`) untuk memastikan bug warna statis di atas benar-benar hilang.
- Widget test empty state: tab "Ditandai" di `MemberScreen` menampilkan "...menandaimu" (getter `_taggedPosts` selalu kosong, tanpa filter produk); di `PublicProfileScreen` menampilkan teks orang-ketiga ("...menandai akun ini") DAN memastikan `profileService.fetchPublicProfile` tidak pernah terpanggil dengan `content: shoppable` (mock verify no-call) saat tab itu di-tap.
- Golden tab bar profil (`profile_tabbar_*`, `public_profile_premium_test.dart`) diregenerasi untuk ikon+label baru.
- Regresi: seluruh test profil (`public_profile_*`, `member_screen_*`) dan feed New Post tetap hijau.

## Yang tidak berubah

- Backend: model `FeedPostProduct`, endpoint create-post, endpoint pinnable-products.
- Model Flutter `FeedPost.products`/`productsInVideo`/`taggedProducts`, `FeedProductPill`, `showFeedProductLinksSheet` — pill produk di kartu feed individual tetap tampil seperti sekarang untuk post yang sudah punya produk tertaut.
- Mekanisme collapsing/pill tab bar profil publik (`PublicProfileHeaderMotion`, `CollapsingHeaderDelegate`) — sudah benar per spec sebelumnya, tidak disentuh, hanya "dihuni" treatment ikon baru.
- Layout header, avatar, stats, tombol Follow/Pesan/Edit Profil/Bagikan Profil — di luar scope (tombol "Pet Profile" ada di Spec E terpisah).

## Referensi

- [2026-07-17-profile-tabbar-polish-design.md](2026-07-17-profile-tabbar-polish-design.md) — asal-usul indikator geser mulus & divider transparan yang sudah ada.
- [2026-07-17-public-profile-pinned-tabbar-design.md](2026-07-17-public-profile-pinned-tabbar-design.md) — mekanisme pill mengambang saat scroll di profil publik.
- [2026-07-16-public-profile-tab-merge-design.md](2026-07-16-public-profile-tab-merge-design.md) — asal-usul pola 3 tab (Postingan/Video/Belanja) yang sekarang sebagian diganti.
