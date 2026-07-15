import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../features/feed/video/adaptive_video_preload_policy.dart';
import '../features/feed/video/post_video_coordinator.dart';
import '../features/feed/widgets/feed_video_post_view.dart';
import '../models/feed_post.dart';
import '../state/feed_store.dart';
import '../state/settings_store.dart';
import '../services/video_quality_service.dart';

typedef ScopedPostPageLoader = Future<FeedPage> Function(String? cursor);

@immutable
class ScopedVideoFeedResult {
  final String postId;
  final int index;
  final Duration timestamp;

  const ScopedVideoFeedResult({
    required this.postId,
    required this.index,
    required this.timestamp,
  });
}

/// Immersive, vertically swipeable video viewer scoped to a caller-
/// supplied list of videos (e.g. "videos tagged to this product", or
/// "videos posted by this user"). Reuses [FeedVideoPostView] so visuals
/// are identical to the main Feed tab. Swiping never leaves [posts].
class ScopedVideoFeedScreen extends StatefulWidget {
  final List<FeedPost> posts;
  final Future<List<FeedPost>>? hydratedPosts;
  final String? initialNextCursor;
  final ScopedPostPageLoader? loadMorePosts;
  final int initialIndex;

  /// Coordinator handoff (§2.6) — di-set HANYA saat viewer dibuka dari alur
  /// Postingan (MemberPostDetailScreen). Kalau non-null, SEMUA item video
  /// managed oleh coordinator (ownership seragam). Kalau null → perilaku lama
  /// (tiap item init controller sendiri).
  ///
  /// T7 (full-managed, mengganti T3b "hanya origin"): saat coordinator ada,
  /// SETIAP item dibangun `ownsController:false, playbackManagedExternally:true`
  /// + terikat ke `coordinator` via `post.id`. Kepemilikan SESI on-demand:
  /// item ASAL ([originPostId]) sudah punya sesi dari handoff (adopt instan);
  /// item lain belum punya sesi → render thumbnail sampai `setActive`/
  /// `preloadNext` melahirkan sesinya, lalu adopt via registry notifier. Urutan
  /// transisi deterministik ada di [_onPageChanged]. Tanpa coordinator → semua
  /// item fallback own-controller (perilaku lama).
  final PostVideoCoordinator? coordinator;

  /// Id post video ASAL (yang di-tap di Postingan) — pinned di coordinator
  /// selama viewer terbuka. Null kalau bukan alur Postingan. Lihat
  /// [coordinator].
  final String? originPostId;
  final NetworkTier? debugNetworkTier;
  @visibleForTesting
  final Stream<NetworkTier>? debugTierChanges;
  final ValueChanged<NetworkTier>? onNetworkTierChanged;
  final ValueChanged<String>? onActivePostChanged;
  final Future<void> Function(ScopedVideoFeedResult result)? onPrepareClose;

  @visibleForTesting
  static bool shouldDismissEdgeSwipe({
    required double offset,
    required double width,
    required double velocity,
  }) {
    return offset >= width * 0.25 || velocity >= 900;
  }

  const ScopedVideoFeedScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
    this.hydratedPosts,
    this.initialNextCursor,
    this.loadMorePosts,
    this.coordinator,
    this.originPostId,
    this.debugNetworkTier,
    this.debugTierChanges,
    this.onNetworkTierChanged,
    this.onActivePostChanged,
    this.onPrepareClose,
  });

  @override
  State<ScopedVideoFeedScreen> createState() => _ScopedVideoFeedScreenState();
}

class _ScopedVideoFeedScreenState extends State<ScopedVideoFeedScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late List<FeedPost> _posts;
  late final AnimationController _horizontalDismissController;
  late int _activeIndex;
  // Guard supaya overscroll-dismiss cuma pop SEKALI per gesture.
  bool _dismissing = false;
  bool _interactionLocked = false;
  double _horizontalDragOffset = 0;
  double _horizontalAnimationStartOffset = 0;
  double _horizontalAnimationEndOffset = 0;
  int? _horizontalPointer;
  final Set<int> _activePointers = <int>{};
  Offset? _pointerDownPosition;
  Offset? _lastPointerPosition;
  VelocityTracker? _horizontalVelocityTracker;
  Duration? _lastHorizontalMoveTime;
  double _recentHorizontalVelocity = 0;
  bool _horizontalGestureActive = false;
  bool _horizontalGestureRejected = false;
  VideoSwipeDirection _swipeDirection = VideoSwipeDirection.forward;
  Duration _activeBufferAhead = Duration.zero;
  late NetworkTier _networkTier;
  StreamSubscription<NetworkTier>? _networkTierSubscription;
  String? _nextCursor;
  bool _loadingMore = false;

  /// Seberapa jauh (px) user harus menarik melewati batas atas (video
  /// pertama) sebelum viewer menutup — ala IG Reels dari profil: tarik
  /// turun di reel pertama = kembali ke halaman sebelumnya.
  static const double _dismissOverscroll = 72;
  static const double _edgeSwipeWidth = 28;

  @override
  void initState() {
    super.initState();
    _posts = List<FeedPost>.of(widget.posts);
    _nextCursor = widget.initialNextCursor;
    _activeIndex = widget.initialIndex.clamp(0, _posts.length - 1);
    _networkTier = widget.debugNetworkTier ?? videoQualityService.currentTier;
    _networkTierSubscription =
        (widget.debugTierChanges ?? videoQualityService.tierChanges)
            .listen(_onNetworkTierChanged);
    _pageController = PageController(initialPage: _activeIndex);
    _horizontalDismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (!mounted) return;
        final progress = Curves.easeOutCubic.transform(
          _horizontalDismissController.value,
        );
        setState(() {
          _horizontalDragOffset = _horizontalAnimationStartOffset +
              ((_horizontalAnimationEndOffset -
                      _horizontalAnimationStartOffset) *
                  progress);
        });
      });
    feedStore.seed(_posts);
    final hydratedPosts = widget.hydratedPosts;
    if (hydratedPosts != null) unawaited(_applyHydratedPosts(hydratedPosts));
    // Full-managed: aktifkan halaman awal setelah frame pertama supaya view
    // managed sudah mounted (adopt sesi via notifier). Item ASAL biasanya sudah
    // punya sesi dari handoff → adopt instan; setActive mem-play + set volume.
    if (widget.coordinator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _activateManaged(_activeIndex, previousIndex: null, swipeDir: 1);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_maybeLoadMore(_activeIndex));
    });
  }

  /// Post yang saat ini attached ke coordinator (view aktif fullscreen). Perlu
  /// di-detach saat viewer ditutup supaya attachment tak menetap dan menghalangi
  /// eviction sesi (KUNCI 2 — attachment harus jujur).
  String? _attachedPostId;

  Future<void> _applyHydratedPosts(Future<List<FeedPost>> future) async {
    try {
      final fresh = await future;
      if (!mounted || fresh.isEmpty) return;
      final byId = {for (final post in fresh) post.id: post};
      final merged = [for (final post in _posts) byId[post.id] ?? post];
      feedStore.mergeFromServer(fresh, fetchedAt: DateTime.now());
      if (!mounted) return;
      setState(() => _posts = merged);
    } catch (_) {
      // Data lokal sudah cukup untuk playback; refresh background best-effort.
    }
  }

  @override
  void dispose() {
    unawaited(_networkTierSubscription?.cancel());
    // Lepas attachment aktif terakhir — kembali ke Postingan, inline yang
    // re-attach origin (member_post_detail._endHandoff). Tanpa ini attachment
    // fullscreen menetap → sesi tak pernah dievict.
    final coord = widget.coordinator;
    final attached = _attachedPostId;
    if (coord != null && !coord.isDisposed && attached != null) {
      coord.detach(_viewIdFor(attached), attached);
    }
    _pageController.dispose();
    _horizontalDismissController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      _cancelHorizontalGestureForConflict();
      return;
    }
    if (_dismissing ||
        _interactionLocked ||
        _horizontalPointer != null ||
        event.localPosition.dx > _edgeSwipeWidth) {
      return;
    }
    _horizontalPointer = event.pointer;
    _pointerDownPosition = event.position;
    _lastPointerPosition = event.position;
    _horizontalVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _lastHorizontalMoveTime = event.timeStamp;
    _recentHorizontalVelocity = 0;
    _horizontalGestureActive = false;
    _horizontalGestureRejected = false;
    _horizontalDismissController.stop();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _horizontalPointer) return;
    final start = _pointerDownPosition;
    final last = _lastPointerPosition;
    if (start == null || last == null || _dismissing || _interactionLocked) {
      return;
    }
    final total = event.position - start;
    final delta = event.position - last;
    final previousMoveTime = _lastHorizontalMoveTime;
    if (previousMoveTime != null) {
      final elapsedMicros = (event.timeStamp - previousMoveTime).inMicroseconds;
      if (elapsedMicros > 0) {
        _recentHorizontalVelocity = delta.dx * 1000000 / elapsedMicros;
      }
    }
    _lastHorizontalMoveTime = event.timeStamp;
    _lastPointerPosition = event.position;
    _horizontalVelocityTracker?.addPosition(event.timeStamp, event.position);
    if (!_horizontalGestureActive && !_horizontalGestureRejected) {
      if (total.distance < 8) return;
      // Keep vertical paging, pinch zoom, and diagonal gestures authoritative.
      // Once rejected, this pointer sequence is never reinterpreted as back.
      if (total.dx <= 0 || total.dx.abs() < total.dy.abs()) {
        _horizontalGestureRejected = true;
        return;
      }
      _horizontalGestureActive = true;
    }
    if (!_horizontalGestureActive) return;
    final next = (_horizontalDragOffset + delta.dx).clamp(
      0.0,
      MediaQuery.sizeOf(context).width,
    );
    if (next != _horizontalDragOffset) {
      setState(() => _horizontalDragOffset = next);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (event.pointer != _horizontalPointer) return;
    if (!_horizontalGestureActive || _dismissing) {
      _resetPointerGesture();
      return;
    }
    _horizontalVelocityTracker?.addPosition(event.timeStamp, event.position);
    final trackedVelocity =
        _horizontalVelocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0;
    final lastMoveTime = _lastHorizontalMoveTime;
    final recentVelocityIsFresh = lastMoveTime != null &&
        event.timeStamp - lastMoveTime <= const Duration(milliseconds: 120);
    final horizontalVelocity =
        recentVelocityIsFresh && _recentHorizontalVelocity > trackedVelocity
            ? _recentHorizontalVelocity
            : trackedVelocity;
    _resetPointerGesture();
    final width = MediaQuery.sizeOf(context).width;
    final shouldDismiss = ScopedVideoFeedScreen.shouldDismissEdgeSwipe(
      offset: _horizontalDragOffset,
      width: width,
      velocity: horizontalVelocity,
    );
    if (shouldDismiss) {
      _dismissing = true;
      final result = _result;
      unawaited(() async {
        await widget.onPrepareClose?.call(result);
        await _animateHorizontalOffsetTo(width).orCancel.catchError((_) {});
        if (mounted) Navigator.of(context).pop(result);
      }());
      return;
    }
    _springHorizontalDragBack(width);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (event.pointer != _horizontalPointer) return;
    if (_horizontalGestureActive && !_dismissing) {
      _springHorizontalDragBack(MediaQuery.sizeOf(context).width);
    }
    _resetPointerGesture();
  }

  void _cancelHorizontalGestureForConflict() {
    if (_horizontalPointer == null) return;
    if (!_dismissing && _horizontalDragOffset > 0) {
      _springHorizontalDragBack(MediaQuery.sizeOf(context).width);
    }
    _resetPointerGesture();
  }

  void _springHorizontalDragBack(double width) {
    if (width <= 0) return;
    _animateHorizontalOffsetTo(0).then((_) {
      if (mounted) setState(() => _horizontalDragOffset = 0);
    });
  }

  TickerFuture _animateHorizontalOffsetTo(double target) {
    _horizontalAnimationStartOffset = _horizontalDragOffset;
    _horizontalAnimationEndOffset = target;
    return _horizontalDismissController.forward(from: 0);
  }

  void _resetPointerGesture() {
    _horizontalPointer = null;
    _pointerDownPosition = null;
    _lastPointerPosition = null;
    _horizontalVelocityTracker = null;
    _lastHorizontalMoveTime = null;
    _recentHorizontalVelocity = 0;
    _horizontalGestureActive = false;
    _horizontalGestureRejected = false;
  }

  String _viewIdFor(String postId) => 'scoped-fs-$postId';

  /// Urutan transisi DETERMINISTIK (§T7 onPageChanged):
  /// (a) `setActive(new)` — coordinator otomatis pause+mute active lama +
  ///     buat/promote sesi halaman baru jadi active;
  /// (b) view halaman baru adopt sesi via registry notifier (otomatis di widget);
  /// (c) `detach(oldViewId)` — SEMUA inactive detach TERMASUK origin (origin
  ///     tetap hidup via pinned, bukan attachment — KUNCI 2);
  /// (d) data-saver? kalau BUKAN → `preloadNext(next)` (next = index+arah swipe);
  /// (e) eviction otomatis di coordinator (sesi bukan origin/active/next dibuang).
  void _activateManaged(
    int index, {
    required int? previousIndex,
    required int swipeDir,
  }) {
    final coord = widget.coordinator;
    if (coord == null || coord.isDisposed) return;
    final postId = _posts[index].id;
    // (a) + attach untuk kejujuran refcount ("view ini sedang merender").
    coord.attach(_viewIdFor(postId), postId);
    _attachedPostId = postId;
    coord.setActive(postId);
    // (c) detach view lama (origin pun) — origin hidup via pinned.
    if (previousIndex != null &&
        previousIndex >= 0 &&
        previousIndex < _posts.length) {
      final prevId = _posts[previousIndex].id;
      if (prevId != postId) {
        coord.detach(_viewIdFor(prevId), prevId);
      }
    }
    _swipeDirection = swipeDir < 0
        ? VideoSwipeDirection.backward
        : VideoSwipeDirection.forward;
    _updatePreloadWindow(index);
  }

  void _updatePreloadWindow(int index) {
    final coord = widget.coordinator;
    if (coord == null || coord.isDisposed) return;
    final offsets = adaptiveVideoPreloadPolicy.offsets(
      qualityPreference: appSettingsStore.feedVideoQuality,
      networkTier: _networkTier,
      autoplayEnabled: appSettingsStore.feedAutoplay,
      swipeDirection: _swipeDirection,
      activeBufferAhead: _activeBufferAhead,
      interactionLocked: _interactionLocked,
    );
    final targetIds = <String>[];
    for (final offset in offsets) {
      final targetIndex = index + offset;
      if (targetIndex < 0 || targetIndex >= _posts.length) continue;
      final id = _posts[targetIndex].id;
      if (!targetIds.contains(id)) targetIds.add(id);
    }
    coord.setPreloadWindow(targetIds);
  }

  void _onNetworkTierChanged(NetworkTier tier) {
    if (!mounted) return;
    final coord = widget.coordinator;
    // Drop only adaptive preloads before the parent switches its URL resolver
    // to the new tier. Origin and active sessions remain pinned, so playback
    // is not interrupted while the next-video window is recreated below.
    if (coord != null && !coord.isDisposed) {
      coord.setPreloadWindow(const []);
    }
    _networkTier = tier;
    widget.onNetworkTierChanged?.call(tier);
    _activeBufferAhead = Duration.zero;
    _updatePreloadWindow(_activeIndex);
  }

  void _setInteractionLocked(bool locked) {
    if (_interactionLocked == locked) return;
    _interactionLocked = locked;
    if (locked) {
      if (_horizontalPointer != null && !_dismissing) {
        _springHorizontalDragBack(MediaQuery.sizeOf(context).width);
        _resetPointerGesture();
      }
      widget.coordinator?.setPreloadWindow(const []);
    } else {
      _updatePreloadWindow(_activeIndex);
    }
  }

  void _onPageChanged(int index) {
    final previousIndex = _activeIndex;
    _activeBufferAhead = Duration.zero;
    setState(() => _activeIndex = index);
    widget.onActivePostChanged?.call(_posts[index].id);
    unawaited(_maybeLoadMore(index));
    if (widget.coordinator == null) return;
    final swipeDir = index >= previousIndex ? 1 : -1;
    _activateManaged(index, previousIndex: previousIndex, swipeDir: swipeDir);
  }

  Future<void> _maybeLoadMore(int index) async {
    final loader = widget.loadMorePosts;
    if (loader == null || _loadingMore || _nextCursor == null) return;
    if (index < _posts.length - 3) return;

    _loadingMore = true;
    try {
      // A profile page can contain photos between videos. Keep advancing the
      // opaque source cursor until at least one video is appended or the
      // source is exhausted, without ever creating a controller here.
      while (mounted && _nextCursor != null) {
        final page = await loader(_nextCursor);
        if (!mounted) return;
        _nextCursor = page.nextCursor;
        final existingIds = _posts.map((post) => post.id).toSet();
        final videos = page.items
            .where((post) => post.isVideo && existingIds.add(post.id))
            .toList(growable: false);
        if (page.items.isNotEmpty) {
          feedStore.mergeFromServer(page.items, fetchedAt: DateTime.now());
        }
        if (videos.isNotEmpty) {
          setState(() => _posts = [..._posts, ...videos]);
          _updatePreloadWindow(_activeIndex);
          break;
        }
      }
    } catch (_) {
      // Keep the cursor unchanged in the source callback contract where
      // possible; a later page change/return near the end retries quietly.
    } finally {
      _loadingMore = false;
    }
  }

  void _onActiveBufferAheadChanged(String postId, Duration bufferAhead) {
    if (_posts[_activeIndex].id != postId) return;
    final wasEligible = _activeBufferAhead >=
        AdaptiveVideoPreloadPolicy.cellularBufferAheadThreshold;
    if (bufferAhead > _activeBufferAhead) _activeBufferAhead = bufferAhead;
    final isEligible = _activeBufferAhead >=
        AdaptiveVideoPreloadPolicy.cellularBufferAheadThreshold;
    if (!wasEligible && isEligible) _updatePreloadWindow(_activeIndex);
  }

  ScopedVideoFeedResult get _result {
    final post = _posts[_activeIndex];
    return ScopedVideoFeedResult(
      postId: post.id,
      index: _activeIndex,
      timestamp: widget.coordinator?.positionOf(post.id) ?? Duration.zero,
    );
  }

  void _close() {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    final result = _result;
    unawaited(() async {
      // A suspended app cannot produce the frame needed to measure the
      // inline reverse target. Waiting here would leave the route stuck
      // until a second interaction after resume. Close immediately; the
      // caller still reconciles post + timestamp from the typed result.
      if (WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed) {
        await widget.onPrepareClose?.call(result);
      }
      if (mounted) Navigator.of(context).pop(result);
    }());
  }

  /// Tarik-turun melewati batas atas (BouncingScrollPhysics → pixels <
  /// minScrollExtent) saat jari masih di layar (dragDetails != null,
  /// supaya animasi bounce-back setelah lepas tidak ikut memicu) →
  /// tutup viewer. Mentok bawah dibiarkan stuck (sesuai spec).
  bool _onScrollNotification(ScrollNotification notification) {
    if (_dismissing) return false;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final metrics = notification.metrics;
      if (metrics.pixels < metrics.minScrollExtent - _dismissOverscroll) {
        _close();
      }
    }
    return false;
  }

  /// Bangun satu page. Full-managed (coordinator ada) → SEMUA item managed +
  /// terikat coordinator via `post.id` (ownership seragam); tanpa coordinator →
  /// own-controller (perilaku lama, mis. Postingan Terkait / deep link).
  Widget _buildItem(int index) {
    final post = _posts[index];
    final coordinator = widget.coordinator;

    if (coordinator == null) {
      return FeedVideoPostView(
        post: post,
        isActive: index == _activeIndex,
        preloadedController: null,
        preloadedCachedPlayer: null,
        onOverlayStateChanged: (_) {},
        onMediaZoomChanged: _setInteractionLocked,
        onBufferAheadChanged: (ahead) =>
            _onActiveBufferAheadChanged(post.id, ahead),
      );
    }

    final postId = post.id;
    return FeedVideoPostView(
      // Key stabil per-post supaya state managed tidak dibangun ulang saat
      // swipe bolak-balik (re-adopt sesi via notifier, bukan state baru).
      key: ValueKey('scoped-fs-$postId'),
      post: post,
      isActive: index == _activeIndex,
      // §2.1: coordinator pemilik controller (dispose) + pengendali playback.
      // Widget hanya merender + melapor intent + adopt sesi via notifier.
      ownsController: false,
      playbackManagedExternally: true,
      coordinator: coordinator,
      preloadedController: null,
      preloadedCachedPlayer: null,
      onOverlayStateChanged: (_) {},
      onMediaZoomChanged: _setInteractionLocked,
      onBufferAheadChanged: (ahead) =>
          _onActiveBufferAheadChanged(post.id, ahead),
      // Visibilitas → resume/pause sesi yang MEMANG aktif (mis. kembali dari
      // comment sheet / route). setActive authoritative di [_onPageChanged];
      // di sini tidak setActive supaya urutan transisi tetap deterministik.
      onVisibleChanged: (visible) {
        // Route teardown can report one final hidden event after the caller
        // has already resumed this shared session. It is stale once closing.
        if (_dismissing) return;
        if (coordinator.activePostId != postId) return;
        if (visible) {
          coordinator.reportVisible(postId);
        } else {
          coordinator.reportHidden(postId);
        }
      },
      // Tap play/pause → satu-satunya sumber user-pause eksplisit.
      onRequestUserTogglePlay: coordinator.userTogglePlay,
      // Cover hilang (route pop / app foreground / comment sheet turun) →
      // resume sesi aktif (guard suspend/user-pause ada di coordinator).
      onRequestPlay: coordinator.resumeAll,
      // Cover (D5): appBackground / commentSheetFull / routePush → pause semua.
      onRequestPause: (_) => coordinator.pauseAll(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalProgress =
        width == 0 ? 0.0 : (_horizontalDragOffset / width).clamp(0.0, 1.0);
    return PopScope<ScopedVideoFeedResult>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Transform.translate(
            offset: Offset(_horizontalDragOffset, 0),
            child: Opacity(
              opacity: 1 - (horizontalProgress * 0.28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.vertical,
                      physics: const PageScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      itemCount: _posts.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) => _buildItem(index),
                    ),
                  ),
                  const IgnorePointer(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        key: ValueKey('scoped-video-top-scrim'),
                        height: 120,
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x73000000), Color(0x00000000)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _close,
                            child: const SizedBox(
                              key: ValueKey('scoped-video-back-target'),
                              width: 48,
                              height: 48,
                              child: Icon(Icons.chevron_left_rounded,
                                  color: Colors.white, size: 26),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
