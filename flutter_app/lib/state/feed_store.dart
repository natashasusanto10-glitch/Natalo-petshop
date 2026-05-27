import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/feed_post.dart';
import '../services/feed_service.dart';

/// Shared, postId-keyed store untuk semua feed post di app.
///
/// **Single source of truth** untuk interaksi (like/comment count) supaya
/// Feed/Reels, Detail Postingan, Postingan Saya, dan Public Profile selalu
/// sinkron. Sebelum store ini ada, setiap screen punya `_likedCache` /
/// `_posts` local state — like di Feed tidak ke-reflect di Detail, comment
/// add di sheet tidak naikkan count di Feed, dst.
///
/// **Cara pakai:**
///   1. List fetch (feed/profile/my-posts) → `mergeFromServer(posts)`
///   2. Single post fetch (detail / deep link) → `applyPostUpdate(post)`
///   3. Screen render → `feedStore.get(postId)` (atau watch via listener)
///   4. User tap like → `feedStore.toggleLike(postId)` (store handle
///      optimistic + API + reconcile + rollback)
///   5. Comment sheet add/delete success → caller call
///      `feedStore.setCommentCount(postId, newCount)` dengan count
///      dari backend response.
///
/// **Stale-write protection:**
/// Setiap optimistic action set `_lastLocalActionAt[postId] = now`.
/// `mergeFromServer(posts, fetchedAt: ...)` skip interaction fields untuk
/// post yang punya local action AFTER `fetchedAt`. Non-interaction fields
/// (caption, thumbnailUrl, dll) tetap di-apply — itu tidak race-prone.
class FeedStore extends ChangeNotifier {
  FeedStore._();

  final Map<String, FeedPost> _byId = {};
  final Map<String, DateTime> _lastLocalActionAt = {};

  /// Cegah parallel toggle untuk post sama — double-tap protection.
  final Set<String> _likeInFlight = {};

  /// Cegah parallel ensureLoaded untuk post sama (deep link spam).
  final Map<String, Future<FeedPost?>> _ensureInFlight = {};

  // ─── Reads (sync) ───

  FeedPost? get(String postId) => _byId[postId];

  bool has(String postId) => _byId.containsKey(postId);

  /// Bulk read — useful saat screen butuh render list of postIds (list
  /// dari feedPostIds order saat ini).
  List<FeedPost> getMany(Iterable<String> ids) {
    final out = <FeedPost>[];
    for (final id in ids) {
      final p = _byId[id];
      if (p != null) out.add(p);
    }
    return out;
  }

  // ─── Writes (sync) ───

  /// Initial seed — only insert kalau belum ada. TIDAK overwrite existing.
  /// Dipakai saat hydrate offline cache di startup, atau untuk gracefully
  /// seed dari list tanpa risiko stomp optimistic state.
  void seed(Iterable<FeedPost> posts) {
    var changed = false;
    for (final post in posts) {
      if (!_byId.containsKey(post.id)) {
        _byId[post.id] = post;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Merge dari server response — overwrite existing TAPI dengan stale-write
  /// protection: kalau ada local action setelah `fetchedAt`, hanya update
  /// non-interaction fields (caption, thumbnail, status, dll).
  ///
  /// **Penting:** caller HARUS capture `fetchedAt = DateTime.now()` BEFORE
  /// kick off HTTP request — bukan setelahnya. Jika tidak, race kondisi
  /// pas user tap like persis saat list refresh selesai bisa flip count.
  ///
  /// Default `fetchedAt = DateTime.now()` saat call site tidak peduli stale
  /// protection (mis. detail single fetch yang TIDAK race dengan toggle —
  /// pakai [applyPostUpdate] saja).
  void mergeFromServer(
    Iterable<FeedPost> posts, {
    DateTime? fetchedAt,
  }) {
    final cutoff = fetchedAt ?? DateTime.now();
    var changed = false;
    for (final incoming in posts) {
      final existing = _byId[incoming.id];
      if (existing == null) {
        _byId[incoming.id] = incoming;
        changed = true;
        continue;
      }
      final lastAction = _lastLocalActionAt[incoming.id];
      final localIsNewer = lastAction != null && lastAction.isAfter(cutoff);
      if (localIsNewer) {
        // Skip interaction fields — preserve optimistic state.
        _byId[incoming.id] = existing.copyWith(
          // Non-interaction fields safe to refresh from server.
          slug: incoming.slug,
          title: incoming.title,
          description: incoming.description,
          caption: incoming.caption,
          videoUrl: incoming.videoUrl,
          thumbnailUrl: incoming.thumbnailUrl,
          blurhash: incoming.blurhash,
          thumbnailBlurhash: incoming.thumbnailBlurhash,
          durationSec: incoming.durationSec,
          aspectRatio: incoming.aspectRatio,
          videoWidth: incoming.videoWidth,
          videoHeight: incoming.videoHeight,
          kind: incoming.kind,
          author: incoming.author,
          products: incoming.products,
          productsInVideo: incoming.productsInVideo,
          taggedProducts: incoming.taggedProducts,
          viewCount: incoming.viewCount,
          shareCount: incoming.shareCount,
          mediaItems: incoming.mediaItems,
          status: incoming.status,
          rejectionReason: incoming.rejectionReason,
          approvedAt: incoming.approvedAt,
          // SKIP: likeCount, commentCount, isLiked, viewerLiked.
        );
      } else {
        // Server data fresher than any local optimistic action — apply all.
        _byId[incoming.id] = incoming;
      }
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Replace single post entirely (e.g. setelah `getPostDetail` API call
  /// atau setelah edit caption response). Tidak stale-check — caller
  /// sudah punya post yang lebih fresh.
  void applyPostUpdate(FeedPost post) {
    _byId[post.id] = post;
    notifyListeners();
  }

  /// Remove dari store (e.g. setelah delete post).
  void removePost(String postId) {
    if (_byId.remove(postId) != null) {
      _lastLocalActionAt.remove(postId);
      notifyListeners();
    }
  }

  /// Set comment count — dipakai saat user add/delete comment dan caller
  /// dapat count baru dari backend response. Bumps lastLocalActionAt
  /// supaya mergeFromServer subsekuen tidak overwrite count ini dengan
  /// list-fetch snapshot lama.
  void setCommentCount(String postId, int newCount) {
    final p = _byId[postId];
    if (p == null) return;
    _byId[postId] = p.copyWith(commentCount: newCount < 0 ? 0 : newCount);
    _lastLocalActionAt[postId] = DateTime.now();
    notifyListeners();
  }

  /// Manual set like state — escape hatch untuk caller yang punya source
  /// of truth dari luar (e.g. backend push update). Normal flow pakai
  /// [toggleLike] yang handle full pipeline.
  void setLikeState(
    String postId, {
    required bool liked,
    required int likeCount,
  }) {
    final p = _byId[postId];
    if (p == null) return;
    _byId[postId] = p.copyWith(
      isLiked: liked,
      viewerLiked: liked,
      likeCount: likeCount < 0 ? 0 : likeCount,
    );
    _lastLocalActionAt[postId] = DateTime.now();
    notifyListeners();
  }

  // ─── Async actions ───

  /// Toggle like dengan optimistic update + API call + reconcile +
  /// rollback on error. Mutex per-postId cegah double-tap spam bikin
  /// out-of-order request.
  ///
  /// Return final state dari server. Caller boleh ignore return value
  /// kalau cuma butuh trigger animation — store sudah update internal +
  /// notify listeners.
  Future<FeedLikeResult> toggleLike(String postId) async {
    final oldPost = _byId[postId];
    if (oldPost == null) {
      throw StateError('toggleLike: post $postId not in store');
    }
    if (_likeInFlight.contains(postId)) {
      // Already toggling — return current state. Caller bisa abaikan.
      return FeedLikeResult(
        liked: oldPost.viewerLiked || oldPost.isLiked,
        likeCount: oldPost.likeCount,
      );
    }
    _likeInFlight.add(postId);

    final wasLiked = oldPost.viewerLiked || oldPost.isLiked;
    final newLiked = !wasLiked;
    final optimisticCount = newLiked
        ? oldPost.likeCount + 1
        : (oldPost.likeCount - 1).clamp(0, 999999);

    // Optimistic.
    _byId[postId] = oldPost.copyWith(
      isLiked: newLiked,
      viewerLiked: newLiked,
      likeCount: optimisticCount,
    );
    _lastLocalActionAt[postId] = DateTime.now();
    notifyListeners();

    try {
      final result = await feedService.toggleLike(
        postId,
        currentlyLiked: wasLiked,
      );
      // Reconcile dengan source-of-truth dari server.
      final current = _byId[postId];
      if (current != null) {
        _byId[postId] = current.copyWith(
          isLiked: result.liked,
          viewerLiked: result.liked,
          likeCount: result.likeCount,
        );
        _lastLocalActionAt[postId] = DateTime.now();
        notifyListeners();
      }
      return result;
    } catch (e) {
      // Rollback ke state sebelum toggle.
      _byId[postId] = oldPost;
      // Note: jangan reset _lastLocalActionAt — kalau ada concurrent
      // list-fetch yang sudah lewat, tetap ingin protect karena server
      // mungkin udah catat like ke-recorded sebagian. Conservative.
      notifyListeners();
      rethrow;
    } finally {
      _likeInFlight.remove(postId);
    }
  }

  /// Pastikan post terload — useful saat user buka detail via deep link
  /// dan store belum punya post tersebut. Idempotent: parallel call
  /// untuk post yang sama akan share satu in-flight Future.
  ///
  /// **Catatan:** belum ada API single-fetch khusus untuk feed post; saat
  /// ini caller masih pass full FeedPost saat navigate. Method ini
  /// reserved untuk future deep-link support.
  Future<FeedPost?> ensureLoaded(String postId) async {
    final existing = _byId[postId];
    if (existing != null) return existing;
    final inFlight = _ensureInFlight[postId];
    if (inFlight != null) return inFlight;
    // No backend endpoint untuk standalone "GET /api/feed/posts/[id]" yang
    // typed return FeedPost — saat ini caller selalu seed via list. Stub
    // di-leave untuk future implementasi.
    final completer = Completer<FeedPost?>();
    _ensureInFlight[postId] = completer.future;
    try {
      // TODO: implementasi single-fetch saat backend siap.
      completer.complete(null);
      return null;
    } finally {
      _ensureInFlight.remove(postId);
    }
  }

  /// Debug helper — clear semua state (e.g. saat logout).
  void clear() {
    _byId.clear();
    _lastLocalActionAt.clear();
    _likeInFlight.clear();
    _ensureInFlight.clear();
    notifyListeners();
  }

  @visibleForTesting
  int get size => _byId.length;
}

final FeedStore feedStore = FeedStore._();
