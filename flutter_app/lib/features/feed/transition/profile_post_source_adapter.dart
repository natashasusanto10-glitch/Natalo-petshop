import 'package:flutter/painting.dart';

import '../../../models/feed_post.dart';
import '../../../widgets/profile_grid_geometry.dart';
import 'post_detail_transition_session.dart';
import 'post_transition_source_tile.dart';

/// Reusable [PostDetailTransitionSourceAdapter] for the profile-style grid
/// screens (Own Profile, Public Profile, Postingan Saya). It bridges a
/// [PostTransitionTileRegistry] (which resolves live tile geometry + media
/// proxies) and a handful of screen-supplied callbacks.
///
/// Registry disposal contract (see [PostTransitionTileRegistry.resolve]): every
/// `resolve` returns a FRESH, source-owned disposable snapshot (a live
/// [PostPageMediaProxy] cloning an [ImageInfo]). This adapter therefore:
///  * caches at most one accepted snapshot and disposes the previous one when a
///    newer snapshot is accepted;
///  * disposes any snapshot it rejects (stale generation / layout / identity /
///    unusable geometry) instead of leaking its proxy;
///  * disposes the cached snapshot and every issued fallback proxy on
///    [dispose].
///
/// Two independent generation axes are honored WITHOUT being conflated:
///  * the session's preparation [generation] (supersede: a late prepare for an
///    older generation returns null without caching), and
///  * the registry's [PostTransitionTileRegistry.layoutGeneration] (a tile
///    relaid out across the async `ensureVisible` gap rejects the snapshot and
///    drives the crossfade fallback).
class ProfilePostSourceAdapter implements PostDetailTransitionSourceAdapter {
  ProfilePostSourceAdapter({
    required PostTransitionTileRegistry registry,
    required bool Function() isMounted,
    required String Function() currentScope,
    required Future<void> Function(FeedPost post, int generation) ensureVisible,
    required void Function(FeedPage page) mergeScopedPage,
    required Color Function(FeedPost post) fallbackColor,
  }) : _registry = registry,
       _isMounted = isMounted,
       _currentScope = currentScope,
       _ensureVisible = ensureVisible,
       _mergeScopedPage = mergeScopedPage,
       _fallbackColor = fallbackColor;

  final PostTransitionTileRegistry _registry;
  final bool Function() _isMounted;
  final String Function() _currentScope;
  final Future<void> Function(FeedPost post, int generation) _ensureVisible;
  final void Function(FeedPage page) _mergeScopedPage;
  final Color Function(FeedPost post) _fallbackColor;

  /// The single accepted snapshot the adapter currently owns.
  PostPageSourceTarget? _cachedTarget;

  /// Fallback proxies handed to the session via [resolveProxy]. The session
  /// clones (and owns the clone of) each, but the originals stay owned here.
  final List<PostPageMediaProxy> _issuedProxies = <PostPageMediaProxy>[];

  int _latestPrepareGeneration = 0;
  String? _pendingReturnPostId;
  bool _disposed = false;

  PostTransitionTileId _idForPost(FeedPost post) => _idForId(post.id);

  PostTransitionTileId _idForId(String postId) =>
      PostTransitionTileId(scope: _currentScope(), postId: postId);

  @override
  bool get mounted => !_disposed && _isMounted();

  @override
  void mergePage(FeedPage page) => _mergeScopedPage(page);

  @override
  PostPageSourceTarget? resolveTarget(FeedPost post) {
    final snapshot = _registry.resolve(_idForPost(post));
    if (snapshot == null) return null;
    if (snapshot.postId != post.id) {
      snapshot.proxy.dispose();
      return null;
    }
    _acceptSnapshot(snapshot);
    return snapshot;
  }

  @override
  Future<PostPageSourceTarget?> prepareTarget(
    FeedPost post, {
    required int generation,
  }) async {
    if (generation > _latestPrepareGeneration) {
      _latestPrepareGeneration = generation;
    }
    // Registry-axis snapshot taken BEFORE the async scroll gap. If the tile is
    // relaid out while `ensureVisible` runs, the resolved snapshot will carry a
    // newer layout generation and be rejected below.
    final capturedLayoutGeneration = _registry.layoutGeneration;

    await _ensureVisible(post, generation);
    if (_disposed || !_isMounted()) return null;

    final snapshot = _registry.resolve(_idForPost(post));
    if (snapshot == null) return null;

    final rejected =
        generation != _latestPrepareGeneration ||
        snapshot.postId != post.id ||
        snapshot.layoutGeneration != capturedLayoutGeneration ||
        !snapshot.hasUsableGeometry;
    if (rejected) {
      snapshot.proxy.dispose();
      return null;
    }

    _acceptSnapshot(snapshot);
    return snapshot;
  }

  @override
  PostPageMediaProxy resolveProxy(FeedPost post) {
    final snapshot = _registry.resolve(_idForPost(post));
    final PostPageMediaProxy proxy;
    if (snapshot != null && snapshot.postId == post.id) {
      proxy = snapshot.proxy;
    } else {
      snapshot?.proxy.dispose();
      proxy = PostPageMediaProxy(placeholderColor: _fallbackColor(post));
    }
    _issuedProxies.add(proxy);
    return proxy;
  }

  @override
  void setTileSuppressed(String postId, bool suppressed) {
    _registry.setSuppressed(_idForId(postId), suppressed);
  }

  @override
  void setPendingReturnPostId(String? postId) {
    _pendingReturnPostId = postId;
  }

  /// The post the source screen should re-anchor to after a fallback pop, or
  /// null if there is none pending. Owned by the SOURCE, never the (disposed)
  /// session.
  String? get pendingReturnPostId => _pendingReturnPostId;

  /// Bounded, best-effort re-anchoring after a fallback pop: positions the grid
  /// near the pending post's row via [profileGridMainAxisOffsetForIndex], one
  /// attempt, then clears the pending id regardless of outcome.
  void consumePendingReturn({
    required double gridWidth,
    required int? Function(String postId) indexOfPostInCurrentScope,
    required void Function(double offset) jumpToOffset,
  }) {
    final postId = _pendingReturnPostId;
    _pendingReturnPostId = null;
    if (postId == null) return;
    final index = indexOfPostInCurrentScope(postId);
    if (index == null || index < 0) return;
    final offset = profileGridMainAxisOffsetForIndex(gridWidth, index: index);
    jumpToOffset(offset);
  }

  void _acceptSnapshot(PostPageSourceTarget snapshot) {
    final previous = _cachedTarget;
    if (identical(previous, snapshot)) return;
    _cachedTarget = snapshot;
    previous?.proxy.dispose();
  }

  /// Releases every source-owned proxy. The source screen calls this once the
  /// zoom route has completed and the session has been disposed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cachedTarget?.proxy.dispose();
    _cachedTarget = null;
    for (final proxy in _issuedProxies) {
      proxy.dispose();
    }
    _issuedProxies.clear();
  }
}
