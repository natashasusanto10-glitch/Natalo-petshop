# Design — Beranda instan: fix banner salah-label + snapshot disk stale-while-revalidate

Tanggal: 2026-07-18
Status: Disetujui arah (paket A + B-disk); menunggu review spec

## Masalah

1. **Banner "Belum berhasil memuat. Tarik ke bawah untuk coba lagi." tampil saat Beranda masih LOADING, bukan hanya saat gagal.** `FutureBuilder` produk home diberi `initialData: ProductResult(fromApi: false)` (`home_screen.dart:658-661`, niatnya supaya skeleton muncul di first paint), sementara syarat banner adalah `result?.fromApi == false` (`home_screen.dart:749`). Selama fetch 48 produk masih jalan, snapshot FutureBuilder memegang `initialData` → banner error dirender sejak frame pertama SETIAP KALI Beranda dibangun. Di jaringan cepat cuma kedip; di jaringan lambat / server dingin nongol berdetik-detik.
2. **Pull-to-refresh tidak me-retry fetch yang gagal.** `_productsFuture` adalah `late final`, di-assign sekali di `initState` (`home_screen.dart:78,160`) dan tidak pernah dibuat ulang. `_refreshAll` (handler pull-to-refresh) hanya me-refresh brands/categories/banners + rekomendasi + explore. Akibat: (a) kalau fetch produk beneran gagal, saran banner "tarik ke bawah" bohong — banner nempel sampai user pindah tab dan balik; (b) Flash Sale & Produk Terlaris tidak pernah segar lewat pull-to-refresh; (c) `onCountdownExpired: _refreshAll` (`home_screen.dart:776-781`) yang niatnya membersihkan flash sale kedaluwarsa efektif no-op untuk section itu.
3. **Setiap pindah tab = remount penuh + refetch dari nol.** Tab bar memakai `pushNamedAndRemoveUntil` (`bottom_nav.dart:215`), jadi balik ke Beranda membangun ulang `HomeScreen` dan `initState` menembakkan ±6-7 request lagi. Tidak ada cache data home antar-instance → user melihat loading (plus banner salah-label) setiap pindah tab.

Pembanding pola benar di codebase sendiri: `member_screen.dart:212-231` — pesan error hanya di-set di blok `catch`, loading punya flag terpisah.

## Tujuan

1. Banner "Belum berhasil memuat" HANYA tampil ketika fetch benar-benar selesai-dan-gagal DAN tidak ada konten yang bisa ditampilkan.
2. Pull-to-refresh benar-benar mengulang fetch produk home (Flash Sale, Terlaris, dst ikut segar).
3. Stale-while-revalidate ala Shopee/IG: pindah tab dan cold start langsung render data home terakhir (dari memori / dari disk), refresh berjalan diam-diam di belakang.

## Keputusan produk (sudah diputuskan user)

- **Refresh gagal saat konten lama sedang tampil → diam saja.** Tidak ada banner/toast. Banner hanya untuk kasus layar kosong (cache tidak ada + fetch gagal).
- **Umur snapshot disk tanpa batas.** Snapshot terakhir selalu dipakai sebagai render awal berapa pun umurnya; selalu ditimpa data segar begitu fetch sukses. Aman untuk flash sale karena `Product.isFlashSaleEligible` (`product.dart:628-638`) mengecek `flashSaleEndsAt` terhadap `DateTime.now()` — item Tier-1 kedaluwarsa otomatis tersaring dari snapshot lama saat build. Konsekuensi yang diterima: harga/diskon lama bisa tampil beberapa detik sampai refresh selesai.

## Non-tujuan

- TIDAK mengubah navigasi tab (`pushNamedAndRemoveUntil`) atau memindah app ke shell IndexedStack (Opsi C ditolak — terlalu berisiko).
- TIDAK meng-cache rekomendasi personal (`_personalizedRecs`) maupun grid "Jelajahi" (infinite scroll + reshuffle generation counter) — keduanya sudah fail-silent dan memang dirancang berganti-ganti antar kunjungan. Perilakunya tidak disentuh.
- TIDAK mengubah layout/visual section mana pun di Beranda. Perubahan terbatas pada SUMBER data + kondisi tampil banner.
- TIDAK mengubah layar lain (Produk, Feed, Transaksi, Akun) — halaman itu punya pola loading sendiri; kalau mau diberi perlakuan sama, itu proyek terpisah.
- TIDAK menyentuh `ProductService.fetchProducts` yang dipakai layar lain (katalog, wishlist, dsb) selain refactor delegasi internal yang dijelaskan di bawah (perilaku publiknya identik).

## Pendekatan

### 1. Unit baru: `HomeSnapshotStore` — `lib/state/home_snapshot_store.dart`

Singleton `ChangeNotifier`, pola sama persis dengan `RecentlyViewedStore` (`lib/state/recently_viewed_store.dart`): konstruktor privat + instance global `homeSnapshotStore`.

**State (in-memory):**

```dart
List<Product> products = const [];        // hasil fetch home limit 48
List<PetBrand> brands = const [];
List<HomeCategory> categories = const [];
List<HomeBanner> banners = const [];
bool refreshing = false;                  // guard anti-dobel + indikator
bool lastRefreshFailed = false;           // HANYA bermakna saat products kosong
bool get hasContent => products.isNotEmpty;
```

**`Future<void> loadFromDisk()`** — dipanggil sekali dari `main.dart` (fire-and-forget, bersebelahan dengan `recentlyViewedStore.loadFromDisk()` di `main.dart:164`):

- Baca prefs key `home_snapshot_v1` → decode JSON → parse tiap bagian lewat konstruktor `fromApiJson` yang SAMA dengan jalur fetch live (`Product.fromApiJson`, `PetBrand.fromApiJson`, `HomeCategory.fromApiJson`, `HomeBanner.fromApiJson`).
- **Guard race (WAJIB):** hasil disk hanya di-apply kalau `products` masih kosong. `loadFromDisk` async dan berlomba dengan `refresh()` yang dipicu `initState` HomeScreen — kalau refresh live sudah lebih dulu mengisi data segar, snapshot lama TIDAK boleh menimpanya.
- Seluruh baca/parse dibungkus try-catch fail-silent (pola store existing). Snapshot korup → `prefs.remove(_key)` lalu lanjut seperti tidak ada snapshot (first-run).

**`Future<void> refresh({bool force = false})`:**

- Guard anti-dobel: kalau `refreshing == true` → return langsung (panggilan menumpuk di-skip, bukan di-queue).
- Soft-throttle: tanpa `force`, skip kalau refresh sukses terakhir < 30 detik lalu (`DateTime? _lastSuccessAt`). Mencegah spam 4 request saat user bolak-balik tab cepat; server memang cache 300s tapi latency jaringan mobile tetap terbayar tiap request. `force: true` (pull-to-refresh, countdown expired) selalu bypass throttle.
- Fetch 4 endpoint PARALEL (`Future.wait`) via method raw baru di `ProductService` (lihat §2): produk home (limit 48), brands, categories, banners.
- **Sukses (produk raw non-null):** parse semua → timpa state memori → `lastRefreshFailed = false` → `notifyListeners()` → tulis snapshot baru ke disk (fire-and-forget, try-catch silent).
- **Gagal (produk raw null — timeout/network/server error):** `lastRefreshFailed = true`, state memori TIDAK diubah (konten lama tetap; kalau kosong ya tetap kosong), `notifyListeners()`. Kalau `hasContent`, UI tidak menampilkan apa-apa (keputusan "diam saja"); banner hanya membaca flag ini saat `!hasContent`.
- **Gagal parsial (produk sukses, brands/categories/banners gagal):** bagian yang gagal mengembalikan raw null → state memori bagian itu DIPERTAHANKAN (bukan dikosongkan), bagian yang sukses ditimpa. Snapshot disk ditulis dari state memori final. Ini meniru perilaku sekarang di mana `fetchBrands` dkk. return `[]` saat gagal — bedanya sekarang kita tidak menghapus data lama yang masih valid.
- Kriteria "refresh gagal" = **fetch produk** gagal. Brands/banner/categories gagal sendirian bukan kegagalan refresh (section terkait tetap menampilkan data lama / auto-hide seperti sekarang).

**Format disk — SATU key prefs `home_snapshot_v1`:**

```json
{
  "savedAt": "2026-07-18T10:19:00.000",
  "products": [ ...raw item JSON persis dari respons /api/products... ],
  "brands": [ ...raw... ],
  "categories": [ ...raw... ],
  "banners": [ ...raw... ]
}
```

- Yang dipersist adalah **JSON mentah respons API**, BUKAN hasil `toJson()` model. Alasan: `Product.fromJson` adalah alias `fromApiJson` (`product.dart:457-458`), jadi replay raw = jalur parse yang identik dengan fetch live — mengeliminasi seluruh kelas bug "field lupa di-serialize" (gotcha yang pernah terjadi di `FeedPost.toJson`).
- `savedAt` informasional saja (debug) — TIDAK ada logika kedaluwarsa (keputusan "tanpa batas").
- Estimasi ukuran: 48 produk + brands + categories + banners ≈ 150-400 KB string prefs. Sebanding dengan pola existing (recently_viewed simpan 30 produk); acceptable untuk SharedPreferences.
- Versioning lewat nama key: perubahan format di masa depan → `home_snapshot_v2`, key lama dibiarkan (atau dihapus saat load).

### 2. `ProductService` — ekspos jalur raw tanpa mengubah API publik lama

Empat method fetch di-refactor jadi delegasi ke varian raw baru, supaya store bisa mendapat JSON mentah untuk dipersist TANPA menduplikasi logika endpoint/shape response:

```dart
/// Return list JSON mentah (belum diparse) atau null saat request gagal.
/// null ≠ list kosong: null = gagal (timeout/network/server),
/// [] = sukses tapi memang kosong.
Future<List<Map<String, dynamic>>?> fetchHomeProductsRaw({int limit = 48});
Future<List<Map<String, dynamic>>?> fetchBrandsRaw();
Future<List<Map<String, dynamic>>?> fetchCategoriesRaw();
Future<List<Map<String, dynamic>>?> fetchBannersRaw();
```

- `fetchHomeProductsRaw`: `GET /api/products?limit=48` (timeout 15s, sama seperti `fetchProducts` sekarang), ekstrak list dari `items ?? data ?? products` (logika `_extractProducts` existing dipecah: ekstraksi-raw terpisah dari parse).
- `fetchBrands()`, `fetchCategories()`, `fetchBanners()` existing menjadi wrapper: panggil varian raw → parse via `fromApiJson` → return (null → `[]`, perilaku publik identik dengan sekarang; pemakai lain seperti `all_brands_screen` tidak terpengaruh).
- `fetchProducts()` (dipakai katalog/wishlist/dll) TIDAK berubah sama sekali.

### 3. `HomeScreen` — store-driven (sekaligus menuntaskan bug A secara struktural)

**Dihapus:**

- `late final Future<ProductResult> _productsFuture` + assignment-nya di `initState` (`home_screen.dart:78,160`).
- `FutureBuilder<ProductResult>` + `initialData(fromApi: false)` (`home_screen.dart:653-661`) — akar salah-label lenyap karena konsepnya tidak ada lagi.
- Field `_brands`, `_categories`, `_banners` + `_loadDynamicSections()` (`home_screen.dart:113-115,216-229`) — digantikan baca langsung dari store.

**Diganti:**

- `FutureBuilder` → `ListenableBuilder(listenable: homeSnapshotStore, ...)` membungkus `CustomScrollView` yang sama. Di dalam builder: `products = homeSnapshotStore.products`, dan semua turunan existing (flashSale, bestSellers, `_buildPersonalizedRecommendations(products)` fallback pool) tetap dihitung dengan cara yang sama.
- `_logoBrands` getter tetap ada, sumbernya `homeSnapshotStore.brands`.
- `_HeroBanner(banners: homeSnapshotStore.banners)`, `_CategorySection(categories: homeSnapshotStore.categories)`, `_BrandChoiceSection(brands: _logoBrands)` — hanya sumber berubah, widget tidak.
- `initState`: tambah `homeSnapshotStore.refresh()` (revalidate non-force, kena soft-throttle 30s). Sisanya (explore, personalized recs, visit counter, feed resume check) tidak berubah.
- `_refreshAll` (pull-to-refresh): tambah `homeSnapshotStore.refresh(force: true)` ke dalam `Future.wait` yang sudah ada — sekarang produk home (Flash Sale/Terlaris) benar-benar ikut segar.
- `onCountdownExpired`: tetap memanggil `_refreshAll` (kini efektif, karena refresh produk benar-benar jalan).

**Kondisi banner baru** (menggantikan `result?.fromApi == false` di `home_screen.dart:749`):

```dart
if (!homeSnapshotStore.hasContent && homeSnapshotStore.lastRefreshFailed)
  const SliverToBoxAdapter(child: _ApiFallbackNotice()),
```

- Widget `_ApiFallbackNotice` sendiri TIDAK berubah (pesan offline via `connectivityService` tetap).
- Selama fetch pertama masih jalan (store kosong, `lastRefreshFailed` masih false): tidak ada banner, section produk auto-hide (perilaku existing), skeleton "Jelajahi" existing tetap tampil lewat state explore sendiri. TIDAK ada mekanisme skeleton baru.

**Perilaku hasil per skenario:**

| Skenario | Sebelum | Sesudah |
|---|---|---|
| Cold start pertama kali (belum ada snapshot) | banner salah-label + skeleton | skeleton saja; banner hanya kalau fetch berakhir gagal |
| Cold start berikutnya | banner salah-label + skeleton beberapa detik | konten sesi terakhir langsung tampil; refresh diam-diam |
| Pindah tab balik ke Beranda | banner salah-label + loading ulang | konten langsung tampil dari memori; revalidate senyap (throttle 30s) |
| Fetch gagal, layar kosong | banner tampil, tarik-ke-bawah tidak me-retry | banner tampil, tarik-ke-bawah benar-benar retry |
| Refresh gagal, konten lama tampil | (kombinasi bug) | diam saja — konten lama tetap |

### 4. Titik hydrate di `main.dart`

Satu baris `homeSnapshotStore.loadFromDisk();` (fire-and-forget, TIDAK di-`await`) di blok init store yang sudah ada — tepat setelah `recentlyViewedStore.loadFromDisk()` (`main.dart:164`). Tidak masuk `Future.wait` blocking di atasnya (`main.dart:142-146`) supaya tidak menunda first frame; UI ter-update via `notifyListeners` begitu hydrate selesai (biasanya < 50ms, jauh sebelum fetch network).

## Error handling — rangkuman

- Semua IO disk try-catch fail-silent; korup → hapus key, lanjut kosong.
- Refresh gagal: state lama dipertahankan; flag error hanya dikonsumsi saat layar kosong.
- Refresh menumpuk: di-skip (guard `refreshing`), bukan queue.
- Snapshot lama vs data segar: hydrate hanya mengisi store yang masih kosong (guard race, WAJIB dites).
- Store tidak pernah `setState` ke widget yang sudah dispose — UI mendengarkan via `ListenableBuilder`, bukan callback manual.

## Testing

**Unit test store (`test/state/home_snapshot_store_test.dart`)** — pakai `SharedPreferences.setMockInitialValues` + fetcher injeksi (`@visibleForTesting` parameter fungsi fetch, pola yang sudah dipakai codebase):

1. `loadFromDisk` dengan snapshot valid → state terisi + `notifyListeners`.
2. `loadFromDisk` dengan JSON korup → state tetap kosong, key terhapus, tidak throw.
3. Guard race: `refresh` sukses duluan → `loadFromDisk` TIDAK menimpa.
4. `refresh` sukses → state ditimpa + snapshot disk tertulis (verifikasi isi prefs).
5. `refresh` gagal dengan konten ada → state tidak berubah, `lastRefreshFailed = true` tapi `hasContent` tetap true.
6. `refresh` gagal tanpa konten → `lastRefreshFailed = true`, `hasContent` false.
7. Refresh gagal lalu sukses → `lastRefreshFailed` kembali false.
8. Guard anti-dobel: `refresh` saat `refreshing` → panggilan kedua no-op.
9. Soft-throttle: refresh non-force < 30s setelah sukses → skip; `force: true` → jalan.
10. Gagal parsial (produk sukses, banner gagal) → produk ditimpa, banner lama dipertahankan.

**Widget test HomeScreen (`test/screens/home_screen_snapshot_test.dart`)** — store di-reset per test; bounded pump-loop (JANGAN `pumpAndSettle` — gotcha shimmer/`AppProductImage` hang yang sudah dikenal); mock prefs + clear cartStore:

1. Store kosong + refresh in-flight → banner "Belum berhasil memuat" TIDAK ada (regresi utama bug A).
2. Store kosong + `lastRefreshFailed` → banner ADA.
3. Store berisi konten (simulasi cache) → section produk langsung render tanpa banner, walau refresh gagal.
4. Pull-to-refresh → `refresh(force: true)` terpanggil (verifikasi via fetcher palsu tercatat).

**Regresi:** `flutter analyze` bersih + seluruh suite widget test existing hijau (HomeScreen dipakai banyak golden/widget test lain — perubahan sumber data tidak boleh mengubah layout).

## Risiko & mitigasi

- `home_screen.dart` 4000+ baris dan FutureBuilder membungkus seluruh body — pencabutannya menyentuh indentasi/scope banyak section. Mitigasi: perubahan murni mekanis (ganti pembungkus + ganti sumber variabel), tidak menyentuh isi section; verifikasi via test existing + analyze.
- Data stale tampil sesaat (harga/diskon lama) — diterima secara eksplisit oleh user; flash sale kedaluwarsa sudah terfilter client-side.
- Ukuran prefs bertambah ±150-400 KB — sebanding pola existing, dipantau kalau nanti limit 48 dinaikkan.

## Ringkasan perubahan file

- **Baru:** `lib/state/home_snapshot_store.dart`
- **Baru:** `test/state/home_snapshot_store_test.dart`, `test/screens/home_screen_snapshot_test.dart`
- **Modifikasi:** `lib/services/product_service.dart` (4 varian raw + 3 wrapper delegasi; `fetchProducts` tidak berubah)
- **Modifikasi:** `lib/screens/home_screen.dart` (FutureBuilder→ListenableBuilder, hapus `_productsFuture`/`_loadDynamicSections`/field lokal brands-categories-banners, kondisi banner baru, `_refreshAll` + `initState` panggil store)
- **Modifikasi:** `lib/main.dart` (satu baris hydrate)
- **Tidak berubah:** `_ApiFallbackNotice`, semua widget section Beranda, explore/personalized recs, navigasi tab, layar lain
