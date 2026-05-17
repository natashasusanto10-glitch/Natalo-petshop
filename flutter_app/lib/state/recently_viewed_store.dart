import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';

/// Local history produk yang user lihat — dipakai untuk carousel di Home
/// + recommendation engine. Capped 30 item supaya disk usage manageable.
class RecentlyViewedStore extends ChangeNotifier {
  RecentlyViewedStore._();

  static const _key = 'recently_viewed_v1';
  static const _maxItems = 30;

  final List<Product> _items = [];

  List<Product> get items => List.unmodifiable(_items);
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _items
        ..clear()
        ..addAll(list.map((j) => Product.fromJson(j)));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _items.map((p) => p.toJson()).toList();
      await prefs.setString(_key, jsonEncode(list));
    } catch (_) {}
  }

  Future<void> add(Product product) async {
    // Promote to head, dedupe by id, cap to max.
    _items.removeWhere((p) => p.id == product.id);
    _items.insert(0, product);
    if (_items.length > _maxItems) {
      _items.removeRange(_maxItems, _items.length);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    await _persist();
  }
}

final RecentlyViewedStore recentlyViewedStore = RecentlyViewedStore._();
