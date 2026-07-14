import 'dart:async';

import 'package:flutter/material.dart';

import '../features/feed/video/adaptive_video_preload_policy.dart';
import '../features/feed/video/post_video_coordinator.dart';
import '../features/feed/widgets/feed_video_post_view.dart';
import '../models/feed_post.dart';
import '../state/feed_store.dart';
import '../state/settings_store.dart';
import '../services/video_quality_service.dart';

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

  const ScopedVideoFeedScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
    this.coordinator,
    this.originPostId,
    this.debugNetworkTier,
    this.debugTierChanges,
    this.onNetworkTierChanged,
  });

  @override
  State<ScopedVideoFeedScreen> createState() => _ScopedVideoFeedScreenState();
}

class _ScopedVideoFeedScreenState extends State<ScopedVideoFeedScreen> {
  late final PageController _pageController;
  late int _activeIndex;
  // Guard supaya overscroll-dismiss cuma pop SEKALI per gesture.
  bool _dismissing = false;
  bool _interactionLocked = false;
  VideoSwipeDirection _swipeDirection = VideoSwipeDirection.forward;
  Duration _activeBufferAhead = Duration.zero;
  late NetworkTier _networkTier;
  StreamSubscription<NetworkTier>? _networkTierSubscription;

  /// Seberapa jauh (px) user harus menarik melewati batas atas (video
  /// pertama) sebelum viewer menutup — ala IG Reels dari profil: tarik
  /// turun di reel pertama = kembali ke halaman sebelumnya.
  static const double _dismissOverscroll = 72;

  @override
  void initState() {
    super.initState();
    _activeIndex = widget.initialIndex.clamp(0, widget.posts.length - 1);
    _networkTier = widget.debugNetworkTier ?? videoQualityService.currentTier;
    _networkTierSubscription =
        (widget.debugTierChanges ?? videoQualityService.tierChanges)
            .listen(_onNetworkTierChanged);
    _pageController = PageController(initialPage: _activeIndex);
    feedStore.seed(widget.posts);
    // Full-managed: aktifkan halaman awal setelah frame pertama supaya view
    // managed sudah mounted (adopt sesi via notifier). Item ASAL biasanya sudah
    // punya sesi dari handoff → adopt instan; setActive mem-play + set volume.
    if (widget.coordinator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _activateManaged(_activeIndex, previousIndex: null, swipeDir: 1);
      });
    }
  }

  /// Post yang saat ini attached ke coordinator (view aktif fullscreen). Perlu
  /// di-detach saat viewer ditutup supaya attachment tak menetap dan menghalangi
  /// eviction sesi (KUNCI 2 — attachment harus jujur).
  String? _attachedPostId;

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
    super.dispose();
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
    final postId = widget.posts[index].id;
    // (a) + attach untuk kejujuran refcount ("view ini sedang merender").
    coord.attach(_viewIdFor(postId), postId);
    _attachedPostId = postId;
    coord.setActive(postId);
    // (c) detach view lama (origin pun) — origin hidup via pinned.
    if (previousIndex != null &&
        previousIndex >= 0 &&
        previousIndex < widget.posts.length) {
      final prevId = widget.posts[previousIndex].id;
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
      if (targetIndex < 0 || targetIndex >= widget.posts.length) continue;
      final id = widget.posts[targetIndex].id;
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
      widget.coordinator?.setPreloadWindow(const []);
    } else {
      _updatePreloadWindow(_activeIndex);
    }
  }

  void _onPageChanged(int index) {
    final previousIndex = _activeIndex;
    _activeBufferAhead = Duration.zero;
    setState(() => _activeIndex = index);
    if (widget.coordinator == null) return;
    final swipeDir = index >= previousIndex ? 1 : -1;
    _activateManaged(index, previousIndex: previousIndex, swipeDir: swipeDir);
  }

  void _onActiveBufferAheadChanged(String postId, Duration bufferAhead) {
    if (widget.posts[_activeIndex].id != postId) return;
    final wasEligible = _activeBufferAhead >=
        AdaptiveVideoPreloadPolicy.cellularBufferAheadThreshold;
    if (bufferAhead > _activeBufferAhead) _activeBufferAhead = bufferAhead;
    final isEligible = _activeBufferAhead >=
        AdaptiveVideoPreloadPolicy.cellularBufferAheadThreshold;
    if (!wasEligible && isEligible) _updatePreloadWindow(_activeIndex);
  }

  ScopedVideoFeedResult get _result {
    final post = widget.posts[_activeIndex];
    return ScopedVideoFeedResult(
      postId: post.id,
      index: _activeIndex,
      timestamp: widget.coordinator?.positionOf(post.id) ?? Duration.zero,
    );
  }

  void _close() {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    Navigator.of(context).pop(_result);
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
    final post = widget.posts[index];
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
    return PopScope<ScopedVideoFeedResult>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                physics:
                    const PageScrollPhysics(parent: BouncingScrollPhysics()),
                itemCount: widget.posts.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _buildItem(index),
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
                        width: 40,
                        height: 40,
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
    );
  }
}
