import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../services/cart_service.dart';
import 'dart:math' as math;
import '../utils/read_only_mode.dart';
import 'member_store.dart';

int effectiveCartVariantPrice(Product product, ProductVariant variant) {
  final discount = product.discountPrice;
  if (product.hasFlashSaleCountdown &&
      discount != null &&
      product.price > 0 &&
      discount > 0 &&
      discount < product.price &&
      variant.price > 0) {
    final discounted = (variant.price * (discount / product.price)).round();
    if (discounted > 0 && discounted < variant.price) return discounted;
  }
  return variant.price;
}

String? cartVariantOptionLabel(Product product, ProductVariant variant) {
  final labels = <String>[];
  for (final attr in product.variantAttrs) {
    for (final option in attr.options) {
      if (variant.optionIds.contains(option.id)) {
        final value = option.value.trim();
        if (value.isNotEmpty) labels.add(value);
        break;
      }
    }
  }
  if (labels.isEmpty) return null;
  return labels.join(', ');
}

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
class CartStore extends ChangeNotifier with WidgetsBindingObserver {
  CartStore._({CartService? service, bool Function()? isLoggedIn})
      : _service = service ?? cartService,
        _isLoggedIn = isLoggedIn ?? _defaultIsLoggedIn;

  /// Constructor test-only — inject fake CartService + seam isLoggedIn
  /// supaya logika sync/merge dapat diuji tanpa jaringan / global state.
  @visibleForTesting
  factory CartStore.forTest({
    CartService? service,
    bool Function()? isLoggedIn,
  }) =>
      CartStore._(service: service, isLoggedIn: isLoggedIn);

  static bool _defaultIsLoggedIn() => memberStore.isLoggedIn;

  final CartService _service;
  final bool Function() _isLoggedIn;

  static const _key = 'cart_items_v2';
  static const Duration _remoteSyncDebounce = Duration(milliseconds: 800);
  static const _pendingKey = 'cart_pending_sync_v1';

  final Map<String, CartItem> _items = {};

  Timer? _remoteSyncTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _observerRegistered = false;

  bool _mergedThisSession = false;

  @visibleForTesting
  bool get mergedThisSession => _mergedThisSession;

  /// Ada perubahan lokal yang belum dikonfirmasi sampai ke server.
  bool _pendingSync = false;

  @visibleForTesting
  bool get pendingSync => _pendingSync;

  @visibleForTesting
  bool get hasPendingRetry => _retryTimer?.isActive ?? false;

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
      final pending = prefs.getBool(_pendingKey) ?? false;
      final raw = prefs.getString(_key);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _items.clear();
        for (final json in list) {
          final item = CartItem.fromJson(json);
          _items[item.key] = item;
        }
        notifyListeners();
      }
      if (pending) {
        // Sesi sebelumnya mati sebelum sync terkonfirmasi. syncToServer
        // self-guard kalau belum login (flag tetap tersimpan untuk nanti).
        _pendingSync = true;
        unawaited(syncToServer());
      }
    } catch (_) {
      // Disk corrupt / format lama — silent reset.
    }
  }

  /// Merge cart server ke local state saat login (union + jumlah qty).
  /// Barang yang ditambahkan sebagai guest TIDAK hilang; item server dari
  /// device lain ikut masuk. Hanya merge SEKALI per sesi login (guard
  /// [_mergedThisSession]) karena setSession juga dipanggil saat update
  /// profil. Hasil union di-push balik ke server supaya konsisten.
  Future<void> loadFromServer() async {
    if (!_isLoggedIn()) return;
    if (_mergedThisSession) return;
    try {
      final remoteItems = await _service.fetchCart();
      _mergeServerCart(remoteItems);
      _mergedThisSession = true;
      notifyListeners();
      await _persist();
      _markDirtyAndSync();
      if (kDebugMode) {
        debugPrint(
            '[CartStore.loadFromServer] merged ${remoteItems.length} server items');
      }
    } catch (e) {
      // Server unreachable / auth fail → tetap pakai local state.
      if (kDebugMode) {
        debugPrint('[CartStore.loadFromServer] failed: $e');
      }
    }
  }

  // Merge ini UNION murni: TIDAK punya semantik hapus/tombstone.
  // Konsekuensi: kalau ada penghapusan item lokal yang BELUM sempat ter-sync
  // ke server (mis. user offline), lalu setSession memicu loadFromServer,
  // item yang masih ada di server bisa "hidup lagi" (resurrected) ke lokal.
  // Ini edge sempit — B1 (retry) biasanya sudah menuntaskan penghapusan
  // sebelum event login, dan union memang perilaku yang diinginkan untuk
  // multi-device. Didokumentasikan supaya pembaca berikutnya tidak salah
  // mengira ini bug.
  void _mergeServerCart(List<CartItem> remoteItems) {
    for (final remote in remoteItems) {
      final existing = _items[remote.key];
      if (existing == null) {
        _items[remote.key] = remote;
      } else {
        final combined = existing.quantity + remote.quantity;
        final stock = remote.effectiveStock;
        final qty = stock > 0 ? combined.clamp(1, stock) : combined;
        // Metadata dari server (lebih fresh), qty gabungan.
        _items[remote.key] = remote.copyWith(quantity: qty);
      }
    }
  }

  /// Reset guard merge — dipanggil dari MemberStore.logout() supaya login
  /// berikutnya (bisa akun berbeda) melakukan merge lagi.
  void resetLoginMergeGuard() {
    _mergedThisSession = false;
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
  Future<bool> addProduct(
    Product product, {
    int quantity = 1,
    ProductVariant? variant,
    String? variantId,
    String? variantLabel,
    int? overridePrice,
    int? overrideStock,
  }) async {
    final resolvedVariant = variant ??
        (variantId != null && variantId.trim().isNotEmpty
            ? ProductVariant(
                id: variantId.trim(),
                price: overridePrice ?? product.finalPrice.round(),
                stock: overrideStock ?? product.stock,
                weightGram: product.weightGram,
              )
            : null);
    if (product.hasVariants && resolvedVariant == null) {
      if (kDebugMode) {
        debugPrint(
          '[CartStore.addProduct] blocked variant product without variant: '
          '${product.id} ${product.title}',
        );
      }
      return false;
    }
    final unitPrice = overridePrice ??
        (resolvedVariant == null
            ? product.finalPrice.round()
            : effectiveCartVariantPrice(product, resolvedVariant));
    final item = CartItem(
      product: product,
      variant: resolvedVariant,
      variantLabel: variantLabel,
      unitPrice: unitPrice,
      quantity: quantity,
      effectiveStock: overrideStock ?? resolvedVariant?.stock ?? product.stock,
    );
    await addItem(item);
    return true;
  }

  /// Qty item tertentu di cart sekarang (0 kalau tidak ada). Dipakai
  /// product detail untuk pre-check stok sebelum add (toast "Stok cuma N").
  int quantityFor(String key) => _items[key]?.quantity ?? 0;

  /// Add cart line (atau increment qty kalau sudah ada).
  ///
  /// Return `true` kalau qty ke-CLAMP ke stok (user minta lebih dari stok).
  /// Caller bisa pakai ini untuk toast "Stok tinggal N". Clamp di sini =
  /// single source of truth: semua entry point (+Keranjang, Beli Sekarang,
  /// reorder, feed quick-add) otomatis ter-batasi tanpa ubah signature.
  /// Stok <= 0 dianggap TIDAK diketahui (data belum fresh) → tidak di-clamp;
  /// server /api/cart/validate tetap backstop otoritatif.
  Future<bool> addItem(CartItem item) async {
    final existing = _items[item.key];
    final desired = (existing?.quantity ?? 0) + item.quantity;
    final stock = item.effectiveStock;
    final capped = stock > 0 ? desired.clamp(1, stock) : desired;
    final clamped = capped < desired;
    final base = existing ?? item;
    _items[item.key] = base.copyWith(quantity: capped);
    notifyListeners();
    await _persist();
    _markDirtyAndSync();
    return clamped;
  }

  /// Return `true` kalau qty diminta di-CLAMP ke stok.
  Future<bool> updateQuantity(String key, int quantity) async {
    final item = _items[key];
    if (item == null) return false;
    if (quantity <= 0) {
      _items.remove(key);
      notifyListeners();
      await _persist();
      _markDirtyAndSync();
      return false;
    }
    final stock = item.effectiveStock;
    final capped = stock > 0 ? quantity.clamp(1, stock) : quantity;
    final clamped = capped < quantity;
    _items[key] = item.copyWith(quantity: capped);
    notifyListeners();
    await _persist();
    _markDirtyAndSync();
    return clamped;
  }

  Future<void> remove(String key) async {
    if (_items.remove(key) != null) {
      notifyListeners();
      await _persist();
      _markDirtyAndSync();
    }
  }

  /// Restore previously-removed item ke posisi semula. Dipakai untuk
  /// undo snackbar di cart screen — user delete by mistake → tap "Batalkan"
  /// → item kembali persis seperti sebelum.
  ///
  /// Kalau `index` di-pass + valid, item di-insert di posisi itu (preserve
  /// urutan visual). Default append ke akhir.
  Future<void> restore(CartItem item, {int? index}) async {
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
    _markDirtyAndSync();
  }

  Future<void> clear() async {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    await _persist();
    _markDirtyAndSync();
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
    if (!_isLoggedIn()) {
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] skip — not logged in');
      }
      return;
    }
    try {
      await _service.replaceCart(_items.values.toList(growable: false));
      _pendingSync = false;
      _retryAttempt = 0;
      _retryTimer?.cancel();
      await _persistPendingFlag();
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] OK — ${_items.length} items');
      }
    } on ReadOnlyModeException catch (e) {
      // Read-only bukan kegagalan sementara — jangan retry loop. Flag tetap
      // true supaya pemicu lifecycle/mutation berikutnya coba lagi.
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] read-only, skip retry: $e');
      }
    } catch (e) {
      // Network / 5xx — flag tetap true, jadwalkan retry backoff.
      if (kDebugMode) {
        debugPrint('[CartStore.syncToServer] failed, will retry: $e');
      }
      _scheduleRetry();
    }
  }

  Future<void> _persistPendingFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pendingKey, _pendingSync);
    } catch (_) {}
  }

  /// Set flag dirty + persist, lalu debounce sync (menggantikan panggilan
  /// langsung ke [_scheduleRemoteSync] dari mutation).
  void _markDirtyAndSync() {
    _pendingSync = true;
    _persistPendingFlag();
    _scheduleRemoteSync();
  }

  /// Retry backoff: 5s → 10s → 20s → 40s → 60s (cap 60s), reset saat sukses.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delaySeconds = math.min(60, 5 * math.pow(2, _retryAttempt)).toInt();
    _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: delaySeconds), syncToServer);
  }

  /// Schedule debounced remote sync — dipanggil setelah tiap mutation.
  /// Reset timer kalau ada mutation baru dalam 800ms, supaya rapid qty
  /// changes (user tap +/- 5x cepat) cuma trigger 1 server call di akhir.
  void _scheduleRemoteSync() {
    _remoteSyncTimer?.cancel();
    _remoteSyncTimer = Timer(_remoteSyncDebounce, syncToServer);
  }

  /// Daftarkan observer lifecycle — dipanggil sekali di main(). CartStore
  /// singleton global (bukan widget), jadi ia mengurus observer-nya sendiri.
  void init() {
    if (_observerRegistered) return;
    WidgetsBinding.instance.addObserver(this);
    _observerRegistered = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingSync) {
      unawaited(syncToServer());
    }
  }

  @override
  void dispose() {
    _remoteSyncTimer?.cancel();
    _retryTimer?.cancel();
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    super.dispose();
  }
}

final CartStore cartStore = CartStore._();
