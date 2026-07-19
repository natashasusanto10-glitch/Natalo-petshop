import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import '../utils/owner_scope.dart';
import 'account_scope.dart';
import 'member_store.dart';

/// Local history produk yang user lihat — dipakai untuk carousel di Home
/// + recommendation engine. Capped 30 item supaya disk usage manageable.
///
/// Owner-scoped: setiap akun (dan guest) punya key disk sendiri, jadi riwayat
/// akun A tidak bocor ke akun B di device yang sama. Legacy key global lama
/// (`recently_viewed_v1`) sengaja tidak dibaca lagi — data itu tidak punya
/// pemilik yang jelas.
class RecentlyViewedStore extends ChangeNotifier {
  RecentlyViewedStore._() {
    _ownerTag = OwnerScope.ownerTag(accountOwnerId());
    memberStore.addListener(_onMemberStoreChanged);
  }

  static const _baseKey = 'recently_viewed_v1';
  static const _maxItems = 30;

  final List<Product> _items = [];
  late String _ownerTag;

  List<Product> get items => List.unmodifiable(_items);
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  String _diskKey(String ownerTag) => '$_baseKey::$ownerTag';

  void _onMemberStoreChanged() {
    // Fire-and-forget; disk reload guards itself against owner changing again
    // mid-flight.
    _syncOwner();
  }

  Future<void> _syncOwner() async {
    final next = OwnerScope.ownerTag(accountOwnerId());
    if (next == _ownerTag) return;
    // Synchronous memory isolation the instant the owner changes so account B
    // never observes account A's list, even for one frame.
    _ownerTag = next;
    _items.clear();
    notifyListeners();
    await loadFromDisk();
  }

  Future<void> loadFromDisk() async {
    final owner = _ownerTag;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (owner != _ownerTag) return; // owner switched during await → discard
      final raw = prefs.getString(_diskKey(owner));
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (owner != _ownerTag) return; // re-check before mutating shared state
      _items
        ..clear()
        ..addAll(list.map((j) => Product.fromJson(j)));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist() async {
    final owner = _ownerTag;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _items.map((p) => p.toJson()).toList();
      await prefs.setString(_diskKey(owner), jsonEncode(list));
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

  /// Test seam: re-evaluate the current owner (after overriding
  /// [accountOwnerId]) exactly as the MemberStore listener would.
  @visibleForTesting
  Future<void> debugSyncOwner() => _syncOwner();
}

final RecentlyViewedStore recentlyViewedStore = RecentlyViewedStore._();
