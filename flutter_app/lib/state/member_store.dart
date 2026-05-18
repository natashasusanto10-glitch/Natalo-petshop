import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/member_profile.dart';

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
  List<MemberAddress> _addresses = const [];

  MemberProfile? get profile => _profile;
  String? get sessionToken => _sessionToken;
  bool get isLoggedIn => _profile != null;
  bool get initialized => _initialized;
  List<MemberAddress> get addresses => _addresses;

  /// Update cached addresses list — dipanggil setelah fetchAddresses().
  void setAddresses(List<MemberAddress> addresses) {
    _addresses = addresses;
    notifyListeners();
  }

  /// Sync constructor — fire-and-forget load from disk. Dipanggil di main()
  /// supaya UI tahu state login sebelum first paint.
  void initialize() {
    if (_initialized) return;
    _initialized = true;
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
      notifyListeners();
    } catch (_) {
      // Disk corrupt / format lama — silent reset.
    }
  }

  Future<void> setSession({
    required MemberProfile profile,
    String? token,
  }) async {
    _profile = profile;
    _sessionToken = token;
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
  }

  Future<void> logout() async {
    _profile = null;
    _sessionToken = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileKey);
      await prefs.remove(_tokenKey);
    } catch (_) {}
  }
}

final MemberStore memberStore = MemberStore._();
