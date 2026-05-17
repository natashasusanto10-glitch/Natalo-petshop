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

class ProductResult {
  final List<Product> products;
  final bool fromApi;
  final String? error;
  final int? total;

  const ProductResult({
    required this.products,
    required this.fromApi,
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
  Future<ProductResult> fetchProducts({
    String query = '',
    int limit = 120,
    String? newFilter,
    String? popularFilter,
    bool inStock = true,
    bool hasPrice = true,
    bool withImage = false,
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/products',
        query: {
          'search': query,
          'limit': '$limit',
          if (newFilter != null) 'new': newFilter,
          if (popularFilter != null) 'popular': popularFilter,
          'inStock': inStock ? 'true' : 'false',
          'hasPrice': hasPrice ? 'true' : 'false',
          if (withImage) 'withImage': 'true',
        },
      );
      final rawItems = data['items'];
      final products = rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(Product.fromApiJson)
              .toList()
          : <Product>[];

      // Empty result dari API = legitimate empty (admin belum tambah produk
      // matching query). Tidak fallback ke sampleProducts — single source
      // of truth = Capacitor backend.
      return ProductResult(
        products: products,
        fromApi: true,
        total: _asInt(data['total']),
      );
    } catch (error) {
      // Network/server error — return empty + error message. UI layer
      // tampilkan banner "Koneksi bermasalah, tarik untuk refresh".
      return ProductResult(
        products: const <Product>[],
        fromApi: false,
        error: error.toString(),
      );
    }
  }

  /// Fetch satu halaman produk untuk infinite scroll. Match PWA endpoint
  /// GET /api/products dengan cursor (offset-based) + hasMore.
  ///
  /// [cursor] = posisi mulai (0 untuk halaman pertama, atau nextCursor
  /// dari respons sebelumnya).
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
          'inStock': inStock ? 'true' : 'false',
          'hasPrice': hasPrice ? 'true' : 'false',
          if (withImage) 'withImage': 'true',
        },
      );
      final rawItems = data['items'];
      final products = rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(Product.fromApiJson)
              .toList()
          : <Product>[];
      final nextCursor = data['nextCursor']?.toString();
      return ProductPage(
        products: products,
        nextCursor: (nextCursor == null || nextCursor.isEmpty)
            ? null
            : nextCursor,
        hasMore: data['hasMore'] == true,
        total: _asInt(data['total']) ?? products.length,
      );
    } catch (_) {
      return ProductPage.empty;
    }
  }

  /// Fetch produk rekomendasi dari endpoint PWA /api/cart/recommendations.
  /// Algoritma server (lihat route.ts): manual rules → kategori/brand match
  /// dari cart+viewed → personalized dari purchase history → fallback popular.
  ///
  /// Limit di-clamp 1..10 oleh server. excludeIds untuk hindari produk
  /// yang sudah di cart, viewedIds untuk konteks personalisasi (kalau guest).
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
      final rawData = data['data'];
      if (rawData is! List) return const [];
      return rawData
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
      final rawData = data['data'];
      if (rawData is! List) return const [];
      return rawData
          .whereType<Map<String, dynamic>>()
          .map(Product.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetch full product detail by slug — match endpoint PWA
  /// GET /api/products/{slug}. Return Product dengan variantAttrs + variants
  /// terisi (untuk variant selector di Product Detail screen).
  ///
  /// Return null kalau 404 / error — caller fallback ke data product yang
  /// di-passing dari navigation arguments.
  Future<Product?> fetchProductBySlug(String slug) async {
    if (slug.isEmpty) return null;
    try {
      final data = await apiClient.getJson(
        '/api/products/${Uri.encodeComponent(slug)}',
      );
      final raw = data['product'];
      if (raw is! Map<String, dynamic>) return null;
      return Product.fromApiJson(raw);
    } catch (_) {
      return null;
    }
  }

  /// Fetch hero banner aktif dari endpoint PWA /api/banners.
  /// Server sudah filter activeFrom/activeUntil, jadi semua yang return
  /// boleh langsung tampil.
  Future<List<HomeBanner>> fetchBanners() async {
    try {
      final data = await apiClient.getJson('/api/banners');
      final raw = data['banners'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(HomeBanner.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetch list brand aktif dari endpoint PWA /api/brands.
  /// Sorted by position → createdAt → name (match server behavior).
  /// Dipakai di Home "Brand Pilihan" + Products screen brand filter.
  Future<List<PetBrand>> fetchBrands() async {
    try {
      final data = await apiClient.getJson('/api/brands');
      final raw = data['brands'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(PetBrand.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetch list kategori aktif dari endpoint PWA /api/categories.
  /// Tiap kategori ikut bawa imageUrl produk pertama (untuk thumbnail Home).
  Future<List<HomeCategory>> fetchCategories() async {
    try {
      final data = await apiClient.getJson('/api/categories');
      final raw = data['categories'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(HomeCategory.fromApiJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fire-and-forget: catat bahwa user melihat produk ini. Dipanggil saat
  /// Product Detail screen mount. Server akan upsert ke `user_product_views`
  /// (kalau user login) — dipakai untuk personalisasi recommendation.
  /// Gagal silent — tracking adalah analytic, jangan blokir UX.
  Future<void> trackView(String slug) async {
    if (slug.isEmpty) return;
    // Read-only mode: skip view tracking (analytics write) supaya
    // counter produk asli tidak ke-inflate dari Flutter testing.
    if (readOnlyMode.isReadOnly) return;
    try {
      await apiClient.postJson(
        '/api/products/${Uri.encodeComponent(slug)}/view',
        body: const <String, dynamic>{},
      );
    } catch (_) {
      // Silent.
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
      return SearchSuggestionResult.fromJson(data);
    } catch (_) {
      return const SearchSuggestionResult();
    }
  }

  // _filterFallback() dihapus — fallback ke sampleProducts tidak dipakai
  // lagi. Error state ditangani di UI layer (banner + pull-to-refresh).

  /// Fetch voucher product-specific yang valid untuk produk ini.
  /// Match endpoint PWA GET /api/products/{slug}/vouchers.
  /// Beda dari /api/cart/vouchers — ini cuma voucher yang tersedia di product
  /// detail card, sebelum user add ke cart.
  Future<List<Map<String, dynamic>>> fetchProductVouchers(String slug) async {
    if (slug.trim().isEmpty) return const [];
    try {
      final data = await apiClient.getJson(
        '/api/products/${Uri.encodeComponent(slug)}/vouchers',
      );
      final raw = data['vouchers'] ?? data['items'] ?? data['data'];
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetch feed posts yang tag/feature produk ini ("Apa kata user").
  /// Match endpoint PWA GET /api/products/{slug}/feed-posts.
  /// Dipakai di product detail untuk show UGC related.
  Future<List<Map<String, dynamic>>> fetchProductFeedPosts(String slug) async {
    if (slug.trim().isEmpty) return const [];
    try {
      final data = await apiClient.getJson(
        '/api/products/${Uri.encodeComponent(slug)}/feed-posts',
      );
      final raw = data['posts'] ?? data['items'] ?? data['data'];
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }
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

final productService = ProductService();
