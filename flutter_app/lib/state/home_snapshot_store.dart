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
/// Satu-satunya pemilik data home (produk limit 48 + terlaris + brands +
/// categories + banners). Beranda render langsung dari sini: pindah tab = instan dari
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

  /// Produk terlaris dari SELURUH katalog (endpoint popular=best-seller).
  /// Dipisah dari [products] karena [products] adalah 48 produk TERBARU —
  /// mengurutkannya by soldCount hanya menghasilkan "terlaris di antara
  /// yang terbaru", bukan terlaris sebenarnya.
  List<Product> bestSellers = const [];
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
  List<Map<String, dynamic>> _rawBestSellers = const [];
  List<Map<String, dynamic>> _rawBrands = const [];
  List<Map<String, dynamic>> _rawCategories = const [];
  List<Map<String, dynamic>> _rawBanners = const [];

  @visibleForTesting
  RawListFetcher? debugProductsFetcher;
  @visibleForTesting
  RawListFetcher? debugBestSellersFetcher;
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
      List<Product> parsedBestSellers;
      List<PetBrand> parsedBrands;
      List<HomeCategory> parsedCategories;
      List<HomeBanner> parsedBanners;
      List<Map<String, dynamic>> rawProducts;
      List<Map<String, dynamic>> rawBestSellers;
      List<Map<String, dynamic>> rawBrands;
      List<Map<String, dynamic>> rawCategories;
      List<Map<String, dynamic>> rawBanners;
      try {
        final decoded = jsonDecode(rawString) as Map<String, dynamic>;
        rawProducts = section(decoded, 'products');
        // Snapshot lama (dibuat sebelum bagian ini ada) tidak punya key-nya:
        // section() mengembalikan [] dan daftar terlaris terisi saat refresh
        // pertama. Tidak perlu membuang snapshot lama.
        rawBestSellers = section(decoded, 'bestSellers');
        rawBrands = section(decoded, 'brands');
        rawCategories = section(decoded, 'categories');
        rawBanners = section(decoded, 'banners');
        parsedProducts = rawProducts.map(Product.fromApiJson).toList();
        parsedBestSellers = rawBestSellers.map(Product.fromApiJson).toList();
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
      bestSellers = parsedBestSellers;
      brands = parsedBrands;
      categories = parsedCategories;
      banners = parsedBanners;
      _rawProducts = rawProducts;
      _rawBestSellers = rawBestSellers;
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
        debugBestSellersFetcher?.call() ??
            productService.fetchBestSellersRaw(),
        debugBrandsFetcher?.call() ?? productService.fetchBrandsRaw(),
        debugCategoriesFetcher?.call() ??
            productService.fetchCategoriesRaw(),
        debugBannersFetcher?.call() ?? productService.fetchBannersRaw(),
      ]);
      final rawProducts = results[0];
      final rawBestSellers = results[1];
      final rawBrands = results[2];
      final rawCategories = results[3];
      final rawBanners = results[4];

      if (rawProducts == null) {
        lastRefreshFailed = true;
        notifyListeners();
        return;
      }

      products = rawProducts.map(Product.fromApiJson).toList();
      _rawProducts = rawProducts;
      // Terlaris gagal sendirian BUKAN kegagalan refresh — pertahankan
      // daftar lama, sama seperti brands/categories/banners.
      if (rawBestSellers != null) {
        bestSellers = rawBestSellers.map(Product.fromApiJson).toList();
        _rawBestSellers = rawBestSellers;
      }
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
          'bestSellers': _rawBestSellers,
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
    bestSellers = const [];
    brands = const [];
    categories = const [];
    banners = const [];
    refreshing = false;
    lastRefreshFailed = false;
    _lastSuccessAt = null;
    _rawProducts = const [];
    _rawBestSellers = const [];
    _rawBrands = const [];
    _rawCategories = const [];
    _rawBanners = const [];
    debugProductsFetcher = null;
    debugBestSellersFetcher = null;
    debugBrandsFetcher = null;
    debugCategoriesFetcher = null;
    debugBannersFetcher = null;
  }
}

final HomeSnapshotStore homeSnapshotStore = HomeSnapshotStore._();
