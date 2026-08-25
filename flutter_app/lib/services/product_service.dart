import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../models/brand.dart';
import '../models/home_banner.dart';
import '../models/home_category.dart';
import '../models/launch_popup.dart';
import '../models/product.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

class ProductFeedPostsPage {
  final List<Map<String, dynamic>> items;
  final int total;
  final int offset;
  final bool hasMore;
  final bool failed;

  const ProductFeedPostsPage({
    this.items = const [],
    this.total = 0,
    this.offset = 0,
    this.hasMore = false,
    this.failed = false,
  });
}

class SearchSuggestionResult {
  final List<ProductSuggestion> products;
  final List<LabelSuggestion> categories;
  final List<LabelSuggestion> brands;

  const SearchSuggestionResult({
    this.products = const [],
    this.categories = const [],
    this.brands = const [],
  });

  bool get isEmpty => products.isEmpty && categories.isEmpty && brands.isEmpty;

  factory SearchSuggestionResult.fromJson(Map<String, dynamic> json) {
    return SearchSuggestionResult(
      products:
          _list(json['products']).map(ProductSuggestion.fromJson).toList(),
      categories:
          _list(json['categories']).map(LabelSuggestion.fromJson).toList(),
      brands: _list(json['brands']).map(LabelSuggestion.fromJson).toList(),
    );
  }

  static List<Map<String, dynamic>> _list(Object? value) {
    return value is List
        ? value.whereType<Map<String, dynamic>>().toList()
        : const [];
  }
}

class ProductSuggestion {
  final String id;
  final String slug;
  final String name;
  final String imageUrl;
  final double priceMin;
  final double priceMax;
  final String? brandName;

  const ProductSuggestion({
    required this.id,
    required this.slug,
    required this.name,
    required this.imageUrl,
    required this.priceMin,
    required this.priceMax,
    this.brandName,
  });

  factory ProductSuggestion.fromJson(Map<String, dynamic> json) {
    return ProductSuggestion(
      id: (json['id'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      name: (json['name'] ?? 'Produk Natalo').toString(),
      imageUrl: _absoluteUrl(
        (json['image_url'] ?? json['imageUrl'] ?? '').toString(),
      ),
      priceMin: _asDouble(json['price_min'] ?? json['priceMin']),
      priceMax: _asDouble(json['price_max'] ?? json['priceMax']),
      brandName:
          json['brand_name']?.toString() ?? json['brandName']?.toString(),
    );
  }
}

class LabelSuggestion {
  final String slug;
  final String name;
  final int count;

  const LabelSuggestion({
    required this.slug,
    required this.name,
    required this.count,
  });

  factory LabelSuggestion.fromJson(Map<String, dynamic> json) {
    return LabelSuggestion(
      slug: (json['slug'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      count: _asInt(json['count']) ?? 0,
    );
  }
}

/// Wrapper hasil fetchProducts. Nama lama `ProductFetchResult` tetap ada supaya
/// call site lama seperti Feed upload dan Wishlist tidak perlu diubah.
class ProductFetchResult {
  final List<Product> products;
  final String? nextCursor;

  const ProductFetchResult({
    this.products = const [],
    this.nextCursor,
  });
}

class ProductResult extends ProductFetchResult {
  final bool fromApi;
  final String? error;
  final int? total;

  /// HTTP status code dari error (kalau ada). null = network/timeout
  /// (offline). Dipakai UI untuk pilih AppErrorVariant yang benar
  /// (5xx=server, dst) supaya error state tidak salah label.
  final int? errorStatusCode;

  const ProductResult({
    super.products = const [],
    super.nextCursor,
    this.fromApi = true,
    this.error,
    this.total,
    this.errorStatusCode,
  });
}

/// Halaman paginated produk untuk infinite scroll. Match response PWA
/// GET /api/products yang return {items, nextCursor, hasMore, total}.
class ProductPage {
  final List<Product> products;
  final String? nextCursor;
  final bool hasMore;
  final int total;

  const ProductPage({
    required this.products,
    required this.nextCursor,
    required this.hasMore,
    required this.total,
  });

  static const empty = ProductPage(
    products: [],
    nextCursor: null,
    hasMore: false,
    total: 0,
  );
}

class ProductService {
  ProductService._();

  Future<ProductResult> fetchProducts({
    String? brand,

    /// Multi-select brand names (dari Filter sheet checkbox) — dikirim
    /// server-side, bukan lagi cuma filter lokal terhadap produk yang
    /// sudah ter-load. Beda dengan `brand` (tunggal, dari home card tap).
    Set<String>? brands,
    String? category,
    String? query,
    int limit = 30,
    String? newFilter,
    String? popularFilter,
    bool inStock = false,
    bool hasPrice = false,
    bool withImage = false,

    /// Filter produk yang sedang diskon (Flash Sale aktif atau Promo
    /// Toko aktif). Server-side filter — lebih akurat dari client-side
    /// karena tidak terkubur di limit pagination.
    bool discountOnly = false,

    /// Filter HANYA produk dengan ID dalam list. Dipakai wishlist.
    /// Backend auto-bypass inStockOnly supaya produk stok 0 yang
    /// di-wishlist tetap muncul.
    List<String>? ids,

    /// Cursor untuk pagination — lanjut dari offset N (response
    /// `nextCursor`). Null = halaman pertama. Dipakai infinite scroll.
    String? cursor,

    /// Seed pengurut beragam untuk daftar "Semua" tanpa filter.
    ///
    /// Backend mengurutkan `ORDER BY md5(id || seed)` — acak tapi
    /// DETERMINISTIK, jadi pagination tetap konsisten selama seed sama.
    ///
    /// Backend MENGABAIKAN seed kalau ada category/brand/search/new/
    /// popular/inStock/hasPrice/withImage/exclude (lihat guard di
    /// lib/products.ts). Jadi aman dikirim selalu — tampilan terfilter
    /// otomatis kembali ke urutan bawaan.
    String? seed,
  }) async {
    try {
      final keyword = query?.trim() ?? '';
      final data = await apiClient.getJson(
        '/api/products',
        timeout: const Duration(seconds: 15),
        query: {
          if (keyword.isNotEmpty) 'search': keyword,
          if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
          if (brands != null && brands.isNotEmpty) 'brands': brands.join(','),
          if (category != null && category.trim().isNotEmpty)
            'category': category.trim(),
          'limit': '$limit',
          if (newFilter != null) 'new': newFilter,
          if (popularFilter != null) 'popular': popularFilter,
          if (inStock) 'inStock': 'true',
          if (hasPrice) 'hasPrice': 'true',
          if (withImage) 'withImage': 'true',
          if (discountOnly) 'discountOnly': 'true',
          if (ids != null && ids.isNotEmpty) 'ids': ids.join(','),
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          if (seed != null && seed.isNotEmpty) 'seed': seed,
        },
      );
      final map = _asMap(data);
      final products = _extractProducts(data);
      // Extract nextCursor untuk pagination. Backend response shape:
      // { items: [...], nextCursor: "24" | null, hasMore: bool, total: N }
      final nextCursor = map?['nextCursor']?.toString();
      return ProductResult(
        products: products,
        nextCursor:
            nextCursor != null && nextCursor.isNotEmpty ? nextCursor : null,
        fromApi: map != null || data is List,
        total: map == null ? products.length : _asInt(map['total']),
      );
    } catch (error) {
      // Simpan statusCode (kalau ApiException) supaya UI bisa bedakan
      // error server (5xx) vs offline (network) — fix mislabel error state.
      return ProductResult(
        products: const <Product>[],
        fromApi: false,
        error: 'Belum berhasil memuat. Tarik ke bawah untuk coba lagi.',
        errorStatusCode: error is ApiException ? error.statusCode : null,
      );
    }
  }

  /// GET /api/products — list dengan optional filter. Kept for older screens
  /// (Produk, Cart fallback, Wishlist) that expect a plain List<Product>.
  Future<List<Product>> fetchAll({
    String? brand,
    String? category,
    String? query,
    int limit = 30,
  }) async {
    final result = await fetchProducts(
      brand: brand,
      category: category,
      query: query,
      limit: limit,
    );
    return result.products;
  }

  Future<ProductPage> fetchProductsPage({
    String? cursor,
    int limit = 24,
    List<String> excludeIds = const [],
    bool inStock = true,
    bool hasPrice = true,
    bool withImage = true,
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/products',
        query: {
          'limit': '$limit',
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          if (excludeIds.isNotEmpty) 'exclude': excludeIds.join(','),
          if (inStock) 'inStock': 'true',
          if (hasPrice) 'hasPrice': 'true',
          if (withImage) 'withImage': 'true',
        },
      );
      final map = _asMap(data);
      if (map == null) return ProductPage.empty;
      final products = _extractProducts(map);
      final nextCursor = map['nextCursor']?.toString();
      return ProductPage(
        products: products,
        nextCursor:
            nextCursor == null || nextCursor.isEmpty ? null : nextCursor,
        hasMore: map['hasMore'] == true,
        total: _asInt(map['total']) ?? products.length,
      );
    } catch (_) {
      return ProductPage.empty;
    }
  }

  /// Fetch produk rekomendasi dari endpoint PWA /api/cart/recommendations.
  Future<List<Product>> fetchRecommendations({
    List<String> cartIds = const [],
    List<String> viewedIds = const [],
    List<String> excludeIds = const [],
    int limit = 10,
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/cart/recommendations',
        query: {
          'limit': '$limit',
          if (cartIds.isNotEmpty) 'cart': cartIds.join(','),
          if (viewedIds.isNotEmpty) 'viewed': viewedIds.join(','),
          if (excludeIds.isNotEmpty) 'exclude': excludeIds.join(','),
        },
      );
      final map = _asMap(data);
      final raw = map == null ? data : (map['data'] ?? map['items']);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Product.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Server-side personalized recommendations untuk home screen
  /// "Rekomendasi Untuk Kamu". Backend scan SELURUH catalog (bukan cuma
  /// pool 48 dari home fetch) + tambah purchase signal (×3.0 brand /
  /// ×2.5 category) di samping view signal.
  ///
  /// Wajib pass `viewedIds` dari client-side `recentlyViewedStore` —
  /// signal anonymous untuk user yang belum login. Untuk user yang
  /// login, backend juga merge dengan `user_product_views` table +
  /// orderItem history.
  ///
  /// Return empty list kalau API gagal (offline, server down). Caller
  /// harus fallback ke client-side scoring.
  Future<List<Product>> fetchPersonalizedRecommendations({
    List<String> viewedIds = const [],
    List<String> excludeIds = const [],
    int limit = 10,
    String? seed,
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/recommendations/personalized',
        query: {
          'limit': '$limit',
          if (viewedIds.isNotEmpty) 'viewed': viewedIds.join(','),
          if (excludeIds.isNotEmpty) 'exclude': excludeIds.join(','),
          if (seed != null && seed.isNotEmpty) 'seed': seed,
        },
      );
      final map = _asMap(data);
      final raw = map == null ? data : (map['data'] ?? map['items']);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Product.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetch recently-viewed produk (server-side stored kalau user login,
  /// merged dengan IDs dari client). Endpoint /api/cart/recently-viewed.
  Future<List<Product>> fetchRecentlyViewed({
    List<String> ids = const [],
    List<String> excludeIds = const [],
    int limit = 10,
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/cart/recently-viewed',
        query: {
          'limit': '$limit',
          if (ids.isNotEmpty) 'ids': ids.join(','),
          if (excludeIds.isNotEmpty) 'exclude': excludeIds.join(','),
        },
      );
      final map = _asMap(data);
      final raw = map == null ? data : (map['data'] ?? map['items']);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Product.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Product?> fetchProductBySlug(String slug) async {
    if (slug.isEmpty) return null;
    try {
      final data = await apiClient.getJson(
        '/api/products/${Uri.encodeComponent(slug)}',
      );
      final map = _asMap(data);
      if (map == null) return null;
      final raw = map['product'] ?? map['data'] ?? map;
      return raw is Map<String, dynamic> ? Product.fromApiJson(raw) : null;
    } catch (_) {
      return null;
    }
  }

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

  /// Produk terlaris SUNGGUHAN — peringkat dari seluruh katalog.
  ///
  /// Dulu Beranda mengurutkan sendiri hasil [fetchHomeProductsRaw] by
  /// soldCount. Itu keliru: daftar itu diambil tanpa filter, jadi urutan
  /// bawaannya Flash Sale dulu lalu createdAt desc — 48 produk TERBARU.
  /// Produk terlaris yang lebih tua tidak pernah masuk kandidat, jadi
  /// "Produk Terlaris" sebenarnya berarti "terlaris di antara 48 produk
  /// terbaru". `popular=best-seller` mengelompokkan OrderItem berbayar di
  /// seluruh katalog dan mengurutkannya by total kuantitas terjual.
  ///
  /// Kontrak null-vs-[] sama seperti fetchHomeProductsRaw: null = gagal
  /// fetch (pertahankan data lama), [] = sukses tapi memang kosong.
  Future<List<Map<String, dynamic>>?> fetchBestSellersRaw({
    int limit = 8,
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/products',
        timeout: const Duration(seconds: 15),
        query: {'popular': 'best-seller', 'limit': '$limit'},
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

  Future<List<HomeBanner>> fetchBanners() async {
    final raw = await fetchBannersRaw();
    if (raw == null) return const [];
    try {
      return raw.map(HomeBanner.fromApiJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Popup promo bergambar cold start (admin-managed, gaya Shopee).
  /// null = tidak ada popup aktif / API gagal → LaunchPromoGate skip total.
  Future<LaunchPopup?> fetchLaunchPopup() async {
    try {
      final data = await apiClient.getJson('/api/launch-popup');
      final map = _asMap(data);
      final raw = map?['popup'];
      if (raw is! Map<String, dynamic>) return null;
      final popup = LaunchPopup.fromApiJson(raw);
      return popup.imageUrl.isEmpty ? null : popup;
    } catch (_) {
      return null;
    }
  }

  /// Fetch daftar brand. `category` opsional (slug) — scope brand ke
  /// kategori itu (dipakai Filter sheet halaman Produk saat kategori
  /// aktif). Tanpa `category`, return daftar brand global (perilaku
  /// lama, dipakai all_brands_screen.dart & home "Brand Favorit").
  Future<List<PetBrand>> fetchBrands({String? category}) async {
    final raw = await fetchBrandsRaw(category: category);
    if (raw == null) return const [];
    try {
      return raw.map(PetBrand.fromApiJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<HomeCategory>> fetchCategories() async {
    final raw = await fetchCategoriesRaw();
    if (raw == null) return const [];
    try {
      return raw.map(HomeCategory.fromApiJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fire-and-forget view tracking. Skipped in read-only testing mode so test
  /// traffic does not inflate real product counters.
  Future<void> trackView(String slug) async {
    if (slug.isEmpty || readOnlyMode.isReadOnly) return;
    try {
      await apiClient.postJson(
        '/api/products/${Uri.encodeComponent(slug)}/view',
        body: const <String, dynamic>{},
        timeout: const Duration(seconds: 4),
      );
    } catch (_) {
      // Non-critical analytics.
    }
  }

  Future<SearchSuggestionResult> fetchSuggestions(
    String query, {
    /// Filter kategori/brand aktif dari catalog screen — supaya suggestion
    /// konsisten dengan grid produk yang sedang di-filter. Boleh nama atau
    /// slug; server resolve keduanya. Null/kosong = suggestion global.
    String? category,
    String? brand,
  }) async {
    final keyword = query.trim();
    if (keyword.length < 2) return const SearchSuggestionResult();
    try {
      final data = await apiClient.getJson(
        '/api/search/suggest',
        query: {
          'q': keyword,
          'limit': '8',
          if (category != null && category.trim().isNotEmpty)
            'category': category.trim(),
          if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
        },
      );
      final map = _asMap(data);
      return map == null
          ? const SearchSuggestionResult()
          : SearchSuggestionResult.fromJson(map);
    } catch (_) {
      return const SearchSuggestionResult();
    }
  }

  Future<List<Map<String, dynamic>>> fetchProductVouchers(String slug) async {
    if (slug.trim().isEmpty) return const [];
    try {
      final data = await apiClient.getJson(
        '/api/products/${Uri.encodeComponent(slug)}/vouchers',
      );
      final map = _asMap(data);
      final raw =
          map == null ? data : (map['vouchers'] ?? map['items'] ?? map['data']);
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchProductFeedPosts(
    String slug, {
    int limit = 12,
  }) async {
    final page = await fetchProductFeedPostsPage(slug, limit: limit);
    return page.items;
  }

  Future<ProductFeedPostsPage> fetchProductFeedPostsPage(
    String slug, {
    int limit = 12,
    int offset = 0,
  }) async {
    if (slug.trim().isEmpty) return const ProductFeedPostsPage();
    try {
      final data = await apiClient.getJson(
        '/api/products/${Uri.encodeComponent(slug)}/feed-posts',
        query: {
          'limit': limit.toString(),
          'offset': offset.toString(),
        },
      );
      final map = _asMap(data);
      final raw =
          map == null ? data : (map['posts'] ?? map['items'] ?? map['data']);
      if (raw is! List) return const ProductFeedPostsPage(failed: true);
      final items = raw.whereType<Map<String, dynamic>>().toList();
      final total = _asInt(map?['total']) ?? items.length;
      final resolvedOffset = _asInt(map?['offset']) ?? offset;
      return ProductFeedPostsPage(
        items: items,
        total: total,
        offset: resolvedOffset,
        hasMore:
            map?['hasMore'] == true || resolvedOffset + items.length < total,
      );
    } catch (_) {
      return const ProductFeedPostsPage(failed: true);
    }
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  return value is Map<String, dynamic> ? value : null;
}

List<Product> _extractProducts(Object? data) {
  final map = _asMap(data);
  final raw = data is List
      ? data
      : map == null
          ? const []
          : (map['items'] ?? map['data'] ?? map['products']);
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(Product.fromApiJson)
      .toList();
}

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

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http') || url.startsWith('assets/')) {
    return url;
  }
  final base = Uri.parse(ApiConfig.baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}

final ProductService productService = ProductService._();
