# Beranda Instan (Snapshot SWR + Banner Jujur) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beranda render instan dari snapshot terakhir (memori saat pindah tab, disk saat cold start) dengan refresh diam-diam di belakang, dan banner "Belum berhasil memuat" hanya tampil saat fetch benar-benar gagal dan layar kosong.

**Architecture:** Store singleton baru `HomeSnapshotStore` (ChangeNotifier, pola `RecentlyViewedStore`) jadi satu-satunya pemilik data home (produk 48 + brands + categories + banners); persist JSON MENTAH respons API ke SharedPreferences key `home_snapshot_v1`; `HomeScreen` diganti dari `FutureBuilder`+`initialData(fromApi:false)` (akar bug banner salah-label) menjadi `ListenableBuilder` atas store. `ProductService` mendapat 4 varian fetch raw; wrapper lama delegasi ke situ tanpa mengubah perilaku publik.

**Tech Stack:** Flutter/Dart, `shared_preferences`, `flutter_test` (unit + widget test).

**Spec:** `docs/superpowers/specs/2026-07-18-beranda-snapshot-swr-design.md`
**Branch:** `claude/beranda-snapshot-swr` (sudah dibuat dari origin/main; spec sudah ter-commit)
**Working dir Flutter:** semua perintah `flutter` dijalankan dari `flutter_app/`

## Global Constraints

- Teks banner PERSIS tidak berubah: `'Belum berhasil memuat. Tarik ke bawah untuk coba lagi.'`; widget `_ApiFallbackNotice` TIDAK dimodifikasi.
- Yang dipersist ke disk = JSON MENTAH respons API — JANGAN pernah pakai `toJson()` model untuk snapshot.
- Kunci prefs: `home_snapshot_v1`. Field `savedAt` informasional saja — TIDAK ada logika kedaluwarsa (keputusan user: umur snapshot tanpa batas).
- Guard race WAJIB: `loadFromDisk` hanya meng-apply hasil kalau store masih kosong (`products.isEmpty`).
- Kriteria "refresh gagal" = fetch PRODUK gagal (raw null). Brands/categories/banners gagal sendirian → data lamanya DIPERTAHANKAN (bukan dikosongkan), bukan kegagalan refresh.
- Refresh gagal saat konten tampil → DIAM (tanpa banner/toast) — keputusan user.
- Soft-throttle refresh non-force: 30 detik sejak sukses terakhir; `force: true` selalu bypass.
- `ProductService.fetchProducts` (dipakai katalog/wishlist) TIDAK berubah sama sekali; `fetchBrands`/`fetchCategories`/`fetchBanners` boleh di-refactor internal tapi perilaku publik identik (return `[]` saat gagal).
- TIDAK ada mekanisme skeleton baru; TIDAK ada perubahan layout/visual section Beranda; navigasi tab TIDAK disentuh.
- Widget test: JANGAN `pumpAndSettle` (marquee header + shimmer skeleton beranimasi terus → hang); pakai bounded pump-loop + unmount di akhir test (matikan timer).
- Konvensi return raw fetcher: `null` = gagal (timeout/network/server/shape tak dikenal); `[]` = sukses tapi kosong. Perbedaan ini load-bearing untuk logika gagal-parsial.

---

### Task 1: ProductService — varian fetch raw + wrapper delegasi

**Files:**
- Modify: `flutter_app/lib/services/product_service.dart`
- Test (create): `flutter_app/test/services/product_service_raw_test.dart`

**Interfaces:**
- Consumes: `apiClient.getJson` (existing), `_asMap` helper (existing di file yang sama).
- Produces (dipakai Task 2):
  - `Future<List<Map<String, dynamic>>?> fetchHomeProductsRaw({int limit = 48})`
  - `Future<List<Map<String, dynamic>>?> fetchBrandsRaw({String? category})`
  - `Future<List<Map<String, dynamic>>?> fetchCategoriesRaw()`
  - `Future<List<Map<String, dynamic>>?> fetchBannersRaw()`
  - Top-level `List<Map<String, dynamic>>? extractRawList(Object? data, List<String> keys)` (`@visibleForTesting`)

- [ ] **Step 1: Tulis failing test**

Buat `flutter_app/test/services/product_service_raw_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/product_service.dart';

void main() {
  group('extractRawList', () {
    test('map dengan key pertama berisi list', () {
      final result = extractRawList(
        {
          'items': [
            {'id': 'a'},
            {'id': 'b'},
          ],
        },
        const ['items', 'data'],
      );
      expect(result, hasLength(2));
      expect(result![0]['id'], 'a');
    });

    test('fallback ke key berikutnya kalau key pertama absen', () {
      final result = extractRawList(
        {
          'data': [
            {'id': 'x'},
          ],
        },
        const ['items', 'data'],
      );
      expect(result, hasLength(1));
    });

    test('data berupa List langsung (tanpa wrapper map)', () {
      final result = extractRawList(
        [
          {'id': 'a'},
        ],
        const ['items'],
      );
      expect(result, hasLength(1));
    });

    test('shape tak dikenal → null (bukan []) — null berarti GAGAL', () {
      expect(extractRawList({'foo': 'bar'}, const ['items']), isNull);
      expect(extractRawList('oops', const ['items']), isNull);
      expect(extractRawList(null, const ['items']), isNull);
    });

    test('list sukses tapi kosong → [] (bukan null)', () {
      expect(
        extractRawList({'items': <Object?>[]}, const ['items']),
        isEmpty,
      );
    });

    test('entry non-map disaring keluar', () {
      final result = extractRawList(
        {
          'items': [
            {'id': 'a'},
            42,
            'x',
          ],
        },
        const ['items'],
      );
      expect(result, hasLength(1));
    });
  });
}
```

- [ ] **Step 2: Jalankan — pastikan gagal**

Run: `cd flutter_app && flutter test test/services/product_service_raw_test.dart`
Expected: FAIL compile — `extractRawList` belum ada ("Undefined name 'extractRawList'" / "isn't defined").

- [ ] **Step 3: Implementasi `extractRawList` + 4 method raw**

Di `flutter_app/lib/services/product_service.dart`:

3a. Tambah import di blok import paling atas (urut alfabetis dengan import package lain):

```dart
import 'package:flutter/foundation.dart';
```

3b. Tambah fungsi top-level SETELAH fungsi `_extractProducts` yang sudah ada (sekitar baris 599, sebelum `int? _asInt`):

```dart
/// Ekstrak list JSON MENTAH dari berbagai bentuk respons API: data berupa
/// List langsung, atau Map dengan salah satu [keys] (dicoba berurutan)
/// berisi List. Return null kalau shape tak dikenal — caller (snapshot
/// store) membedakan "gagal" (null) dari "sukses tapi kosong" ([]).
@visibleForTesting
List<Map<String, dynamic>>? extractRawList(Object? data, List<String> keys) {
  Object? raw = data is List ? data : null;
  final map = _asMap(data);
  if (raw == null && map != null) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) {
        raw = value;
        break;
      }
    }
  }
  if (raw is! List) return null;
  return raw.whereType<Map<String, dynamic>>().toList();
}
```

3c. Tambah 4 method raw di dalam class `ProductService`, letakkan tepat SEBELUM method `fetchBanners()` yang sudah ada:

```dart
  /// GET /api/products?limit=N — JSON item MENTAH untuk HomeSnapshotStore.
  /// null = gagal (timeout/network/server/shape tak dikenal); [] = sukses
  /// tapi kosong. Raw ini dipersist apa adanya ke snapshot disk SWR supaya
  /// replay lewat Product.fromApiJson identik dengan fetch live.
  Future<List<Map<String, dynamic>>?> fetchHomeProductsRaw({
    int limit = 48,
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/products',
        timeout: const Duration(seconds: 15),
        query: {'limit': '$limit'},
      );
      return extractRawList(data, const ['items', 'data', 'products']);
    } catch (_) {
      return null;
    }
  }

  /// Varian raw fetchBrands — lihat kontrak null-vs-[] di fetchHomeProductsRaw.
  Future<List<Map<String, dynamic>>?> fetchBrandsRaw({
    String? category,
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/brands',
        query: {
          if (category != null && category.trim().isNotEmpty)
            'category': category.trim(),
        },
      );
      return extractRawList(data, const ['brands', 'items']);
    } catch (_) {
      return null;
    }
  }

  /// Varian raw fetchCategories — lihat kontrak null-vs-[] di fetchHomeProductsRaw.
  Future<List<Map<String, dynamic>>?> fetchCategoriesRaw() async {
    try {
      final data = await apiClient.getJson('/api/categories');
      return extractRawList(data, const ['categories', 'items']);
    } catch (_) {
      return null;
    }
  }

  /// Varian raw fetchBanners — lihat kontrak null-vs-[] di fetchHomeProductsRaw.
  Future<List<Map<String, dynamic>>?> fetchBannersRaw() async {
    try {
      final data = await apiClient.getJson('/api/banners');
      return extractRawList(data, const ['banners', 'items']);
    } catch (_) {
      return null;
    }
  }
```

3d. Refactor 3 wrapper existing jadi delegasi (perilaku publik identik: `[]` saat gagal). GANTI SELURUH BODY masing-masing method (doc comment existing di atasnya DIPERTAHANKAN):

`fetchBanners()` (sekarang di baris ~410-423) jadi:

```dart
  Future<List<HomeBanner>> fetchBanners() async {
    final raw = await fetchBannersRaw();
    if (raw == null) return const [];
    try {
      return raw.map(HomeBanner.fromApiJson).toList();
    } catch (_) {
      return const [];
    }
  }
```

`fetchBrands({String? category})` (baris ~444-463) jadi:

```dart
  Future<List<PetBrand>> fetchBrands({String? category}) async {
    final raw = await fetchBrandsRaw(category: category);
    if (raw == null) return const [];
    try {
      return raw.map(PetBrand.fromApiJson).toList();
    } catch (_) {
      return const [];
    }
  }
```

`fetchCategories()` (baris ~465-478) jadi:

```dart
  Future<List<HomeCategory>> fetchCategories() async {
    final raw = await fetchCategoriesRaw();
    if (raw == null) return const [];
    try {
      return raw.map(HomeCategory.fromApiJson).toList();
    } catch (_) {
      return const [];
    }
  }
```

`fetchProducts`, `fetchProductsPage`, dan semua method lain TIDAK disentuh.

- [ ] **Step 4: Jalankan test — pastikan pass**

Run: `cd flutter_app && flutter test test/services/product_service_raw_test.dart`
Expected: PASS (6 test).

- [ ] **Step 5: Analyze + regresi cepat**

Run: `cd flutter_app && flutter analyze lib/services/product_service.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/services/product_service.dart flutter_app/test/services/product_service_raw_test.dart
git commit -m "refactor(product-service): varian fetch raw + wrapper delegasi (perilaku publik tetap)"
```

---

### Task 2: HomeSnapshotStore — snapshot disk SWR

**Files:**
- Create: `flutter_app/lib/state/home_snapshot_store.dart`
- Test (create): `flutter_app/test/state/home_snapshot_store_test.dart`

**Interfaces:**
- Consumes (dari Task 1): `productService.fetchHomeProductsRaw()`, `fetchBrandsRaw()`, `fetchCategoriesRaw()`, `fetchBannersRaw()` — semua `Future<List<Map<String, dynamic>>?>`.
- Produces (dipakai Task 3):
  - Singleton global `homeSnapshotStore` (`HomeSnapshotStore extends ChangeNotifier`)
  - `List<Product> products`, `List<PetBrand> brands`, `List<HomeCategory> categories`, `List<HomeBanner> banners`
  - `bool get hasContent`, `bool lastRefreshFailed`, `bool refreshing`
  - `Future<void> loadFromDisk()`, `Future<void> refresh({bool force = false})`
  - `@visibleForTesting void resetForTest()`, 4 field `debug*Fetcher` (`RawListFetcher?`)

- [ ] **Step 1: Tulis failing test (10 kasus dari spec)**

Buat `flutter_app/test/state/home_snapshot_store_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/state/home_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> productJson(String id, {String? name}) => {
      'id': id,
      'slug': id,
      'name': name ?? 'Produk $id',
      'price': 10000,
      'image_url': '',
    };

Map<String, dynamic> snapshotJson({
  required List<Map<String, dynamic>> products,
}) =>
    {
      'savedAt': '2026-07-01T00:00:00.000',
      'products': products,
      'brands': [
        {'name': 'BrandUji', 'slug': 'branduji', 'logoUrl': 'https://x/l.png'},
      ],
      'categories': [
        {'id': 'c1', 'name': 'Makanan', 'slug': 'makanan'},
      ],
      'banners': [
        {'id': 'b1', 'image': 'https://x/b.jpg'},
      ],
    };

/// Set semua fetcher non-produk ke sukses-kosong supaya tiap test cukup
/// mengatur fetcher produk (kriteria gagal = produk).
void stubOthersEmpty() {
  homeSnapshotStore.debugBrandsFetcher = () async => [];
  homeSnapshotStore.debugCategoriesFetcher = () async => [];
  homeSnapshotStore.debugBannersFetcher = () async => [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    homeSnapshotStore.resetForTest();
  });

  test('loadFromDisk snapshot valid → state terisi + notify sekali', () async {
    SharedPreferences.setMockInitialValues({
      'home_snapshot_v1':
          jsonEncode(snapshotJson(products: [productJson('p1')])),
    });
    var notified = 0;
    homeSnapshotStore.addListener(() => notified++);
    await homeSnapshotStore.loadFromDisk();
    expect(homeSnapshotStore.products, hasLength(1));
    expect(homeSnapshotStore.products.first.id, 'p1');
    expect(homeSnapshotStore.brands, hasLength(1));
    expect(homeSnapshotStore.categories, hasLength(1));
    expect(homeSnapshotStore.banners, hasLength(1));
    expect(homeSnapshotStore.hasContent, isTrue);
    expect(notified, 1);
  });

  test('loadFromDisk JSON korup → tetap kosong + key dihapus, tidak throw',
      () async {
    SharedPreferences.setMockInitialValues({'home_snapshot_v1': '{rusak'});
    await homeSnapshotStore.loadFromDisk();
    expect(homeSnapshotStore.hasContent, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('home_snapshot_v1'), isNull);
  });

  test('guard race: refresh sukses duluan → loadFromDisk TIDAK menimpa',
      () async {
    SharedPreferences.setMockInitialValues({
      'home_snapshot_v1':
          jsonEncode(snapshotJson(products: [productJson('lama')])),
    });
    homeSnapshotStore.debugProductsFetcher =
        () async => [productJson('segar')];
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    await homeSnapshotStore.loadFromDisk();
    expect(homeSnapshotStore.products.single.id, 'segar');
  });

  test('refresh sukses → state ditimpa + snapshot disk tertulis (raw)',
      () async {
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p1')];
    homeSnapshotStore.debugBrandsFetcher = () async => [
          {'name': 'BrandBaru', 'slug': 'brandbaru'},
        ];
    homeSnapshotStore.debugCategoriesFetcher = () async => [];
    homeSnapshotStore.debugBannersFetcher = () async => [];
    await homeSnapshotStore.refresh();
    // _persist fire-and-forget — kasih kesempatan microtask selesai.
    await Future<void>.delayed(Duration.zero);
    expect(homeSnapshotStore.products.single.id, 'p1');
    expect(homeSnapshotStore.brands.single.name, 'BrandBaru');
    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString('home_snapshot_v1')!) as Map<String, dynamic>;
    expect((saved['products'] as List).single['id'], 'p1');
    expect((saved['brands'] as List).single['name'], 'BrandBaru');
    expect(saved['savedAt'], isNotNull);
  });

  test('refresh gagal saat konten ada → state tetap + flag set (UI diam)',
      () async {
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p1')];
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    homeSnapshotStore.debugProductsFetcher = () async => null; // gagal
    await homeSnapshotStore.refresh(force: true);
    expect(homeSnapshotStore.products.single.id, 'p1'); // dipertahankan
    expect(homeSnapshotStore.lastRefreshFailed, isTrue);
    expect(homeSnapshotStore.hasContent, isTrue); // banner tetap tak tampil
  });

  test('refresh gagal tanpa konten → lastRefreshFailed + hasContent false',
      () async {
    homeSnapshotStore.debugProductsFetcher = () async => null;
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    expect(homeSnapshotStore.lastRefreshFailed, isTrue);
    expect(homeSnapshotStore.hasContent, isFalse);
  });

  test('gagal lalu sukses → lastRefreshFailed kembali false', () async {
    homeSnapshotStore.debugProductsFetcher = () async => null;
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    expect(homeSnapshotStore.lastRefreshFailed, isTrue);
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p1')];
    await homeSnapshotStore.refresh(force: true);
    expect(homeSnapshotStore.lastRefreshFailed, isFalse);
    expect(homeSnapshotStore.hasContent, isTrue);
  });

  test('guard anti-dobel: panggilan kedua saat in-flight = no-op', () async {
    var calls = 0;
    final gate = Completer<List<Map<String, dynamic>>?>();
    homeSnapshotStore.debugProductsFetcher = () {
      calls++;
      return gate.future;
    };
    stubOthersEmpty();
    final first = homeSnapshotStore.refresh();
    await homeSnapshotStore.refresh(force: true); // langsung return (skip)
    expect(calls, 1);
    gate.complete([productJson('p1')]);
    await first;
    expect(homeSnapshotStore.products, hasLength(1));
  });

  test('soft-throttle: non-force <30s setelah sukses skip; force jalan',
      () async {
    var calls = 0;
    homeSnapshotStore.debugProductsFetcher = () async {
      calls++;
      return [productJson('p1')];
    };
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    expect(calls, 1);
    await homeSnapshotStore.refresh(); // throttled
    expect(calls, 1);
    await homeSnapshotStore.refresh(force: true); // bypass
    expect(calls, 2);
  });

  test('gagal parsial: produk sukses + banner gagal → banner lama bertahan',
      () async {
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p1')];
    homeSnapshotStore.debugBrandsFetcher = () async => [];
    homeSnapshotStore.debugCategoriesFetcher = () async => [];
    homeSnapshotStore.debugBannersFetcher = () async => [
          {'id': 'b1', 'image': 'https://x/b.jpg'},
        ];
    await homeSnapshotStore.refresh();
    expect(homeSnapshotStore.banners, hasLength(1));
    homeSnapshotStore.debugProductsFetcher = () async => [productJson('p2')];
    homeSnapshotStore.debugBannersFetcher = () async => null; // gagal
    await homeSnapshotStore.refresh(force: true);
    expect(homeSnapshotStore.products.single.id, 'p2'); // ditimpa
    expect(homeSnapshotStore.banners, hasLength(1)); // dipertahankan
    // Produk sukses = refresh sukses walau banner gagal.
    expect(homeSnapshotStore.lastRefreshFailed, isFalse);
  });
}
```

- [ ] **Step 2: Jalankan — pastikan gagal**

Run: `cd flutter_app && flutter test test/state/home_snapshot_store_test.dart`
Expected: FAIL compile — file `home_snapshot_store.dart` belum ada.

- [ ] **Step 3: Implementasi store**

Buat `flutter_app/lib/state/home_snapshot_store.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/brand.dart';
import '../models/home_banner.dart';
import '../models/home_category.dart';
import '../models/product.dart';
import '../services/product_service.dart';

/// Signature fetcher raw injeksi untuk test (null default → productService).
typedef RawListFetcher = Future<List<Map<String, dynamic>>?> Function();

/// Snapshot data Beranda — stale-while-revalidate (SWR) ala Shopee/IG.
///
/// Satu-satunya pemilik data home (produk limit 48 + brands + categories +
/// banners). Beranda render langsung dari sini: pindah tab = instan dari
/// memori (singleton hidup terus), cold start = instan dari disk
/// ([loadFromDisk] dipanggil main.dart), refresh jalan diam-diam.
///
/// Yang dipersist ke disk adalah JSON MENTAH respons API, BUKAN hasil
/// toJson() model — Product.fromJson alias fromApiJson, jadi replay
/// snapshot = jalur parse identik dengan fetch live (eliminasi kelas bug
/// "field lupa di-serialize", gotcha lama FeedPost.toJson).
class HomeSnapshotStore extends ChangeNotifier {
  HomeSnapshotStore._();

  static const _prefsKey = 'home_snapshot_v1';

  /// Revalidate non-force di-skip kalau sukses terakhir < durasi ini —
  /// mencegah spam 4 request saat user bolak-balik tab cepat.
  static const softThrottle = Duration(seconds: 30);

  List<Product> products = const [];
  List<PetBrand> brands = const [];
  List<HomeCategory> categories = const [];
  List<HomeBanner> banners = const [];

  /// Guard anti-dobel — panggilan refresh saat masih in-flight di-skip
  /// (bukan di-queue).
  bool refreshing = false;

  /// HANYA bermakna untuk banner saat [hasContent] false (layar kosong).
  /// Saat konten tampil, refresh gagal = diam saja (keputusan produk).
  bool lastRefreshFailed = false;

  bool get hasContent => products.isNotEmpty;

  DateTime? _lastSuccessAt;

  // Raw payload per bagian — sumber tulisan snapshot disk. Ikut diisi dari
  // disk saat hydrate supaya persist berikutnya tidak menghapus bagian
  // yang belum pernah di-fetch ulang (kasus gagal parsial).
  List<Map<String, dynamic>> _rawProducts = const [];
  List<Map<String, dynamic>> _rawBrands = const [];
  List<Map<String, dynamic>> _rawCategories = const [];
  List<Map<String, dynamic>> _rawBanners = const [];

  @visibleForTesting
  RawListFetcher? debugProductsFetcher;
  @visibleForTesting
  RawListFetcher? debugBrandsFetcher;
  @visibleForTesting
  RawListFetcher? debugCategoriesFetcher;
  @visibleForTesting
  RawListFetcher? debugBannersFetcher;

  /// Hydrate dari disk — fire-and-forget dari main.dart.
  ///
  /// GUARD RACE (WAJIB): hasil disk hanya di-apply kalau store masih
  /// kosong. loadFromDisk berlomba dengan refresh() dari initState
  /// HomeScreen; refresh live yang menang duluan tidak boleh ditimpa
  /// snapshot lama.
  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawString = prefs.getString(_prefsKey);
      if (rawString == null) return;

      List<Map<String, dynamic>> section(
        Map<String, dynamic> map,
        String key,
      ) {
        final value = map[key];
        return value is List
            ? value.whereType<Map<String, dynamic>>().toList()
            : const [];
      }

      List<Product> parsedProducts;
      List<PetBrand> parsedBrands;
      List<HomeCategory> parsedCategories;
      List<HomeBanner> parsedBanners;
      List<Map<String, dynamic>> rawProducts;
      List<Map<String, dynamic>> rawBrands;
      List<Map<String, dynamic>> rawCategories;
      List<Map<String, dynamic>> rawBanners;
      try {
        final decoded = jsonDecode(rawString) as Map<String, dynamic>;
        rawProducts = section(decoded, 'products');
        rawBrands = section(decoded, 'brands');
        rawCategories = section(decoded, 'categories');
        rawBanners = section(decoded, 'banners');
        parsedProducts = rawProducts.map(Product.fromApiJson).toList();
        parsedBrands = rawBrands.map(PetBrand.fromApiJson).toList();
        parsedCategories =
            rawCategories.map(HomeCategory.fromApiJson).toList();
        parsedBanners = rawBanners.map(HomeBanner.fromApiJson).toList();
      } catch (_) {
        // Snapshot korup → buang key, jalan seperti first-run.
        await prefs.remove(_prefsKey);
        return;
      }

      if (hasContent) return; // guard race — data segar sudah masuk duluan

      products = parsedProducts;
      brands = parsedBrands;
      categories = parsedCategories;
      banners = parsedBanners;
      _rawProducts = rawProducts;
      _rawBrands = rawBrands;
      _rawCategories = rawCategories;
      _rawBanners = rawBanners;
      notifyListeners();
    } catch (_) {
      // IO prefs error — fail silent (pola store existing).
    }
  }

  /// Revalidate data home. [force] (pull-to-refresh / countdown expired)
  /// bypass soft-throttle.
  ///
  /// Kriteria GAGAL = fetch PRODUK gagal (raw null) → state lama utuh +
  /// [lastRefreshFailed]. Brands/categories/banners gagal sendirian hanya
  /// mempertahankan data lamanya — bukan kegagalan refresh.
  Future<void> refresh({bool force = false}) async {
    if (refreshing) return;
    if (!force &&
        _lastSuccessAt != null &&
        DateTime.now().difference(_lastSuccessAt!) < softThrottle) {
      return;
    }
    refreshing = true;
    try {
      final results = await Future.wait<List<Map<String, dynamic>>?>([
        debugProductsFetcher?.call() ?? productService.fetchHomeProductsRaw(),
        debugBrandsFetcher?.call() ?? productService.fetchBrandsRaw(),
        debugCategoriesFetcher?.call() ??
            productService.fetchCategoriesRaw(),
        debugBannersFetcher?.call() ?? productService.fetchBannersRaw(),
      ]);
      final rawProducts = results[0];
      final rawBrands = results[1];
      final rawCategories = results[2];
      final rawBanners = results[3];

      if (rawProducts == null) {
        lastRefreshFailed = true;
        notifyListeners();
        return;
      }

      products = rawProducts.map(Product.fromApiJson).toList();
      _rawProducts = rawProducts;
      if (rawBrands != null) {
        brands = rawBrands.map(PetBrand.fromApiJson).toList();
        _rawBrands = rawBrands;
      }
      if (rawCategories != null) {
        categories = rawCategories.map(HomeCategory.fromApiJson).toList();
        _rawCategories = rawCategories;
      }
      if (rawBanners != null) {
        banners = rawBanners.map(HomeBanner.fromApiJson).toList();
        _rawBanners = rawBanners;
      }
      lastRefreshFailed = false;
      _lastSuccessAt = DateTime.now();
      notifyListeners();
      unawaited(_persist());
    } catch (_) {
      // Parse error tak terduga — perlakukan seperti fetch gagal:
      // state lama dipertahankan.
      lastRefreshFailed = true;
      notifyListeners();
    } finally {
      refreshing = false;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          // savedAt informasional saja (debug) — TIDAK ada logika
          // kedaluwarsa; keputusan produk: umur snapshot tanpa batas.
          'savedAt': DateTime.now().toIso8601String(),
          'products': _rawProducts,
          'brands': _rawBrands,
          'categories': _rawCategories,
          'banners': _rawBanners,
        }),
      );
    } catch (_) {}
  }

  /// Reset penuh untuk test — state, throttle, fetcher injeksi.
  @visibleForTesting
  void resetForTest() {
    products = const [];
    brands = const [];
    categories = const [];
    banners = const [];
    refreshing = false;
    lastRefreshFailed = false;
    _lastSuccessAt = null;
    _rawProducts = const [];
    _rawBrands = const [];
    _rawCategories = const [];
    _rawBanners = const [];
    debugProductsFetcher = null;
    debugBrandsFetcher = null;
    debugCategoriesFetcher = null;
    debugBannersFetcher = null;
  }
}

final HomeSnapshotStore homeSnapshotStore = HomeSnapshotStore._();
```

- [ ] **Step 4: Jalankan test — pastikan pass**

Run: `cd flutter_app && flutter test test/state/home_snapshot_store_test.dart`
Expected: PASS (10 test).

- [ ] **Step 5: Analyze**

Run: `cd flutter_app && flutter analyze lib/state/home_snapshot_store.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/state/home_snapshot_store.dart flutter_app/test/state/home_snapshot_store_test.dart
git commit -m "feat(beranda): HomeSnapshotStore — snapshot disk SWR + guard race/anti-dobel/throttle"
```

---

### Task 3: HomeScreen store-driven + hydrate main.dart + widget test

**Files:**
- Modify: `flutter_app/lib/screens/home_screen.dart` (baris rujukan di bawah dari kondisi branch saat plan ditulis — verifikasi konteks sekitarnya sebelum edit)
- Modify: `flutter_app/lib/main.dart` (~baris 164)
- Test (create): `flutter_app/test/screens/home_screen_snapshot_test.dart`

**Interfaces:**
- Consumes (dari Task 2): `homeSnapshotStore` — `products`, `brands`, `categories`, `banners`, `hasContent`, `lastRefreshFailed`, `refresh({bool force})`, `loadFromDisk()`, `resetForTest()`, `debug*Fetcher`.
- Produces: tidak ada (task terminal).

- [ ] **Step 1: Tulis failing widget test**

Buat `flutter_app/test/screens/home_screen_snapshot_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/home_screen.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';
import 'package:natalo_petshop_flutter/state/home_snapshot_store.dart';
import 'package:natalo_petshop_flutter/widgets/natalo_paw_refresh_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> productJson(String id, String name) => {
      'id': id,
      'slug': id,
      'name': name,
      'price': 10000,
      'image_url': '',
    };

/// Bounded pump — JANGAN pumpAndSettle: marquee header + shimmer skeleton
/// beranimasi terus, settle tidak pernah tercapai (gotcha dikenal).
Future<void> pumpBounded(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> mountHome(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await pumpBounded(tester);
}

/// Unmount + drain supaya timer periodik (marquee/countdown) dibatalkan
/// oleh dispose — tanpa ini test gagal "Timer is still pending".
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void stubOthersEmpty() {
  homeSnapshotStore.debugBrandsFetcher = () async => [];
  homeSnapshotStore.debugCategoriesFetcher = () async => [];
  homeSnapshotStore.debugBannersFetcher = () async => [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    homeSnapshotStore.resetForTest();
    cartStore.clear();
  });

  testWidgets('fetch in-flight: banner "Belum berhasil memuat" TIDAK tampil',
      (tester) async {
    final gate = Completer<List<Map<String, dynamic>>?>();
    homeSnapshotStore.debugProductsFetcher = () => gate.future;
    stubOthersEmpty();
    await mountHome(tester);
    // Regresi utama bug A: selama loading tidak boleh ada pesan gagal.
    expect(find.textContaining('Belum berhasil memuat'), findsNothing);
    gate.complete(const []);
    await pumpBounded(tester);
    await unmount(tester);
  });

  testWidgets('store kosong + fetch gagal: banner tampil', (tester) async {
    homeSnapshotStore.debugProductsFetcher = () async => null;
    stubOthersEmpty();
    await mountHome(tester);
    expect(find.textContaining('Belum berhasil memuat'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
      'konten cache tampil + refresh gagal: konten render, banner absen',
      (tester) async {
    // Seed konten (simulasi hydrate/sesi sebelumnya) via refresh sukses.
    homeSnapshotStore.debugProductsFetcher =
        () async => [productJson('p1', 'Produk Cache Uji')];
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    // Refresh berikutnya gagal.
    homeSnapshotStore.debugProductsFetcher = () async => null;
    await mountHome(tester);
    await homeSnapshotStore.refresh(force: true);
    await pumpBounded(tester);
    // CustomScrollView lazy — section produk (Terlaris) bisa di bawah
    // fold viewport test 800x600; scroll dulu supaya kartunya ter-build.
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -600),
    );
    await pumpBounded(tester, 3);
    expect(find.textContaining('Produk Cache Uji'), findsWidgets);
    expect(find.textContaining('Belum berhasil memuat'), findsNothing);
    await unmount(tester);
  });

  testWidgets('pull-to-refresh me-retry fetch produk (bypass throttle)',
      (tester) async {
    var calls = 0;
    homeSnapshotStore.debugProductsFetcher = () async {
      calls++;
      return [productJson('p1', 'Produk Uji')];
    };
    stubOthersEmpty();
    await mountHome(tester);
    expect(calls, 1); // refresh dari initState
    final indicator = tester.widget<NataloPawRefreshIndicator>(
      find.byType(NataloPawRefreshIndicator),
    );
    // Panggil handler langsung — gesture pull dengan indikator custom
    // pinContent tidak deterministik di test.
    await indicator.onRefresh();
    await pumpBounded(tester);
    // force:true bypass soft-throttle 30s → fetch benar-benar diulang.
    expect(calls, 2);
    await unmount(tester);
  });
}
```

Catatan implementer: kalau mount HomeScreen melempar `MissingPluginException` dari plugin platform (mis. connectivity), stub channel terkait via `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(...)` di `setUp` — JANGAN mengubah kode produksi untuk itu; catat di report kalau perlu.

- [ ] **Step 2: Jalankan — pastikan gagal karena perilaku lama**

Run: `cd flutter_app && flutter test test/screens/home_screen_snapshot_test.dart`
Expected: FAIL — test 1 menemukan banner saat loading (perilaku bug lama, `initialData fromApi:false`), dan/atau test 4 gagal (fetcher store tidak pernah terpanggil karena HomeScreen masih pakai `_productsFuture`).

- [ ] **Step 3: Rewire `home_screen.dart`**

Semua edit di `flutter_app/lib/screens/home_screen.dart`. Nomor baris = posisi saat plan ditulis; cocokkan lewat isi snippet, bukan nomor.

3a. Tambah import (blok import relatif, urut alfabetis):

```dart
import '../state/home_snapshot_store.dart';
```

3b. HAPUS field `_productsFuture` (baris ~78):

```dart
  late final Future<ProductResult> _productsFuture;
```

3c. HAPUS SELURUH blok field brand/category/banner berikut (baris ~112-115) — data kini dibaca langsung dari `homeSnapshotStore`, tidak ada penggantinya di sini:

```dart
  // ── Brand, Category, Banner dynamic fetch ──
  List<PetBrand> _brands = const [];
  List<HomeCategory> _categories = const [];
  List<HomeBanner> _banners = const [];
```

3d. GANTI sumber getter `_logoBrands` (baris ~124-126):

```dart
  List<PetBrand> get _logoBrands => _brands
      .where((b) => b.logoUrl != null && b.logoUrl!.trim().isNotEmpty)
      .toList();
```

menjadi:

```dart
  List<PetBrand> get _logoBrands => homeSnapshotStore.brands
      .where((b) => b.logoUrl != null && b.logoUrl!.trim().isNotEmpty)
      .toList();
```

3e. Di `initState` (baris ~160-162), GANTI:

```dart
    _productsFuture = productService.fetchProducts(limit: 48);
    _scrollController.addListener(_onScroll);
    _loadDynamicSections();
```

menjadi:

```dart
    // Revalidate data home (SWR) — Beranda render dari homeSnapshotStore
    // (memori saat pindah tab, disk saat cold start), fetch segar jalan
    // diam-diam di belakang. Soft-throttle 30s di dalam store.
    homeSnapshotStore.refresh();
    _scrollController.addListener(_onScroll);
```

3f. HAPUS seluruh method `_loadDynamicSections` (baris ~216-229):

```dart
  Future<void> _loadDynamicSections() async {
    // Fetch paralel — semua endpoint cached di server (revalidate 300s).
    final results = await Future.wait([
      productService.fetchBrands(),
      productService.fetchCategories(),
      productService.fetchBanners(),
    ]);
    if (!mounted) return;
    setState(() {
      _brands = results[0] as List<PetBrand>;
      _categories = results[1] as List<HomeCategory>;
      _banners = results[2] as List<HomeBanner>;
    });
  }
```

3g. Di `_refreshAll` (baris ~240-245), GANTI:

```dart
    // _loadDynamicSections paralel — tidak ada dependency dengan
    // personalized/explore. _initializeRecsAndExplore sequential
    // internal (personalized DULU baru explore — mencegah race
    // duplikat IDs).
    await Future.wait([_loadDynamicSections(), _initializeRecsAndExplore()]);
```

menjadi:

```dart
    // Store refresh force:true — user eksplisit minta, bypass throttle;
    // sekaligus membuat saran banner "tarik ke bawah" jujur (dulu fetch
    // produk utama tidak pernah di-retry). _initializeRecsAndExplore
    // sequential internal (personalized DULU baru explore — mencegah
    // race duplikat IDs).
    await Future.wait([
      homeSnapshotStore.refresh(force: true),
      _initializeRecsAndExplore(),
    ]);
```

3h. GANTI pembuka `FutureBuilder` (baris ~653-664):

```dart
              child: FutureBuilder<ProductResult>(
                future: _productsFuture,
                // Initial data empty supaya skeleton/loading UI muncul first paint
                // — bukan flash sampleProducts mock. Capacitor admin dashboard
                // adalah single source of truth.
                initialData: const ProductResult(
                  products: <Product>[],
                  fromApi: false,
                ),
                builder: (context, snapshot) {
                  final result = snapshot.data;
                  final products = result?.products ?? const <Product>[];
```

menjadi:

```dart
              child: ListenableBuilder(
                listenable: homeSnapshotStore,
                // Store-driven (SWR): render langsung dari snapshot store —
                // memori saat pindah tab, disk saat cold start. FutureBuilder
                // + initialData(fromApi:false) lama dihapus: initialData itu
                // yang membuat banner error tampil SELAMA loading (salah
                // label), karena kondisi banner cuma cek fromApi == false.
                builder: (context, _) {
                  final products = homeSnapshotStore.products;
```

(Penutup blok `},` `)` FutureBuilder lama tetap valid untuk ListenableBuilder — jumlah kurung tidak berubah.)

3i. GANTI kondisi banner (baris ~749-750):

```dart
                        if (result?.fromApi == false)
                          const SliverToBoxAdapter(child: _ApiFallbackNotice()),
```

menjadi:

```dart
                        // Banner HANYA saat benar-benar tidak ada yang bisa
                        // ditampilkan: fetch produk berakhir gagal DAN store
                        // kosong (tak ada cache). Selama loading → tidak ada
                        // banner. Konten cache tampil + refresh gagal → diam
                        // (keputusan produk, ala IG/Shopee).
                        if (!homeSnapshotStore.hasContent &&
                            homeSnapshotStore.lastRefreshFailed)
                          const SliverToBoxAdapter(child: _ApiFallbackNotice()),
```

(Baris terakhir berakhir `_ApiFallbackNotice()),` dengan SATU koma — sama seperti aslinya.)

3j. GANTI sumber `_HeroBanner` (baris ~758-759):

```dart
                        SliverToBoxAdapter(
                          child: _HeroBanner(banners: _banners),
                        ),
```

menjadi:

```dart
                        SliverToBoxAdapter(
                          child: _HeroBanner(banners: homeSnapshotStore.banners),
                        ),
```

3k. GANTI sumber `_CategorySection` (baris ~809-811):

```dart
                        SliverToBoxAdapter(
                          child: _CategorySection(
                            categories: _categories,
```

menjadi:

```dart
                        SliverToBoxAdapter(
                          child: _CategorySection(
                            categories: homeSnapshotStore.categories,
```

3l. Cek sisa referensi: `grep -n "_productsFuture\|_brands\b\|_categories\b\|_banners\b\|_loadDynamicSections\|result?" flutter_app/lib/screens/home_screen.dart` — tidak boleh ada sisa (kecuali `_logoBrands` yang sudah diganti sumbernya). Import model `PetBrand`/`HomeCategory`/`HomeBanner` tetap dipakai (tipe di widget section) — jangan dihapus kalau analyze tidak menandai unused.

- [ ] **Step 4: Hydrate di `main.dart`**

Di `flutter_app/lib/main.dart`, SETELAH blok (baris ~162-164):

```dart
  // Recently viewed — load history dari disk supaya Home carousel
  // langsung populated saat user buka app.
  recentlyViewedStore.loadFromDisk();
```

tambahkan:

```dart
  // Home snapshot — hydrate data Beranda sesi terakhir dari disk (SWR)
  // supaya cold start langsung render konten, bukan skeleton + banner.
  // Fire-and-forget (tidak blocking first frame); guard internal mencegah
  // snapshot lama menimpa data segar yang datang duluan.
  homeSnapshotStore.loadFromDisk();
```

dan tambah import (blok import relatif main.dart, urut alfabetis):

```dart
import 'state/home_snapshot_store.dart';
```

- [ ] **Step 5: Jalankan widget test — pastikan pass**

Run: `cd flutter_app && flutter test test/screens/home_screen_snapshot_test.dart`
Expected: PASS (4 test).

- [ ] **Step 6: Analyze + suite penuh**

Run: `cd flutter_app && flutter analyze`
Expected: No issues found.

Run: `cd flutter_app && flutter test`
Expected: semua hijau (kecuali kegagalan yang SUDAH ada di main sebelum branch ini — kalau ada yang gagal, bandingkan dengan `git stash && flutter test <file> && git stash pop` atau catat dan laporkan; JANGAN diklaim pre-existing tanpa bukti).

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/screens/home_screen.dart flutter_app/lib/main.dart flutter_app/test/screens/home_screen_snapshot_test.dart
git commit -m "feat(beranda): store-driven SWR — banner hanya saat benar-benar gagal + retry jujur + render instan"
```

---

### Task 4: Verifikasi akhir

- [ ] **Step 1: Analyze seluruh project**

Run: `cd flutter_app && flutter analyze`
Expected: No issues found.

- [ ] **Step 2: Suite test penuh**

Run: `cd flutter_app && flutter test`
Expected: semua pass (bandingkan jumlah pass/skip dengan baseline main bila ada kegagalan).

- [ ] **Step 3: Smoke checklist manual (dokumentasikan di report, eksekusi di device menyusul)**

Perilaku yang harus benar (dari tabel spec):
1. First-run (belum ada snapshot): tidak ada banner selama loading; banner hanya kalau fetch berakhir gagal.
2. Cold start berikutnya: konten sesi terakhir langsung tampil.
3. Pindah tab balik ke Beranda: konten instan dari memori, tanpa banner/skeleton.
4. Pull-to-refresh saat gagal: fetch produk benar-benar diulang.
5. Refresh gagal saat konten tampil: diam.

- [ ] **Step 4: Commit sisa perbaikan (kalau ada) — pesan sesuai isi perbaikan**
