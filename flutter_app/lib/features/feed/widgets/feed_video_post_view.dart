import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../config/api_config.dart';
import '../../../models/cart_item.dart';
import '../../../models/feed_post.dart';
import '../../../models/product.dart';
import '../../../screens/checkout_screen.dart';
import '../../../services/api_client.dart';
import '../../../services/block_service.dart';
import '../../../services/feed_service.dart';
import '../../../services/product_service.dart';
import '../../../services/report_service.dart';
import '../../../services/video_quality_service.dart';
import '../../../state/cart_store.dart';
import '../../../state/feed_local_store.dart';
import '../../../state/feed_store.dart';
import '../../../state/member_store.dart';
import '../../../state/settings_store.dart';
import '../../../utils/android_back_overlays.dart';
import '../../../utils/app_route_observer.dart';
import '../../../utils/formatters.dart';
import '../../../utils/haptics.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/feed_comment_sheet.dart';
import '../../../widgets/moderation_action_sheet.dart';
import 'feed_action_rail.dart';
import 'feed_creator_overlay.dart';
import 'feed_post_scrim.dart';
import 'feed_post_shared_widgets.dart';
import 'feed_video_scrubber.dart';

/// Satu fullscreen page Reels-style — video/thumbnail + Reels overlay.
class FeedVideoPostView extends StatefulWidget {
  final FeedPost post;
  final bool isActive;
  final VideoPlayerController? preloadedController;

  /// Wrapper instance dari CachedVideoPlayerPlus — null kalau controller
  /// adopt dari preload tapi wrapper sudah hilang (rare), atau kalau
  /// child create fresh via _maybeInitVideo. Disimpan supaya dispose
  /// proper handle cache file lifecycle via wrapper.dispose().
  final CachedVideoPlayerPlus? preloadedCachedPlayer;
  final ValueChanged<bool> onOverlayStateChanged;
  final ValueChanged<bool> onMediaZoomChanged;

  const FeedVideoPostView({
    super.key,
    required this.post,
    required this.isActive,
    required this.preloadedController,
    required this.onOverlayStateChanged,
    required this.onMediaZoomChanged,
    this.preloadedCachedPlayer,
  });

  @override
  State<FeedVideoPostView> createState() => _FeedVideoPostViewState();
}

class _FeedVideoPostViewState extends State<FeedVideoPostView>
    with TickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  static const double _commentSheetMinExtent = 0.22;
  static const double _commentSheetInitialExtent = 0.60;
  static const double _commentSheetMaxExtentCap = 0.82;
  static const double _commentSheetDismissExtent = 0.30;

  VideoPlayerController? _videoController;

  /// Wrapper instance untuk lifecycle network video (disk cache). Null
  /// kalau ga ada wrapper (defensive). Disposed di dispose() lebih dulu
  /// dari _videoController supaya cache file di-release proper. Untuk
  /// adopt-from-parent path: copy dari widget.preloadedCachedPlayer.
  /// Untuk fresh-create path: di-set di _maybeInitVideo.
  CachedVideoPlayerPlus? _cachedPlayer;
  final DraggableScrollableController _commentSheetController =
      DraggableScrollableController();
  final ValueNotifier<double> _commentSheetExtent =
      ValueNotifier<double>(_commentSheetInitialExtent);
  bool _liked = false;
  int _likeCount = 0;
  int _commentCount = 0;
  int _shareCount = 0;
  bool _isPaused = false;
  bool _commentDrawerMounted = false;
  bool _commentSheetOpen = false;
  bool _videoLoadFailed = false;
  bool _commentSheetClosingFromDrag = false;
  int _commentAddedCount = 0;
  int _featuredProductIndex = 0;
  Timer? _productRotationTimer;
  double _commentDragOffset = 0;

  // Product CTA card — slide-in sekali di detik ~4 (min(4s, durasi/2))
  // lalu menetap sampai user dismiss (gaya TikTok Shop). Tombol "Beli"
  // lebih prominent dari product chip kecil di bottom info yang selalu
  // visible. Dismiss sticky per post; reset saat swipe ke post lain.
  // Skip untuk post tanpa tagged products.
  bool _endOfVideoCtaVisible = false;
  bool _endOfVideoCtaDismissed = false;

  // Panel caption ala IG: saat terbuka, scrim gelap naik + pill produk
  // fade menghilang (mode baca fokus). State di-lift ke sini supaya semua
  // elemen ber-transisi serempak dan tap area video bisa menutup panel.
  bool _captionExpanded = false;

  void _setCaptionExpanded(bool value) {
    if (_captionExpanded == value || !mounted) return;
    setState(() => _captionExpanded = value);
    // Card CTA pop-up otomatis tertutup saat caption naik — jangan ada
    // dua permukaan commerce beradu di mode baca.
    if (value && _endOfVideoCtaVisible) _dismissEndOfVideoCta();
  }

  // Delayed loading spinner — sebagian besar video load <1s (preloaded
  // controller siap instan, fresh init biasanya 400-900ms). Spinner yang
  // muncul instant bikin user anxiety ("kok lama?"). Delay 800ms supaya
  // kalau video keburu ready, spinner gak pernah muncul = perceived
  // instant. Kalau lewat 800ms baru spinner muncul (genuine slow load,
  // butuh feedback visual).
  Timer? _loadingSpinnerDelay;
  bool _showLoadingSpinner = false;

  // Animation untuk heart burst di tengah saat double-tap.
  late final AnimationController _heartBurstController;
  late final Animation<double> _heartScale;
  late final Animation<double> _heartOpacity;
  late final Animation<double> _heartTravel;
  Offset? _heartBurstPosition;
  // Target "terbang ke rail" — pusat tombol like, di-capture saat gesture.
  Offset? _heartBurstTarget;
  final GlobalKey _likeButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Seed shared FeedStore + subscribe — single source of truth untuk
    // like/comment sync antar screen. Detail screen yang juga listen ke
    // store akan auto-update kalau user toggle dari sini, dan sebaliknya.
    feedStore.seed([widget.post]);
    feedStore.addListener(_onFeedStoreChanged);
    // Gap #7: initialize _liked dari backend/store + local cache.
    // Kalau FeedStore sudah punya post, store/backend adalah source of
    // truth. Local cache hanya fallback awal agar launch offline tetap
    // terasa instant, dan tidak boleh membuat unlike terbaru tetap merah.
    _liked = widget.post.viewerLiked ||
        widget.post.isLiked ||
        (feedStore.get(widget.post.id) == null &&
            feedLocalStore.isLiked(widget.post.id));
    _likeCount = widget.post.likeCount;
    _commentCount = widget.post.commentCount;
    _shareCount = widget.post.shareCount;

    _heartBurstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.35, end: 1.42)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 34,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.42, end: 1.00)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.00, end: 0.82)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.82, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 26,
      ),
    ]).animate(_heartBurstController);
    _heartOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.0),
        weight: 38,
      ),
      TweenSequenceItem(
        tween:
            Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 37,
      ),
    ]).animate(_heartBurstController);
    // Terbang ke rail: mulai setelah pop (0.5) lalu melesat easeIn.
    _heartTravel = CurvedAnimation(
      parent: _heartBurstController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInCubic),
    );

    _commentSheetController.addListener(_syncCommentSheetProgress);

    // Pause deterministik saat app ke background — VisibilityDetector tidak
    // fire untuk lifecycle app, hanya untuk perubahan layout.
    WidgetsBinding.instance.addObserver(this);

    _adoptPreloadedController();
    _maybeInitVideo();
    _syncProductRotation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe RouteAware — pause pasti SEBELUM route lain menutup feed,
    // tidak lagi menunggu debounce VisibilityDetector (~500ms) yang
    // membiarkan dua video bersuara bersamaan (fix double-audio).
    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
  }

  // ── Pause/resume deterministik (route + app lifecycle) ──
  // _pausedByCover true HANYA kalau kita yang mem-pause karena tertutup —
  // supaya resume tidak menyalakan video yang memang di-pause user.
  bool _pausedByCover = false;

  void _pauseForCover() {
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (!ctrl.value.isPlaying) return;
    _pausedByCover = true;
    ctrl.pause();
  }

  void _resumeFromCover() {
    if (!_pausedByCover) return;
    _pausedByCover = false;
    if (!mounted || !widget.isActive) return;
    if (_isPaused || !_shouldAutoplay) return;
    _videoController?.play();
  }

  @override
  void didPushNext() {
    // Halaman penuh menutup feed → pause. Sheet/dialog transparan (mis.
    // sheet produk) TIDAK mem-pause — video tetap jalan di baliknya (ala
    // TikTok/IG) dan tidak ada konflik audio dari sheet.
    if (lastPushedRouteIsOpaque()) {
      _pauseForCover();
    }
  }

  @override
  void didPopNext() {
    _resumeFromCover();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _pauseForCover();
      case AppLifecycleState.resumed:
        _resumeFromCover();
      case AppLifecycleState.detached:
        break;
    }
  }

  bool get _dataSaverEnabled =>
      appSettingsStore.feedVideoQuality == 'data_saver';

  bool get _shouldAutoplay =>
      appSettingsStore.feedAutoplay && !_dataSaverEnabled;

  Future<void> _adoptPreloadedController() async {
    final controller = widget.preloadedController;
    if (controller == null) {
      // RACE FIX: post jadi aktif sebelum preload MP4 selesai — controller
      // belum masuk map (baru di-add di .then initialize), tapi wrapper
      // in-flight SUDAH ter-remove dari map oleh itemBuilder dan sampai ke
      // sini. Dulu wrapper ini dibiarkan → VideoPlayerController native
      // bocor (tidak pernah dispose). Sekarang: dispose begitu init-nya
      // settle; _maybeInitVideo lanjut bikin controller fresh.
      final orphan = widget.preloadedCachedPlayer;
      if (orphan != null) {
        Future(() async {
          try {
            await orphan.dispose();
          } catch (_) {}
        });
      }
      return;
    }
    _videoController = controller;
    // Adopt wrapper juga supaya child bisa dispose properly. Wrapper
    // might be null (legacy or unwrapped). Either way, controller-level
    // ops tetap work.
    _cachedPlayer = widget.preloadedCachedPlayer;
    controller.addListener(_handleVideoPositionForCta);
    // Preloaded controller selalu sudah initialize() — timer reset di sini
    // cuma untuk kasus defensif (controller mungkin dispose dari luar). Kalau
    // sudah initialized, helper-nya early-return tanpa schedule spinner.
    _resetLoadingSpinnerTimer();
    await controller.setVolume(appSettingsStore.feedMuted ? 0 : 1);
    if (widget.isActive && _shouldAutoplay) {
      await controller.play();
    }
    // HLS bisa ter-adopt SEBELUM initialize selesai (controller masuk map
    // sinkron, init jalan async). play()/setVolume di atas jadi no-op diam
    // → tanpa hook ini video stuck di poster sampai user interaksi.
    // Listener one-shot: begitu initialized, apply volume + play.
    if (!controller.value.isInitialized) {
      void onInit() {
        if (!controller.value.isInitialized) return;
        controller.removeListener(onInit);
        if (!mounted || _videoController != controller) return;
        controller.setVolume(appSettingsStore.feedMuted ? 0 : 1);
        if (widget.isActive && _shouldAutoplay && !_isPaused) {
          controller.play();
        }
        _cancelLoadingSpinnerDelay();
        if (mounted) setState(() {});
      }

      controller.addListener(onInit);
    }
    if (mounted) setState(() {});
  }

  /// Listener position video → trigger product CTA visibility.
  /// Dipanggil tiap frame video (puluhan kali/detik). Cepat-keluar untuk
  /// kondisi yang gak perlu re-render supaya gak ngabisin frame budget.
  ///
  /// Gaya TikTok Shop: kartu muncul SEKALI di detik ~4 (atau setengah
  /// durasi untuk video pendek) lalu MENETAP sampai user dismiss — tidak
  /// hilang saat loop. Pola lama (2.5 dtk terakhir tiap loop) tidak
  /// efektif: mayoritas penonton swipe sebelum video habis, dan 2.5 dtk
  /// tidak cukup untuk baca produk + harga.
  void _handleVideoPositionForCta() {
    final ctrl = _videoController;
    if (ctrl == null || !mounted) return;
    if (_endOfVideoCtaVisible || _endOfVideoCtaDismissed) return;
    final value = ctrl.value;
    if (!value.isInitialized) return;

    final durMs = value.duration.inMilliseconds;
    if (durMs <= 0) return;
    final posMs = value.position.inMilliseconds;

    // Trigger: min(4 dtk, setengah durasi) — video 5 dtk tetap dapat
    // kartu di ~2.5 dtk.
    final showAtMs = durMs ~/ 2 < 4000 ? durMs ~/ 2 : 4000;
    if (posMs < showAtMs) return;
    // Cek post punya tagged product yang valid sebelum trigger setState —
    // hindari render kosong.
    if (_rotatingProductsForPost(widget.post).isEmpty) return;
    setState(() => _endOfVideoCtaVisible = true);
  }

  void _dismissEndOfVideoCta() {
    if (!mounted) return;
    setState(() {
      _endOfVideoCtaVisible = false;
      _endOfVideoCtaDismissed = true;
    });
  }

  /// Reset spinner-delay timer setelah controller di-set atau di-swap. Kalau
  /// controller sudah initialized (preload sukses), spinner tidak diperlukan
  /// sama sekali — early return. Kalau belum, schedule spinner muncul 1200ms
  /// kemudian — kalau initialize keburu selesai sebelum timer fire,
  /// _cancelLoadingSpinnerDelay dipanggil dan spinner tidak pernah render.
  ///
  /// Delay 1200ms (sebelumnya 800ms) — match IG/TikTok pattern. Video load
  /// fast di 4G/WiFi (~500-1000ms), spinner sebelum 1200ms cuma bikin user
  /// anxious padahal video sebentar lagi siap. Kalau load >1.2 detik (4G
  /// marginal / 3G), baru spinner muncul sebagai genuine feedback.
  void _resetLoadingSpinnerTimer() {
    _loadingSpinnerDelay?.cancel();
    _loadingSpinnerDelay = null;
    if (_showLoadingSpinner) {
      _showLoadingSpinner = false;
    }
    final ctrl = _videoController;
    if (ctrl == null || ctrl.value.isInitialized || _videoLoadFailed) return;
    _loadingSpinnerDelay = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final c = _videoController;
      if (c == null || c.value.isInitialized || _videoLoadFailed) return;
      setState(() => _showLoadingSpinner = true);
    });
  }

  void _cancelLoadingSpinnerDelay() {
    _loadingSpinnerDelay?.cancel();
    _loadingSpinnerDelay = null;
    if (_showLoadingSpinner && mounted) {
      setState(() => _showLoadingSpinner = false);
    }
  }

  @override
  void didUpdateWidget(covariant FeedVideoPostView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        if (!_isPaused && _shouldAutoplay) {
          _videoController?.play();
        }
        _syncProductRotation();
      } else {
        _isPaused = false;
        _commentDrawerMounted = false;
        _commentSheetOpen = false;
        _commentAddedCount = 0;
        _featuredProductIndex = 0;
        _commentSheetClosingFromDrag = false;
        _commentDragOffset = 0;
        _commentSheetExtent.value = _commentSheetInitialExtent;
        // Reset CTA: user swipe ke post lain → next visit dapat fresh
        // chance (dismissed flag clear, visible flag clear).
        _endOfVideoCtaVisible = false;
        _endOfVideoCtaDismissed = false;
        // Panel caption ikut tertutup — post berikutnya mulai collapsed.
        _captionExpanded = false;
        // Reset long-press state (paused / 2x speed) + scrubber state.
        // Defensive — pastikan video tidak stuck di 2x atau paused saat
        // user swipe ke post lain di tengah long-press.
        _longPressPaused = false;
        _longPressSpeedActive = false;
        _hideOverlayForLongPress = false;
        _hideOverlayForPinchZoom = false;
        _isScrubbing = false;
        widget.onOverlayStateChanged(false);
        widget.onMediaZoomChanged(false);
        _videoController?.pause();
        try {
          _videoController?.setPlaybackSpeed(1.0);
        } catch (_) {}
        _videoController?.seekTo(Duration.zero);
        _stopProductRotation();
      }
    }
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.taggedProducts.length !=
            widget.post.taggedProducts.length) {
      _featuredProductIndex = 0;
      _endOfVideoCtaVisible = false;
      _endOfVideoCtaDismissed = false;
      _syncProductRotation();
    }
  }

  Future<void> _maybeInitVideo({bool userInitiated = false}) async {
    if (_videoController != null) return;
    final url = widget.post.videoUrl;
    if (url.isEmpty) return;
    if (_dataSaverEnabled && !userInitiated) return;
    setState(() => _videoLoadFailed = false);
    // Sprint 2 #7 — Network-aware quality rewrite + user preference.
    final resolvedUrl = videoQualityService.resolvePlaybackUrl(
      url,
      userPreference: appSettingsStore.feedVideoQuality,
    );
    final isHls = resolvedUrl.contains('.m3u8');

    // Attempt 1: pakai cached_video_player_plus wrapper kalau MP4
    // (repeat-view benefit). HLS bypass karena segments tidak ke-cache.
    final firstAttempt = await _tryInitVideoController(
      resolvedUrl: resolvedUrl,
      useCacheWrapper: !isHls,
      userInitiated: userInitiated,
    );
    if (firstAttempt || !mounted) return;

    // Attempt 2: bug recovery — cold-start setelah force-kill app kadang
    // bikin cache wrapper punya partial file (force-kill mid-write).
    // Wrapper baca SQLite entry "cached" → coba play dari local file
    // corrupt → init throw. Solusi: invalidate cache untuk URL ini lalu
    // re-init bypass wrapper (langsung network). Kalau ini juga gagal
    // baru declare _videoLoadFailed (real network/codec error).
    if (!isHls) {
      try {
        await DefaultCacheManager().removeFile(resolvedUrl);
      } catch (_) {
        // Ignore — cache entry mungkin tidak ada (race), retry tetap
        // worth dicoba dengan plain controller.
      }
    }
    final secondAttempt = await _tryInitVideoController(
      resolvedUrl: resolvedUrl,
      useCacheWrapper: false, // bypass wrapper di retry
      userInitiated: userInitiated,
    );
    if (secondAttempt || !mounted) return;

    setState(() => _videoLoadFailed = true);
  }

  /// Helper init satu attempt. Return true kalau sukses (controller
  /// ready & assigned ke _videoController), false kalau exception.
  /// Cleanup dispose dilakukan internal kalau gagal supaya caller tidak
  /// perlu handle leak.
  Future<bool> _tryInitVideoController({
    required String resolvedUrl,
    required bool useCacheWrapper,
    required bool userInitiated,
  }) async {
    CachedVideoPlayerPlus? wrapper;
    VideoPlayerController? controller;
    try {
      if (useCacheWrapper) {
        wrapper = CachedVideoPlayerPlus.networkUrl(
          Uri.parse(resolvedUrl),
          invalidateCacheIfOlderThan: const Duration(days: 7),
        );
        controller = wrapper.controller;
      } else {
        controller = VideoPlayerController.networkUrl(Uri.parse(resolvedUrl));
      }
      _cachedPlayer = wrapper;
      _resetLoadingSpinnerTimer();
      if (mounted) setState(() {});
      if (useCacheWrapper) {
        await wrapper!.initialize();
      } else {
        await controller.initialize();
      }
      if (!mounted) {
        if (wrapper != null) {
          await wrapper.dispose();
        } else {
          await controller.dispose();
        }
        _cachedPlayer = null;
        return true; // not failed, just unmounted; skip retry
      }
      _videoController = controller;
      controller.addListener(_handleVideoPositionForCta);
      _cancelLoadingSpinnerDelay();
      await controller.setLooping(true);
      await controller.setVolume(appSettingsStore.feedMuted ? 0 : 1);
      if (widget.isActive && (_shouldAutoplay || userInitiated)) {
        await controller.play();
      }
      _isPaused = !controller.value.isPlaying;
      setState(() {});
      return true;
    } catch (_) {
      _cancelLoadingSpinnerDelay();
      if (wrapper != null) {
        try {
          await wrapper.dispose();
        } catch (_) {}
      } else if (controller != null) {
        try {
          await controller.dispose();
        } catch (_) {}
      }
      _cachedPlayer = null;
      _videoController = null;
      return false;
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    feedStore.removeListener(_onFeedStoreChanged);
    _loadingSpinnerDelay?.cancel();
    _stopProductRotation();
    // Defensive: kalau widget unmount sebelum drawer close (mis. user
    // scroll ke post lain saat drawer open), cleanup back closer
    // supaya gak ghost ke widget yang udah dispose.
    popAndroidBackOverlayCloser(_androidBackCommentCloser);
    _commentSheetController.removeListener(_syncCommentSheetProgress);
    _commentSheetController.dispose();
    _commentSheetExtent.dispose();
    _videoController?.removeListener(_handleVideoPositionForCta);
    // Prefer dispose via wrapper — handle cache reference cleanup.
    // Wrapper.dispose() internally call controller.dispose() too, jadi
    // tidak perlu double-dispose. Kalau wrapper null (defensive), fallback
    // ke controller dispose direct.
    if (_cachedPlayer != null) {
      _cachedPlayer!.dispose();
      _cachedPlayer = null;
    } else {
      _videoController?.dispose();
    }
    _videoController = null;
    _heartBurstController.dispose();
    super.dispose();
  }

  void _syncCommentSheetProgress() {
    if (!_commentSheetController.isAttached) return;
    final hostHeight = _commentSheetHostHeight(context);
    final maxExtent = _commentSheetMaxExtentFor(hostHeight);
    final size = _commentSheetController.size;
    final extent = size.clamp(_commentSheetMinExtent, maxExtent).toDouble();
    if ((_commentSheetExtent.value - extent).abs() > 0.002) {
      _commentSheetExtent.value = extent;
    }
    if (_commentSheetOpen &&
        !_commentSheetClosingFromDrag &&
        size <= _commentSheetMinExtent + 0.012) {
      _commentSheetClosingFromDrag = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeComments();
      });
    }
  }

  double _commentSheetHostHeight(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return math.max(1.0, screenHeight - keyboardInset);
  }

  double _commentMinVideoHeightFor(double hostHeight) {
    return (hostHeight * 0.30).clamp(220.0, 280.0).toDouble();
  }

  double _commentSheetMaxExtentFor(double hostHeight) {
    final minVideoHeight = _commentMinVideoHeightFor(hostHeight);
    final extent = 1 - (minVideoHeight / math.max(1.0, hostHeight));
    return extent
        .clamp(_commentSheetInitialExtent, _commentSheetMaxExtentCap)
        .toDouble();
  }

  List<FeedProductLink> _rotatingProductsForPost(FeedPost post) {
    final maxProducts = post.author.isAdmin ? 5 : 3;
    // Pakai `taggedProducts` — itu yang backend return (lihat
    // lib/feed/queries.ts:208). Sebelumnya pakai `productsInVideo` yang
    // tidak pernah di-populate backend → product bar di atas nama user
    // tidak pernah muncul untuk admin post yang tag produk.
    // `productsInVideo` field tetap di model untuk future use kalau ada
    // timed product feature (produk muncul di detik tertentu video).
    return post.taggedProducts.take(maxProducts).toList();
  }

  void _syncProductRotation() {
    _stopProductRotation();
    final products = _rotatingProductsForPost(widget.post);
    if (!widget.isActive || products.length <= 1) return;
    _productRotationTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) {
        if (!mounted || !widget.isActive) return;
        setState(() {
          _featuredProductIndex = (_featuredProductIndex + 1) % products.length;
        });
      },
    );
  }

  void _stopProductRotation() {
    _productRotationTimer?.cancel();
    _productRotationTimer = null;
  }

  /// Sync local mirror dari shared FeedStore. Dipanggil saat store
  /// notify (toggle dari Detail/Profile screen yang lain juga update
  /// store → kita ikut rebuild).
  void _onFeedStoreChanged() {
    if (!mounted) return;
    final fresh = feedStore.get(widget.post.id);
    if (fresh == null) return;
    final newLiked = fresh.viewerLiked || fresh.isLiked;
    if (newLiked == _liked &&
        fresh.likeCount == _likeCount &&
        fresh.commentCount == _commentCount &&
        fresh.shareCount == _shareCount) {
      return;
    }
    setState(() {
      _liked = newLiked;
      _likeCount = fresh.likeCount;
      _commentCount = fresh.commentCount;
      _shareCount = fresh.shareCount;
    });
  }

  Future<void> _onLikePressed() async {
    // TANPA busy-guard — tiap tap langsung diteruskan ke store yang flip
    // UI optimistis instan + coalesce request (intent terakhir menang).
    // Dulu guard di sini menelan tap selama request jalan → unlike harus
    // ditekan berkali-kali di jaringan lambat.
    AppHaptics.impact();
    try {
      final result = await feedStore.toggleLike(widget.post.id);
      // Sync ke FeedLocalStore (SharedPreferences) supaya next launch
      // reflect liked state instant.
      feedLocalStore.setLiked(widget.post.id, result.liked);
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        // BUG FIX: kalau backend reject 401 padahal client kira logged-in
        // (zombie session — user.id tidak ada di DB / token expired), JANGAN
        // langsung push login. Clear local cache dulu via logout() supaya
        // memberStore.isLoggedIn = false → halaman lain auto-respond.
        // Tanpa ini, user di-redirect ke login tapi cache "logged in" tetap,
        // jadi looping.
        if (memberStore.isLoggedIn) {
          await memberStore.logout();
        }
        if (!mounted) return;
        Navigator.pushNamed(context, '/member/login');
      } else {
        AppToast.show(
          context,
          error is ApiException && error.statusCode == 404
              ? 'Postingan tidak tersedia.'
              : 'Like belum tersimpan. Coba lagi.',
          kind: ToastKind.warning,
        );
      }
    }
  }

  /// Double-tap → like (kalau belum) + heart burst di posisi jari.
  /// Instagram Reels signature gesture.
  void _rememberHeartBurstPosition(TapDownDetails details) {
    _heartBurstPosition = details.localPosition;
  }

  /// Pusat tombol like rail dalam koordinat ~global (Stack mengisi layar
  /// dari 0,0), untuk target "terbang ke rail". Null kalau belum ter-render.
  Offset? _resolveLikeCenter() {
    final box = _likeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _onDoubleTapLike() {
    if (!_liked) {
      _onLikePressed();
    } else {
      AppHaptics.impact();
    }
    _heartBurstTarget = _resolveLikeCenter();
    _heartBurstController.forward(from: 0);
  }

  Future<void> _onComment() async {
    if (_commentDrawerMounted) return;
    AppHaptics.tap();
    FocusScope.of(context).unfocus();
    widget.onOverlayStateChanged(true);
    // Register closer ke Android back coordinator — Samsung Back press
    // di MainNavigationScreen akan call ini DULU sebelum tab nav /
    // double-back exit. Closer dipanggil ulang via _closeComments,
    // sehingga state UI + back stack sync.
    pushAndroidBackOverlayCloser(_androidBackCommentCloser);
    setState(() {
      _commentDrawerMounted = true;
      _commentAddedCount = 0;
      _commentSheetClosingFromDrag = false;
      _commentDragOffset = 0;
      // Panel caption tertutup saat komentar dibuka — dua panel baca
      // tidak boleh tumpang tindih.
      _captionExpanded = false;
    });
    _commentSheetExtent.value = _commentSheetInitialExtent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_commentDrawerMounted) return;
      if (_commentSheetController.isAttached) {
        _commentSheetController.jumpTo(_commentSheetInitialExtent);
      }
      setState(() => _commentSheetOpen = true);
    });
  }

  /// Stable reference closer untuk Android back coordinator. Method
  /// (bukan variable assignment ke lambda) supaya consistent reference
  /// + lint-clean. Identitas reference match via tear-off di push/pop.
  void _androidBackCommentCloser() {
    if (_commentDrawerMounted) _closeComments();
  }

  void _closeComments([int addedCount = 0]) {
    if (!_commentDrawerMounted) return;
    FocusScope.of(context).unfocus();
    AppHaptics.tap();
    // Cleanup Android back closer reference — defensive double-pop
    // dilindungi oleh identical() check di popAndroidBackOverlayCloser.
    // Aman dipanggil walau closer udah ke-consume oleh back press
    // (consumeAndroidBackOverlay sudah removeLast SEBELUM call closer).
    popAndroidBackOverlayCloser(_androidBackCommentCloser);
    final countDelta = math.max(addedCount, _commentAddedCount);
    if (countDelta > 0) {
      // Propagasi ke FeedStore — semua screen lain (Detail / Public
      // Profile / Postingan Saya) yang baca count dari store ikut update.
      // Local _commentCount field auto-update via _onFeedStoreChanged.
      final base = feedStore.get(widget.post.id)?.commentCount ?? _commentCount;
      feedStore.setCommentCount(widget.post.id, base + countDelta);
    }
    setState(() {
      _commentSheetOpen = false;
      _commentAddedCount = 0;
      _commentDragOffset = 0;
    });
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (!mounted || _commentSheetOpen) return;
      _commentSheetExtent.value = _commentSheetInitialExtent;
      _commentSheetClosingFromDrag = false;
      if (_commentSheetController.isAttached) {
        _commentSheetController.jumpTo(_commentSheetInitialExtent);
      }
      setState(() => _commentDrawerMounted = false);
      widget.onOverlayStateChanged(false);
    });
  }

  void _onCommentDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (!_commentSheetController.isAttached || delta == 0) return;
    final screenHeight = math.max(1.0, MediaQuery.sizeOf(context).height);
    final maxExtent =
        _commentSheetMaxExtentFor(_commentSheetHostHeight(context));
    final nextSize = (_commentSheetController.size - (delta / screenHeight))
        .clamp(_commentSheetMinExtent, maxExtent)
        .toDouble();
    _commentSheetController.jumpTo(nextSize);
  }

  void _onCommentDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final size = _commentSheetController.isAttached
        ? _commentSheetController.size
        : _commentSheetInitialExtent;
    final maxExtent =
        _commentSheetMaxExtentFor(_commentSheetHostHeight(context));
    if (velocity > 520 || size <= _commentSheetDismissExtent) {
      _closeComments();
      return;
    }
    final expandThreshold = (_commentSheetInitialExtent + maxExtent) / 2;
    final target =
        size >= expandThreshold ? maxExtent : _commentSheetInitialExtent;
    _commentSheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// Open moderation actions sheet (Report / Block).
  ///
  /// Wajib ada per Google Play UGC policy — see [moderation_action_sheet.dart]
  /// untuk rasionalnya. Setelah block, kirim signal ke parent supaya
  /// post dari user yang baru di-block langsung hilang dari feed (pakai
  /// notifyListeners dari [blockService] yang di-listen di FeedScreen).
  Future<void> _onMoreActions() async {
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    final post = widget.post;
    await showModerationActions(
      context,
      targetKind: ReportTargetKind.feedPost,
      targetId: post.id,
      authorId: post.author.id,
      authorName:
          post.author.isOfficialAccount ? null : post.author.displayName,
      allowBlock: !post.author.isOfficialAccount,
      useFeedStyle: true,
    );
    if (mounted) widget.onOverlayStateChanged(false);
  }

  Future<void> _onShare() async {
    AppHaptics.tap();
    final url =
        '${ApiConfig.publicSiteUrl}/feed/${Uri.encodeComponent(widget.post.id)}';
    final caption = widget.post.title.isNotEmpty
        ? '${widget.post.title}\n$url'
        : 'Lihat di Natalo Petshop:\n$url';
    final box = context.findRenderObject() as RenderBox?;
    try {
      await Share.share(
        caption,
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
      if (!mounted) return;
      setState(() => _shareCount += 1);
      await feedService.trackShare(widget.post.id);
    } catch (_) {}
  }

  void _openCart({bool fromFeed = false}) {
    AppHaptics.tap();
    Navigator.pushNamed(
      context,
      '/cart',
      arguments: fromFeed ? const {'origin': 'feed'} : null,
    );
  }

  /// Sprint 3 #10 — Cinema mode fullscreen native player.
  ///
  /// Push fullscreen route dengan VideoPlayer yang re-attach ke controller
  /// existing — playback state (currentTime, volume, looping) preserved.
  /// User dapat AVPlayer-style fullscreen experience tanpa kehilangan
  /// position playback saat balik ke feed.
  ///
  /// iOS: AVPlayer di-render native via video_player package — sudah
  /// support gesture native, scrubbing, AirPlay button (kalau enabled
  /// di Info.plist).
  // ignore: unused_element
  Future<void> _openCinemaMode() async {
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    // Pause feed video selama fullscreen open — restore saat user balik.
    // Hindari double-playback (audio overlap dari 2 controller).
    final wasPlaying = ctrl.value.isPlaying;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenVideoPage(controller: ctrl),
        fullscreenDialog: true,
      ),
    );
    widget.onOverlayStateChanged(false);
    if (mounted && wasPlaying && !ctrl.value.isPlaying) {
      // Restore playback kalau user pause di fullscreen lalu close.
      ctrl.play();
    }
  }

  Future<void> _openFeedCartSheet() async {
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => _FeedCartSheet(
        onOpenFullCart: () {
          Navigator.of(sheetContext).pop();
          _openCart(fromFeed: true);
        },
      ),
    ).whenComplete(() => widget.onOverlayStateChanged(false));
  }

  Future<void> _onProductsTap(List<FeedProductLink> products) async {
    if (products.isEmpty) {
      await _openFeedCartSheet();
      return;
    }
    if (products.length == 1) {
      await _onProductTap(products.first);
      return;
    }
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => FeedPostTaggedProductsSheet(
        products: products,
        onOpenProduct: (link) async {
          await _onProductTap(link);
        },
        onAdd: (link, quantity) async {
          _addFeedLinkToCart(link, quantity: quantity);
        },
        onBuy: (link, quantity) async {
          _buyFeedLinkNow(link, quantity: quantity);
        },
      ),
    ).whenComplete(() => widget.onOverlayStateChanged(false));
  }

  Future<void> _quickAddProduct(FeedProductLink link) async {
    _addFeedLinkToCart(link);
  }

  void _addFeedLinkToCart(
    FeedProductLink link, {
    int quantity = 1,
  }) {
    if (!link.isAvailable || link.stock <= 0) {
      _showProductUnavailable();
      return;
    }

    if (link.hasVariants) {
      _onProductTap(link);
      return;
    }

    final product = feedPostProductFromFeedLink(link);
    cartStore.addProduct(product, quantity: quantity);
    if (!mounted) return;
    AppToast.showCartAdded(
      context,
      quantity > 1
          ? '$quantity x ${link.name} masuk keranjang'
          : '${link.name} masuk keranjang',
    );
  }

  void _buyFeedLinkNow(
    FeedProductLink link, {
    int quantity = 1,
  }) {
    if (!link.isAvailable || link.stock <= 0) {
      _showProductUnavailable();
      return;
    }

    if (link.hasVariants) {
      _onProductTap(link);
      return;
    }

    _buyProductNow(feedPostProductFromFeedLink(link), quantity: quantity);
  }

  Future<void> _onProductTap(FeedProductLink link) async {
    AppHaptics.tap();
    widget.onOverlayStateChanged(true);
    final product = await productService.fetchProductBySlug(link.slug);
    if (!mounted) {
      widget.onOverlayStateChanged(false);
      return;
    }
    if (product == null) {
      widget.onOverlayStateChanged(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produk tidak ditemukan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => FeedPostProductSheet(
        product: product,
        onOpenProduct: () => _openProductDetail(product),
        onAdd: (quantity) => _addProductToCart(product, quantity: quantity),
        onBuy: (quantity) => _buyProductNow(product, quantity: quantity),
      ),
    ).whenComplete(() => widget.onOverlayStateChanged(false));
  }

  void _openProductDetail(Product product) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/product-detail', arguments: product);
  }

  void _addProductToCart(
    Product product, {
    int quantity = 1,
  }) {
    if (product.stock <= 0) {
      _showProductUnavailable();
      return;
    }
    if (product.hasVariants) {
      _openProductDetail(product);
      return;
    }
    cartStore.addProduct(product, quantity: quantity);
    if (!mounted) return;
    AppToast.showCartAdded(
      context,
      quantity > 1
          ? '$quantity x ${product.title} masuk keranjang'
          : '${product.title} masuk keranjang',
    );
  }

  void _buyProductNow(
    Product product, {
    int quantity = 1,
  }) {
    if (product.stock <= 0) {
      _showProductUnavailable();
      return;
    }
    if (product.hasVariants) {
      _openProductDetail(product);
      return;
    }
    AppHaptics.impact();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(
          items: [
            CartItem(
              product: product,
              quantity: quantity.clamp(1, math.max(1, product.stock)),
            ),
          ],
        ),
      ),
    );
  }

  void _showProductUnavailable() {
    AppToast.show(
      context,
      'Produk sedang tidak tersedia.',
      kind: ToastKind.warning,
    );
  }

  Future<void> _onTapMedia() async {
    final ctrl = _videoController;
    if (ctrl == null) {
      await _maybeInitVideo(userInitiated: true);
      if (mounted) setState(() => _isPaused = false);
      return;
    }
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      setState(() => _isPaused = true);
    } else {
      ctrl.play();
      setState(() => _isPaused = false);
    }
  }

  /// Long-press gesture with 3-zone behavior (TikTok/IG Reels signature):
  ///   - Left third  → temporary 2x speed
  ///   - Center third → temporary pause (existing behavior)
  ///   - Right third → temporary 2x speed
  ///
  /// Zone detection via `LongPressStartDetails.localPosition.dx` /
  /// container width. State direset di `_onLongPressEnd` regardless of
  /// zone. Hide overlay tetap aktif untuk semua zone supaya feels native.
  ///
  /// Scrubber guard: kalau `_isScrubbing` true (user lagi drag progress
  /// bar), long-press di-skip — scrubber pegang gesture priority.
  bool _longPressPaused = false;
  bool _longPressSpeedActive = false;
  bool _hideOverlayForLongPress = false;
  bool _hideOverlayForPinchZoom = false;
  // Last-known media area width (set di build LayoutBuilder). Dipakai
  // untuk hitung zone dari localPosition.dx. Default screen width — akan
  // di-update ke real value saat build pertama.
  double _mediaAreaWidth = 0;

  /// Scrubber state — true saat user lagi drag/tap progress bar.
  /// Disable long-press handler supaya gesture tidak conflict.
  bool _isScrubbing = false;

  void _onMediaZoomChanged(bool zooming) {
    if (!mounted || _hideOverlayForPinchZoom == zooming) return;
    setState(() => _hideOverlayForPinchZoom = zooming);
    widget.onMediaZoomChanged(zooming);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_isScrubbing) return; // Scrubber priority
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    // Zone detection: 0-0.4 = left, 0.4-0.6 = center, 0.6-1.0 = right.
    // Center zone dibuat lebih kecil supaya 2x speed lebih mudah
    // di-trigger (zona kiri/kanan luas).
    final width = _mediaAreaWidth > 0
        ? _mediaAreaWidth
        : MediaQuery.of(context).size.width;
    final ratio = (details.localPosition.dx / width).clamp(0.0, 1.0);
    final isCenterZone = ratio >= 0.4 && ratio <= 0.6;

    if (isCenterZone) {
      // Center: pause-while-held (existing behavior).
      if (!ctrl.value.isPlaying) return; // Hanya kalau playing
      AppHaptics.impact();
      ctrl.pause();
      setState(() {
        _longPressPaused = true;
        _hideOverlayForLongPress = true;
      });
    } else {
      // Left or right: 2x speed-while-held.
      if (!ctrl.value.isPlaying) return; // Hanya kalau playing
      AppHaptics.impact();
      ctrl.setPlaybackSpeed(2.0);
      setState(() {
        _longPressSpeedActive = true;
        _hideOverlayForLongPress = true;
      });
    }
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    final ctrl = _videoController;
    if (_longPressPaused) {
      setState(() {
        _longPressPaused = false;
        _hideOverlayForLongPress = false;
      });
      if (ctrl != null && !_isPaused) {
        // Resume cuma kalau user tidak previously tap-paused juga.
        ctrl.play();
      }
    } else if (_longPressSpeedActive) {
      setState(() {
        _longPressSpeedActive = false;
        _hideOverlayForLongPress = false;
      });
      // Reset speed ke 1.0 + force position resync. AVPlayer di iOS
      // (dan kemungkinan ExoPlayer di Android) drift internal time
      // tracking setelah rate change → release ke 1.0 = position
      // reporter "lompat" ke posisi yang dia hitung based on
      // rate × elapsed, sementara visible frame ketinggalan. Player
      // resync visible → keliatan LONCAT.
      //
      // Fix: capture position SEBELUM rate change, set 1.0, seek
      // explicit ke captured position. Force player re-sync internal
      // time tracking ke actual rendered frame. SeekTo ke posisi
      // yang frame-nya masih di buffer (sama persis) biasanya
      // instant — no visible decode delay.
      // Defensive try-catch — controller bisa di-dispose tengah
      // jalan (mis. user swipe ke post lain saat masih long-press).
      try {
        final pos = ctrl?.value.position;
        ctrl?.setPlaybackSpeed(1.0);
        if (pos != null && ctrl != null && ctrl.value.isInitialized) {
          await ctrl.seekTo(pos);
        }
      } catch (_) {}
    }
  }

  Future<void> _toggleMuteWhilePaused() async {
    final ctrl = _videoController;
    if (ctrl == null || !_isPaused) return;
    AppHaptics.tap();
    final nextMuted = !appSettingsStore.feedMuted;
    await appSettingsStore.setFeedMuted(nextMuted);
    await ctrl.setVolume(nextMuted ? 0 : 1);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final products = _rotatingProductsForPost(post);
    final featuredProduct = products.isEmpty
        ? null
        : products[_featuredProductIndex % products.length];
    return VisibilityDetector(
      key: ValueKey('feed-post-${post.id}'),
      onVisibilityChanged: (info) {
        final ctrl = _videoController;
        if (!mounted) return;
        // Gap #3: track view event saat post >50% visible + active.
        // Debounced via FeedLocalStore.hasViewedThisSession — no
        // double-count saat user swipe back/forth ke post sama.
        if (info.visibleFraction > 0.5 &&
            widget.isActive &&
            !feedLocalStore.hasViewedThisSession(post.id)) {
          feedLocalStore.markViewedThisSession(post.id);
          // Fire-and-forget — analytics non-critical, jangan await.
          feedService.trackView(post.id);
        }
        if (ctrl == null) return;
        if (info.visibleFraction > 0.7 && widget.isActive && _shouldAutoplay) {
          if (!ctrl.value.isPlaying && !_isPaused) ctrl.play();
        } else {
          ctrl.pause();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          final commentSheetHostHeight =
              math.max(1.0, constraints.biggest.height - keyboard);
          final commentSheetMaxExtent =
              _commentSheetMaxExtentFor(commentSheetHostHeight);
          // Cache media area width untuk zone detection di long-press
          // handler (left/center/right 2x speed vs pause).
          _mediaAreaWidth = constraints.maxWidth;
          // MediaQuery.padding.bottom SUDAH mencakup tinggi nav
          // (extendBody) — lihat feedPostOverlayBaseInset. Jangan tambah
          // kFloatingNavClearance (dulu ditambah → jarak dobel).
          final navClearance = feedPostOverlayBaseInset(context);
          // Stack bawah rapat ala IG Reels (bawah → atas):
          //   nav → rail durasi (bottom: navClearance) → caption → nama.
          // Scrubber box 28px (hit-area), visual line 2px di DASAR box →
          // line duduk tepat di atas floating nav.
          //
          // Caption + rail pakai anchor BERSAMA feedPostOverlayBottomGap —
          // SAMA dengan foto carousel (jangan bedakan foto vs video).
          // Dulu video +32 (di atas seluruh box scrubber) → melayang jauh
          // di atas garis progress, beda 28px dari foto. Sekarang overlap
          // 12px ke atas hit-area scrub (zona transparan) — sisa 16px +
          // area garis tetap bisa di-scrub, persis kompromi IG.
          final feedInfoInset = navClearance + feedPostOverlayBottomGap;
          final actionRailInset = navClearance + feedPostOverlayBottomGap;
          final minimized = _commentSheetOpen;

          return ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_commentDrawerMounted)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_commentSheetOpen,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _closeComments,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          color: Colors.black.withValues(
                            alpha: _commentSheetOpen ? 0.72 : 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_commentDrawerMounted)
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    offset:
                        _commentSheetOpen ? Offset.zero : const Offset(0, 1),
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.only(bottom: keyboard),
                      child: DraggableScrollableSheet(
                        controller: _commentSheetController,
                        initialChildSize: FeedCommentSheet.reelsHeightFactor,
                        minChildSize: _commentSheetMinExtent,
                        maxChildSize: commentSheetMaxExtent,
                        snap: false,
                        builder: (context, scrollController) {
                          return FeedCommentSheet(
                            post: widget.post,
                            applyKeyboardInset: false,
                            sheetScrollController: scrollController,
                            onClose: _closeComments,
                            onAddedCountChanged: (count) {
                              _commentAddedCount = count;
                            },
                            onDragUpdate: _onCommentDragUpdate,
                            onDragEnd: _onCommentDragEnd,
                          );
                        },
                      ),
                    ),
                  ),
                _CommentVideoFrame(
                  open: minimized,
                  extentListenable: _commentSheetExtent,
                  dragOffsetPx: _commentDragOffset,
                  keyboardInsetPx: keyboard,
                  screenSize: constraints.biggest,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ── Background: video atau thumbnail ──
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: _onTapMedia,
                          onDoubleTapDown: _rememberHeartBurstPosition,
                          onDoubleTap: _onDoubleTapLike,
                          // Sprint 4 #1 — Long-press signature gesture.
                          onLongPressStart: _onLongPressStart,
                          onLongPressEnd: _onLongPressEnd,
                          child: FeedPostSnapBackZoomMedia(
                            minScale: 1,
                            maxScale: 4,
                            onZoomingChanged: _onMediaZoomChanged,
                            child: _MediaBackground(
                              post: post,
                              videoController: _videoController,
                              compactPreview: _commentDrawerMounted,
                            ),
                          ),
                        ),
                      ),
                      if (_videoLoadFailed)
                        Positioned.fill(
                          child: Center(
                            child: _VideoRetryButton(onRetry: _maybeInitVideo),
                          ),
                        ),
                      // Spinner hanya muncul kalau video belum ready DAN
                      // sudah lewat 800ms grace period (lihat
                      // _resetLoadingSpinnerTimer). Kalau initialize selesai
                      // < 800ms, spinner tidak pernah render → perceived
                      // instant. Thumbnail dari _MediaBackground tetap
                      // visible di atas background hitam selama itu.
                      if (_showLoadingSpinner &&
                          _videoController != null &&
                          !_videoController!.value.isInitialized &&
                          !_videoLoadFailed)
                        Positioned.fill(
                          child: Center(
                            child: SizedBox(
                              height: 26,
                              width: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                            ),
                          ),
                        ),
                      // ── Heart burst double-tap — MERAH, muncul di titik
                      // jari lalu terbang mengecil ke tombol like rail ──
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _heartBurstController,
                            builder: (context, _) =>
                                feedPostBuildFlyingBurstHeart(
                              tap: _heartBurstPosition,
                              target: _heartBurstTarget,
                              scale: _heartScale.value,
                              opacity: _heartOpacity.value,
                              travel: _heartTravel.value,
                              screenSize: MediaQuery.sizeOf(context),
                            ),
                          ),
                        ),
                      ),
                      // Play + volume controls hide saat:
                      // 1. Comment drawer open (mode preview minimized)
                      // 2. Cinema/fullscreen mode (irrelevant — handled
                      //    di Cinema screen sendiri)
                      // Per user spec: play button besar tidak boleh
                      // muncul di video preview saat comment drawer aktif.
                      if (_isPaused &&
                          _videoController != null &&
                          !minimized &&
                          !_commentSheetOpen)
                        Center(
                          child: _PausedVideoControls(
                            muted: appSettingsStore.feedMuted,
                            onToggleMute: _toggleMuteWhilePaused,
                            onTogglePlayPause: _onTapMedia,
                          ),
                        ),
                      if (!minimized) ...[
                        // Fullscreen button di-hapus per user spec — tidak
                        // perlu, bikin UI Reels feels cluttered. Video
                        // tetap fullscreen vertical default. Cinema mode
                        // (kalau perlu nanti) bisa di-trigger lewat
                        // long-press atau gesture, bukan dedicated button.
                        // ── Bottom gradient untuk text readability ──
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: FeedPostScrim(),
                          ),
                        ),
                        // ── Scrim panel caption (mode baca ala IG) ──
                        // Saat caption expand: gradien gelap naik menutupi
                        // ~2/3 bawah layar supaya teks putih terbaca di atas
                        // video terang; tap di mana pun area ini menutup
                        // panel. Saat tertutup: sepenuhnya tembus sentuhan.
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: !_captionExpanded,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _setCaptionExpanded(false),
                              child: AnimatedOpacity(
                                opacity: _captionExpanded ? 1 : 0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.30),
                                        Colors.black.withValues(alpha: 0.66),
                                        Colors.black.withValues(alpha: 0.72),
                                      ],
                                      stops: const [0.18, 0.40, 0.72, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_videoController != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: navClearance,
                            child: FeedVideoScrubber(
                              controller: _videoController!,
                              isCurrent: widget.isActive,
                              onScrubbingChanged: (scrubbing) {
                                if (!mounted) return;
                                setState(() => _isScrubbing = scrubbing);
                              },
                            ),
                          ),
                        // ── Right action column (Reels-style: tight + minimal) ──
                        // Sprint 4 #1 — Hide overlays selama long-press
                        // supaya user dapat clean view sementara hold.
                        // Action rail hide saat comment drawer open + saat
                        // long-press. Per user spec: video preview clean,
                        // tidak ada actions yang mengganggu.
                        Positioned(
                          right: feedPostActionRailRightInset,
                          bottom: actionRailInset,
                          child: AnimatedOpacity(
                            opacity: (_hideOverlayForLongPress ||
                                    _hideOverlayForPinchZoom ||
                                    _commentSheetOpen)
                                ? 0
                                : 1,
                            duration: const Duration(milliseconds: 200),
                            child: IgnorePointer(
                              ignoring: _hideOverlayForLongPress ||
                                  _hideOverlayForPinchZoom ||
                                  _commentSheetOpen,
                              // Cart di rail DIHAPUS — duplikat dengan cart
                              // kanan-atas (satu-satunya pintu keranjang di
                              // feed sekarang).
                              child: FeedActionRail(
                                likeKey: _likeButtonKey,
                                likeCount: _likeCount,
                                liked: _liked,
                                commentCount: _commentCount,
                                shareCount: _shareCount,
                                onLike: _onLikePressed,
                                onComment: _onComment,
                                onShare: _onShare,
                                onMore: _onMoreActions,
                              ),
                            ),
                          ),
                        ),
                        // ── Bottom info: commerce group + creator + caption ──
                        // Same AnimatedOpacity wrapper untuk hide saat long-press.
                        Positioned(
                          left: 16,
                          right: 78,
                          bottom: feedInfoInset,
                          child: AnimatedOpacity(
                            opacity: (_hideOverlayForLongPress ||
                                    _hideOverlayForPinchZoom)
                                ? 0
                                : 1,
                            duration: const Duration(milliseconds: 150),
                            child: IgnorePointer(
                              ignoring: _hideOverlayForLongPress ||
                                  _hideOverlayForPinchZoom,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (products.isNotEmpty)
                                    // Pill produk "tenggelam ke belakang
                                    // caption" saat panel naik: tinggi
                                    // mengempis (AnimatedAlign heightFactor)
                                    // + fade-out + turun tipis, serempak
                                    // dengan scrim; muncul kembali saat
                                    // panel diturunkan.
                                    ClipRect(
                                      child: AnimatedAlign(
                                        alignment: Alignment.bottomLeft,
                                        heightFactor: _captionExpanded ? 0 : 1,
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                        child: AnimatedSlide(
                                          offset: _captionExpanded
                                              ? const Offset(0, 0.12)
                                              : Offset.zero,
                                          duration:
                                              const Duration(milliseconds: 300),
                                          curve: Curves.easeOutCubic,
                                          child: AnimatedOpacity(
                                            opacity: _captionExpanded ? 0 : 1,
                                            duration: const Duration(
                                                milliseconds: 220),
                                            curve: Curves.easeOut,
                                            child: IgnorePointer(
                                              ignoring: _captionExpanded,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 12),
                                                child:
                                                    _ProductCommerceOverlayGroup(
                                                  featuredProduct:
                                                      featuredProduct!,
                                                  showProductCard:
                                                      _endOfVideoCtaVisible &&
                                                          !_commentSheetOpen,
                                                  onTap: () =>
                                                      _onProductsTap(products),
                                                  onBuy: () => _quickAddProduct(
                                                      featuredProduct),
                                                  onQuickAdd: () =>
                                                      _quickAddProduct(
                                                          featuredProduct),
                                                  onDismiss:
                                                      _dismissEndOfVideoCta,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  FeedPostCreatorIdentity(
                                    author: post.author,
                                    displayName: post.author.displayHandle,
                                  ),
                                  const SizedBox(height: 7),
                                  FeedExpandableCaption(
                                    text: post.caption ?? '',
                                    createdAt: post.createdAt,
                                    expanded: _captionExpanded,
                                    onExpandedChanged: _setCaptionExpanded,
                                    onMentionTap: (handle) =>
                                        Navigator.of(context).pushNamed(
                                      '/u',
                                      arguments: handle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommentVideoFrame extends StatelessWidget {
  final bool open;
  final ValueListenable<double> extentListenable;
  final double dragOffsetPx;
  final double keyboardInsetPx;
  final Size screenSize;
  final Widget child;

  const _CommentVideoFrame({
    required this.open,
    required this.extentListenable,
    required this.dragOffsetPx,
    required this.keyboardInsetPx,
    required this.screenSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final width = math.max(1.0, screenSize.width);
    final height = math.max(1.0, screenSize.height);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: open ? 1 : 0),
      duration: Duration(milliseconds: open ? 260 : 220),
      curve: open ? Curves.easeOutCubic : Curves.easeInOutCubic,
      child: RepaintBoundary(child: child),
      builder: (context, openProgress, child) {
        return ValueListenableBuilder<double>(
          valueListenable: extentListenable,
          child: child,
          builder: (context, sheetExtent, child) {
            // Pattern linked motion: video FILLS area di atas drawer,
            // bukan floating rounded preview card. Saat drawer grow ke
            // atas, video shrink vertically dari bawah. Saat drawer drag
            // ke bawah, video expand lagi. Width selalu full screen.
            //
            // Drawer extent berasal langsung dari DraggableScrollableSheet.
            // Ini membuat video dan drawer bergerak 1:1 saat user drag,
            // termasuk saat sheet berada di bawah initial extent.
            final drawerExtent = sheetExtent.clamp(0.0, 1.0).toDouble();
            // Saat keyboard terbuka, comment drawer di-layout dalam area yang
            // sudah dikurangi bottom inset oleh AnimatedPadding. Video frame
            // harus memakai tinggi efektif yang sama, kalau tidak sheet naik
            // tetapi video tetap menimpa bagian atas drawer.
            final keyboardInset =
                keyboardInsetPx.clamp(0.0, height - 1).toDouble();
            final sheetHostHeight = math.max(1.0, height - keyboardInset);
            final drawerTopY =
                sheetHostHeight * (1 - drawerExtent) + dragOffsetPx;
            final fullRect = Rect.fromLTWH(0, 0, width, height);
            // Video frame saat drawer open: full width, dari y=0 sampai
            // drawer's top edge. Animasi rect interpolate dari fullscreen
            // ke aboveDrawer rect.
            final aboveDrawerRect = Rect.fromLTWH(
              0,
              0,
              width,
              drawerTopY.clamp(0.0, height),
            );
            final rect = Rect.lerp(fullRect, aboveDrawerRect, openProgress)!;
            final bottomRadius = 22.0 * openProgress;
            return Positioned.fromRect(
              rect: rect,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Colors.black),
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(bottomRadius),
                    bottomRight: Radius.circular(bottomRadius),
                  ),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Colors.black),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Menjembatani state reaktif (memberStore + followOverrides + follow
/// service) dengan widget bersama `FeedCreatorIdentity`
/// (features/feed/widgets/feed_creator_overlay.dart) — tetap di
/// feed_screen.dart karena terikat langsung ke model FeedAuthor & service
/// layer, bukan bagian widget presentasional yang di-share.

class _MediaBackground extends StatelessWidget {
  final FeedPost post;
  final VideoPlayerController? videoController;
  final bool compactPreview;

  const _MediaBackground({
    required this.post,
    required this.videoController,
    this.compactPreview = false,
  });

  /// Aturan fit ala IG Reels: full-bleed cover HANYA kalau crop-nya tipis
  /// (video ±9:16 = 0.5625 di layar 19.5:9 cuma kepotong ~9% per sisi).
  /// Video yang lebih "pendek" (4:5, square, landscape) kalau di-cover
  /// terpotong 30-50% → terasa zoom; IG me-letterbox-nya (fit-lebar,
  /// bar hitam atas/bawah). 0.68 = titik tengah 9:16 (0.5625) dan 4:5
  /// (0.8) supaya tidak ada kasus ambang yang goyah.
  static const double _coverMaxAspect = 0.68;

  static BoxFit _fitForAspect(double aspect) =>
      aspect <= _coverMaxAspect ? BoxFit.cover : BoxFit.contain;

  @override
  Widget build(BuildContext context) {
    final ctrl = videoController;

    if (ctrl != null && ctrl.value.isInitialized) {
      final size = ctrl.value.size;
      // Rasio dari dimensi AKTUAL player (metadata server bisa salah).
      final aspect = size.height > 0 ? size.width / size.height : 9 / 16;
      final fit = compactPreview ? BoxFit.contain : _fitForAspect(aspect);
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          // StackFit.expand → constraint tight fullscreen; FittedBox
          // memusatkan sendiri (contain = letterbox, cover = crop).
          FittedBox(
            fit: fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(ctrl),
            ),
          ),
        ],
      );
    }
    final thumb = post.thumbnailUrl;
    if (thumb != null) {
      // Pakai aspectRatio post supaya thumbnail mengikuti aturan yang
      // sama dengan videonya — tidak ada lompatan cover→contain saat
      // player siap.
      final fit =
          compactPreview ? BoxFit.contain : _fitForAspect(post.aspectRatio);
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          CachedNetworkImage(
            imageUrl: thumb,
            fit: fit,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
      );
    }
    return const ColoredBox(color: Colors.black);
  }
}

/// Sprint 3 #10 — Cinema mode fullscreen player.
///
/// Wrap existing VideoPlayerController di Scaffold full-screen dengan
/// AppBar minimal + tap-to-toggle controls. Aspect ratio preserved supaya
/// landscape video tampil proper letterbox di portrait phone, dan vice
/// versa.
///
/// Tidak buat controller baru — re-attach controller yang sudah playing
/// di feed supaya position + buffered chunks preserved. User tap close →
/// kembali ke feed dengan playback state continued.
class _FullScreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;

  const _FullScreenVideoPage({required this.controller});

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    // Set immersive mode — hide status bar + nav bar untuk true cinema feel.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleHideControls();
    // Unmute video di cinema mode (default feed muted).
    widget.controller.setVolume(1.0);
    if (!widget.controller.value.isPlaying) {
      widget.controller.play();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    // Restore system UI saat exit fullscreen.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Mute back saat balik ke feed (feed default mute).
    widget.controller.setVolume(0);
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.controller.value.size;
    final aspect =
        size.width > 0 && size.height > 0 ? size.width / size.height : 9 / 16;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(widget.controller),
              ),
            ),
            // Controls overlay — fade in/out smooth.
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Tutup cinema mode',
                        ),
                        const Spacer(),
                      ],
                    ),
                    const Spacer(),
                    // Progress bar bawah + play/pause toggle
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              widget.controller.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: () {
                              setState(() {
                                widget.controller.value.isPlaying
                                    ? widget.controller.pause()
                                    : widget.controller.play();
                              });
                              _scheduleHideControls();
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: VideoProgressIndicator(
                              widget.controller,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Colors.white,
                                bufferedColor: Colors.white24,
                                backgroundColor: Colors.white12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoRetryButton extends StatelessWidget {
  final VoidCallback onRetry;

  const _VideoRetryButton({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              SizedBox(width: 7),
              Text(
                'Coba lagi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PausedVideoControls extends StatelessWidget {
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePlayPause;

  const _PausedVideoControls({
    required this.muted,
    required this.onToggleMute,
    required this.onTogglePlayPause,
  });

  @override
  Widget build(BuildContext context) {
    // Gaya IG Reels: play = lingkaran scrim 52px (glyph polos ditolak
    // setelah device-verify; 80px lama terlalu berat), mute = lingkaran
    // kecil 32px di atasnya. Keduanya pakai _PausedControlButton dengan
    // feedback tekan pegas. Hit-area tetap lega via InkResponse radius.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PausedControlButton(
          diameter: 32,
          scrimAlpha: 0.42,
          inkRadius: 22,
          onTap: onToggleMute,
          child: Icon(
            muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            color: Colors.white,
            size: 17,
            shadows: const [
              Shadow(color: Colors.black87, blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Play: lingkaran 52 — satu keluarga dengan mute (~1.6×), jauh
        // dari 80px lama yang berat. Glyph polos tanpa lingkaran ditolak
        // user setelah device-verify (kurang jelas sebagai tombol).
        _PausedControlButton(
          diameter: 52,
          scrimAlpha: 0.40,
          inkRadius: 36,
          onTap: onTogglePlayPause,
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 28,
            shadows: [
              Shadow(color: Colors.black54, blurRadius: 8),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tombol bundar kontrol pause (mute + play) dengan feedback tekan pegas —
/// mengecil ke 0.86 saat jari turun (90ms) lalu membal balik easeOutBack
/// (240ms). Tanpa ini toggle terasa kaku: state berubah tanpa ada respons
/// fisik dari tombolnya.
class _PausedControlButton extends StatefulWidget {
  final double diameter;
  final double scrimAlpha;
  final double inkRadius;
  final VoidCallback onTap;
  final Widget child;

  const _PausedControlButton({
    required this.diameter,
    required this.scrimAlpha,
    required this.inkRadius,
    required this.onTap,
    required this.child,
  });

  @override
  State<_PausedControlButton> createState() => _PausedControlButtonState();
}

class _PausedControlButtonState extends State<_PausedControlButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkResponse(
        onTap: widget.onTap,
        radius: widget.inkRadius,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        child: AnimatedScale(
          scale: _pressed ? 0.86 : 1.0,
          duration: Duration(milliseconds: _pressed ? 90 : 240),
          curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
          child: Container(
            height: widget.diameter,
            width: widget.diameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: widget.scrimAlpha),
              shape: BoxShape.circle,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _ProductCommerceOverlayGroup extends StatelessWidget {
  final FeedProductLink featuredProduct;
  final bool showProductCard;
  final VoidCallback onTap;
  final VoidCallback onBuy;
  final VoidCallback? onQuickAdd;
  final VoidCallback onDismiss;

  const _ProductCommerceOverlayGroup({
    required this.featuredProduct,
    required this.showProductCard,
    required this.onTap,
    required this.onBuy,
    this.onQuickAdd,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: showProductCard
              ? Column(
                  key: const ValueKey('product-card-open'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSlide(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      offset: Offset.zero,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: 1,
                        child: _EndOfVideoProductCta(
                          product: featuredProduct,
                          onTap: onTap,
                          onBuy: onBuy,
                          onDismiss: onDismiss,
                        ),
                      ),
                    ),
                    const _ProductCardArrowPointer(),
                  ],
                )
              : const SizedBox.shrink(key: ValueKey('product-card-closed')),
        ),
        feedPostProductAnchorCardFor(
          featuredProduct,
          onTap: onTap,
          onAddToCart: onQuickAdd,
        ),
      ],
    );
  }
}

class _ProductCardArrowPointer extends StatelessWidget {
  const _ProductCardArrowPointer();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size(22, 10),
      painter: _DownArrowPainter(),
    );
  }
}

class _DownArrowPainter extends CustomPainter {
  const _DownArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    final fill = Paint()
      ..color = Colors.black.withValues(alpha: 0.50)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);

    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FeedCartSheet extends StatelessWidget {
  final VoidCallback onOpenFullCart;

  const _FeedCartSheet({
    required this.onOpenFullCart,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.60,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D12),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 30,
              offset: const Offset(0, -14),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: cartStore,
            builder: (context, _) {
              final items = cartStore.items;
              final itemCount = cartStore.totalQuantity;
              final subtotal = cartStore.subtotal;

              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        height: 4,
                        width: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Keranjang Feed',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      itemCount > 0
                          ? '$itemCount item di keranjang utama.'
                          : 'Keranjang masih kosong.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: items.isEmpty
                          ? const _FeedCartEmptyState()
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return _FeedCartItemTile(item: item);
                              },
                            ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  itemCount > 0
                                      ? '$itemCount item'
                                      : 'Belum ada item',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.56),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatRupiah(subtotal),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: onOpenFullCart,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Lihat Keranjang',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FeedCartEmptyState extends StatelessWidget {
  const _FeedCartEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 58,
              width: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: feedPostGoldColor,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Keranjang masih kosong',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap tombol kecil di produk video untuk menambahkan item tanpa keluar dari Feed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.56),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedCartItemTile extends StatelessWidget {
  final CartItem item;

  const _FeedCartItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.product.imageUrl;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 62,
              width: 62,
              child: imageUrl.isEmpty
                  ? const ColoredBox(
                      color: Color(0xFF171B22),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white70,
                      ),
                    )
                  : imageUrl.startsWith('assets/')
                      ? Image.asset(imageUrl, fit: BoxFit.cover)
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const ColoredBox(
                            color: Color(0xFF171B22),
                            child: Icon(
                              Icons.shopping_bag_outlined,
                              color: Colors.white70,
                            ),
                          ),
                        ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    height: 1.18,
                  ),
                ),
                if (item.variantLabel != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.variantLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.52),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatRupiah(item.unitPrice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: feedPostGoldColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        'x${item.quantity}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EndOfVideoProductCta extends StatelessWidget {
  final FeedProductLink product;
  final VoidCallback onTap;
  final VoidCallback onBuy;
  final VoidCallback onDismiss;

  const _EndOfVideoProductCta({
    required this.product,
    required this.onTap,
    required this.onBuy,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final pricing = feedPostProductPricing(product);
    final canBuy = product.isAvailable && product.stock > 0;
    final imageUrl = product.imageUrl;
    final hasRatingData = product.avgRating > 0 || product.soldCount > 0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.50),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Thumbnail produk (4:5 portrait) ──
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 72,
                            height: 90,
                            child: imageUrl != null && imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                        color: const Color(0xFF2A2F36)),
                                    errorWidget: (_, __, ___) => Container(
                                        color: const Color(0xFF2A2F36)),
                                  )
                                : Container(color: const Color(0xFF2A2F36)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // ── Content right ──
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Spacer kecil supaya beri ruang untuk X di top-right
                              // tanpa overlap text. Padding right ~20 lewat
                              // contentPadding gak available — pakai SizedBox.
                              Padding(
                                padding: const EdgeInsets.only(right: 22),
                                child: Text(
                                  product.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.18,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              // Badges row
                              Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (pricing.hasPromo)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF4D4F),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        'Diskon ${pricing.discountPercent}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              // Rating row (conditional)
                              if (hasRatingData) ...[
                                const SizedBox(height: 5),
                                FeedPostProductRatingRow(
                                  avgRating: product.avgRating,
                                  soldCount: product.soldCount,
                                ),
                              ],
                              const SizedBox(height: 6),
                              // Harga row
                              Wrap(
                                spacing: 6,
                                runSpacing: 3,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (pricing.hasPromo)
                                    Text(
                                      formatRupiah(pricing.originalPrice),
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.45),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        decoration: TextDecoration.lineThrough,
                                        decorationColor: Colors.white
                                            .withValues(alpha: 0.45),
                                        height: 1,
                                      ),
                                    ),
                                  Text(
                                    formatRupiah(pricing.displayPrice),
                                    style: const TextStyle(
                                      color: Color(0xFFFF4D4F),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Cart icon + Beli button row
                              Row(
                                children: [
                                  _PopupCartButton(
                                    enabled: canBuy,
                                    onTap: canBuy ? onBuy : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _CtaBuyButton(
                                      enabled: canBuy,
                                      onTap: canBuy ? onBuy : null,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ── X dismiss (top-right) ──
              Positioned(
                top: 6,
                right: 6,
                child: InkResponse(
                  onTap: onDismiss,
                  radius: 18,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tombol Beli di popup preview — spec: warna Natalo biru agak ringan
/// (bukan merah). Match `_FeedPrimaryProductButton` style.
class _CtaBuyButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _CtaBuyButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF5FBFFF),
                    Color(0xFF1E87FF),
                  ],
                )
              : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          enabled ? 'Beli' : 'Habis',
          style: TextStyle(
            color:
                enabled ? Colors.white : Colors.white.withValues(alpha: 0.45),
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// Cart icon button di popup preview — line biru tema Natalo.
class _PopupCartButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _PopupCartButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF1E5BFF).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF1E5BFF)
                .withValues(alpha: enabled ? 0.65 : 0.15),
            width: 1.4,
          ),
        ),
        child: Icon(
          Icons.shopping_cart_outlined,
          color: enabled
              ? const Color(0xFF1E5BFF)
              : Colors.white.withValues(alpha: 0.28),
          size: 18,
        ),
      ),
    );
  }
}

/// Keep Product import referenced (untuk type-safety navigation arguments).
// ignore: unused_element
Product? _typeHint() => null;

// Note: _UploadChoiceSheet (split video/photo dulu) di-remove. Flow upload
// sekarang unified via FeedMediaPickerScreen.open() yang handle photo +
// video di satu picker IG-style. Konsisten dengan entry point dari
// member_screen + member_posts_screen.
