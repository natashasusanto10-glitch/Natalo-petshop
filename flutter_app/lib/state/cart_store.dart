import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../services/app_analytics.dart';
import '../services/cart_service.dart';
import '../services/home_widget_service.dart';

class CartStore extends ChangeNotifier {
  static const _kCartCacheKey = 'natalo_cart_v1';
  static const _kSavedCacheKey = 'natalo_cart_saved_v1';

  final List<CartItem> _items = [];
  // Save for later — items dipindahkan dari cart aktif ke saved supaya
  // tidak hilang & tidak dihitung total checkout. User bisa pindahkan
  // kembali ke cart kapan saja.
  final List<CartItem> _saved = [];
  bool _diskLoaded = false;

  List<CartItem> get items => List.unmodifiable(_items);
  List<CartItem> get savedItems => List.unmodifiable(_saved);
  bool get diskLoaded => _diskLoaded;

  int get totalQuantity {
    return _items.fold(0, (sum, item) => sum + item.quantity);
  }

  double get subtotal {
    // item.lineTotal sudah pakai effectivePrice (varian price kalau ada).
    return _items.fold(0, (sum, item) => sum + item.lineTotal);
  }

  double get voucherDiscount {
    if (subtotal < 150000) return 0;
    return subtotal * 0.08;
  }

  double get total => (subtotal - voucherDiscount).clamp(0, double.infinity);

  void addProduct(
    Product product, {
    int quantity = 1,
    ProductVariant? variant,
  }) {
    // Composite key supaya kalau user pilih 2 varian dari produk yang sama,
    // masing-masing jadi line item terpisah (tidak menumpuk).
    final cartKey =
        variant != null ? '${product.id}::${variant.id}' : product.id;
    final index = _items.indexWhere((item) => item.key == cartKey);
    final maxStock = variant?.stock ?? product.stock;
    if (index == -1) {
      _items.add(CartItem(
        product: product,
        quantity: quantity.clamp(1, maxStock),
        variant: variant,
      ));
    } else {
      final current = _items[index];
      final nextQuantity = (current.quantity + quantity).clamp(1, maxStock);
      _items[index] = current.copyWith(quantity: nextQuantity);
    }
    notifyListeners();
    _persistToDisk();
    // Analytics — track add_to_cart event untuk funnel analysis.
    // Gracefully no-op kalau Firebase belum setup.
    AppAnalytics.logAddToCart(
      productId: product.id,
      productName: product.title,
      price: variant?.price ?? product.price,
      quantity: quantity,
    );
  }

  void updateQuantity(String key, int quantity) {
    final index = _items.indexWhere((item) => item.key == key);
    if (index == -1) return;

    if (quantity <= 0) {
      _items.removeAt(index);
    } else {
      final item = _items[index];
      final nextQuantity = quantity.clamp(1, item.effectiveStock);
      _items[index] = item.copyWith(quantity: nextQuantity);
    }
    notifyListeners();
    _persistToDisk();
  }

  void remove(String key) {
    _items.removeWhere((item) => item.key == key);
    notifyListeners();
    _persistToDisk();
  }

  void restore(CartItem item, {int? index}) {
    if (_items.any((current) => current.key == item.key)) return;
    final insertAt = (index ?? _items.length).clamp(0, _items.length);
    _items.insert(insertAt, item);
    notifyListeners();
    _persistToDisk();
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _persistToDisk();
  }

  /// Pindahkan item dari cart aktif → saved list. Item tidak dihitung
  /// untuk total checkout, tapi tetap di-persist supaya user bisa
  /// kembalikan nanti.
  void moveToSaved(String key) {
    final index = _items.indexWhere((item) => item.key == key);
    if (index == -1) return;
    final item = _items.removeAt(index);
    // Dedupe — kalau sudah ada di saved, skip insert.
    if (!_saved.any((s) => s.key == item.key)) {
      _saved.insert(0, item);
    }
    notifyListeners();
    _persistToDisk();
  }

  /// Pindahkan dari saved → cart aktif. Quantity dijaga, atau di-clamp
  /// ke stock kalau berubah.
  void moveToCart(String key) {
    final index = _saved.indexWhere((item) => item.key == key);
    if (index == -1) return;
    final item = _saved.removeAt(index);
    // Dedupe — kalau sudah ada di cart, increment qty.
    final existingIndex = _items.indexWhere((c) => c.key == item.key);
    if (existingIndex != -1) {
      final current = _items[existingIndex];
      _items[existingIndex] = current.copyWith(
        quantity:
            (current.quantity + item.quantity).clamp(1, current.effectiveStock),
      );
    } else {
      _items.add(item);
    }
    notifyListeners();
    _persistToDisk();
  }

  void removeSaved(String key) {
    _saved.removeWhere((item) => item.key == key);
    notifyListeners();
    _persistToDisk();
  }

  Future<void> syncToServer() {
    return cartService.replaceCart(_items);
  }

  Future<void> loadFromServer() async {
    final serverItems = await cartService.fetchCart();
    _items
      ..clear()
      ..addAll(serverItems);
    notifyListeners();
    _persistToDisk();
  }

  /// Load cart dari disk (SharedPreferences) — dipanggil sekali di app start.
  /// Cart yang sudah ditambah user (guest atau pre-login) survive app restart.
  /// Match keuntungan offline-first Flutter native atas PWA yang re-fetch
  /// localStorage hanya saat halaman buka.
  Future<void> loadFromDisk() async {
    if (_diskLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCartCacheKey);
      if (raw == null || raw.isEmpty) {
        _diskLoaded = true;
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _diskLoaded = true;
        return;
      }
      _items.clear();
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          try {
            _items.add(CartItem.fromJson(entry));
          } catch (_) {
            // Skip item yang corrupt — lanjut yang lain.
          }
        }
      }
      // Load saved-for-later list — separate cache key.
      final savedRaw = prefs.getString(_kSavedCacheKey);
      if (savedRaw != null && savedRaw.isNotEmpty) {
        try {
          final savedDecoded = jsonDecode(savedRaw);
          if (savedDecoded is List) {
            _saved.clear();
            for (final entry in savedDecoded) {
              if (entry is Map<String, dynamic>) {
                try {
                  _saved.add(CartItem.fromJson(entry));
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }
      _diskLoaded = true;
      notifyListeners();
    } catch (_) {
      _diskLoaded = true;
    }
  }

  /// Persist cart ke disk — dipanggil setelah setiap mutation.
  /// Fire-and-forget supaya UI tidak ke-block.
  Future<void> _persistToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_items.map((i) => i.toJson()).toList());
      await prefs.setString(_kCartCacheKey, json);
      // Saved list — persist juga supaya survive restart.
      final savedJson =
          jsonEncode(_saved.map((i) => i.toJson()).toList());
      await prefs.setString(_kSavedCacheKey, savedJson);
    } catch (_) {
      // Silent — disk write failure tidak boleh blokir cart UX.
    }
    // Update Android home widget — fire and forget, silent fail kalau
    // widget tidak di-pin. iOS no-op via Platform.isAndroid guard.
    AppHomeWidgetService.updateCartCount(totalQuantity);
  }
}

final cartStore = CartStore();
