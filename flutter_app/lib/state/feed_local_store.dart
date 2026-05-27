import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_post.dart';

/// Local persistence untuk feed module — dipakai untuk:
///
/// 1. **Liked posts cache (#7)** — set post IDs yang user pernah like di
///    device ini. Saat feed di-fetch, merge backend `viewerLiked` dengan
///    local cache supaya animation langsung correct + survive offline.
///    Backend tetap source of truth — local cache hanya fast-path.
///
/// 2. **Offline feed cache (#11)** — last 10 posts ter-fetch di-cache
///    sebagai JSON. Kalau next-launch offline / network fail, app show
///    stale data daripada empty state. Auto-replaced saat fetch sukses.
///
/// 3. **Viewed posts session-scoped** — Set<String> in-memory untuk
///    debounce trackView per-session (avoid double-count saat user
///    swipe back-and-forth ke post sama).
///
/// Storage: SharedPreferences keyed:
///   - `feed_liked_v1` — JSON list of post IDs (string set)
///   - `feed_offline_cache_v1` — JSON list of FeedPost.toJson
class FeedLocalStore extends ChangeNotifier {
  FeedLocalStore._();

  static const _likedKey = 'feed_liked_v1';
  // v2: schema FeedPost berubah (rename media→mediaItems, tambah status,
  // rejectionReason, approvedAt, recentLikers). Bump key supaya client
  // lama drop cache v1 dan re-fetch dari backend. Tanpa bump, FeedPost.
  // fromJson tetap parse cache lama tapi field baru kosong → grid degraded.
  static const _cacheKey = 'feed_offline_cache_v2';
  // Old key tetap di-reference untuk one-time cleanup (lihat initialize).
  static const _legacyCacheKey = 'feed_offline_cache_v1';
  static const _maxLikedEntries = 500;
  static const _maxCacheEntries = 10;

  // ── Liked posts ──
  final Set<String> _likedIds = <String>{};
  bool _initialized = false;
  bool get initialized => _initialized;

  // ── Offline cache ──
  List<FeedPost> _cachedPosts = const [];
  List<FeedPost> get cachedPosts => _cachedPosts;

  // ── In-memory viewed (session-scoped, no persistence) ──
  final Set<String> _viewedThisSession = <String>{};

  /// Initialize — call di main() atau saat feed first open.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load liked.
      final rawLiked = prefs.getString(_likedKey);
      if (rawLiked != null) {
        final decoded = jsonDecode(rawLiked);
        if (decoded is List) {
          _likedIds.addAll(
            decoded.whereType<String>(),
          );
        }
      }

      // One-time cleanup: hapus key cache lama (v1) — schema migrate ke v2.
      // Idempotent: kalau key tidak ada, NoOp. Fire-and-forget, gagal pun OK.
      // ignore: unawaited_futures
      prefs.remove(_legacyCacheKey);

      // Load offline cache.
      final rawCache = prefs.getString(_cacheKey);
      if (rawCache != null) {
        final decoded = jsonDecode(rawCache);
        if (decoded is List) {
          _cachedPosts = decoded
              .whereType<Map<String, dynamic>>()
              .map((json) {
                try {
                  return FeedPost.fromJson(json);
                } catch (_) {
                  return null;
                }
              })
              .whereType<FeedPost>()
              .toList(growable: false);
        }
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[feedLocalStore.init] $e');
    }
  }

  // ──────────── Liked posts ────────────

  bool isLiked(String postId) => _likedIds.contains(postId);

  /// Merge backend viewerLiked dengan local cache. Backend wins —
  /// kalau backend say viewerLiked=true, add to cache. Kalau false,
  /// remove. Dipanggil saat fetch feed/post.
  void mergeBackendLiked(List<FeedPost> posts) {
    var changed = false;
    for (final post in posts) {
      final wasLocallyLiked = _likedIds.contains(post.id);
      final isBackendLiked = post.viewerLiked || post.isLiked;
      if (isBackendLiked && !wasLocallyLiked) {
        _likedIds.add(post.id);
        changed = true;
      } else if (!isBackendLiked && wasLocallyLiked) {
        _likedIds.remove(post.id);
        changed = true;
      }
    }
    if (changed) {
      _capLikedEntries();
      _persistLiked();
      notifyListeners();
    }
  }

  /// User toggle like — update local cache langsung (optimistic).
  /// Caller still hits backend untuk source-of-truth count.
  Future<void> setLiked(String postId, bool liked) async {
    final wasLiked = _likedIds.contains(postId);
    if (liked == wasLiked) return;
    if (liked) {
      _likedIds.add(postId);
    } else {
      _likedIds.remove(postId);
    }
    _capLikedEntries();
    notifyListeners();
    await _persistLiked();
  }

  void _capLikedEntries() {
    if (_likedIds.length <= _maxLikedEntries) return;
    // Drop oldest by removing first N — Set order is insertion-order in
    // Dart, jadi yang dimasukin pertama akan kebuang. Acceptable
    // approximation untuk "least recently liked".
    final toRemove = _likedIds.length - _maxLikedEntries;
    final iter = _likedIds.iterator;
    final dropping = <String>[];
    for (var i = 0; i < toRemove && iter.moveNext(); i++) {
      dropping.add(iter.current);
    }
    _likedIds.removeAll(dropping);
  }

  Future<void> _persistLiked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_likedKey, jsonEncode(_likedIds.toList()));
    } catch (e) {
      if (kDebugMode) debugPrint('[feedLocalStore.persistLiked] $e');
    }
  }

  // ──────────── Offline cache ────────────

  bool get hasCachedPosts => _cachedPosts.isNotEmpty;

  /// Persist last successful fetch — keep top N posts as JSON.
  Future<void> cachePosts(List<FeedPost> posts) async {
    if (posts.isEmpty) return;
    final capped = posts.take(_maxCacheEntries).toList(growable: false);
    _cachedPosts = capped;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      // Pakai canonical FeedPost.toJson — single source of truth supaya
      // shape tidak drift dengan fromJson. Sebelumnya ada _postToJson
      // helper yang manual dan ketinggalan field (mediaItems, status,
      // recentLikers, dll) → cache lama load jadi partial.
      final list = capped.map((p) => p.toJson()).toList();
      await prefs.setString(_cacheKey, jsonEncode(list));
    } catch (e) {
      if (kDebugMode) debugPrint('[feedLocalStore.cachePosts] $e');
    }
  }

  /// Clear cache (e.g. saat logout atau settings "clear cache").
  Future<void> clearCache() async {
    _cachedPosts = const [];
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      // Juga clear legacy key supaya storage clean.
      await prefs.remove(_legacyCacheKey);
    } catch (_) {}
  }

  // ──────────── Viewed (session-scoped) ────────────

  /// Has user viewed this post in current session? Dipakai untuk
  /// dedupe trackView call (avoid double-count saat swipe back).
  bool hasViewedThisSession(String postId) =>
      _viewedThisSession.contains(postId);

  void markViewedThisSession(String postId) {
    _viewedThisSession.add(postId);
  }

  /// Reset session-scoped data (e.g. on logout). Liked + cache tetap.
  void resetSession() {
    _viewedThisSession.clear();
  }
}

final FeedLocalStore feedLocalStore = FeedLocalStore._();
