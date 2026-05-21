import '../config/api_config.dart';
import '../models/brand.dart';
import '../models/home_banner.dart';
import '../models/home_category.dart';
import '../models/product.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

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

  const ProductResult({
    super.products = const [],
    super.nextCursor,
    this.fromApi = true,
    this.error,
    this.total,
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
  }) async {
    try {
      final keyword = query?.trim() ?? '';
      final data = await apiClient.getJson(
        '/api/products',
        query: {
          if (keyword.isNotEmpty) 'search': keyword,
          if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
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
        },
      );
      final map = _asMap(data);
      final products = _extractProducts(data);
      // Extract nextCursor untuk pagination. Backend response shape:
      // { items: [...], nextCursor: "24" | null, hasMore: bool, total: N }
      final nextCursor = map?['nextCursor']?.toString();
      return ProductResult(
        products: products,
        nextCursor: nextCursor != null && nextCursor.isNotEmpty
            ? nextCursor
            : null,
        fromApi: map != null || data is List,
        total: map == null ? products.length : _asInt(map['total']),
      );
    } catch (error) {
      return ProductResult(
        products: const <Product>[],
        fromApi: false,
        error: error.toString(),
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
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/recommendations/personalized',
        query: {
          'limit': '$limit',
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

  Future<List<HomeBanner>> fetchBanners() async {
    try {
      final data = await apiClient.getJson('/api/banners');
      final map = _asMap(data);
      final raw = map == null ? data : (map['banners'] ?? map['items']);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(HomeBanner.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<PetBrand>> fetchBrands() async {
    try {
      final data = await apiClient.getJson('/api/brands');
      final map = _asMap(data);
      final raw = map == null ? data : (map['brands'] ?? map['items']);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(PetBrand.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<HomeCategory>> fetchCategories() async {
    try {
      final data = await apiClient.getJson('/api/categories');
      final map = _asMap(data);
      final raw = map == null ? data : (map['categories'] ?? map['items']);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(HomeCategory.fromApiJson)
          .toList();
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

  Future<SearchSuggestionResult> fetchSuggestions(String query) async {
    final keyword = query.trim();
    if (keyword.length < 2) return const SearchSuggestionResult();
    try {
      final data = await apiClient.getJson(
        '/api/search/suggest',
        query: {'q': keyword, 'limit': '8'},
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

  Future<List<Map<String, dynamic>>> fetchProductFeedPosts(String slug) async {
    if (slug.trim().isEmpty) return const [];
    try {
      final data = await apiClient.getJson(
        '/api/products/${Uri.encodeComponent(slug)}/feed-posts',
      );
      final map = _asMap(data);
      final raw =
          map == null ? data : (map['posts'] ?? map['items'] ?? map['data']);
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
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
