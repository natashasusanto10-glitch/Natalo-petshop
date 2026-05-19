import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local block list — match Google Play UGC policy syarat "user can
/// block other users".
///
/// **Strategi**: simpan blocked user IDs di SharedPreferences (local
/// device only, tidak sync ke server). UI Feed/Comment/Review filter
/// out konten dari user yang ada di list ini sebelum render.
///
/// Kenapa local-only: simple, no backend dependency, dan dari sisi
/// Google Play policy: "user has ability to block" = tercapai. Kalau
/// nanti perlu sync cross-device, tambah `POST /api/moderation/blocks`
/// di backend dan call dari sini.
///
/// **Trade-off block by name vs by ID**:
/// - FeedPost punya `author.id` → block by ID (akurat)
/// - ProductReview belum punya `userId` field → block by `userName`
///   (less akurat, dua user beda dengan nama sama akan ter-block dua-
///   duanya). Workaround sementara sampai backend kirim userId untuk
///   review.
class BlockService extends ChangeNotifier {
  BlockService._();

  static const _prefsKey = 'natalo.moderation.blocked_v1';
  static const _maxEntries = 500;

  Set<String> _blockedIds = <String>{};
  Set<String> _blockedNames = <String>{};
  bool _loaded = false;

  Set<String> get blockedIds => Set.unmodifiable(_blockedIds);
  Set<String> get blockedNames => Set.unmodifiable(_blockedNames);
  bool get isLoaded => _loaded;
  int get count => _blockedIds.length + _blockedNames.length;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        _loaded = true;
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final ids = decoded['ids'];
        final names = decoded['names'];
        if (ids is List) {
          _blockedIds = ids.whereType<String>().toSet();
        }
        if (names is List) {
          _blockedNames = names.whereType<String>().toSet();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[blockService.load] $e');
      // Corrupt → reset, jangan crash app.
      _blockedIds = <String>{};
      _blockedNames = <String>{};
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  bool isUserBlocked({String? userId, String? userName}) {
    if (userId != null && _blockedIds.contains(userId)) return true;
    if (userName != null && _blockedNames.contains(userName.toLowerCase())) {
      return true;
    }
    return false;
  }

  Future<void> blockUser({String? userId, String? userName}) async {
    if (!_loaded) await load();
    var changed = false;
    if (userId != null && userId.isNotEmpty) {
      if (_blockedIds.add(userId)) changed = true;
    }
    if (userName != null && userName.trim().isNotEmpty) {
      if (_blockedNames.add(userName.trim().toLowerCase())) changed = true;
    }
    if (!changed) return;
    // Cap supaya pref blob tidak unbounded growth.
    if (_blockedIds.length > _maxEntries) {
      _blockedIds = _blockedIds.skip(_blockedIds.length - _maxEntries).toSet();
    }
    if (_blockedNames.length > _maxEntries) {
      _blockedNames =
          _blockedNames.skip(_blockedNames.length - _maxEntries).toSet();
    }
    await _persist();
    notifyListeners();
  }

  Future<void> unblockUser({String? userId, String? userName}) async {
    if (!_loaded) await load();
    var changed = false;
    if (userId != null && _blockedIds.remove(userId)) changed = true;
    if (userName != null &&
        _blockedNames.remove(userName.trim().toLowerCase())) {
      changed = true;
    }
    if (!changed) return;
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    if (_blockedIds.isEmpty && _blockedNames.isEmpty) return;
    _blockedIds.clear();
    _blockedNames.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        'ids': _blockedIds.toList(),
        'names': _blockedNames.toList(),
      });
      await prefs.setString(_prefsKey, encoded);
    } catch (e) {
      if (kDebugMode) debugPrint('[blockService._persist] $e');
    }
  }
}

final BlockService blockService = BlockService._();
