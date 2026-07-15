import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/member_profile.dart';
import '../services/api_client.dart';
import '../services/member_service.dart';
import 'cart_store.dart';
import 'feed_comment_session_store.dart';
import 'follow_override_store.dart';

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
      // Fetch profile DULU + addresses + orders parallel. Profile refresh
      // ini critical — login endpoint kadang return user object minimal
      // (id/name/email/phone tanpa profilePhotoUrl/birthDate). Tanpa
      // refresh ini, foto user "hilang" balik ke initial paw icon
      // setelah logout+login. /api/auth/me selalu return full snapshot.
      final results = await Future.wait<dynamic>([
        memberService.fetchProfile(),
        memberService.fetchAddresses(),
        memberService.fetchOrders(),
      ]);
      final freshProfile = results[0] as MemberProfile?;
      _addresses = results[1] as List<MemberAddress>;
      _orders = results[2] as List<OrderSummary>;
      if (freshProfile != null) {
        // Merge: gunakan fresh data dari /api/auth/me sebagai source of
        // truth. Persist ke disk supaya offline reload juga punya foto
        // terbaru. Avoid drop kalau API return null (network glitch).
        _profile = freshProfile;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_profileKey, jsonEncode(freshProfile.toJson()));
        } catch (_) {}
      }
      notifyListeners();
    } on ApiException catch (error) {
      // BUG FIX: session invalid (401/403) — user di JWT tidak ada di DB
      // (mis. admin switch ke DB baru, atau user dihapus, atau token
      // expired). Sebelumnya: cuma swallow error → _profile stay cached
      // → user "logged in" hantu walaupun server udah reject.
      //
      // Sekarang: detect 401/403 → force logout + clear local cache.
      // Network error (statusCode null) atau 5xx tetap di-keep cache
      // supaya UX offline tidak putus.
      if (error.isUnauthorized || error.isForbidden) {
        if (kDebugMode) {
          debugPrint(
            '[memberStore.hydrate] Session invalid (${error.statusCode}) — auto logout',
          );
        }
        await logout();
      }
    } catch (_) {
      // Network glitch / parsing error — keep cache. Screens fetch
      // fresh data sendiri saat dibutuhkan.
    }
  }

  void setProfile(MemberProfile profile) {
    _clearFollowStateForAccountChange(profile.id);
    _profile = profile;
    _initialized = true;
    _initializing = false;
    notifyListeners();
    hydrateFromApi();
  }

  /// Update profile + persist ke disk **tanpa** menyentuh session token.
  /// Dipakai saat user update foto profil / data pribadi dari EditProfile
  /// atau bottom sheet update foto — jangan log out karena setSession()
  /// akan remove token kalau token null.
  Future<void> persistProfileUpdate(MemberProfile profile) async {
    _profile = profile;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
    } catch (_) {
      // Disk write best-effort — in-memory tetap update.
    }
  }

  Future<void> setSession({
    required MemberProfile profile,
    String? token,
  }) async {
    _clearFollowStateForAccountChange(profile.id);
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
    // Merge cart server (device lain) ke local + push balik hasil union.
    // Guard idempotensi di dalam loadFromServer (aman dipanggil tiap
    // setSession, termasuk update profil).
    cartStore.loadFromServer();
  }

  void _clearFollowStateForAccountChange(String nextMemberId) {
    final currentMemberId = _profile?.id;
    if (currentMemberId != null && currentMemberId != nextMemberId) {
      clearFollowOverrides();
      feedCommentSessionStore.clear();
    }
  }

  Future<void> logout() async {
    _profile = null;
    _sessionToken = null;
    _addresses = const [];
    _orders = const [];
    cartStore.resetLoginMergeGuard();
    clearFollowOverrides();
    feedCommentSessionStore.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileKey);
      await prefs.remove(_tokenKey);
    } catch (_) {}
  }
}

final MemberStore memberStore = MemberStore._();
