import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../utils/read_only_mode.dart';

/// Cart state store — offline-first. Item disimpan ke SharedPreferences supaya
/// survive app restart. Sync ke server (`/api/cart`) belum di-implement —
/// stub `syncToServer()` no-op untuk sekarang.
class CartStore extends ChangeNotifier {
  CartStore._();

  static const _key = 'cart_items_v2';

  final Map<String, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList(growable: false);
  int get count => _items.values.fold(0, (sum, it) => sum + it.quantity);
  int get subtotal => _items.values.fold(0, (sum, it) => sum + it.lineTotal);
  /// Alias `subtotal` — beberapa code (checkout) pakai `total`. Note:
  /// tidak include shipping cost — itu di-add di checkout flow.
  int get total => subtotal;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  /// Alias `count` — beberapa screen pakai totalQuantity, beberapa count.
  int get totalQuantity => count;

  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _items.clear();
      for (final json in list) {
        final item = CartItem.fromJson(json);
        _items[item.key] = item;
      }
      notifyListeners();
    } catch (_) {
      // Disk corrupt / format lama — silent reset.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _items.values.map((it) => it.toJson()).toList();
      await prefs.setString(_key, jsonEncode(list));
    } catch (_) {}
  }

  /// Add product langsung — convenience wrapper sekitar [addItem].
  /// Boleh pass `variant` (full ProductVariant) atau `variantId`/`variantLabel`.
  Future<void> addProduct(
    Product product, {
    int quantity = 1,
    ProductVariant? variant,
    String? variantId,
    String? variantLabel,
    int? overridePrice,
    int? overrideStock,
  }) async {
    final item = CartItem(
      product: product,
      variant: variant,
      variantLabel: variantLabel,
      unitPrice: overridePrice ?? variant?.price ?? product.finalPrice.round(),
      quantity: quantity,
      effectiveStock: overrideStock ?? variant?.stock ?? product.stock,
    );
    await addItem(item);
  }

  /// Add cart line (atau increment qty kalau sudah ada).
  Future<void> addItem(CartItem item) async {
    readOnlyMode.guard('addItem');
    final existing = _items[item.key];
    _items[item.key] = existing == null
        ? item
        : existing.copyWith(quantity: existing.quantity + item.quantity);
    notifyListeners();
    await _persist();
  }

  Future<void> updateQuantity(String key, int quantity) async {
    readOnlyMode.guard('updateQuantity');
    final item = _items[key];
    if (item == null) return;
    if (quantity <= 0) {
      _items.remove(key);
    } else {
      _items[key] = item.copyWith(quantity: quantity);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String key) async {
    readOnlyMode.guard('removeItem');
    if (_items.remove(key) != null) {
      notifyListeners();
      await _persist();
    }
  }

  /// Restore previously-removed item ke posisi semula. Dipakai untuk
  /// undo snackbar di cart screen — user delete by mistake → tap "Batalkan"
  /// → item kembali persis seperti sebelum.
  ///
  /// Kalau `index` di-pass + valid, item di-insert di posisi itu (preserve
  /// urutan visual). Default append ke akhir.
  Future<void> restore(CartItem item, {int? index}) async {
    readOnlyMode.guard('restoreItem');
    if (index != null && index >= 0 && index < _items.length) {
      final entries = _items.entries.toList();
      entries.insert(index, MapEntry(item.key, item));
      _items
        ..clear()
        ..addEntries(entries);
    } else {
      _items[item.key] = item;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    readOnlyMode.guard('clearCart');
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    await _persist();
  }

  /// Sync local cart ke server (`/api/cart`). Stub — TODO real implementation
  /// setelah backend auth integration ready.
  Future<void> syncToServer() async {
    if (kDebugMode) {
      debugPrint('[CartStore.syncToServer] stub — ${_items.length} items');
    }
  }
}

final CartStore cartStore = CartStore._();
