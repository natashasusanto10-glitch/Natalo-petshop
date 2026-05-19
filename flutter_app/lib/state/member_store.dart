import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/member_profile.dart';
import '../services/member_service.dart';

/// Member auth + profile store. Setelah login success, cache profile +
/// session token ke disk. Saat app start, load + verify dengan server di
/// background.
class MemberStore extends ChangeNotifier {
  MemberStore._();

  static const _profileKey = 'member_profile_v1';
  static const _tokenKey = 'member_session_token';

  MemberProfile? _profile;
  String? _sessionToken;
  bool _initialized = false;
  bool _initializing = false;
  List<MemberAddress> _addresses = const [];
  List<OrderSummary> _orders = const [];

  MemberProfile? get profile => _profile;
  String? get sessionToken => _sessionToken;
  bool get isLoggedIn => _profile != null;
  bool get initialized => _initialized;
  bool get initializing => _initializing;
  List<MemberAddress> get addresses => _addresses;
  List<OrderSummary> get orders => _orders;

  /// Update cached addresses list — dipanggil setelah fetchAddresses().
  void setAddresses(List<MemberAddress> addresses) {
    _addresses = addresses;
    notifyListeners();
  }

  void setOrders(List<OrderSummary> orders) {
    _orders = orders;
    notifyListeners();
  }

  /// Sync constructor — fire-and-forget load from disk. Dipanggil di main()
  /// supaya UI tahu state login sebelum first paint.
  void initialize() {
    if (_initialized || _initializing) return;
    _initializing = true;
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _sessionToken = prefs.getString(_tokenKey);
      final raw = prefs.getString(_profileKey);
      if (raw != null) {
        _profile = MemberProfile.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
      if (_profile != null) {
        hydrateFromApi();
      }
    } catch (_) {
      // Disk corrupt / format lama — silent reset.
    } finally {
      _initialized = true;
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> hydrateFromApi() async {
    if (_profile == null) return;
    try {
      final results = await Future.wait<dynamic>([
        memberService.fetchAddresses(),
        memberService.fetchOrders(),
      ]);
      _addresses = results[0] as List<MemberAddress>;
      _orders = results[1] as List<OrderSummary>;
      notifyListeners();
    } catch (_) {
      // Screens still fetch their own fresh data; this cache is optional.
    }
  }

  void setProfile(MemberProfile profile) {
    _profile = profile;
    _initialized = true;
    _initializing = false;
    notifyListeners();
    hydrateFromApi();
  }

  Future<void> setSession({
    required MemberProfile profile,
    String? token,
  }) async {
    _profile = profile;
    _sessionToken = token;
    _initialized = true;
    _initializing = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
      if (token != null) {
        await prefs.setString(_tokenKey, token);
      } else {
        await prefs.remove(_tokenKey);
      }
    } catch (_) {}
    hydrateFromApi();
  }

  Future<void> logout() async {
    _profile = null;
    _sessionToken = null;
    _addresses = const [];
    _orders = const [];
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileKey);
      await prefs.remove(_tokenKey);
    } catch (_) {}
  }
}

final MemberStore memberStore = MemberStore._();
