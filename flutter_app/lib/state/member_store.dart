import 'package:flutter/foundation.dart';

import '../models/member_profile.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/member_service.dart';

/// MemberStore — single in-memory cache untuk profile + collections member.
///
/// **Lifecycle**:
/// 1. App start → `initialize()` → restore session cookie → `authService.me()`
///    → kalau success: `setProfile(profile)` + `hydrateFromApi()` populate
///    addresses/vouchers/orders cache
/// 2. Login screen → `setProfile()` + `hydrateFromApi()` after auth
/// 3. Logout → clear semua state
///
/// Cache di sini bersifat **read-only mirror** — screens yang butuh data
/// terkini tetap fetch langsung via `memberService.fetch*()` (mis. orders
/// screen pakai FutureBuilder + memberService.fetchOrders supaya pull-to-
/// refresh works). Store cache dipakai untuk:
/// - Checkout initial paint addresses
/// - Account screen badge counter
class MemberStore extends ChangeNotifier {
  MemberProfile? _profile;
  bool _initialized = false;
  bool _initializing = false;

  // Empty defaults — di-fill via hydrateFromApi() setelah login. Sebelumnya
  // hardcoded 2-3 sample untuk dev demo, sekarang pure API-driven supaya
  // sinkron dengan Capacitor database (single source of truth).
  final List<MemberAddress> _addresses = [];
  final List<MemberVoucher> _vouchers = [];
  final List<OrderSummary> _orders = [];

  MemberProfile? get profile => _profile;
  bool get isLoggedIn => _profile != null;
  bool get initialized => _initialized;
  bool get initializing => _initializing;
  List<MemberAddress> get addresses => List.unmodifiable(_addresses);
  List<MemberVoucher> get vouchers => List.unmodifiable(_vouchers);
  List<OrderSummary> get orders => List.unmodifiable(_orders);

  int get unpaidOrders =>
      _orders.where((order) => order.status == 'PENDING').length;
  int get processingOrders {
    return _orders.where((order) {
      return order.status == 'PAID' || order.status == 'PROCESSING';
    }).length;
  }

  int get shippedOrders =>
      _orders.where((order) => order.status == 'SHIPPED').length;
  int get deliveredOrders =>
      _orders.where((order) => order.status == 'DELIVERED').length;

  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    notifyListeners();
    // Wire 401 handler — kalau server reject session di tengah usage app,
    // auto-clear profile lokal + notify supaya UI react (mis. AccountPage
    // jadi guest view, route auto-redirect ke login di next interaction).
    apiClient.onUnauthorized = _handleUnauthorized;
    try {
      await apiClient.restoreSession();
      final profile = await authService.me();
      _profile = profile;
      // Profile restored dari session → hydrate cache lookup di background
      // (fire-and-forget). Screens yang butuh data fresh akan re-fetch via
      // memberService langsung (FutureBuilder pattern).
      hydrateFromApi();
    } catch (_) {
      await authService.logoutLocal();
      _profile = null;
    } finally {
      _initialized = true;
      _initializing = false;
      notifyListeners();
    }
  }

  /// Populate addresses/vouchers/orders cache dari API. Fire-and-forget.
  /// Aman dipanggil multiple kali — last write wins, tidak ada race.
  ///
  /// Dipanggil:
  /// - Setelah `initialize()` ketika session restored
  /// - Setelah login sukses di login_screen (via `setProfile()`)
  Future<void> hydrateFromApi() async {
    if (_profile == null) return;
    try {
      final results = await Future.wait<dynamic>([
        memberService.fetchAddresses(),
        memberService.fetchVouchers(),
        memberService.fetchOrders(),
      ]);
      _addresses
        ..clear()
        ..addAll(results[0] as List<MemberAddress>);
      _vouchers
        ..clear()
        ..addAll(results[1] as List<MemberVoucher>);
      _orders
        ..clear()
        ..addAll(results[2] as List<OrderSummary>);
      notifyListeners();
    } catch (_) {
      // Silent — screens punya own fetch + error handling. Cache cuma
      // optional supaya pre-populated saat user navigate antar screen.
    }
  }

  /// Called by api_client saat dapat 401 response. Sudah di-clear session
  /// cookie di api_client side; sini cuma reset state in-memory.
  void _handleUnauthorized() {
    if (_profile == null) return; // already logged out, no-op
    _profile = null;
    _addresses.clear();
    _vouchers.clear();
    _orders.clear();
    notifyListeners();
  }

  void setProfile(MemberProfile profile) {
    _profile = profile;
    _initialized = true;
    notifyListeners();
    // Populate cache setelah login — fire-and-forget supaya UI tidak block.
    hydrateFromApi();
  }

  Future<void> logout() async {
    await authService.logout();
    _profile = null;
    _addresses.clear();
    _vouchers.clear();
    _orders.clear();
    _initialized = true;
    notifyListeners();
  }
}

final memberStore = MemberStore();
