import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../services/favorite_service.dart';
import '../services/product_service.dart';
import 'member_store.dart';

class FavoriteStore extends ChangeNotifier {
  final Set<String> _ids = {};
  bool _loaded = false;
  bool _loading = false;

  bool get loaded => _loaded;
  bool get loading => _loading;
  Set<String> get ids => Set.unmodifiable(_ids);
  int get count => _ids.length;

  bool isFavorite(String productId) => _ids.contains(productId);

  Future<void> ensureLoaded() async {
    if (_loaded || _loading || !memberStore.isLoggedIn) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (!memberStore.isLoggedIn) {
      clear();
      return;
    }

    _loading = true;
    notifyListeners();
    try {
      final ids = await favoriteService.fetchFavoriteIds();
      _ids
        ..clear()
        ..addAll(ids);
      _loaded = true;
    } catch (e) {
      // Catch + log instead of bubble up — sebelumnya unhandled
      // exception saat parse response bikin _loaded stuck false
      // tanpa user tahu kenapa wishlist gagal sync. Sekarang error
      // tertangkap, _loaded tetap false sampai next successful refresh.
      if (kDebugMode) {
        debugPrint('[favoriteStore.refresh] $e');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> toggle(Product product) async {
    if (!memberStore.isLoggedIn) {
      throw const FavoriteAuthRequiredException();
    }

    final wasFavorite = _ids.contains(product.id);
    if (wasFavorite) {
      _ids.remove(product.id);
    } else {
      _ids.add(product.id);
    }
    notifyListeners();

    try {
      if (wasFavorite) {
        await favoriteService.removeFavorite(product.id);
      } else {
        await favoriteService.addFavorite(product.id);
      }
      _loaded = true;
      return !wasFavorite;
    } catch (error) {
      if (wasFavorite) {
        _ids.add(product.id);
      } else {
        _ids.remove(product.id);
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<List<Product>> fetchFavoriteProducts() async {
    await ensureLoaded();
    if (_ids.isEmpty) return [];

    final result = await productService.fetchProducts(limit: 240);
    return result.products
        .where((product) => _ids.contains(product.id))
        .toList();
  }

  void clear() {
    _ids.clear();
    _loaded = false;
    _loading = false;
    notifyListeners();
  }
}

class FavoriteAuthRequiredException implements Exception {
  const FavoriteAuthRequiredException();

  @override
  String toString() => 'Login member diperlukan untuk memakai wishlist.';
}

final favoriteStore = FavoriteStore();
