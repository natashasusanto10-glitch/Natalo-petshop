import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Search history store — persist daftar keyword yang user search di
/// products screen. Dipakai untuk:
///
/// 1. Wishlist "Ayo Dilihat Kembali" ranking — kombinasi kata kunci
///    historis vs product title/brand/category buat scoring relevance.
/// 2. (Future) search bar suggestions di home_screen — show recent
///    queries saat user tap search field tanpa ketik apapun.
///
/// Storage: SharedPreferences key `search_history_v1` (versioned).
/// Format: JSON list of strings, sorted newest first.
/// Capacity: max 20 entries — pop oldest saat penuh.
/// Dedup: query yang sama (case-insensitive, trim) di-push ke depan
/// (bukan di-duplicate).
class SearchHistoryStore extends ChangeNotifier {
  SearchHistoryStore._();

  static const _key = 'search_history_v1';
  static const _maxEntries = 20;

  List<String> _entries = const [];
  bool _initialized = false;

  /// Newest-first list of historical queries.
  List<String> get entries => _entries;
  bool get initialized => _initialized;
  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;

  /// Load dari disk. Fire-and-forget di main() atau di first screen usage.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key);
      if (raw != null) {
        _entries = raw;
        notifyListeners();
      }
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
    final filtered = _entries
        .where((e) => e.toLowerCase() != lower)
        .toList(growable: true);

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
    final filtered = _entries
        .where((e) => e.toLowerCase() != lower)
        .toList(growable: false);
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
      await prefs.remove(_key);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _entries);
    } catch (_) {
      // Silent. UI sudah update via notifyListeners — disk fail nanti
      // hilang saat restart, tidak block flow.
    }
  }
}

final SearchHistoryStore searchHistoryStore = SearchHistoryStore._();
