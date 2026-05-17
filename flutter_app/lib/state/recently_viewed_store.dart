import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';

/// Recently viewed products — track 12 produk terakhir yang user buka.
/// Persisted di SharedPreferences supaya survive app restart.
///
/// Pattern: tap product detail → `recentlyViewedStore.add(product)` →
/// Home carousel show 6 terbaru. Bring-back UX, drive repeat sessions.
class RecentlyViewedStore extends ChangeNotifier {
  static const _kKey = 'natalo_recently_viewed_v1';
  static const _maxItems = 12;

  final List<Product> _items = [];
  bool _loaded = false;

  List<Product> get items => List.unmodifiable(_items);
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  Future<void> loadFromDisk() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null || raw.isEmpty) {
        notifyListeners();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _items.clear();
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          try {
            _items.add(Product.fromApiJson(entry));
          } catch (_) {}
        }
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[recently_viewed] load failed: $e');
    }
  }

  /// Tambahkan produk ke head of list. Kalau sudah ada di list,
  /// pindahkan ke depan (most-recent). Max 12 items.
  Future<void> add(Product product) async {
    // Dedup: remove existing entry kalau ada.
    _items.removeWhere((p) => p.id == product.id);
    _items.insert(0, product);
    // Cap to _maxItems.
    if (_items.length > _maxItems) {
      _items.removeRange(_maxItems, _items.length);
    }
    notifyListeners();
    _persistToDisk();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    _persistToDisk();
  }

  Future<void> _persistToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_items.map((p) => p.toJson()).toList());
      await prefs.setString(_kKey, json);
    } catch (_) {}
  }
}

final recentlyViewedStore = RecentlyViewedStore();
