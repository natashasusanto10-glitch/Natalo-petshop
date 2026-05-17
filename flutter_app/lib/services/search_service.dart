import 'api_client.dart';
import '../utils/read_only_mode.dart';

/// Result item dari /api/search (full text + faceted search).
class SearchHit {
  final String id;
  final String slug;
  final String title;
  final String? imageUrl;
  final num price;
  final num? originalPrice;
  final String? brand;
  final String? category;
  final double rating;
  final int reviewCount;
  final int stock;

  const SearchHit({
    required this.id,
    required this.slug,
    required this.title,
    this.imageUrl,
    required this.price,
    this.originalPrice,
    this.brand,
    this.category,
    this.rating = 0,
    this.reviewCount = 0,
    this.stock = 0,
  });

  factory SearchHit.fromJson(Map<String, dynamic> json) {
    return SearchHit(
      id: (json['id'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      imageUrl: json['imageUrl']?.toString(),
      price: _asNum(json['price']),
      originalPrice: json['originalPrice'] is num
          ? json['originalPrice'] as num
          : null,
      brand: json['brand']?.toString(),
      category: json['category']?.toString(),
      rating: _asNum(json['rating']).toDouble(),
      reviewCount: _asInt(json['reviewCount']),
      stock: _asInt(json['stock']),
    );
  }
}

class SearchResult {
  final List<SearchHit> hits;
  final int total;
  final Map<String, dynamic> facets;
  final String? nextCursor;

  const SearchResult({
    required this.hits,
    required this.total,
    this.facets = const {},
    this.nextCursor,
  });
}

class SearchService {
  /// Full search dengan facet filter. Match endpoint PWA GET /api/search.
  /// Query params: q, category, brand, minPrice, maxPrice, sort, cursor.
  Future<SearchResult> search({
    required String query,
    String? category,
    String? brand,
    num? minPrice,
    num? maxPrice,
    String? sort,
    String? cursor,
  }) async {
    try {
      final data = await apiClient.getJson('/api/search', query: {
        'q': query,
        if (category != null) 'category': category,
        if (brand != null) 'brand': brand,
        if (minPrice != null) 'minPrice': '$minPrice',
        if (maxPrice != null) 'maxPrice': '$maxPrice',
        if (sort != null) 'sort': sort,
        if (cursor != null) 'cursor': cursor,
      });
      final raw = data['items'] ?? data['hits'];
      final hits = raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(SearchHit.fromJson)
              .toList()
          : <SearchHit>[];
      return SearchResult(
        hits: hits,
        total: _asInt(data['total']),
        facets:
            data['facets'] is Map<String, dynamic> ? data['facets'] as Map<String, dynamic> : {},
        nextCursor: data['nextCursor']?.toString(),
      );
    } catch (_) {
      return const SearchResult(hits: [], total: 0);
    }
  }

  /// Search facets (brand/category/price ranges) untuk filter UI.
  /// Match GET /api/search/facets?q=...
  Future<Map<String, dynamic>> facets({String? query}) async {
    try {
      final data = await apiClient.getJson('/api/search/facets', query: {
        if (query != null) 'q': query,
      });
      return data;
    } catch (_) {
      return const {};
    }
  }

  /// Popular search terms (top queries) — match GET /api/search/popular.
  Future<List<String>> popular() async {
    try {
      final data = await apiClient.getJson('/api/search/popular');
      final raw = data['terms'] ?? data['items'] ?? data['data'];
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Trending search terms — match GET /api/search/trending.
  Future<List<String>> trending() async {
    try {
      final data = await apiClient.getJson('/api/search/trending');
      final raw = data['terms'] ?? data['items'] ?? data['data'];
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Log search query untuk popular/trending aggregation di server.
  /// Match POST /api/search/log. Fire-and-forget.
  Future<void> log(String query) async {
    if (query.trim().isEmpty) return;
    if (readOnlyMode.isReadOnly) return; // skip di read-only
    try {
      await apiClient.postJson(
        '/api/search/log',
        body: {'query': query.trim()},
      );
    } catch (_) {
      // Silent — logging adalah analytics, jangan blokir UX.
    }
  }
}

num _asNum(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

final searchService = SearchService();
