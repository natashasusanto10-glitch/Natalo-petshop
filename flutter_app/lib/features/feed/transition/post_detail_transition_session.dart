import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../../models/feed_post.dart';

enum PostDetailDestinationReadiness {
  preparing,
  geometryReady,
  crossfadeFallback,
}

@immutable
class PostPageMediaProxy {
  PostPageMediaProxy({required this.placeholderColor, ImageInfo? imageInfo})
    : imageInfo = imageInfo?.clone();

  final Color placeholderColor;
  final ImageInfo? imageInfo;

  PostPageMediaProxy clone() => PostPageMediaProxy(
    placeholderColor: placeholderColor,
    imageInfo: imageInfo,
  );

  void dispose() => imageInfo?.dispose();
}

@immutable
class PostPageSourceTarget {
  const PostPageSourceTarget({
    required this.postId,
    required this.rect,
    required this.proxy,
    required this.viewportSize,
    required this.textDirection,
    required this.layoutGeneration,
    this.borderRadius = 0,
  });

  final String postId;
  final Rect rect;
  final PostPageMediaProxy proxy;
  final Size viewportSize;
  final TextDirection textDirection;
  final int layoutGeneration;
  final double borderRadius;

  bool get hasUsableGeometry =>
      rect.left.isFinite &&
      rect.top.isFinite &&
      rect.right.isFinite &&
      rect.bottom.isFinite &&
      rect.width > 0 &&
      rect.height > 0 &&
      rect.overlaps(Offset.zero & viewportSize);
}

@immutable
class PostPageFrozenTarget {
  const PostPageFrozenTarget({
    required this.post,
    required this.target,
    required this.proxy,
  });

  final FeedPost post;
  final PostPageSourceTarget? target;
  final PostPageMediaProxy proxy;

  bool get usesFallback => target == null;
}

abstract interface class PostDetailTransitionSourceAdapter {
  bool get mounted;

  void mergePage(FeedPage page);

  Future<PostPageSourceTarget?> prepareTarget(
    FeedPost post, {
    required int generation,
  });

  PostPageSourceTarget? resolveTarget(FeedPost post);

  PostPageMediaProxy resolveProxy(FeedPost post);

  void setTileSuppressed(String postId, bool suppressed);

  void setPendingReturnPostId(String? postId);
}

class PostDetailTransitionSession extends ChangeNotifier {
  PostDetailTransitionSession({
    required FeedPost initialPost,
    required PostDetailTransitionSourceAdapter source,
  }) : _source = source,
       _activePost = initialPost,
       _loadedPostsById = LinkedHashMap<String, FeedPost>.fromEntries([
         MapEntry(initialPost.id, initialPost),
       ]) {
    _touchedPostIds.add(initialPost.id);
    final resolvedOpeningTarget = source.resolveTarget(initialPost);
    if (resolvedOpeningTarget != null &&
        resolvedOpeningTarget.postId == initialPost.id) {
      _openingTarget = _retainTarget(resolvedOpeningTarget);
    }
    if (_openingTarget?.hasUsableGeometry ?? false) {
      _openingFallbackProxy = _openingTarget!.proxy;
    } else {
      _openingFallbackProxy = _retainProxy(source.resolveProxy(initialPost));
      _fallbackProxiesByPostId[initialPost.id] = _openingFallbackProxy!;
    }
  }

  final PostDetailTransitionSourceAdapter _source;
  final LinkedHashMap<String, FeedPost> _loadedPostsById;
  final HashSet<PostPageMediaProxy> _ownedProxies = HashSet.identity();
  final Map<String, PostPageMediaProxy> _fallbackProxiesByPostId = {};
  final LinkedHashSet<String> _touchedPostIds = LinkedHashSet<String>();
  final Set<String> _restoredPostIds = <String>{};
  final Set<String> _invalidatedPostIds = <String>{};

  FeedPost _activePost;
  PostPageSourceTarget? _openingTarget;
  PostPageSourceTarget? _preparedTarget;
  PostPageFrozenTarget? _frozenTarget;
  PostPageMediaProxy? _openingFallbackProxy;
  PostDetailDestinationReadiness _destinationReadiness =
      PostDetailDestinationReadiness.preparing;
  int _preparationGeneration = 0;
  String? _suppressedPostId;
  bool _playbackAllowed = false;
  bool _routeAttached = false;
  bool _destinationMediaSuppressed = false;
  Rect? _destinationMediaSlotRect;
  double? _destinationMediaAspect;
  VideoPlayerController? _destinationVideoController;
  bool _isDisposed = false;

  FeedPost get activePost => _activePost;

  List<FeedPost> get loadedPosts =>
      List<FeedPost>.unmodifiable(_loadedPostsById.values);

  PostPageSourceTarget? get openingTarget => _openingTarget;

  PostPageSourceTarget? get preparedTarget => _preparedTarget;

  PostDetailDestinationReadiness get destinationReadiness =>
      _destinationReadiness;

  bool get isFrozen => _frozenTarget != null;

  bool get playbackAllowed => _playbackAllowed;

  bool get routeAttached => _routeAttached;

  /// True while a hero flight is actively covering the active post's media
  /// (open/close transit). The destination screen must render that post's
  /// own media slot fully transparent while this holds — otherwise the hero
  /// layer and the destination's real media would paint on top of each
  /// other (double-drawn), see Task 3 in hero-task-3-brief.md.
  bool get destinationMediaSuppressed => _destinationMediaSuppressed;

  /// The active post's media slot rect in the destination, as last measured
  /// by the destination screen's own visibility-measurement pass (in overlay
  /// coordinates). `null` until the destination has laid out and measured at
  /// least once. The route (which only holds an opaque `WidgetBuilder` for
  /// the destination) has no other channel into this measured `RenderBox`
  /// state — this is that channel. See [reportDestinationMediaSlot].
  Rect? get destinationMediaSlotRect => _destinationMediaSlotRect;

  /// The active post's intrinsic media aspect ratio (width / height), as
  /// resolved by the destination via `resolvePostinganMediaAspectRatio`.
  /// `null` until the destination has reported at least once. Reported
  /// alongside [destinationMediaSlotRect] by [reportDestinationMediaSlot].
  double? get destinationMediaAspect => _destinationMediaAspect;

  /// The live [VideoPlayerController] the destination's own inline player is
  /// currently bound to for the active post, or `null` when the active post
  /// is not a video or the destination has not attached a controller yet
  /// (e.g. before `playbackAllowed`). The hero layer draws through this SAME
  /// controller (never a separate thumbnail/proxy once it has visual
  /// output) so a video's surface is one continuous texture read across the
  /// whole flight — see [reportDestinationVideoController].
  VideoPlayerController? get destinationVideoController =>
      _destinationVideoController;

  bool tryAttachRoute() {
    if (_isDisposed || _routeAttached) return false;
    _routeAttached = true;
    notifyListeners();
    return true;
  }

  void detachRoute() {
    if (_isDisposed || !_routeAttached) return;
    _routeAttached = false;
    notifyListeners();
  }

  void reportActivePost(FeedPost post) {
    if (_isDisposed || isFrozen) return;
    final activePostIdChanged = _activePost.id != post.id;
    final activePostChanged = !identical(_activePost, post);
    final loadedPostChanged = !identical(_loadedPostsById[post.id], post);
    _activePost = post;
    _loadedPostsById[post.id] = post;
    _touchedPostIds.add(post.id);
    if (activePostIdChanged) {
      _preparationGeneration++;
      _replacePreparedTarget(null);
    }
    if (activePostChanged || loadedPostChanged) notifyListeners();
  }

  void reportLoadedPage(FeedPage page) {
    if (_isDisposed) return;
    if (_source.mounted) _source.mergePage(page);
    var changed = false;
    for (final post in page.items) {
      if (!identical(_loadedPostsById[post.id], post)) {
        _loadedPostsById[post.id] = post;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void invalidatePost(String postId) {
    if (_isDisposed) return;
    _preparationGeneration++;
    _invalidatedPostIds.add(postId);

    if (_openingTarget?.postId == postId) {
      final oldOpeningTarget = _openingTarget!;
      _openingTarget = null;
      if (identical(_openingFallbackProxy, oldOpeningTarget.proxy)) {
        _openingFallbackProxy = null;
      }
      _releaseProxyUnlessFrozen(oldOpeningTarget.proxy);
    }
    if (_preparedTarget?.postId == postId) {
      _replacePreparedTarget(null);
    }

    final fallbackProxy = _fallbackProxiesByPostId.remove(postId);
    if (fallbackProxy != null) {
      if (identical(fallbackProxy, _openingFallbackProxy)) {
        _openingFallbackProxy = null;
      }
      _releaseProxyUnlessFrozen(fallbackProxy);
    }
    notifyListeners();
  }

  Future<PostPageSourceTarget?> prepareActiveTarget() async {
    if (_isDisposed) return null;
    if (isFrozen) return _frozenTarget?.target;

    final post = _activePost;
    final generation = ++_preparationGeneration;
    if (!_source.mounted) {
      if (_replacePreparedTarget(null)) notifyListeners();
      return null;
    }

    final sourceTarget = await _source.prepareTarget(
      post,
      generation: generation,
    );
    if (_isDisposed ||
        generation != _preparationGeneration ||
        _activePost.id != post.id) {
      return null;
    }
    if (!_source.mounted ||
        sourceTarget == null ||
        sourceTarget.postId != post.id) {
      if (_replacePreparedTarget(null)) notifyListeners();
      return null;
    }

    final retainedTarget = _retainTarget(sourceTarget);
    _invalidatedPostIds.remove(post.id);
    _touchedPostIds.add(post.id);
    _replacePreparedTarget(retainedTarget);
    notifyListeners();
    return retainedTarget;
  }

  PostPageFrozenTarget freeze() {
    if (_isDisposed) {
      throw StateError('Cannot freeze a disposed transition session.');
    }
    final existingFrozenTarget = _frozenTarget;
    if (existingFrozenTarget != null) return existingFrozenTarget;

    final post = _activePost;
    final candidate = _preparedTarget;
    final target =
        candidate?.postId == post.id &&
            candidate!.hasUsableGeometry &&
            !_invalidatedPostIds.contains(post.id)
        ? candidate
        : null;
    final proxy = target?.proxy ?? _resolveFallbackProxy(post);
    final frozenTarget = PostPageFrozenTarget(
      post: post,
      target: target,
      proxy: proxy,
    );
    _frozenTarget = frozenTarget;
    _touchedPostIds.add(post.id);
    if (!_isDisposed) notifyListeners();
    return frozenTarget;
  }

  void resumeTrackingAfterCanceledBack() {
    if (_isDisposed || _frozenTarget == null) return;
    _restoreSuppressedTile();
    _frozenTarget = null;
    notifyListeners();
  }

  void markDestinationReady(PostDetailDestinationReadiness readiness) {
    if (_isDisposed || _destinationReadiness == readiness) return;
    _destinationReadiness = readiness;
    notifyListeners();
  }

  void setPlaybackAllowed(bool value) {
    if (_isDisposed || _playbackAllowed == value) return;
    _playbackAllowed = value;
    notifyListeners();
  }

  void setFrozenTileSuppressed(bool suppressed) {
    if (_isDisposed || !_source.mounted) return;
    final frozenPostId = _frozenTarget?.post.id;
    if (frozenPostId == null) return;

    if (suppressed) {
      if (_suppressedPostId == frozenPostId) return;
      _restoreSuppressedTile();
      _source.setTileSuppressed(frozenPostId, true);
      _suppressedPostId = frozenPostId;
      _restoredPostIds.remove(frozenPostId);
      _touchedPostIds.add(frozenPostId);
      return;
    }
    _restoreSuppressedTile();
  }

  /// Signal consumed by the destination screen (see
  /// [destinationMediaSuppressed]). Unlike [setFrozenTileSuppressed] (which
  /// suppresses the SOURCE grid tile via the adapter), this flag is purely
  /// destination-side rendering state — no `_source` call needed.
  void setDestinationMediaSuppressed(bool suppressed) {
    if (_isDisposed || _destinationMediaSuppressed == suppressed) return;
    _destinationMediaSuppressed = suppressed;
    notifyListeners();
  }

  /// Reports the active post's current measured media-slot rect + intrinsic
  /// aspect ratio, as observed by the destination screen's own visibility-
  /// measurement pass. Called on every such pass (every scroll-driven
  /// remeasure), so the value stays continuously fresh — the route freezes
  /// whatever is current at the moment it leaves `preparingOpen`.
  void reportDestinationMediaSlot({
    required Rect rect,
    required double mediaAspect,
  }) {
    if (_isDisposed) return;
    if (_destinationMediaSlotRect == rect &&
        _destinationMediaAspect == mediaAspect) {
      return;
    }
    _destinationMediaSlotRect = rect;
    _destinationMediaAspect = mediaAspect;
    notifyListeners();
  }

  /// Reports the [VideoPlayerController] the destination's own inline player
  /// is currently bound to for the active post (or `null` when there isn't
  /// one — non-video post, or not attached yet). Compared by identity, not
  /// value, since the controller is a long-lived mutable object whose
  /// `value` changes as it initializes.
  void reportDestinationVideoController(VideoPlayerController? controller) {
    if (_isDisposed) return;
    if (identical(_destinationVideoController, controller)) return;
    _destinationVideoController = controller;
    notifyListeners();
  }

  void assignPendingReturnTarget() {
    if (_isDisposed || !_source.mounted) return;
    _source.setPendingReturnPostId(_frozenTarget?.post.id ?? _activePost.id);
  }

  PostPageSourceTarget _retainTarget(PostPageSourceTarget target) =>
      PostPageSourceTarget(
        postId: target.postId,
        rect: target.rect,
        proxy: _retainProxy(target.proxy),
        viewportSize: target.viewportSize,
        textDirection: target.textDirection,
        layoutGeneration: target.layoutGeneration,
        borderRadius: target.borderRadius,
      );

  PostPageMediaProxy _retainProxy(PostPageMediaProxy proxy) {
    final retainedProxy = proxy.clone();
    _ownedProxies.add(retainedProxy);
    return retainedProxy;
  }

  PostPageMediaProxy _resolveFallbackProxy(FeedPost post) {
    return _fallbackProxiesByPostId.putIfAbsent(
      post.id,
      () => _retainProxy(_source.resolveProxy(post)),
    );
  }

  bool _replacePreparedTarget(PostPageSourceTarget? target) {
    final oldTarget = _preparedTarget;
    if (identical(oldTarget, target)) return false;
    _preparedTarget = target;
    if (oldTarget != null) _releaseProxyUnlessFrozen(oldTarget.proxy);
    return true;
  }

  void _releaseProxyUnlessFrozen(PostPageMediaProxy proxy) {
    if (identical(_frozenTarget?.proxy, proxy)) return;
    if (_ownedProxies.remove(proxy)) proxy.dispose();
  }

  void _restoreSuppressedTile() {
    final suppressedPostId = _suppressedPostId;
    if (suppressedPostId == null) return;
    if (_source.mounted) {
      _source.setTileSuppressed(suppressedPostId, false);
      _restoredPostIds.add(suppressedPostId);
    }
    _suppressedPostId = null;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _preparationGeneration++;
    _restoreSuppressedTile();
    if (_source.mounted) {
      for (final postId in _touchedPostIds) {
        if (_restoredPostIds.add(postId)) {
          _source.setTileSuppressed(postId, false);
        }
      }
    }
    for (final proxy in _ownedProxies) {
      proxy.dispose();
    }
    _ownedProxies.clear();
    _fallbackProxiesByPostId.clear();
    _routeAttached = false;
    _playbackAllowed = false;
    _destinationMediaSuppressed = false;
    _destinationMediaSlotRect = null;
    _destinationMediaAspect = null;
    _destinationVideoController = null;
    super.dispose();
  }
}
