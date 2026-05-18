import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../services/cart_service.dart';
import '../utils/read_only_mode.dart';
import 'member_store.dart';

/// Cart state store — offline-first dengan optional remote sync.
///
/// Local state persisted ke SharedPreferences (survive app restart).
/// Saat user login + online, mutation cart auto-sync ke server via debounced
/// `PUT /api/cart` (lihat [_scheduleRemoteSync]) supaya cart ke-share antar
/// device dan persist saat user pindah platform (Flutter ⇄ PWA web).
///
/// Debounce 800ms supaya tidak spam server saat user rapid-fire qty change.
/// Local mutation langsung notifyListeners + persist disk — server sync
/// fire-and-forget background, gagal silent (cart tetap consistent di lokal).
class CartStore extends ChangeNotifier {
  CartStore._();

  static const _key = 'cart_items_v2';
  static const Duration _remoteSyncDebounce = Duration(milliseconds: 800);

  final Map<String, CartItem> _items = {};

  Timer? _remoteSyncTimer;

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

  /// Pull cart dari server lalu replace local state. Dipanggil saat user
  /// login (memberStore.setSession callback) supaya cart dari device lain
  /// muncul. Local state di-overwrite oleh server (server = source of truth
  /// untuk multi-device sync).
  Future<void> loadFromServer() async {
    if (!memberStore.isLoggedIn) return;
    try {
      final remoteItems = await cartService.fetchCart();
      _items.clear();
      for (final item in remoteItems) {
        _items[item.key] = item;
      }
      notifyListeners();
      await _persist();
      if (kDebugMode) {
        debugPrint('[CartStore.loadFromServer] OK — ${remoteItems.length} items');
      }
    } catch (e) {
      // Server unreachable atau auth fail → tetap pakai local state.
      if (kDebugMode) {
        debugPrint('[CartStore.loadFromServer] failed: $e');
      }
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
    _scheduleRemoteSync();
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
    _scheduleRemoteSync();
  }

  Future<void> remove(String key) async {
    readOnlyMode.guard('removeItem');
    if (_items.remove(key) != null) {
      notifyListeners();
      await _persist();
      _scheduleRemoteSync();
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
    _scheduleRemoteSync();
  }

  Future<void> clear() async {
    readOnlyMode.guard('clearCart');
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    await _persist();
    _scheduleRemoteSync();
  }

  /// Sync local cart ke server lewat `PUT /api/cart`.
  ///
  /// Hanya jalan kalau user login. Gagal silent — local state tetap source
  /// of truth, retry otomatis di mutation berikutnya. Tidak block UI: caller
  /// bisa fire-and-forget.
  ///
  /// Untuk batch mutation rapid (mis. user tap +/- qty cepat), pakai
  /// [_scheduleRemoteSync] yang debounce 800ms instead of langsung call ini.
  Future<void> syncToServer() async {
    if (!memberStore.isLoggedIn) {
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] skip — not logged in');
      }
      return;
    }
    try {
      await cartService.replaceCart(_items.values.toList(growable: false));
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] OK — ${_items.length} items');
      }
    } catch (e) {
      // Network / 500 — silent. Local state tetap valid, retry next mutation.
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] failed: $e');
      }
    }
  }

  /// Schedule debounced remote sync — dipanggil setelah tiap mutation.
  /// Reset timer kalau ada mutation baru dalam 800ms, supaya rapid qty
  /// changes (user tap +/- 5x cepat) cuma trigger 1 server call di akhir.
  void _scheduleRemoteSync() {
    _remoteSyncTimer?.cancel();
    _remoteSyncTimer = Timer(_remoteSyncDebounce, syncToServer);
  }

  @override
  void dispose() {
    _remoteSyncTimer?.cancel();
    super.dispose();
  }
}

final CartStore cartStore = CartStore._();
