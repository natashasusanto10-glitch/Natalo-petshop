import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/feed_post.dart';
import '../services/feed_service.dart';
import 'member_store.dart';

typedef FeedSavedSetter = Future<bool> Function(
  String postId, {
  required bool saved,
});

typedef FeedLikeToggler = Future<FeedLikeResult> Function(
  String postId, {
  required bool currentlyLiked,
});

/// A like/save request completed after the authenticated viewer changed.
///
/// Callers must ignore this completion. Its payload belongs to the previous
/// account and must not update local persistence or show an error to the new
/// viewer.
class FeedViewerChangedException implements Exception {
  const FeedViewerChangedException();

  @override
  String toString() => 'Feed viewer changed while request was in flight';
}

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
  FeedStore._({FeedSavedSetter? savedSetter, FeedLikeToggler? likeToggler})
      : _setSaved = savedSetter ?? feedService.setSaved,
        _toggleLike = likeToggler ?? feedService.toggleLike,
        _viewerGeneration = memberStore.viewerGeneration,
        _observesMemberStore = true {
    memberStore.addListener(_onMemberStoreChanged);
  }

  @visibleForTesting
  FeedStore.forTesting({
    required FeedSavedSetter savedSetter,
    FeedLikeToggler? likeToggler,
    int viewerGeneration = 0,
  })  : _setSaved = savedSetter,
        _toggleLike = likeToggler ?? feedService.toggleLike,
        _viewerGeneration = viewerGeneration,
        _observesMemberStore = false;

  final FeedSavedSetter _setSaved;
  final FeedLikeToggler _toggleLike;
  final bool _observesMemberStore;
  int _viewerGeneration;
  DateTime _viewerChangedAt = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, FeedPost> _byId = {};
  final Map<String, DateTime> _lastLocalActionAt = {};
  final Map<String, DateTime> _lastViewerActionAt = {};
  final Map<String, DateTime> _removedAt = {};

  /// Cegah parallel REQUEST untuk post sama — hanya satu request like di
  /// jaringan per post. Tap tambahan dicatat sebagai intent, bukan dibuang.
  final Map<String, int> _likeInFlight = {};

  /// Intent liked terakhir per post (lihat [toggleLike]).
  final Map<String, bool> _likeDesired = {};
  final Map<String, FeedPost> _likeBaselines = {};

  /// Save uses idempotent desired-state endpoints, but keeps the same
  /// latest-intent-wins behavior as likes for rapid repeated taps.
  final Map<String, int> _saveInFlight = {};
  final Map<String, bool> _saveDesired = {};

  /// Cegah parallel ensureLoaded untuk post sama (deep link spam).
  final Map<String, Future<FeedPost?>> _ensureInFlight = {};

  // ─── Reads (sync) ───

  FeedPost? get(String postId) => _byId[postId];

  bool has(String postId) => _byId.containsKey(postId);

  bool wasRemoved(String postId) => _removedAt.containsKey(postId);

  int get viewerGeneration => _viewerGeneration;

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
      if (_removedAt.containsKey(post.id)) continue;
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
    // Equality is intentionally treated as stale. Some platforms expose a
    // coarse wall-clock resolution, so a request started immediately before
    // an account switch can share the exact timestamp of the switch.
    final responseBelongsToCurrentViewer = cutoff.isAfter(_viewerChangedAt);
    var changed = false;
    for (final rawIncoming in posts) {
      final incoming = responseBelongsToCurrentViewer
          ? rawIncoming
          : _withoutViewerState(rawIncoming);
      final removedAt = _removedAt[incoming.id];
      if (removedAt != null && removedAt.isAfter(cutoff)) {
        continue;
      }
      _removedAt.remove(incoming.id);
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
          // SKIP shareCount juga: share yang selesai setelah request list
          // dimulai tidak boleh ditimpa snapshot server yang lebih lama.
          mediaItems: incoming.mediaItems,
          status: incoming.status,
          rejectionReason: incoming.rejectionReason,
          approvedAt: incoming.approvedAt,
          // SKIP: likeCount, commentCount, isLiked, viewerLiked, recentLikers.
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
    _removedAt.remove(post.id);
    _byId[post.id] = post;
    notifyListeners();
  }

  /// Remove dari store (e.g. setelah delete post).
  void removePost(String postId) {
    if (_byId.remove(postId) != null) {
      _removedAt[postId] = DateTime.now();
      _lastLocalActionAt.remove(postId);
      _lastViewerActionAt.remove(postId);
      _likeDesired.remove(postId);
      _likeBaselines.remove(postId);
      _saveDesired.remove(postId);
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

  /// Optimistic/reconciled share count untuk seluruh layar feed.
  ///
  /// Share sebelumnya hanya dinaikkan di State widget. Saat PageView
  /// rebuild atau user swipe balik, model lama menimpa angka itu menjadi
  /// 0/1. Menaruhnya di store membuat Feed, Postingan, dan Profile membaca
  /// sumber yang sama serta mendapat stale-write protection.
  void setShareCount(String postId, int newCount) {
    final p = _byId[postId];
    if (p == null) return;
    final normalized = newCount < 0 ? 0 : newCount;
    if (p.shareCount == normalized) return;
    _byId[postId] = p.copyWith(shareCount: normalized);
    _lastLocalActionAt[postId] = DateTime.now();
    notifyListeners();
  }

  int incrementShareCount(String postId) {
    final current = _byId[postId]?.shareCount ?? 0;
    final next = current + 1;
    setShareCount(postId, next);
    return next;
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
      recentLikers: _reconcileCurrentUserLiker(p.recentLikers, liked),
    );
    _markViewerAction(postId);
    notifyListeners();
  }

  /// Apply a known saved state and protect it from older list responses.
  void setSavedState(String postId, {required bool saved}) {
    final post = _byId[postId];
    if (post == null || post.viewerSaved == saved) return;
    _byId[postId] = post.copyWith(viewerSaved: saved);
    _markViewerAction(postId);
    notifyListeners();
  }

  // ─── Async actions ───

  /// Toggle like — UI flip optimistis INSTAN di setiap tap, jaringan
  /// menyusul dengan model "intent terakhir menang":
  ///
  /// - Tap saat tidak ada request → flip optimistis + kirim request.
  /// - Tap saat request in-flight → flip optimistis + catat intent;
  ///   TIDAK dibuang (dulu di-drop → unlike butuh ditekan berkali-kali
  ///   di jaringan lambat). Chain aktif kirim follow-up toggle sampai
  ///   state server == intent terakhir.
  /// - Error → rollback ke state server terakhir yang terkonfirmasi.
  ///
  /// Return state sesuai intent tap ini (optimistis kalau coalesced) —
  /// caller boleh ignore; store sudah notify listeners.
  Future<FeedLikeResult> toggleLike(String postId) async {
    final actionGeneration = _viewerGeneration;
    final oldPost = _byId[postId];
    if (oldPost == null) {
      // Defensive: post not in store (e.g. caller lupa seed, atau post
      // sudah ke-remove via concurrent action). Fallback: panggil API
      // langsung dengan currentlyLiked=false (safer default — server
      // toggle berdasar DB state, bukan trust client param). Hasil tidak
      // di-cache karena no anchor post; caller bertanggung jawab handle.
      try {
        final result = await _toggleLike(postId, currentlyLiked: false);
        _ensureCurrentViewer(actionGeneration);
        return result;
      } catch (e) {
        rethrow;
      }
    }

    final wasLiked = oldPost.viewerLiked || oldPost.isLiked;
    final newLiked = !wasLiked;
    final optimisticCount = newLiked
        ? oldPost.likeCount + 1
        : (oldPost.likeCount - 1).clamp(0, 999999);

    // Optimistic SELALU — tiap tap langsung terasa (rasa IG), termasuk
    // saat request sebelumnya masih jalan.
    _byId[postId] = oldPost.copyWith(
      isLiked: newLiked,
      viewerLiked: newLiked,
      likeCount: optimisticCount,
      recentLikers: _reconcileCurrentUserLiker(oldPost.recentLikers, newLiked),
    );
    _likeBaselines.putIfAbsent(postId, () => oldPost);
    _markViewerAction(postId);
    _likeDesired[postId] = newLiked;
    notifyListeners();

    if (_likeInFlight[postId] == actionGeneration) {
      // Chain aktif yang akan menyamakan server dengan intent terbaru.
      return FeedLikeResult(liked: newLiked, likeCount: optimisticCount);
    }
    _likeInFlight[postId] = actionGeneration;

    // State liked terakhir yang TERKONFIRMASI server. Sebelum request
    // pertama sukses, itu adalah state sebelum tap ini.
    var serverLiked = wasLiked;
    FeedLikeResult? lastResult;

    try {
      while (true) {
        _ensureCurrentViewer(actionGeneration);
        final desired = _likeDesired[postId];
        if (desired == null || desired == serverLiked) break;
        final result = await _toggleLike(
          postId,
          currentlyLiked: serverLiked,
        );
        _ensureCurrentViewer(actionGeneration);
        serverLiked = result.liked;
        lastResult = result;
      }

      _likeDesired.remove(postId);
      // Reconcile dengan source-of-truth server (kalau ada request yang
      // benar-benar terkirim; kalau intent balik ke state awal sebelum
      // request pertama, tidak ada yang perlu di-reconcile).
      final current = _byId[postId];
      if (lastResult != null && current != null) {
        _byId[postId] = current.copyWith(
          isLiked: lastResult.liked,
          viewerLiked: lastResult.liked,
          likeCount: lastResult.likeCount,
          recentLikers: lastResult.recentLikers.isNotEmpty
              ? lastResult.recentLikers
              : _reconcileCurrentUserLiker(
                  current.recentLikers,
                  lastResult.liked,
                ),
        );
        _markViewerAction(postId);
        notifyListeners();
      }
      return lastResult ??
          FeedLikeResult(
            liked: serverLiked,
            likeCount: current?.likeCount ?? optimisticCount,
          );
    } catch (e) {
      if (actionGeneration != _viewerGeneration) rethrow;
      // Rollback ke state server terakhir yang terkonfirmasi (bukan buta
      // ke oldPost — sebagian chain mungkin sudah tercatat di server).
      _likeDesired.remove(postId);
      final current = _byId[postId];
      if (current != null) {
        _byId[postId] = lastResult != null
            ? current.copyWith(
                isLiked: lastResult.liked,
                viewerLiked: lastResult.liked,
                likeCount: lastResult.likeCount,
                recentLikers: _reconcileCurrentUserLiker(
                  current.recentLikers,
                  lastResult.liked,
                ),
              )
            : oldPost;
      }
      // Note: jangan reset _lastLocalActionAt — kalau ada concurrent
      // list-fetch yang sudah lewat, tetap ingin protect karena server
      // mungkin udah catat like ke-recorded sebagian. Conservative.
      notifyListeners();
      rethrow;
    } finally {
      if (_likeInFlight[postId] == actionGeneration) {
        _likeInFlight.remove(postId);
        _likeBaselines.remove(postId);
      }
    }
  }

  /// Toggle saved state optimistically and converge the server to the latest
  /// desired state. Additional taps during a request update intent instead of
  /// starting parallel requests or being dropped.
  Future<bool> toggleSaved(String postId) async {
    final actionGeneration = _viewerGeneration;
    final oldPost = _byId[postId];
    if (oldPost == null) {
      final result = await _setSaved(postId, saved: true);
      _ensureCurrentViewer(actionGeneration);
      return result;
    }

    final wasSaved = oldPost.viewerSaved;
    final desiredSaved = !wasSaved;
    _byId[postId] = oldPost.copyWith(viewerSaved: desiredSaved);
    _markViewerAction(postId);
    _saveDesired[postId] = desiredSaved;
    notifyListeners();

    if (_saveInFlight[postId] == actionGeneration) return desiredSaved;
    _saveInFlight[postId] = actionGeneration;

    var serverSaved = wasSaved;
    try {
      while (true) {
        _ensureCurrentViewer(actionGeneration);
        final desired = _saveDesired[postId];
        if (desired == null || desired == serverSaved) break;
        serverSaved = await _setSaved(postId, saved: desired);
        _ensureCurrentViewer(actionGeneration);
        // A successful response may still reject the requested state. Treat
        // that response as authoritative instead of retrying forever.
        if (serverSaved != desired) break;
      }

      _saveDesired.remove(postId);
      final current = _byId[postId];
      if (current != null && current.viewerSaved != serverSaved) {
        _byId[postId] = current.copyWith(viewerSaved: serverSaved);
        _markViewerAction(postId);
        notifyListeners();
      }
      return serverSaved;
    } catch (_) {
      if (actionGeneration != _viewerGeneration) rethrow;
      _saveDesired.remove(postId);
      final current = _byId[postId];
      if (current != null) {
        _byId[postId] = current.copyWith(viewerSaved: serverSaved);
        notifyListeners();
      }
      rethrow;
    } finally {
      if (_saveInFlight[postId] == actionGeneration) {
        _saveInFlight.remove(postId);
      }
    }
  }

  void _markViewerAction(String postId) {
    final now = DateTime.now();
    _lastLocalActionAt[postId] = now;
    _lastViewerActionAt[postId] = now;
  }

  void _ensureCurrentViewer(int generation) {
    if (generation != _viewerGeneration) {
      throw const FeedViewerChangedException();
    }
  }

  void _onMemberStoreChanged() {
    rebaseForViewer(memberStore.viewerGeneration);
  }

  /// Invalidates viewer-owned state without discarding public post data.
  ///
  /// Generation checks also make completions from the previous viewer inert.
  /// In-flight optimistic likes restore their pre-request public count until a
  /// fresh server snapshot arrives for the new account.
  @visibleForTesting
  void rebaseForViewer(int generation) {
    if (generation == _viewerGeneration) return;
    _viewerGeneration = generation;
    _viewerChangedAt = DateTime.now();

    for (final entry in _lastViewerActionAt.entries) {
      if (_lastLocalActionAt[entry.key] == entry.value) {
        _lastLocalActionAt.remove(entry.key);
      }
    }
    _lastViewerActionAt.clear();

    final baselines = Map<String, FeedPost>.from(_likeBaselines);
    _likeDesired.clear();
    _likeBaselines.clear();
    _likeInFlight.clear();
    _saveDesired.clear();
    _saveInFlight.clear();

    for (final entry in _byId.entries.toList(growable: false)) {
      final post = entry.value;
      final baseline = baselines[entry.key];
      _byId[entry.key] = post.copyWith(
        author: _copyAuthorWithFollowing(post.author, false),
        likeCount: baseline?.likeCount ?? post.likeCount,
        recentLikers: baseline?.recentLikers ?? post.recentLikers,
        isLiked: false,
        viewerLiked: false,
        viewerSaved: false,
      );
    }
    notifyListeners();
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
    _lastViewerActionAt.clear();
    _removedAt.clear();
    _likeInFlight.clear();
    _likeDesired.clear();
    _likeBaselines.clear();
    _saveInFlight.clear();
    _saveDesired.clear();
    _ensureInFlight.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_observesMemberStore) {
      memberStore.removeListener(_onMemberStoreChanged);
    }
    super.dispose();
  }

  @visibleForTesting
  int get size => _byId.length;
}

final FeedStore feedStore = FeedStore._();

FeedAuthor _copyAuthorWithFollowing(FeedAuthor author, bool isFollowing) {
  if (author.isFollowing == isFollowing) return author;
  return FeedAuthor(
    id: author.id,
    name: author.name,
    username: author.username,
    avatarUrl: author.avatarUrl,
    profilePhotoUrl: author.profilePhotoUrl,
    role: author.role,
    isAdmin: author.isAdmin,
    isOfficial: author.isOfficial,
    isFollowing: isFollowing,
  );
}

FeedPost _withoutViewerState(FeedPost post) {
  return post.copyWith(
    author: _copyAuthorWithFollowing(post.author, false),
    isLiked: false,
    viewerLiked: false,
    viewerSaved: false,
  );
}

List<FeedAuthor> _reconcileCurrentUserLiker(
  List<FeedAuthor> existing,
  bool liked,
) {
  final profile = memberStore.profile;
  if (profile == null || profile.id.isEmpty) return existing;
  final withoutMe =
      existing.where((liker) => liker.id != profile.id).toList(growable: true);
  if (!liked) return withoutMe;
  return [
    FeedAuthor(
      id: profile.id,
      name: profile.name,
      username: profile.username,
      avatarUrl: profile.profilePhotoUrl,
      profilePhotoUrl: profile.profilePhotoUrl,
      role: profile.role,
      isAdmin: profile.isAdmin,
    ),
    ...withoutMe,
  ].take(3).toList(growable: false);
}
