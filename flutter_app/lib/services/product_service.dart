import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/product.dart';

/// Stub product service — hit /api/products endpoints. Saat ini implementasi
/// minimal: list + by-slug + recommendations. Failure → return empty / null,
/// tidak throw (UI seharusnya tetap render skeleton/empty state).
class ProductService {
  ProductService._();

  /// Variant `fetchAll` — return wrapper dengan `products` getter supaya
  /// feed_upload_sheet bisa `result.products`. Accept extra filter args
  /// (inStock, hasPrice, withImage) yang saat ini di-apply client-side.
  Future<ProductFetchResult> fetchProducts({
    String? brand,
    String? category,
    String? query,
    int limit = 30,
    bool inStock = false,
    bool hasPrice = false,
    bool withImage = false,
  }) async {
    var products = await fetchAll(
      brand: brand,
      category: category,
      query: query,
      limit: limit,
    );
    if (inStock) products = products.where((p) => p.stock > 0).toList();
    if (hasPrice) products = products.where((p) => p.price > 0).toList();
    if (withImage) {
      products = products.where((p) => p.imageUrl.isNotEmpty).toList();
    }
    return ProductFetchResult(products: products);
  }

  /// GET /api/products — list dengan optional filter.
  Future<List<Product>> fetchAll({
    String? brand,
    String? category,
    String? query,
    int limit = 30,
  }) async {
    try {
      final uri = ApiConfig.uri('/api/products', {
        if (brand != null) 'brand': brand,
        if (category != null) 'category': category,
        if (query != null) 'q': query,
        'limit': limit,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      final list = body is List
          ? body
          : (body is Map
              ? body['items'] ?? body['data'] ?? body['products']
              : null);
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(Product.fromJson)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[productService.fetchAll] $e');
      return const [];
    }
  }

  Future<Product?> fetchProductBySlug(String slug) async {
    try {
      final uri = ApiConfig.uri('/api/products/$slug');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        final data = body['product'] ?? body['data'] ?? body;
        if (data is Map<String, dynamic>) return Product.fromJson(data);
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[productService.fetchProductBySlug] $e');
      return null;
    }
  }

  /// Recommendation engine — POST viewedIds + excludeIds, return suggestions.
  Future<List<Product>> fetchRecommendations({
    List<String> viewedIds = const [],
    List<String> excludeIds = const [],
    int limit = 6,
  }) async {
    try {
      final uri = ApiConfig.uri('/api/cart/recommendations');
      final res = await http
          .post(
            uri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'viewedIds': viewedIds,
              'excludeIds': excludeIds,
              'limit': limit,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      final list = body is List ? body : (body is Map ? body['data'] : null);
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(Product.fromJson)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[productService.fetchRecommendations] $e');
      return const [];
    }
  }

  /// Fire-and-forget view tracking — populates recommendation engine.
  Future<void> trackView(String slug) async {
    try {
      final uri = ApiConfig.uri('/api/products/$slug/view');
      await http.post(uri).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Silent — non-critical.
    }
  }
}

final ProductService productService = ProductService._();

/// Wrapper hasil fetchProducts — punya `products` field supaya call site
/// bisa `result.products.take(N)`.
class ProductFetchResult {
  final List<Product> products;
  final String? nextCursor;
  const ProductFetchResult({this.products = const [], this.nextCursor});
}
