import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/owner_scope.dart';
import 'account_scope.dart';
import 'member_store.dart';

/// Search history store — persist daftar keyword yang user search di
/// products screen. Dipakai untuk:
///
/// 1. Wishlist "Ayo Dilihat Kembali" ranking — kombinasi kata kunci
///    historis vs product title/brand/category buat scoring relevance.
/// 2. (Future) search bar suggestions di home_screen — show recent
///    queries saat user tap search field tanpa ketik apapun.
///
/// Storage: SharedPreferences key `search_history_v1::<owner>` (owner-scoped
/// per akun/guest supaya riwayat pencarian tidak bocor antar-akun di device
/// yang sama). Legacy key global `search_history_v1` sengaja tidak dibaca.
/// Format: JSON list of strings, sorted newest first.
/// Capacity: max 20 entries — pop oldest saat penuh.
/// Dedup: query yang sama (case-insensitive, trim) di-push ke depan
/// (bukan di-duplicate).
class SearchHistoryStore extends ChangeNotifier {
  SearchHistoryStore._() {
    _ownerTag = OwnerScope.ownerTag(accountOwnerId());
    memberStore.addListener(_onMemberStoreChanged);
  }

  static const _baseKey = 'search_history_v1';
  static const _maxEntries = 20;

  List<String> _entries = const [];
  bool _initialized = false;
  late String _ownerTag;

  /// Newest-first list of historical queries.
  List<String> get entries => _entries;
  bool get initialized => _initialized;
  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;

  String _diskKey(String ownerTag) => '$_baseKey::$ownerTag';

  /// Load dari disk. Fire-and-forget di main() atau di first screen usage.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _loadFromDisk();
  }

  void _onMemberStoreChanged() {
    _syncOwner();
  }

  Future<void> _syncOwner() async {
    final next = OwnerScope.ownerTag(accountOwnerId());
    if (next == _ownerTag) return;
    _ownerTag = next;
    _entries = const []; // synchronous memory isolation
    notifyListeners();
    await _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    final owner = _ownerTag;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (owner != _ownerTag) return;
      final raw = prefs.getStringList(_diskKey(owner));
      if (owner != _ownerTag) return;
      _entries = raw ?? const [];
      notifyListeners();
    } catch (_) {
      // Disk corrupt — silent reset.
    }
  }

  /// Push query baru ke history. Idempotent — kalau query sudah ada,
  /// move ke depan (most recent), tidak duplicate.
  Future<void> push(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length < 2) return; // skip single char

    // Remove existing case-insensitive match (akan di-push ke depan).
    final lower = trimmed.toLowerCase();
    final filtered =
        _entries.where((e) => e.toLowerCase() != lower).toList(growable: true);

    // Insert at top.
    filtered.insert(0, trimmed);

    // Cap at max.
    if (filtered.length > _maxEntries) {
      filtered.removeRange(_maxEntries, filtered.length);
    }

    _entries = filtered;
    notifyListeners();
    await _persist();
  }

  /// Remove specific query (mis. user tap "X" di history chip).
  Future<void> remove(String query) async {
    final lower = query.trim().toLowerCase();
    final filtered =
        _entries.where((e) => e.toLowerCase() != lower).toList(growable: false);
    if (filtered.length == _entries.length) return;
    _entries = filtered;
    notifyListeners();
    await _persist();
  }

  /// Clear all history (settings option).
  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries = const [];
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_diskKey(_ownerTag));
    } catch (_) {}
  }

  Future<void> _persist() async {
    final owner = _ownerTag;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_diskKey(owner), _entries);
    } catch (_) {
      // Silent. UI sudah update via notifyListeners — disk fail nanti
      // hilang saat restart, tidak block flow.
    }
  }

  /// Test seam mirroring the MemberStore listener after overriding
  /// [accountOwnerId].
  @visibleForTesting
  Future<void> debugSyncOwner() => _syncOwner();
}

final SearchHistoryStore searchHistoryStore = SearchHistoryStore._();
