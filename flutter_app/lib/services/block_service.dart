import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/account_scope.dart';
import '../state/member_store.dart';
import '../utils/owner_scope.dart';

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
  BlockService._() {
    _ownerTag = OwnerScope.ownerTag(accountOwnerId());
    memberStore.addListener(_onMemberStoreChanged);
  }

  static const _baseKey = 'natalo.moderation.blocked_v1';
  static const _maxEntries = 500;

  Set<String> _blockedIds = <String>{};
  Set<String> _blockedNames = <String>{};
  bool _loaded = false;
  late String _ownerTag;

  Set<String> get blockedIds => Set.unmodifiable(_blockedIds);
  Set<String> get blockedNames => Set.unmodifiable(_blockedNames);
  bool get isLoaded => _loaded;
  int get count => _blockedIds.length + _blockedNames.length;

  String _diskKey(String ownerTag) => '$_baseKey::$ownerTag';

  Future<void> load() async {
    if (_loaded) return;
    await _loadForOwner();
  }

  void _onMemberStoreChanged() {
    _syncOwner();
  }

  Future<void> _syncOwner() async {
    final next = OwnerScope.ownerTag(accountOwnerId());
    if (next == _ownerTag) return;
    _ownerTag = next;
    // Synchronous isolation: block list is per-account, drop it immediately.
    _blockedIds = <String>{};
    _blockedNames = <String>{};
    notifyListeners();
    await _loadForOwner();
  }

  Future<void> _loadForOwner() async {
    final owner = _ownerTag;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (owner != _ownerTag) return;
      final raw = prefs.getString(_diskKey(owner));
      var ids = <String>{};
      var names = <String>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final rawIds = decoded['ids'];
          final rawNames = decoded['names'];
          if (rawIds is List) ids = rawIds.whereType<String>().toSet();
          if (rawNames is List) names = rawNames.whereType<String>().toSet();
        }
      }
      if (owner != _ownerTag) return;
      _blockedIds = ids;
      _blockedNames = names;
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
    final owner = _ownerTag;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        'ids': _blockedIds.toList(),
        'names': _blockedNames.toList(),
      });
      await prefs.setString(_diskKey(owner), encoded);
    } catch (e) {
      if (kDebugMode) debugPrint('[blockService._persist] $e');
    }
  }

  /// Test seam mirroring the MemberStore listener after overriding
  /// [accountOwnerId].
  @visibleForTesting
  Future<void> debugSyncOwner() => _syncOwner();
}

final BlockService blockService = BlockService._();
