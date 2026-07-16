import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../state/feed_comment_session_store.dart';
import '../../../state/feed_local_store.dart';
import '../../../state/feed_store.dart';
import '../../../state/member_store.dart';
import '../../../state/settings_store.dart';
import '../../../utils/android_back_overlays.dart';
import '../../../utils/app_route_observer.dart';
import '../../../utils/formatters.dart';
import '../../../utils/haptics.dart';
import '../video/post_video_coordinator.dart';
import '../video/frame_output_heartbeat_service.dart';
import '../video/feed_video_observation.dart';
import '../video/single_dispose_guard.dart';
import '../video/social_video_session_observer.dart';
import '../video/video_audio_arbiter.dart';
import '../video/video_media_cache.dart';
import '../video/video_player_session.dart';
import '../video/video_playback_health_monitor.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/feed_comment_sheet.dart';
import '../../../widgets/moderation_action_sheet.dart';
import 'feed_action_rail.dart';
import 'feed_accessibility_overlay.dart';
import 'feed_creator_overlay.dart';
import 'feed_post_scrim.dart';
import 'feed_post_shared_widgets.dart';
import 'feed_video_scrubber.dart';

typedef FeedVideoHealthMonitorFactory = VideoPlaybackHealthMonitor Function({
  required VideoPlaybackSnapshot Function() readSnapshot,
  required Future<void> Function(Duration position) onPlaybackStall,
  required FrameOutputStallRecover onFrameOutputStall,
  required Map<String, Object> metricContext,
});

/// Alasan sebuah cover-pause dilaporkan lewat [FeedVideoPostView.onRequestPause]
/// (gap D5). Satu sinyal pause dulu opaque untuk 3 sumber berbeda; T3 tidak
/// bisa membedakan "aku sedang push fullscreen handoff" (controller SAMA
/// lanjut di fullscreen → JANGAN pauseAll) dari cover asli.
///
/// Panduan konsumsi (T3):
///  - [routePush] + sedang-handoff (fullscreen borrow controller yang sama)
///    → JANGAN `pauseAll`; controller identik lanjut jalan di fullscreen.
///  - [routePush] non-handoff (route opaque lain didorong) → `pauseAll`
///    sesuai kebutuhan supaya video Postingan berhenti di balik route.
///  - [appBackground] → `pauseAll` (app ke background/lock → nol audio hantu).
///  - [commentSheetFull] → `pauseAll` (comment sheet full menutup video).
enum CoverPauseReason { routePush, appBackground, commentSheetFull }

/// Hasil klaim preload dari pemilik map (FeedScreen). Controller +
/// wrapper cache 1:1 — wrapper bisa null (HLS bypass wrapper), controller
/// bisa null saat init MP4 masih in-flight (wrapper sudah ada, controller
/// belum) → penerima dispose wrapper orphan itu, lalu init fresh.
class PreloadedVideoClaim {
  final VideoPlayerController? controller;
  final CachedVideoPlayerPlus? cachedPlayer;
  final bool isPending;

  const PreloadedVideoClaim({
    required this.controller,
    required this.cachedPlayer,
  }) : isPending = false;

  const PreloadedVideoClaim.pending()
      : controller = null,
        cachedPlayer = null,
        isPending = true;
}

enum _PreloadClaimState { none, pending, adopted }

enum _CommentDrawerPhase { closed, opening, open, closing }

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

  /// Handoff preload TERKONFIRMASI (fix A5): kalau di-set, state MENGKLAIM
  /// controller dari pemilik map saat initState (adopt) — remove dari map
  /// terjadi di dalam callback ini, BUKAN di build() parent. Rebuild parent
  /// dengan state ber-key sama yang masih hidup jadi tidak lagi menjatuhkan
  /// controller dari map tanpa pernah diadopsi (controller yatim: tak pernah
  /// di-dispose → leak + kandidat audio hantu). Kalau di-set, callback ini
  /// menang atas [preloadedController]/[preloadedCachedPlayer].
  final FutureOr<PreloadedVideoClaim?> Function()? claimPreloadedVideo;
  final ValueListenable<int>? preloadListenable;
  final ValueChanged<bool>? onLocalOwnershipChanged;

  /// Low-frequency contiguous buffered-ahead telemetry for the active video.
  /// Reports without rebuilding this widget and works for local and managed
  /// controllers alike.
  final ValueChanged<Duration>? onBufferAheadChanged;
  final ValueChanged<bool> onOverlayStateChanged;
  final ValueChanged<bool> onMediaZoomChanged;

  /// Kontrak §2.1 (KUNCI USER) — siapa yang boleh men-DISPOSE controller.
  /// `false` → controller/wrapper milik coordinator (T3); widget ini TIDAK
  /// memanggil `dispose()` di `dispose()`-nya. Default `true` = perilaku
  /// lama (widget membuat + memiliki + men-dispose controllernya sendiri).
  final bool ownsController;

  /// Kontrak §2.1 (KUNCI USER) — siapa yang boleh play/pause/seek/setVolume.
  /// `true` → SEMUA sumber kontrol internal (VisibilityDetector, lifecycle
  /// route/app, tap/toggle, comment-sheet cover) TIDAK menyentuh controller
  /// langsung; sebaliknya widget MELAPOR intent lewat callback di bawah dan
  /// coordinator (T3) yang mengeksekusi. Widget juga tidak meng-init
  /// controller sendiri — controller datang dari luar (preloaded/claim).
  /// Default `false` = perilaku lama (nol perubahan pada call site lama).
  final bool playbackManagedExternally;

  /// T7 (integrasi full-managed) — sumber sesi DINAMIS. Kalau di-set BERSAMA
  /// [playbackManagedExternally], widget mengikat controllernya ke
  /// `coordinator.sessionFor(post.id)` secara dinamis (bukan cuma
  /// [preloadedController] statis sekali di initState):
  ///  - initState + saat `coordinator.registryListenable` fire → re-cek
  ///    `sessionFor(post.id)`; sesi muncul (mis. hasil `preloadNext` saat swipe)
  ///    → adopt controllernya. Belum ada sesi → render thumbnail/frozen, TIDAK
  ///    membuat controller sendiri.
  ///  - Ikut `VideoPlayerSession.revision` sesi terikat supaya begitu init
  ///    controller selesai (controller lahir async), frame pertama dirender.
  ///  - Sesi dievict-dispose coordinator (sessionFor → null) → lepas referensi
  ///    controller (tidak merender controller mati), balik ke thumbnail.
  /// Widget TETAP tidak pernah men-dispose controller (`ownsController:false`).
  /// Null → jalur lama (managed via [preloadedController] statis / non-managed).
  final PostVideoCoordinator? coordinator;

  /// [playbackManagedExternally] — video jadi cukup terlihat (`true`, >0.7
  /// fraction + aktif) atau tersembunyi (`false`). T3 memetakan ke
  /// `coordinator.reportVisible` / `reportHidden`.
  final ValueChanged<bool>? onVisibleChanged;

  /// [playbackManagedExternally] — video harus di-pause karena tertutup.
  /// Membawa [CoverPauseReason] (gap D5) supaya T3 bisa membedakan
  /// route-push handoff (controller sama lanjut di fullscreen → JANGAN
  /// pauseAll) dari cover asli (app background / comment full → pauseAll).
  final ValueChanged<CoverPauseReason>? onRequestPause;

  /// [playbackManagedExternally] — penutup hilang (route dibuka lagi, app
  /// foreground, comment sheet turun) → boleh resume. T3 memetakan ke
  /// `coordinator.resumeAll`.
  final VoidCallback? onRequestPlay;

  /// [playbackManagedExternally] — user tap play/pause di area video. T3
  /// memetakan ke `coordinator.userTogglePlay` (satu-satunya sumber
  /// user-pause eksplisit).
  final VoidCallback? onRequestUserTogglePlay;

  /// Test seams for the native frame-output route and watchdog scheduling.
  final FrameOutputHeartbeatService? frameOutputHeartbeatService;
  final FeedVideoHealthMonitorFactory? healthMonitorFactory;
  final SocialVideoSessionObserver? observationObserver;
  final Future<void> Function()? beforeObserveInitialized;

  const FeedVideoPostView({
    super.key,
    required this.post,
    required this.isActive,
    required this.preloadedController,
    required this.onOverlayStateChanged,
    required this.onMediaZoomChanged,
    this.preloadedCachedPlayer,
    this.claimPreloadedVideo,
    this.preloadListenable,
    this.onLocalOwnershipChanged,
    this.onBufferAheadChanged,
    this.ownsController = true,
    this.playbackManagedExternally = false,
    this.coordinator,
    this.onVisibleChanged,
    this.onRequestPause,
    this.onRequestPlay,
    this.onRequestUserTogglePlay,
    this.frameOutputHeartbeatService,
    this.healthMonitorFactory,
    this.observationObserver,
    this.beforeObserveInitialized,
  });

  @override
  State<FeedVideoPostView> createState() => _FeedVideoPostViewState();
}

class _FeedVideoPostViewState extends State<FeedVideoPostView>
    with TickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  static const double _commentSheetMinExtent = 0.0;
  static const double _commentSheetInitialExtent = feedCommentInitialExtent;
  static const double _commentSheetDismissExtent = feedCommentDismissExtent;

  VideoPlayerController? _videoController;

  /// Wrapper instance untuk lifecycle network video (disk cache). Null
  /// kalau ga ada wrapper (defensive). Disposed di dispose() lebih dulu
  /// dari _videoController supaya cache file di-release proper. Untuk
  /// adopt-from-parent path: copy dari widget.preloadedCachedPlayer.
  /// Untuk fresh-create path: di-set di _maybeInitVideo.
  CachedVideoPlayerPlus? _cachedPlayer;
  CachedVideoPlayerPlus? _localInitCachedPlayer;
  VideoPlayerController? _localInitController;
  final SingleDisposeGuard<CachedVideoPlayerPlus> _localWrapperDisposeGuard =
      SingleDisposeGuard<CachedVideoPlayerPlus>();
  final SingleDisposeGuard<VideoPlayerController> _localControllerDisposeGuard =
      SingleDisposeGuard<VideoPlayerController>();
  int _localInitGeneration = 0;
  Future<void>? _localCachedInitialization;

  SocialVideoSessionObserver get _observationObserver =>
      widget.observationObserver ?? socialVideoSessionObserver;

  bool _localInitIdentityIsCurrent({
    required int generation,
    required CachedVideoPlayerPlus? wrapper,
    required VideoPlayerController controller,
  }) {
    return mounted &&
        generation == _localInitGeneration &&
        identical(wrapper, _localInitCachedPlayer) &&
        identical(controller, _localInitController) &&
        _videoController == null;
  }

  Future<void> _disposeLocalInitResource({
    CachedVideoPlayerPlus? wrapper,
    VideoPlayerController? controller,
  }) async {
    if (wrapper != null && identical(wrapper, _localInitCachedPlayer)) {
      final initialization = _localCachedInitialization;
      await _localWrapperDisposeGuard.dispose(wrapper, () async {
        if (initialization != null) {
          try {
            await initialization;
          } catch (_) {}
        }
        final controllerIdentity = controller ??
            _localInitController ??
            (wrapper.isInitialized ? wrapper.controller : null);
        try {
          await wrapper.dispose();
        } finally {
          if (controllerIdentity != null) {
            observeFeedControllerDisposed(
              _observationObserver,
              postId: widget.post.id,
              controller: controllerIdentity,
              ownerId: feedLocalOwnerId(widget.post.id),
            );
          }
        }
      });
      return;
    }
    if (controller != null && identical(controller, _localInitController)) {
      await _localControllerDisposeGuard.dispose(controller, () async {
        try {
          await controller.dispose();
        } finally {
          observeFeedControllerDisposed(
            _observationObserver,
            postId: widget.post.id,
            controller: controller,
            ownerId: feedLocalOwnerId(widget.post.id),
          );
        }
      });
    }
  }

  Future<void> _disposeUnadoptedPreload({
    CachedVideoPlayerPlus? wrapper,
    VideoPlayerController? controller,
  }) async {
    final controllerIdentity = controller ??
        (wrapper?.isInitialized ?? false ? wrapper!.controller : null);
    try {
      if (wrapper != null) {
        await wrapper.dispose();
      } else {
        await controller!.dispose();
      }
    } finally {
      if (controllerIdentity != null) {
        observeFeedControllerDisposed(
          _observationObserver,
          postId: widget.post.id,
          controller: controllerIdentity,
          ownerId: feedPreloadOwnerId(widget.post.id),
        );
      }
    }
  }

  DraggableScrollableController _commentSheetController =
      DraggableScrollableController();
  bool _commentSheetControllerNeedsReset = false;
  AnimationController? _commentSheetAnimationController;
  final ValueNotifier<double> _commentSheetExtent = ValueNotifier<double>(
    _commentSheetInitialExtent,
  );
  bool _liked = false;
  bool _saved = false;
  int _likeCount = 0;
  int _commentCount = 0;
  int _shareCount = 0;
  bool _shareInFlight = false;
  bool _isPaused = false;
  bool _videoLoadFailed = false;
  _CommentDrawerPhase _commentDrawerPhase = _CommentDrawerPhase.closed;
  bool _commentOverlayLockHeld = false;
  int _commentOverlayLockEpoch = 0;
  bool _androidBackCommentCloserRegistered = false;
  late final VoidCallback _androidBackCommentCloserCallback =
      _androidBackCommentCloser;
  bool _commentSheetReachedVisibleExtent = false;
  FeedCommentSession? _activeCommentSession;
  Completer<void>? _commentDrawerClosedCompleter;
  bool _pausedByCommentSheet = false;
  int _commentSheetTransitionEpoch = 0;
  int _featuredProductIndex = 0;
  Timer? _productRotationTimer;
  Timer? _commentDrawerOpenWatchdog;
  double _commentDragOffset = 0;

  bool get _commentDrawerMounted =>
      _commentDrawerPhase != _CommentDrawerPhase.closed;

  // Keep the existing visual treatment through the closing animation. The
  // explicit phase, rather than this presentation getter, owns transitions.
  bool get _commentSheetOpen => _commentDrawerMounted;

  bool get _commentSheetClosingFromDrag =>
      _commentDrawerPhase == _CommentDrawerPhase.closing;

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
  late final VideoPlaybackHealthMonitor _playbackHealthMonitor;
  FrameOutputHeartbeatRegistration? _frameOutputRegistration;
  VideoPlayerController? _frameOutputController;
  int _playbackDiscontinuitySequence = 0;
  int _controllerGeneration = 0;
  final Stopwatch _startupStopwatch = Stopwatch()..start();
  bool _initMetricStarted = false;
  bool _playMetricRecorded = false;
  Duration? _lastReportedBufferAhead;
  DateTime? _lastBufferAheadReportAt;

  static const Duration _bufferReportInterval = Duration(milliseconds: 500);
  static const Duration _bufferReportMinDelta = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    final metricContext = <String, Object>{
      'surface': 'feed',
      'media_type': widget.post.videoUrl.contains('.m3u8') ? 'hls' : 'mp4',
      'media_key': widget.post.id.hashCode.toUnsigned(32).toRadixString(16),
      'network_tier': videoQualityService.currentTier.name,
      'quality_preference': appSettingsStore.feedVideoQuality,
    };
    _playbackHealthMonitor = widget.healthMonitorFactory?.call(
          readSnapshot: _playbackHealthSnapshot,
          onPlaybackStall: _recoverPlaybackStall,
          onFrameOutputStall: _recoverFrameOutputStall,
          metricContext: metricContext,
        ) ??
        VideoPlaybackHealthMonitor(
          readSnapshot: _playbackHealthSnapshot,
          onRecover: _recoverPlaybackStall,
          onFrameOutputStallRecover: _recoverFrameOutputStall,
          metricContext: metricContext,
        );
    if (!_managed) _playbackHealthMonitor.start();
    // Seed shared FeedStore + subscribe — single source of truth untuk
    // like/comment sync antar screen. Detail screen yang juga listen ke
    // store akan auto-update kalau user toggle dari sini, dan sebaliknya.
    feedStore.seed([widget.post]);
    feedStore.addListener(_onFeedStoreChanged);
    // Gap #7: initialize _liked dari backend/store + local cache.
    // Kalau FeedStore sudah punya post, store/backend adalah source of
    // truth. Local cache hanya fallback awal agar launch offline tetap
    // terasa instant, dan tidak boleh membuat unlike terbaru tetap merah.
    final fresh = feedStore.get(widget.post.id) ?? widget.post;
    _liked = fresh.viewerLiked || fresh.isLiked;
    _saved = fresh.viewerSaved;
    _likeCount = fresh.likeCount;
    _commentCount = fresh.commentCount;
    _shareCount = fresh.shareCount;

    _heartBurstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.35,
          end: 1.42,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 34,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.42,
          end: 1.00,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.00,
          end: 0.82,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.82,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 26,
      ),
    ]).animate(_heartBurstController);
    _heartOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 38),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
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

    // D1 (§2.2) — mute LIVE di Feed utama (jalur non-managed/legacy). Controller
    // feed yang SUDAH hidup harus ikut perubahan `feedMuted` (mis. user mute
    // dari layar lain / Postingan) secara live, bukan cuma saat init/adopt.
    // HANYA controller AKTIF yang mengikuti feedMuted (0/1); non-aktif tetap 0.
    // Managed (coordinator) tidak pakai listener ini — coordinator yang urus
    // volume controller pinjaman (§2.1).
    if (!_managed) {
      appSettingsStore.addListener(_onFeedMutedChangedLive);
    }

    // T7: managed-source DINAMIS bila coordinator di-set — ikat controller ke
    // `coordinator.sessionFor(post.id)` via registry notifier (adopt saat sesi
    // muncul), bukan preloadedController statis. Tanpa coordinator → jalur lama
    // (managed via preloadedController statis, atau non-managed fresh-init).
    if (_managed && widget.coordinator != null) {
      widget.coordinator!.registryListenable.addListener(
        _onCoordinatorRegistryChanged,
      );
      widget.coordinator!.playbackListenable.addListener(
        _onCoordinatorPlaybackChanged,
      );
      _syncManagedSession();
    } else {
      widget.preloadListenable?.addListener(_onLatePreloadAvailable);
      unawaited(_claimOrInitOnActivation(allowLocalInit: widget.isActive));
    }
    _syncProductRotation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
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

  // Race fix (Feed→Profile) — jalur legacy non-managed: `didPushNext()` dulu
  // early-return TANPA mencatat cover kalau controller belum siap
  // (null/belum initialized/belum playing). Kalau saat itu init masih
  // berjalan async, begitu init selesai DI BELAKANG route baru, beberapa
  // jalur play() cuma cek `isActive && shouldAutoplay` — video pun mulai
  // bermain di belakang layar. `_routeCovered` dicatat SEGERA saat route
  // opaque didorong, independen dari state controller, supaya semua jalur
  // play() (via `_canAutoplayNow`) tahu Feed sedang tertutup meski
  // controllernya belum lahir.
  bool _routeCovered = false;

  // App ke background/lock (paused/inactive/hidden) — dicatat SEGERA (sebelum
  // _pauseForCover) untuk alasan sama seperti _routeCovered: kalau init masih
  // in-flight, play() yang lahir di belakang layar terkunci app harus tetap
  // digerbang.
  bool _appBackgrounded = false;
  bool _dependenciesReady = false;
  VideoAudioClaim? _audioClaim;
  int _legacyPlaybackGeneration = 0;
  bool _legacyDisposed = false;

  VideoAudioClaim _claimAudio() {
    final claim = videoAudioArbiter.claim(
      owner: this,
      onFocusLost: _onAudioFocusLost,
    );
    _audioClaim = claim;
    return claim;
  }

  void _releaseAudio() {
    _legacyPlaybackGeneration++;
    _audioClaim?.release();
    _audioClaim = null;
  }

  void _onAudioFocusLost() {
    _legacyPlaybackGeneration++;
    _audioClaim = null;
    final ctrl = _videoController;
    if (ctrl == null) return;
    unawaited(_silenceLegacyController(ctrl));
  }

  Future<void> _silenceLegacyController(VideoPlayerController ctrl) async {
    try {
      await ctrl.setVolume(0);
      await ctrl.pause();
    } catch (_) {
      // Expected when native teardown wins a race with lifecycle cleanup.
    }
  }

  bool _legacyPlaybackIsValid(
    VideoPlayerController ctrl,
    VideoAudioClaim claim,
    int generation, {
    required bool userInitiated,
  }) {
    return !_legacyDisposed &&
        mounted &&
        identical(_videoController, ctrl) &&
        generation == _legacyPlaybackGeneration &&
        identical(_audioClaim, claim) &&
        claim.isCurrent &&
        _canAutoplayNow(userInitiated: userInitiated);
  }

  bool _hasNewerLegacyPlayback(
    VideoPlayerController ctrl,
    VideoAudioClaim claim,
  ) {
    final current = _audioClaim;
    return !_legacyDisposed &&
        mounted &&
        identical(_videoController, ctrl) &&
        current != null &&
        !identical(current, claim) &&
        current.isCurrent &&
        _canAutoplayNow();
  }

  Future<void> _playLegacy(
    VideoPlayerController ctrl,
    String source, {
    bool userInitiated = false,
  }) async {
    if (!_canAutoplayNow(userInitiated: userInitiated)) return;
    final generation = ++_legacyPlaybackGeneration;
    final claim = _claimAudio();
    _logPlay(source);
    try {
      await ctrl.setVolume(
        !appSettingsStore.feedMuted && _postHasAudio && claim.isCurrent ? 1 : 0,
      );
      if (!_legacyPlaybackIsValid(
        ctrl,
        claim,
        generation,
        userInitiated: userInitiated,
      )) {
        if (_hasNewerLegacyPlayback(ctrl, claim)) {
          await ctrl.setVolume(
            appSettingsStore.feedMuted || !_postHasAudio ? 0 : 1,
          );
          return;
        }
        if (identical(_audioClaim, claim)) _releaseAudio();
        await _silenceLegacyController(ctrl);
        return;
      }
      await ctrl.play();
      if (!_legacyPlaybackIsValid(
        ctrl,
        claim,
        generation,
        userInitiated: userInitiated,
      )) {
        if (_hasNewerLegacyPlayback(ctrl, claim)) {
          await ctrl.setVolume(
            appSettingsStore.feedMuted || !_postHasAudio ? 0 : 1,
          );
          return;
        }
        if (identical(_audioClaim, claim)) _releaseAudio();
        await _silenceLegacyController(ctrl);
      }
    } catch (_) {
      if (identical(_audioClaim, claim)) _releaseAudio();
      await _silenceLegacyController(ctrl);
    }
  }

  /// Gate tunggal untuk SEMUA jalur play() legacy (non-managed). Managed
  /// (coordinator) tidak lewat sini — dijaga terpisah oleh guard `_managed`
  /// di tiap call site.
  ///
  /// [userInitiated] — tap paksa walau data-saver (dari `_tryInitVideoController`
  /// saat user tap media sebelum controller ada). Tetap WAJIB
  /// `!_routeCovered && !_appBackgrounded` — user-initiated tidak boleh
  /// menembus route-covered (pertahanan berlapis, bukan pelonggaran; kalau
  /// user genuinely tap, route seharusnya sudah tidak covered).
  bool _canAutoplayNow({bool userInitiated = false}) {
    return !_managed &&
        mounted &&
        widget.isActive &&
        !_routeCovered &&
        !_appBackgrounded &&
        !_isPaused &&
        (_shouldAutoplay || userInitiated);
  }

  /// TELEMETRY-ONLY (poin 8) — apakah route Feed BENAR-BENAR teratas/aktif,
  /// dibaca HANYA untuk log `_logPlay` (`routeCurrent=…`). BUKAN gate playback.
  ///
  /// Dulu ikut menggerbang `_canAutoplayNow`, tapi itu REGRESI: sheet
  /// produk/cart/tagged dibuka via `showModalBottomSheet(backgroundColor:
  /// transparent)` = ModalBottomSheetRoute NON-opaque → `isCurrent` jadi false
  /// padahal desain SENGAJA membiarkan video Feed TETAP MAIN di balik sheet
  /// transparan (`_routeCovered` HANYA di-set untuk route OPAQUE via
  /// `lastPushedRouteIsOpaque()`). Efek paling nyata: video main di balik sheet
  /// produk → app background → foreground → `_resumeFromCover` gagal (isCurrent
  /// false) → video BEKU sampai sheet ditutup. Gate kini murni mengandalkan
  /// `_routeCovered` (opaque-aware) + `_appBackgrounded`, yang juga BENAR untuk
  /// nested-route: RouteObserver cuma notif route adjacent, sehingga
  /// `_routeCovered` tetap true sepanjang Profile menutupi Feed (termasuk saat
  /// Postingan didorong / di-pop di atas Profile).
  ///
  /// Fallback `true` bila context tak punya route (mis. widget test tanpa
  /// Navigator). Context-guard: hanya baca `ModalRoute.of` saat `mounted`.
  bool get _feedRouteIsCurrent {
    if (!mounted || !_dependenciesReady) return true;
    final r = ModalRoute.of(context);
    return r?.isCurrent ?? true;
  }

  /// Telemetry playback (poin 8) — debug-only log TEPAT sebelum tiap
  /// `ctrl.play()` legacy yang benar-benar memutar (di dalam gate). Membantu
  /// menemukan jalur play tersembunyi di device: sumber perintah + route aktif
  /// + status lifecycle. HANYA `kDebugMode` (nol overhead + nol bocor di
  /// production). Tidak membocorkan data sensitif — postId saja.
  void _logPlay(String source) {
    if (!kDebugMode) return;
    debugPrint(
      '[feed-play] post=${widget.post.id} source=$source '
      'routeCurrent=$_feedRouteIsCurrent covered=$_routeCovered '
      'bg=$_appBackgrounded active=${widget.isActive}',
    );
  }

  void _pauseForCover(CoverPauseReason reason) {
    if (_managed) {
      // Coordinator memiliki playback — lapor intent + alasan (D5), jangan
      // sentuh controller (lifecycle level-halaman yang mengeksekusi, §2.5).
      widget.onRequestPause?.call(reason);
      return;
    }
    _releaseAudio();
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) {
      // Controller belum siap (mis. masih initialize() async) — state cover
      // sudah cukup dicatat oleh caller (_routeCovered/_appBackgrounded)
      // SEBELUM method ini dipanggil. Begitu controller lahir, titik
      // penyelesaian init (_tryInitVideoController / listener onInit) akan
      // mengecek flag ini dan mute + skip play.
      return;
    }
    if (!ctrl.value.isPlaying) return;
    _pausedByCover = true;
    ctrl.pause();
  }

  /// [forceIfUncovered] — GAP #4: di race Feed→Profile, controller bisa `null`
  /// saat cover → `_pauseForCover` early-return → `_pausedByCover` TAK PERNAH
  /// jadi true, sehingga resume via state-machine (didPopNext → sini) mati dan
  /// video hanya bangun karena VisibilityDetector re-fire (~500ms, jeda
  /// terlihat). Saat caller tahu kita "baru saja uncover" (route pop / app
  /// resume), kirim `forceIfUncovered: true` supaya resume tetap jalan walau
  /// `_pausedByCover == false`.
  void _resumeFromCover({bool forceIfUncovered = false}) {
    if (_managed) {
      // BLOCKER: guard isActive — view origin yang MASIH mounted tapi INACTIVE
      // (user sudah swipe ke sibling di fullscreen; sibling tak pernah
      // setActive → coordinator.activePostId nyangkut di origin) TIDAK boleh
      // minta resume. Tanpa guard ini, app-foreground / didPopNext memanggil
      // onRequestPlay → resumeAll() memutar origin tersembunyi di belakang
      // sibling = dua suara (audio hantu). Hanya origin yang benar-benar AKTIF
      // (user di halaman origin) yang meminta resume.
      if (!mounted || !widget.isActive) return;
      widget.onRequestPlay?.call();
      return;
    }
    // Non-managed. Normalnya resume hanya kalau KITA yang pause
    // (_pausedByCover); tapi kalau caller menandai uncover (forceIfUncovered),
    // teruskan walau _pausedByCover false (kasus controller-null-saat-cover).
    if (!_pausedByCover && !forceIfUncovered) return;
    _pausedByCover = false;
    if (!mounted || !widget.isActive) return;
    if (_isPaused || !_shouldAutoplay) return;
    // GAP #3: kembalikan volume saat uncover. Init yang selesai DI BAWAH cover
    // memaksa setVolume(0) (pertahanan anti audio-hantu); tanpa mengembalikan
    // di sini, video resume SENYAP (volume 0 nyangkut) sampai user toggle mute
    // / navigasi. Idempoten & murah. Hanya video aktif yang akan main.
    final ctrl = _videoController;
    if (ctrl != null && ctrl.value.isInitialized) {
      ctrl.setVolume(
        !appSettingsStore.feedMuted &&
                _postHasAudio &&
                (_audioClaim?.isCurrent ?? false)
            ? 1
            : 0,
      );
    }
    // Play hanya kalau controller SUDAH ada; kalau masih null, init-path yang
    // meng-handle (dan karena _routeCovered sudah false, _canAutoplayNow di
    // init-path akan mengizinkan play + volume sudah benar). _canAutoplayNow
    // tetap penjaga akhir (blok _appBackgrounded / _routeCovered / dsb).
    if (_canAutoplayNow()) {
      if (ctrl != null) unawaited(_playLegacy(ctrl, 'resume-cover'));
    }
  }

  @override
  void didPushNext() {
    // Halaman penuh menutup feed → pause. Sheet/dialog transparan (mis.
    // sheet produk) TIDAK mem-pause — video tetap jalan di baliknya (ala
    // TikTok/IG) dan tidak ada konflik audio dari sheet.
    if (lastPushedRouteIsOpaque()) {
      // Race fix: catat _routeCovered SEGERA, SEBELUM _pauseForCover —
      // independen dari state controller (null/belum initialized/belum
      // playing semua tetap dicatat). Kalau ditunda sampai controller siap
      // (perilaku lama _pauseForCover early-return diam), init yang selesai
      // async di belakang route baru bisa lolos gate isActive/shouldAutoplay
      // lama dan mulai bermain di belakang layar.
      if (!_managed) _routeCovered = true;
      // D5: route opaque didorong (mis. buka fullscreen). T3 memakai reason
      // untuk men-DROP kasus ini saat handoff sedang berlangsung (controller
      // sama lanjut di fullscreen → JANGAN pauseAll).
      _pauseForCover(CoverPauseReason.routePush);
    }
  }

  @override
  void didPopNext() {
    // GAP #4: tangkap wasCovered SEBELUM reset supaya _resumeFromCover tahu kita
    // baru saja uncover — resume via state-machine walau controller null saat
    // cover (jadi _pausedByCover tak pernah true), bukan menunggu VD re-fire.
    final wasCovered = _routeCovered;
    _routeCovered = false;
    _resumeFromCover(forceIfUncovered: wasCovered);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (!_managed) _appBackgrounded = true;
        _pauseForCover(CoverPauseReason.appBackground);
      case AppLifecycleState.resumed:
        // GAP #4: sama seperti didPopNext — kalau app di-background SAAT init
        // in-flight, controller null → _pausedByCover tak pernah true; treat
        // resume sebagai uncover supaya state-machine tetap menyalakan.
        {
          final wasBackgrounded = _appBackgrounded;
          _appBackgrounded = false;
          _resumeFromCover(forceIfUncovered: wasBackgrounded);
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  bool get _dataSaverEnabled =>
      appSettingsStore.feedVideoQuality == 'data_saver';

  bool get _shouldAutoplay =>
      appSettingsStore.feedAutoplay && !_dataSaverEnabled;

  /// Playback dikendalikan coordinator (§2.1) — semua kontrol internal jadi
  /// laporan intent, bukan panggilan langsung ke controller.
  bool get _managed => widget.playbackManagedExternally;

  bool get _postHasAudio => widget.post.hasAudio != false;

  /// T8 — di managed view, error/loading/ready dibedakan dari sesi coordinator
  /// terikat ([_managedSession], hanya di-set bila sesi benar-benar
  /// [VideoPlayerSession]). Sesi fake non-VideoPlayerSession → _managedSession
  /// null → dianggap thumbnail (bukan error), jalur legacy tak terpengaruh.
  bool get _managedHasError => _managed && (_managedSession?.hasError ?? false);

  /// Loading managed: sesi terikat ADA, belum error, tapi controllernya belum
  /// terpasang/siap — init awal ATAU selama [VideoPlayerSession.retry] mengganti
  /// controller (controller lama sudah dilepas, yang baru belum lahir). Beda
  /// dari spinner legacy yang butuh `_videoController != null`.
  bool get _managedLoading {
    if (!_managed) return false;
    final session = _managedSession;
    if (session == null || session.hasError) return false;
    final ctrl = _videoController;
    return ctrl == null ||
        !ctrl.value.isInitialized ||
        !session.hasVisualOutput ||
        session.isRecoveringVisualOutput;
  }

  /// T8 — tombol "Coba lagi" di managed view: reset budget + re-init sesi
  /// coordinator. JANGAN membuat/men-dispose controller sendiri — coordinator
  /// satu-satunya pemilik (§2.1). Controller baru hasil retry diadopsi lewat
  /// listener REVISION sesi (identitas sesi tetap sama, controllernya yang
  /// berganti) → [_onManagedSessionRevision] → [_syncManagedSession].
  void _retryManagedSession() {
    final session = _managedSession;
    if (session == null) return;
    AppHaptics.tap();
    unawaited(session.retry());
    // Rebuild optimistis: singkirkan surface error + tampilkan spinner segera
    // (revision juga akan fire saat _init mulai, ini cuma menghindari 1 frame
    // error yang tersisa antara tap dan fire).
    if (mounted) setState(() {});
  }

  /// D1 (§2.2) — re-apply volume LIVE saat `feedMuted` berubah (jalur legacy
  /// non-managed). Aturan aktif-saja: HANYA controller post yang sedang tampil
  /// (`widget.isActive`) yang naik ke volume 1 saat unmute global; controller
  /// background/inactive TETAP volume 0 (unmute global tidak boleh membocorkan
  /// audio video di belakang). Dipanggil dari listener `appSettingsStore`;
  /// listener itu juga fire untuk setting lain (theme/haptics/quality) — apply
  /// volume di sini idempoten dan tak berbahaya untuk trigger tersebut.
  void _onFeedMutedChangedLive() {
    if (_managed || !mounted) return;
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (!widget.isActive) {
      // Non-aktif: pastikan tetap senyap (biasanya sudah 0).
      ctrl.setVolume(0);
      return;
    }
    ctrl.setVolume(
      !appSettingsStore.feedMuted &&
              _postHasAudio &&
              (_audioClaim?.isCurrent ?? false)
          ? 1
          : 0,
    );
  }

  /// Guard in-flight untuk [_maybeInitVideo] (fix A4): true selama sebuah
  /// init sedang berjalan supaya panggilan kedua (mis. tap saat loading)
  /// tidak memulai controller/download kedua.
  bool _initInFlight = false;
  bool _ownsLocalController = false;

  void _unregisterFrameOutput() {
    _frameOutputRegistration?.unregister();
    _frameOutputRegistration = null;
    _frameOutputController = null;
  }

  void _registerFrameOutput(VideoPlayerController controller) {
    if (_managed || !controller.value.isInitialized) return;
    if (identical(_frameOutputController, controller) &&
        (_frameOutputRegistration?.isRegistered ?? false)) {
      return;
    }
    _unregisterFrameOutput();
    try {
      _frameOutputRegistration = (widget.frameOutputHeartbeatService ??
              FrameOutputHeartbeatService.instance)
          .register(controller);
      _frameOutputController = controller;
    } catch (_) {
      // Native heartbeat support is optional and must never affect playback.
    }
  }

  void _replaceController(VideoPlayerController? controller) {
    if (identical(_videoController, controller)) return;
    _unregisterFrameOutput();
    _controllerGeneration++;
    _playbackDiscontinuitySequence++;
    _videoController = controller;
  }

  Future<void> _seekWithDiscontinuity(
    VideoPlayerController controller,
    Duration position,
  ) {
    _playbackDiscontinuitySequence++;
    return controller.seekTo(position);
  }

  void _commitLocalOwnership() {
    if (_ownsLocalController) return;
    _ownsLocalController = true;
    widget.onLocalOwnershipChanged?.call(true);
  }

  void _onLatePreloadAvailable() {
    if (!mounted || _managed || _initInFlight || _videoController != null) {
      return;
    }
    unawaited(_claimOrInitOnActivation(allowLocalInit: widget.isActive));
  }

  Future<_PreloadClaimState> _adoptPreloadedController() async {
    // Jalur klaim (fix A5): ambil dari map pemilik HANYA saat state ini
    // benar-benar mengadopsi (initState) — bukan pass-by-value di build
    // parent. Klaim adalah remove atomik: dua state tidak mungkin dapat
    // controller yang sama (nol double-adopt/double-dispose); controller
    // yang tidak pernah diklaim tetap di map dan di-dispose pemiliknya.
    VideoPlayerController? controller;
    CachedVideoPlayerPlus? cachedPlayer;
    final claim = widget.claimPreloadedVideo;
    if (claim != null) {
      final claimed = await claim();
      if (!mounted) {
        final cachedPlayer = claimed?.cachedPlayer;
        final controller = claimed?.controller;
        if (cachedPlayer != null || controller != null) {
          unawaited(_disposeUnadoptedPreload(
            wrapper: cachedPlayer,
            controller: controller,
          ));
        }
        return _PreloadClaimState.none;
      }
      if (claimed?.isPending ?? false) return _PreloadClaimState.pending;
      controller = claimed?.controller;
      cachedPlayer = claimed?.cachedPlayer;
    } else {
      controller = widget.preloadedController;
      cachedPlayer = widget.preloadedCachedPlayer;
    }
    if (_videoController != null || _initInFlight) {
      if (cachedPlayer != null || controller != null) {
        unawaited(_disposeUnadoptedPreload(
          wrapper: cachedPlayer,
          controller: controller,
        ));
      }
      return _PreloadClaimState.none;
    }
    if (controller == null) {
      // RACE FIX: post jadi aktif sebelum preload MP4 selesai — controller
      // belum masuk map (baru di-add di .then initialize), tapi wrapper
      // in-flight SUDAH ter-remove dari map oleh itemBuilder dan sampai ke
      // sini. Dulu wrapper ini dibiarkan → VideoPlayerController native
      // bocor (tidak pernah dispose). Sekarang: dispose begitu init-nya
      // settle; _maybeInitVideo lanjut bikin controller fresh.
      final orphan = cachedPlayer;
      if (orphan != null) {
        Future(() async {
          try {
            await _disposeUnadoptedPreload(wrapper: orphan);
          } catch (_) {}
        });
      }
      return _PreloadClaimState.none;
    }
    // Binding non-nullable — promotion `controller` gagal di dalam closure
    // onInit (variabel lokal assignable yang di-capture).
    final ctrl = controller;
    _resetBufferAheadReporting();
    _replaceController(ctrl);
    observeFeedPreloadAdopted(
      _observationObserver,
      postId: widget.post.id,
      controller: ctrl,
    );
    _commitLocalOwnership();
    // Adopt wrapper juga supaya child bisa dispose properly. Wrapper
    // might be null (legacy or unwrapped). Either way, controller-level
    // ops tetap work.
    _cachedPlayer = cachedPlayer;
    ctrl.addListener(_handleVideoPositionForCta);
    // Preloaded controller selalu sudah initialize() — timer reset di sini
    // cuma untuk kasus defensif (controller mungkin dispose dari luar). Kalau
    // sudah initialized, helper-nya early-return tanpa schedule spinner.
    _resetLoadingSpinnerTimer();
    // Managed (§2.1): coordinator yang set volume + play (via setActive).
    // Widget cuma merender VideoPlayer + overlay. Jangan sentuh controller.
    if (!_managed) {
      if (ctrl.value.isInitialized) _registerFrameOutput(ctrl);
      if (_canAutoplayNow()) {
        await _playLegacy(ctrl, 'adopt');
      } else {
        await ctrl.setVolume(0);
      }
      // HLS bisa ter-adopt SEBELUM initialize selesai (controller masuk map
      // sinkron, init jalan async). play()/setVolume di atas jadi no-op diam
      // → tanpa hook ini video stuck di poster sampai user interaksi.
      // Listener one-shot: begitu initialized, apply volume + play.
      if (!ctrl.value.isInitialized) {
        void onInit() {
          if (!ctrl.value.isInitialized) return;
          ctrl.removeListener(onInit);
          if (!mounted || _videoController != ctrl) return;
          _registerFrameOutput(ctrl);
          // Race fix: controller BENAR-BENAR siap sekarang — kalau Feed
          // sudah tertutup (route/app) di titik ini, paksa senyap eksplisit
          // + jangan play. _canAutoplayNow di bawah sudah blokir play(), tapi
          // setVolume(0) eksplisit di sini jadi pertahanan tambahan kalau ada
          // race lain.
          if (_routeCovered || _appBackgrounded) {
            ctrl.setVolume(0);
          } else {
            ctrl.setVolume(0);
          }
          if (_canAutoplayNow()) {
            unawaited(_playLegacy(ctrl, 'adopt-oninit'));
          }
          _cancelLoadingSpinnerDelay();
          if (mounted) setState(() {});
        }

        ctrl.addListener(onInit);
      }
    } else if (!ctrl.value.isInitialized) {
      // Managed: tetap butuh rebuild + cancel spinner saat init selesai
      // supaya VideoPlayer merender frame pertama (tanpa menyentuh playback).
      void onInit() {
        if (!ctrl.value.isInitialized) return;
        ctrl.removeListener(onInit);
        if (!mounted || _videoController != ctrl) return;
        _cancelLoadingSpinnerDelay();
        if (mounted) setState(() {});
      }

      ctrl.addListener(onInit);
    }
    if (mounted) setState(() {});
    return _PreloadClaimState.adopted;
  }

  // ── T7: managed-source dinamis (adopsi sesi via registry notifier) ──
  /// Sesi coordinator yang sedang terikat — dilistened `revision`-nya supaya
  /// controller yang lahir async (init selesai) langsung dirender. Hanya
  /// [VideoPlayerSession] yang punya controller; sesi fake (test) tidak.
  VideoPlayerSession? _managedSession;

  /// Coordinator membuat/menghapus sesi → re-cek `sessionFor(post.id)`.
  void _onCoordinatorRegistryChanged() {
    if (!mounted) return;
    _syncManagedSession();
    // Rebuild: sesi bisa lahir dalam keadaan loading/error tanpa mengganti
    // identitas controller (tetap null) — build harus ikut menampilkan
    // spinner / surface error meski _syncManagedSession tak setState.
    if (mounted) setState(() {});
  }

  /// Managed fullscreen receives user-pause state from the coordinator rather
  /// than guessing it from controller callbacks. This keeps the play/mute
  /// controls visible immediately after a tap in Profile -> Postingan.
  void _onCoordinatorPlaybackChanged() {
    if (!mounted || widget.coordinator == null) return;
    final paused = widget.coordinator!.isUserPaused(widget.post.id);
    if (_isPaused == paused) return;
    setState(() => _isPaused = paused);
  }

  /// Init controller sesi terikat selesai/gagal/retry → re-render. Revision
  /// bump menandai transisi loading→ready→error (KUNCI T8): controller BARU
  /// hasil retry (identitas sesi SAMA, controllernya berganti) dipungut di
  /// sini, dan transisi ready→error yang tak pernah punya controller tetap
  /// memicu surface error via setState di bawah.
  void _onManagedSessionRevision() {
    if (!mounted) return;
    _syncManagedSession();
    if (mounted) setState(() {});
  }

  /// Sinkronkan controller yang dirender dengan sesi coordinator untuk
  /// `post.id`. Idempoten: aman dipanggil dari initState, registry fire, dan
  /// revision fire. TIDAK pernah membuat controller sendiri (§2.1) — kalau sesi
  /// belum ada/controllernya belum lahir, render thumbnail/frozen.
  void _syncManagedSession() {
    final coord = widget.coordinator;
    if (coord == null || !mounted) return;
    final session = coord.sessionFor(widget.post.id);
    final videoSession = session is VideoPlayerSession ? session : null;
    // Rebind listener revision bila identitas sesi berubah (lahir / diganti /
    // dievict). Sesi fake (test) → videoSession null → cukup thumbnail.
    if (!identical(videoSession, _managedSession)) {
      _managedSession?.revision.removeListener(_onManagedSessionRevision);
      _managedSession = videoSession;
      _managedSession?.revision.addListener(_onManagedSessionRevision);
    }
    final ctrl = videoSession?.controller;
    if (ctrl == null) {
      // Sesi belum ada / controller belum init / sudah dievict-dispose oleh
      // coordinator → lepas referensi controller lama (jangan render controller
      // yang mungkin sudah mati) dan tampilkan thumbnail. TIDAK dispose:
      // coordinator satu-satunya pemilik.
      if (_videoController != null) {
        _videoController!.removeListener(_handleVideoPositionForCta);
        _resetBufferAheadReporting();
        _replaceController(null);
        if (mounted) setState(() {});
      }
      return;
    }
    if (identical(ctrl, _videoController)) return;
    _adoptManagedController(ctrl);
  }

  /// Adopsi controller dari sesi coordinator (bukan pemilik → tak pernah
  /// dispose). Controller sesi hanya di-set SETELAH init selesai, jadi ia
  /// dianggap siap dirender; cukup pasang listener CTA + rebuild.
  void _adoptManagedController(VideoPlayerController ctrl) {
    final old = _videoController;
    if (identical(old, ctrl)) return;
    old?.removeListener(_handleVideoPositionForCta);
    _resetBufferAheadReporting();
    _replaceController(ctrl);
    ctrl.addListener(_handleVideoPositionForCta);
    _cancelLoadingSpinnerDelay();
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
    _playbackHealthMonitor.observePlaybackStateTransition();
    _reportBufferAhead(ctrl.value);
    if (ctrl.value.isPlaying) _recordPlayMetric();
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

  void _resetBufferAheadReporting() {
    _lastReportedBufferAhead = null;
    _lastBufferAheadReportAt = null;
  }

  void _reportBufferAhead(VideoPlayerValue value) {
    final callback = widget.onBufferAheadChanged;
    if (callback == null || !widget.isActive || !value.isInitialized) return;
    final ahead = _bufferAhead(value);
    final previous = _lastReportedBufferAhead;
    final now = DateTime.now();
    final crossedThreshold = previous != null &&
        previous < const Duration(seconds: 3) &&
        ahead >= const Duration(seconds: 3);
    final enoughTime = _lastBufferAheadReportAt == null ||
        now.difference(_lastBufferAheadReportAt!) >= _bufferReportInterval;
    final enoughChange =
        previous == null || (ahead - previous).abs() >= _bufferReportMinDelta;
    if (!crossedThreshold && !(enoughTime && enoughChange)) return;
    _lastReportedBufferAhead = ahead;
    _lastBufferAheadReportAt = now;
    callback(ahead);
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
    if (oldWidget.post.id != widget.post.id && _commentDrawerMounted) {
      _forceDeactivateCommentDrawer(deferOverlayNotification: true);
    }
    if (oldWidget.isActive != widget.isActive) {
      _resetBufferAheadReporting();
      if (widget.isActive) {
        if (_videoController == null) {
          unawaited(_claimOrInitOnActivation());
        }
        // Managed: coordinator.setActive yang memutar video aktif; widget
        // tidak play() langsung (§2.1).
        if (_canAutoplayNow()) {
          final ctrl = _videoController;
          if (ctrl != null) unawaited(_playLegacy(ctrl, 'active'));
        }
        _syncProductRotation();
      } else {
        if (!_managed) _releaseAudio();
        _isPaused = false;
        _forceDeactivateCommentDrawer(deferOverlayNotification: true);
        _featuredProductIndex = 0;
        _commentDragOffset = 0;
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
        widget.onMediaZoomChanged(false);
        // Managed: coordinator yang mem-pause aktif-lama saat setActive ke
        // video lain (dan tetap pinned untuk resume di timestamp — §2.6).
        // Widget TIDAK pause/seek langsung supaya tidak mereset posisi.
        if (!_managed) {
          _videoController?.pause();
          try {
            _videoController?.setPlaybackSpeed(1.0);
          } catch (_) {}
          final controller = _videoController;
          if (controller != null) {
            unawaited(_seekWithDiscontinuity(controller, Duration.zero));
          }
        }
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
    // Managed (§2.1): controller di-attach dari luar (preloaded/claim);
    // widget tidak boleh membuat/mengunduh controllernya sendiri.
    if (_managed) return;
    if (!widget.isActive && !userInitiated) return;
    // Fix A4 — guard in-flight: init sedang berjalan untuk controller ini,
    // panggilan kedua (mis. tap :onTapMedia saat loading) no-op supaya tidak
    // ada dua controller / dua download.
    if (_initInFlight) return;
    final url = videoQualityService.resolvePlaybackUrl(
      widget.post.videoPlaybackUrl,
      dataSaverUrl: widget.post.videoDataSaverUrl,
      userPreference: appSettingsStore.feedVideoQuality,
    );
    if (url.isEmpty) return;
    if (_dataSaverEnabled && !userInitiated) return;
    if (!_initMetricStarted) {
      _initMetricStarted = true;
      _playbackHealthMonitor.record('video_init_started');
    }
    _initInFlight = true;
    try {
      await _runInitVideo(userInitiated: userInitiated);
    } finally {
      _initInFlight = false;
    }
  }

  Future<void> _claimOrInitOnActivation({bool allowLocalInit = true}) async {
    final claimState = await _adoptPreloadedController();
    if (!mounted || _videoController != null || !allowLocalInit) return;
    if (claimState == _PreloadClaimState.pending) return;
    await _maybeInitVideo();
  }

  Future<void> _runInitVideo({required bool userInitiated}) async {
    setState(() => _videoLoadFailed = false);
    // Sprint 2 #7 — Network-aware source selection + user preference.
    final resolvedUrl = videoQualityService.resolvePlaybackUrl(
      widget.post.videoPlaybackUrl,
      dataSaverUrl: widget.post.videoDataSaverUrl,
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
        await evictVideoMediaCache(
          mediaId: widget.post.id,
          url: resolvedUrl,
        );
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
    _playbackHealthMonitor.record('video_init_failed', {
      'duration_ms': _startupStopwatch.elapsedMilliseconds,
    });
  }

  /// Helper init satu attempt. Return true kalau sukses (controller
  /// ready & assigned ke _videoController), false kalau exception.
  /// Cleanup dispose dilakukan internal kalau gagal supaya caller tidak
  /// perlu handle leak.
  Future<bool> _tryInitVideoController({
    required String resolvedUrl,
    required bool useCacheWrapper,
    required bool userInitiated,
    Duration? initialPosition,
  }) async {
    final initGeneration = ++_localInitGeneration;
    CachedVideoPlayerPlus? wrapper;
    VideoPlayerController? controller;
    try {
      if (useCacheWrapper) {
        wrapper = CachedVideoPlayerPlus.networkUrl(
          Uri.parse(resolvedUrl),
          invalidateCacheIfOlderThan: const Duration(days: 7),
          cacheKey: videoMediaCacheKey(
            mediaId: widget.post.id,
            url: resolvedUrl,
          ),
        );
      } else {
        controller = VideoPlayerController.networkUrl(Uri.parse(resolvedUrl));
      }
      _localInitCachedPlayer = wrapper;
      _localInitController = controller;
      if (controller != null) {
        observeFeedLocalControllerCreated(
          _observationObserver,
          postId: widget.post.id,
          controller: controller,
        );
      }
      _cachedPlayer = wrapper;
      _resetLoadingSpinnerTimer();
      if (mounted) setState(() {});
      if (useCacheWrapper) {
        final initialization = wrapper!.initialize();
        _localCachedInitialization = initialization;
        await initialization;
        controller = wrapper.controller;
        _localInitController = controller;
      } else {
        await controller!.initialize();
      }
      final initializedController = controller;
      if (!_localInitIdentityIsCurrent(
        generation: initGeneration,
        wrapper: wrapper,
        controller: initializedController,
      )) {
        await _disposeLocalInitResource(
          wrapper: wrapper,
          controller: initializedController,
        );
        if (identical(_cachedPlayer, wrapper)) _cachedPlayer = null;
        return true;
      }
      if (useCacheWrapper) {
        observeFeedLocalControllerCreated(
          _observationObserver,
          postId: widget.post.id,
          controller: initializedController,
        );
      }
      final beforeObserveInitialized = widget.beforeObserveInitialized;
      if (beforeObserveInitialized != null) {
        await beforeObserveInitialized();
      }
      if (!_localInitIdentityIsCurrent(
        generation: initGeneration,
        wrapper: wrapper,
        controller: initializedController,
      )) {
        await _disposeLocalInitResource(
          wrapper: wrapper,
          controller: initializedController,
        );
        if (identical(_cachedPlayer, wrapper)) _cachedPlayer = null;
        return true;
      }
      observeFeedControllerInitialized(
        _observationObserver,
        postId: widget.post.id,
        controller: initializedController,
        ownerId: feedLocalOwnerId(widget.post.id),
      );
      _replaceController(initializedController);
      _resetBufferAheadReporting();
      _commitLocalOwnership();
      initializedController.addListener(_handleVideoPositionForCta);
      _registerFrameOutput(initializedController);
      _cancelLoadingSpinnerDelay();
      await initializedController.setLooping(true);
      if (initialPosition != null) {
        await _seekWithDiscontinuity(initializedController, initialPosition);
      }
      _playbackHealthMonitor.record('video_init_ready', {
        'duration_ms': _startupStopwatch.elapsedMilliseconds,
      });
      // Race fix: controller BENAR-BENAR siap sekarang (init selesai async) —
      // kalau Feed sudah tertutup di titik ini, paksa senyap eksplisit +
      // jangan play, walau init dimulai saat masih terlihat.
      await initializedController.setVolume(0);
      if (_canAutoplayNow(userInitiated: userInitiated)) {
        await _playLegacy(
          initializedController,
          'init',
          userInitiated: userInitiated,
        );
        _recordPlayMetric();
      }
      // Fix A1: JANGAN turunkan _isPaused dari state controller. Video yang
      // selesai init saat inactive (belum diputar) BUKAN "user pause" — kalau
      // di-set _isPaused=true di sini, gate autoplay saat jadi aktif
      // (didUpdateWidget) menolak play → video diam padahal user tak pernah
      // pause. _isPaused HANYA true dari aksi user eksplisit (_onTapMedia).
      setState(() {});
      return true;
    } catch (_) {
      _cancelLoadingSpinnerDelay();
      if (controller != null &&
          initGeneration == _localInitGeneration &&
          identical(wrapper, _localInitCachedPlayer) &&
          identical(controller, _localInitController)) {
        observeFeedControllerFailed(
          _observationObserver,
          postId: widget.post.id,
          controller: controller,
          ownerId: feedLocalOwnerId(widget.post.id),
        );
      }
      try {
        await _disposeLocalInitResource(
          wrapper: wrapper,
          controller: controller,
        );
      } catch (_) {}
      _cachedPlayer = null;
      _replaceController(null);
      return false;
    }
  }

  VideoPlaybackSnapshot _playbackHealthSnapshot() {
    final value = _videoController?.value;
    return VideoPlaybackSnapshot(
      shouldMonitor: shouldMonitorIntendedPlayback(
        intendsPlayback:
            !_managed && widget.isActive && !_isPaused && _canAutoplayNow(),
        isInitialized: value?.isInitialized ?? false,
      ),
      isBuffering: value?.isBuffering ?? false,
      position: value?.position ?? Duration.zero,
      duration: value?.duration ?? Duration.zero,
      bufferAhead: _bufferAhead(value),
      frameOutputCount: _frameOutputRegistration?.latest?.frameCount,
      playbackDiscontinuitySequence: _playbackDiscontinuitySequence,
    );
  }

  Duration _bufferAhead(VideoPlayerValue? value) {
    if (value == null) return Duration.zero;
    final position = value.position;
    var furthestEnd = position;
    for (final range in value.buffered) {
      if (range.end <= position) continue;
      if (range.start > furthestEnd) break;
      if (range.end > furthestEnd) {
        furthestEnd = range.end;
      }
    }
    return furthestEnd - position;
  }

  Future<void> _recoverPlaybackStall(Duration position) async {
    final controller = _videoController;
    if (controller == null ||
        !widget.isActive ||
        _isPaused ||
        !_canAutoplayNow()) {
      return;
    }
    await controller.pause();
    await _seekWithDiscontinuity(controller, position);
    if (_canAutoplayNow() && !_isPaused && widget.isActive) {
      await _playLegacy(controller, 'stall-recovery');
    }
  }

  Future<void> _recoverFrameOutputStall(
    Duration position,
    int attempt,
  ) async {
    final controller = _videoController;
    final generation = _controllerGeneration;
    final discontinuity = _playbackDiscontinuitySequence;
    if (controller == null || !_canAutoplayNow() || !widget.isActive) return;

    if (attempt == 1) {
      await controller.pause();
      if (!mounted ||
          generation != _controllerGeneration ||
          discontinuity != _playbackDiscontinuitySequence ||
          !identical(controller, _videoController)) {
        return;
      }
      await _seekWithDiscontinuity(controller, position);
      if (mounted &&
          generation == _controllerGeneration &&
          identical(controller, _videoController) &&
          _canAutoplayNow()) {
        await _playLegacy(controller, 'frame-stall-recovery-1');
      }
      return;
    }

    if (attempt != 2 || !widget.ownsController || !_ownsLocalController) return;
    final resolvedUrl = videoQualityService.resolvePlaybackUrl(
      widget.post.videoPlaybackUrl,
      dataSaverUrl: widget.post.videoDataSaverUrl,
      userPreference: appSettingsStore.feedVideoQuality,
    );
    if (resolvedUrl.isEmpty) return;

    final wrapper = _cachedPlayer;
    controller.removeListener(_handleVideoPositionForCta);
    _replaceController(null);
    _cachedPlayer = null;
    _localInitCachedPlayer = null;
    _localInitController = null;
    _localCachedInitialization = null;
    _releaseAudio();
    try {
      if (wrapper != null) {
        await wrapper.dispose();
      } else {
        await controller.dispose();
      }
    } finally {
      observeFeedControllerDisposed(
        _observationObserver,
        postId: widget.post.id,
        controller: controller,
        ownerId: feedLocalOwnerId(widget.post.id),
      );
    }
    if (!mounted ||
        _videoController != null ||
        discontinuity + 1 != _playbackDiscontinuitySequence) {
      return;
    }

    final rebuilt = await _tryInitVideoController(
      resolvedUrl: resolvedUrl,
      useCacheWrapper: !resolvedUrl.contains('.m3u8'),
      userInitiated: false,
      initialPosition: position,
    );
    if (!rebuilt && mounted) setState(() => _videoLoadFailed = true);
  }

  void _recordPlayMetric() {
    if (_playMetricRecorded) return;
    _playMetricRecorded = true;
    _playbackHealthMonitor.record('video_play_started', {
      'startup_ms': _startupStopwatch.elapsedMilliseconds,
    });
  }

  void _acquireCommentOverlayLock() {
    if (_commentOverlayLockHeld) return;
    _commentOverlayLockHeld = true;
    _commentOverlayLockEpoch++;
    widget.onOverlayStateChanged(true);
  }

  void _releaseCommentOverlayLock({bool deferNotification = false}) {
    if (!_commentOverlayLockHeld) return;
    _commentOverlayLockHeld = false;
    final notificationEpoch = ++_commentOverlayLockEpoch;
    final callback = widget.onOverlayStateChanged;
    if (!deferNotification) {
      callback(false);
      return;
    }
    scheduleMicrotask(() {
      if (_commentOverlayLockHeld ||
          notificationEpoch != _commentOverlayLockEpoch) {
        return;
      }
      callback(false);
    });
  }

  void _registerAndroidBackCommentCloser() {
    if (_androidBackCommentCloserRegistered) return;
    pushAndroidBackOverlayCloser(_androidBackCommentCloserCallback);
    _androidBackCommentCloserRegistered = true;
  }

  void _unregisterAndroidBackCommentCloser() {
    if (!_androidBackCommentCloserRegistered) return;
    _androidBackCommentCloserRegistered = false;
    popAndroidBackOverlayCloser(_androidBackCommentCloserCallback);
  }

  void _stopCommentSheetAnimation() {
    final controller = _commentSheetAnimationController;
    _commentSheetAnimationController = null;
    controller?.dispose();
  }

  void _animateCommentSheetExtent({
    required double target,
    required Duration duration,
    required Curve curve,
    required bool Function() isCurrent,
    VoidCallback? onComplete,
  }) {
    _stopCommentSheetAnimation();
    if (!_commentSheetController.isAttached || !isCurrent()) {
      onComplete?.call();
      return;
    }

    final begin = _commentSheetController.size;
    final animationController = AnimationController(
      vsync: this,
      duration: duration,
    );
    _commentSheetAnimationController = animationController;

    void applyExtent(double extent) {
      if (!mounted || !isCurrent() || !_commentSheetController.isAttached) {
        return;
      }
      try {
        _commentSheetController.jumpTo(extent);
      } catch (_) {
        // The sheet's scroll position can be replaced while data states swap.
      }
    }

    animationController.addListener(() {
      final progress = curve.transform(animationController.value);
      applyExtent(begin + ((target - begin) * progress));
    });
    animationController.addStatusListener((status) {
      if (status != AnimationStatus.completed ||
          !identical(_commentSheetAnimationController, animationController)) {
        return;
      }
      applyExtent(target);
      _commentSheetAnimationController = null;
      animationController.dispose();
      if (mounted && isCurrent()) onComplete?.call();
    });
    animationController.forward();
  }

  void _forceDeactivateCommentDrawer({
    bool deferOverlayNotification = false,
  }) {
    _commentDrawerOpenWatchdog?.cancel();
    _commentDrawerOpenWatchdog = null;
    _commentSheetTransitionEpoch++;
    _stopCommentSheetAnimation();
    _commentDrawerPhase = _CommentDrawerPhase.closed;
    _commentSheetControllerNeedsReset = true;
    _commentSheetReachedVisibleExtent = false;
    _activeCommentSession = null;
    _completeCommentDrawerClose();
    _commentDragOffset = 0;
    _unregisterAndroidBackCommentCloser();
    _releaseCommentOverlayLock(
      deferNotification: deferOverlayNotification,
    );
    _resumeAfterComments(allowLegacyPlayback: false);
  }

  @override
  void deactivate() {
    _forceDeactivateCommentDrawer(deferOverlayNotification: true);
    super.deactivate();
  }

  @override
  void dispose() {
    _forceDeactivateCommentDrawer(deferOverlayNotification: true);
    _legacyDisposed = true;
    _localInitGeneration++;
    _unregisterFrameOutput();
    if (!_managed) _releaseAudio();
    _playbackHealthMonitor.dispose();
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    // D1: lepas listener feedMuted live (hanya terpasang di jalur non-managed).
    if (!_managed) {
      appSettingsStore.removeListener(_onFeedMutedChangedLive);
      widget.preloadListenable?.removeListener(_onLatePreloadAvailable);
      if (_ownsLocalController) widget.onLocalOwnershipChanged?.call(false);
    }
    // T7: lepas listener registry + revision sesi (managed-source dinamis).
    if (_managed && widget.coordinator != null) {
      widget.coordinator!.registryListenable.removeListener(
        _onCoordinatorRegistryChanged,
      );
      widget.coordinator!.playbackListenable.removeListener(
        _onCoordinatorPlaybackChanged,
      );
    }
    _managedSession?.revision.removeListener(_onManagedSessionRevision);
    _managedSession = null;
    feedStore.removeListener(_onFeedStoreChanged);
    _loadingSpinnerDelay?.cancel();
    _commentDrawerOpenWatchdog?.cancel();
    _stopProductRotation();
    _commentSheetController.removeListener(_syncCommentSheetProgress);
    _commentSheetController.dispose();
    _commentSheetExtent.dispose();
    _videoController?.removeListener(_handleVideoPositionForCta);
    // Kontrak §2.1: kalau widget BUKAN pemilik controller (coordinator yang
    // pemilik, T3), JANGAN dispose — cukup lepas referensi. Coordinator
    // satu-satunya pemanggil dispose (nol double-dispose / audio hantu).
    if (widget.ownsController) {
      // Prefer dispose via wrapper — handle cache reference cleanup.
      // Wrapper.dispose() internally call controller.dispose() too, jadi
      // tidak perlu double-dispose. Kalau wrapper null (defensive), fallback
      // ke controller dispose direct.
      if (_cachedPlayer != null) {
        final cachedPlayer = _cachedPlayer!;
        if (identical(cachedPlayer, _localInitCachedPlayer)) {
          unawaited(_disposeLocalInitResource(wrapper: cachedPlayer));
        } else {
          final controller = _videoController ??
              (cachedPlayer.isInitialized ? cachedPlayer.controller : null);
          unawaited(() async {
            try {
              await cachedPlayer.dispose();
            } finally {
              if (controller != null) {
                observeFeedControllerDisposed(
                  _observationObserver,
                  postId: widget.post.id,
                  controller: controller,
                  ownerId: feedLocalOwnerId(widget.post.id),
                );
              }
            }
          }());
        }
      } else {
        final controller = _videoController ?? _localInitController;
        if (identical(controller, _localInitController)) {
          unawaited(_disposeLocalInitResource(controller: controller));
        } else {
          if (controller != null) {
            unawaited(() async {
              try {
                await controller.dispose();
              } finally {
                observeFeedControllerDisposed(
                  _observationObserver,
                  postId: widget.post.id,
                  controller: controller,
                  ownerId: feedLocalOwnerId(widget.post.id),
                );
              }
            }());
          }
        }
      }
    }
    _cachedPlayer = null;
    _replaceController(null);
    _heartBurstController.dispose();
    super.dispose();
  }

  void _syncCommentSheetProgress() {
    if (!_commentDrawerMounted || !_commentSheetController.isAttached) return;
    final hostHeight = _commentSheetHostHeight(context);
    final maxExtent = _commentSheetMaxExtentFor(context, hostHeight);
    final size = _commentSheetController.size;
    final extent = size.clamp(_commentSheetMinExtent, maxExtent).toDouble();
    if (extent >= _commentSheetDismissExtent) {
      _commentSheetReachedVisibleExtent = true;
    }
    if ((_commentSheetExtent.value - extent).abs() > 0.002) {
      _commentSheetExtent.value = extent;
    }
    if (!_commentSheetClosingFromDrag && extent >= _commentSheetDismissExtent) {
      _activeCommentSession?.sheetExtent = extent;
    }

    // Pause/resume video ala IG Reels — full-screen comment sheet berarti
    // video harus hilang dari layar dan berhenti (bukan cuma tersembunyi).
    final shouldPause = shouldPauseForCommentExtent(
      extent: extent,
      maxExtent: maxExtent,
    );
    if (_managed) {
      // Managed (§2.1): comment sheet full = cover → lapor pause/resume ke
      // coordinator, jangan sentuh controller. Pakai flag lokal untuk
      // memastikan lapor sekali per transisi.
      if (shouldPause && !_pausedByCommentSheet) {
        _pausedByCommentSheet = true;
        widget.onRequestPause?.call(CoverPauseReason.commentSheetFull);
      } else if (!shouldPause && _pausedByCommentSheet) {
        _pausedByCommentSheet = false;
        widget.onRequestPlay?.call();
      }
    } else {
      final ctrl = _videoController;
      if (shouldPause &&
          !_pausedByCommentSheet &&
          ctrl != null &&
          ctrl.value.isInitialized &&
          ctrl.value.isPlaying) {
        _pausedByCommentSheet = true;
        ctrl.pause();
      } else if (!shouldPause && _pausedByCommentSheet) {
        _pausedByCommentSheet = false;
        if (_canAutoplayNow() && ctrl != null && ctrl.value.isInitialized) {
          unawaited(_playLegacy(ctrl, 'comment-close'));
        }
      }
    }
  }

  double _commentSheetHostHeight(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return math.max(1.0, screenHeight - keyboardInset);
  }

  /// Full-height ala IG: sheet naik sampai top hampir menyentuh status
  /// bar (respect top safe area). Clamp bawah tetap di initial extent
  /// (0.60) untuk safety kalau top inset sangat besar (mis. notch device
  /// aneh / testing environment).
  double _commentSheetMaxExtentFor(BuildContext context, double hostHeight) {
    final topSafeArea = MediaQuery.paddingOf(context).top;
    final extent = 1 - (topSafeArea / math.max(1.0, hostHeight));
    return extent.clamp(_commentSheetInitialExtent, 1.0).toDouble();
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
    _productRotationTimer = Timer.periodic(const Duration(milliseconds: 2500), (
      _,
    ) {
      if (!mounted || !widget.isActive) return;
      setState(() {
        _featuredProductIndex = (_featuredProductIndex + 1) % products.length;
      });
    });
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
        fresh.viewerSaved == _saved &&
        fresh.likeCount == _likeCount &&
        fresh.commentCount == _commentCount &&
        fresh.shareCount == _shareCount) {
      return;
    }
    setState(() {
      _liked = newLiked;
      _saved = fresh.viewerSaved;
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
    } on FeedViewerChangedException {
      // Completion belongs to the account that was active before login/logout.
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

  Future<void> _onSavePressed() async {
    AppHaptics.tap();
    try {
      await feedStore.toggleSaved(widget.post.id);
    } on FeedViewerChangedException {
      // The new viewer owns the rebased saved state.
    } catch (error) {
      if (!mounted) return;
      if (error is ApiException && error.statusCode == 401) {
        if (memberStore.isLoggedIn) await memberStore.logout();
        if (!mounted) return;
        Navigator.pushNamed(context, '/member/login');
        return;
      }
      AppToast.show(
        context,
        error is ApiException && error.statusCode == 404
            ? 'Postingan tidak tersedia.'
            : 'Postingan belum bisa disimpan. Coba lagi.',
        kind: ToastKind.warning,
      );
    }
  }

  /// Double-tap → like (kalau belum) + heart burst di posisi jari.
  /// Instagram Reels signature gesture.
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
    if (_commentDrawerPhase != _CommentDrawerPhase.closed) return;
    if (_commentSheetControllerNeedsReset) {
      _commentSheetController.removeListener(_syncCommentSheetProgress);
      _commentSheetController.dispose();
      _commentSheetController = DraggableScrollableController()
        ..addListener(_syncCommentSheetProgress);
      _commentSheetControllerNeedsReset = false;
    }
    AppHaptics.tap();
    FocusScope.of(context).unfocus();
    _acquireCommentOverlayLock();
    // Register closer ke Android back coordinator — Samsung Back press
    // di MainNavigationScreen akan call ini DULU sebelum tab nav /
    // double-back exit. Closer dipanggil ulang via _closeComments,
    // sehingga state UI + back stack sync.
    _registerAndroidBackCommentCloser();
    _activeCommentSession = feedCommentSessionStore.sessionFor(
      viewerId: memberStore.profile?.id ?? 'guest',
      postId: widget.post.id,
    );
    _completeCommentDrawerClose();
    _commentDrawerClosedCompleter = Completer<void>();
    setState(() {
      _commentDrawerPhase = _CommentDrawerPhase.opening;
      _commentSheetReachedVisibleExtent = false;
      _commentDragOffset = 0;
      // Panel caption tertutup saat komentar dibuka — dua panel baca
      // tidak boleh tumpang tindih.
      _captionExpanded = false;
    });
    final transitionEpoch = ++_commentSheetTransitionEpoch;
    _commentSheetExtent.value = _commentSheetMinExtent;
    _scheduleCommentDrawerOpen(transitionEpoch);
    _commentDrawerOpenWatchdog?.cancel();
    _commentDrawerOpenWatchdog = Timer(
      const Duration(milliseconds: 700),
      () {
        if (!mounted ||
            transitionEpoch != _commentSheetTransitionEpoch ||
            !_commentDrawerMounted) {
          return;
        }
        final visible = _commentSheetExtent.value >= _commentSheetDismissExtent;
        if (!visible) {
          _forceDeactivateCommentDrawer();
          if (mounted) setState(() {});
        }
      },
    );
  }

  void _scheduleCommentDrawerOpen(int transitionEpoch, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!mounted ||
            transitionEpoch != _commentSheetTransitionEpoch ||
            _commentDrawerPhase != _CommentDrawerPhase.opening) {
          return;
        }
        if (!_commentSheetController.isAttached) {
          if (attempt < 2) {
            _scheduleCommentDrawerOpen(
              transitionEpoch,
              attempt: attempt + 1,
            );
            WidgetsBinding.instance.scheduleFrame();
            return;
          }
          _forceDeactivateCommentDrawer();
          if (mounted) setState(() {});
          return;
        }
        _animateCommentDrawerOpen(transitionEpoch);
      });
    });
  }

  void _animateCommentDrawerOpen(int transitionEpoch) {
    if (!mounted ||
        transitionEpoch != _commentSheetTransitionEpoch ||
        _commentDrawerPhase != _CommentDrawerPhase.opening ||
        !_commentSheetController.isAttached) {
      return;
    }
    final maxExtent = _commentSheetMaxExtentFor(
      context,
      _commentSheetHostHeight(context),
    );
    final targetExtent =
        (_activeCommentSession?.sheetExtent ?? _commentSheetInitialExtent)
            .clamp(_commentSheetInitialExtent, maxExtent)
            .toDouble();
    _animateCommentSheetExtent(
      target: targetExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      isCurrent: () =>
          mounted &&
          transitionEpoch == _commentSheetTransitionEpoch &&
          _commentDrawerPhase == _CommentDrawerPhase.opening,
      onComplete: () {
        _commentDrawerOpenWatchdog?.cancel();
        _commentDrawerOpenWatchdog = null;
        if (mounted) {
          setState(() => _commentDrawerPhase = _CommentDrawerPhase.open);
        }
      },
    );
  }

  /// Stable reference closer untuk Android back coordinator. Method
  /// (bukan variable assignment ke lambda) supaya consistent reference
  /// + lint-clean. Identitas reference match via tear-off di push/pop.
  void _androidBackCommentCloser() {
    // consumeAndroidBackOverlay removes the closer before invoking it. Put it
    // back immediately so another back press during the close animation is
    // consumed by this drawer instead of reaching the route underneath.
    _androidBackCommentCloserRegistered = false;
    if (!_commentDrawerMounted) return;
    _registerAndroidBackCommentCloser();
    _closeComments();
  }

  void _closeComments() {
    if (_commentDrawerPhase == _CommentDrawerPhase.closed ||
        _commentDrawerPhase == _CommentDrawerPhase.closing) {
      return;
    }
    FocusScope.of(context).unfocus();
    AppHaptics.tap();
    final transitionEpoch = ++_commentSheetTransitionEpoch;
    if (mounted) {
      setState(() {
        _commentDrawerPhase = _CommentDrawerPhase.closing;
        _commentDragOffset = 0;
      });
    }

    void finishClose() {
      if (!mounted ||
          transitionEpoch != _commentSheetTransitionEpoch ||
          _commentDrawerPhase != _CommentDrawerPhase.closing) {
        return;
      }
      _commentSheetExtent.value = _commentSheetMinExtent;
      setState(() {
        _commentDrawerPhase = _CommentDrawerPhase.closed;
        _commentSheetReachedVisibleExtent = false;
      });
      _commentSheetControllerNeedsReset = true;
      _activeCommentSession = null;
      _completeCommentDrawerClose();
      _unregisterAndroidBackCommentCloser();
      _releaseCommentOverlayLock();

      // Resume only after the drawer is fully gone. This avoids audio
      // returning while a closing sheet still covers the video.
      _resumeAfterComments();
    }

    if (!_commentSheetController.isAttached) {
      finishClose();
      return;
    }
    final size = _commentSheetController.size;
    final durationMs = (size * 340).clamp(120, 280).round();
    final closeDuration = Duration(milliseconds: durationMs);
    _animateCommentSheetExtent(
      target: _commentSheetMinExtent,
      duration: closeDuration,
      curve: Curves.easeOutCubic,
      isCurrent: () =>
          mounted &&
          transitionEpoch == _commentSheetTransitionEpoch &&
          _commentDrawerPhase == _CommentDrawerPhase.closing,
      onComplete: finishClose,
    );
    // Defensive completion: platform/text-field transitions can detach the
    // draggable position without completing its visual animation. Never let
    // that leave an invisible drawer/back lease mounted indefinitely.
    unawaited(
      Future<void>.delayed(
        closeDuration + const Duration(milliseconds: 32),
        finishClose,
      ),
    );
  }

  Future<void> _closeCommentsAndWait() {
    final closeCompleter = _commentDrawerClosedCompleter;
    _closeComments();
    return closeCompleter?.future ?? Future<void>.value();
  }

  void _completeCommentDrawerClose() {
    final completer = _commentDrawerClosedCompleter;
    _commentDrawerClosedCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _resumeAfterComments({bool allowLegacyPlayback = true}) {
    if (!_pausedByCommentSheet) return;
    _pausedByCommentSheet = false;
    final ctrl = _videoController;
    if (_managed) {
      widget.onRequestPlay?.call();
    } else if (allowLegacyPlayback &&
        _canAutoplayNow() &&
        ctrl != null &&
        ctrl.value.isInitialized) {
      unawaited(_playLegacy(ctrl, 'comment-close-full'));
    }
  }

  void _onCommentDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (!_commentSheetController.isAttached || delta == 0) return;
    _stopCommentSheetAnimation();
    if (_commentDrawerPhase == _CommentDrawerPhase.opening && mounted) {
      setState(() => _commentDrawerPhase = _CommentDrawerPhase.open);
    }
    final screenHeight = math.max(1.0, MediaQuery.sizeOf(context).height);
    final maxExtent = _commentSheetMaxExtentFor(
      context,
      _commentSheetHostHeight(context),
    );
    // Tracking penuh 0..maxExtent — jari mengikuti sheet sepanjang seluruh
    // rentang (ala IG Reels), tidak berhenti di suatu extent minimum.
    final nextSize = (_commentSheetController.size - (delta / screenHeight))
        .clamp(0.0, maxExtent)
        .toDouble();
    _commentSheetController.jumpTo(nextSize);
  }

  void _onCommentDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final size = _commentSheetController.isAttached
        ? _commentSheetController.size
        : _commentSheetInitialExtent;
    final maxExtent = _commentSheetMaxExtentFor(
      context,
      _commentSheetHostHeight(context),
    );
    final target = commentSnapTargetFor(
      size: size,
      velocity: velocity,
      maxExtent: maxExtent,
    );
    switch (target) {
      case CommentSnapTarget.close:
        _closeComments();
      case CommentSnapTarget.max:
        _activeCommentSession?.sheetExtent = maxExtent;
        _animateCommentSheetTo(maxExtent);
      case CommentSnapTarget.initial:
        _activeCommentSession?.sheetExtent = _commentSheetInitialExtent;
        _animateCommentSheetTo(_commentSheetInitialExtent);
    }
  }

  void _animateCommentSheetTo(double target) {
    if (!_commentSheetController.isAttached || !_commentDrawerMounted) return;
    final transitionEpoch = _commentSheetTransitionEpoch;
    _animateCommentSheetExtent(
      target: target,
      duration: feedCommentSnapDuration,
      curve: Curves.easeOutCubic,
      isCurrent: () =>
          mounted &&
          transitionEpoch == _commentSheetTransitionEpoch &&
          (_commentDrawerPhase == _CommentDrawerPhase.opening ||
              _commentDrawerPhase == _CommentDrawerPhase.open),
      onComplete: () {
        if (mounted && _commentDrawerPhase == _CommentDrawerPhase.opening) {
          setState(() => _commentDrawerPhase = _CommentDrawerPhase.open);
        }
      },
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
    if (_shareInFlight) return;
    _shareInFlight = true;
    AppHaptics.tap();
    final url =
        '${ApiConfig.publicSiteUrl}/feed/${Uri.encodeComponent(widget.post.id)}';
    final caption = widget.post.title.isNotEmpty
        ? '${widget.post.title}\n$url'
        : 'Lihat di Natalo Petshop:\n$url';
    final box = context.findRenderObject() as RenderBox?;
    try {
      final result = await Share.share(
        caption,
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
      if (result.status != ShareResultStatus.success || !mounted) return;
      feedStore.incrementShareCount(widget.post.id);
      final serverCount = await feedService.trackShare(widget.post.id);
      if (serverCount != null) {
        feedStore.setShareCount(widget.post.id, serverCount);
      }
    } catch (_) {
      // Native share dibatalkan/gagal.
    } finally {
      _shareInFlight = false;
    }
  }

  void _onMediaDoubleTapDown(TapDownDetails details) {
    _heartBurstPosition = details.localPosition;
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
        builder: (_) => _FullScreenVideoPage(
          controller: ctrl,
          hasAudio: widget.post.hasAudio,
        ),
        fullscreenDialog: true,
      ),
    );
    widget.onOverlayStateChanged(false);
    // POIN 2 (satu pintu lengkap): resume dari cinema-mode WAJIB lewat gate
    // legacy. `_openCinemaMode` saat ini dead code (`unused_element`), tapi
    // kalau kelak diaktifkan, restore playback tanpa gate bisa memutar video
    // Feed walau route lain sudah menutup Feed (mis. pop cinema langsung ke
    // route non-Feed) atau app di-background — persis kelas audio-hantu yang
    // sedang di-hardening. Bungkus dengan `_canAutoplayNow()` supaya patuh
    // master-guard (isCurrent) + lifecycle.
    if (mounted && wasPlaying && !ctrl.value.isPlaying && _canAutoplayNow()) {
      unawaited(_playLegacy(ctrl, 'cinema'));
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

  void _addFeedLinkToCart(FeedProductLink link, {int quantity = 1}) {
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

  void _buyFeedLinkNow(FeedProductLink link, {int quantity = 1}) {
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

  void _addProductToCart(Product product, {int quantity = 1}) {
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

  void _buyProductNow(Product product, {int quantity = 1}) {
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
    // Managed (§2.1): tap = intent user-toggle ke coordinator; widget tidak
    // play/pause langsung dan tidak init sendiri (controller dari luar).
    if (_managed) {
      widget.onRequestUserTogglePlay?.call();
      return;
    }
    final ctrl = _videoController;
    if (ctrl == null) {
      await _maybeInitVideo(userInitiated: true);
      if (mounted) setState(() => _isPaused = false);
      return;
    }
    if (ctrl.value.isPlaying) {
      _releaseAudio();
      ctrl.pause();
      ctrl.setVolume(0);
      setState(() => _isPaused = true);
    } else {
      _isPaused = false;
      // User-initiated: pertahanan berlapis via _canAutoplayNow (tetap wajib
      // !_routeCovered && !_appBackgrounded — kalau user genuinely tap,
      // route seharusnya sudah tidak covered).
      if (_canAutoplayNow(userInitiated: true)) {
        unawaited(_playLegacy(ctrl, 'tap', userInitiated: true));
      }
      setState(() {});
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
    // Managed (§2.1): playback dikuasai coordinator — peek-pause & 2x-speed
    // menyentuh controller pinjaman langsung → race (resume bisa menembus
    // _suspended = audio hantu; speed 2x bisa nyangkut kalau widget disposed
    // mid-press). Nonaktifkan gesture ini saat managed (default aman D5/§2.1).
    if (_managed) return;
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
    // Managed: gesture di-nonaktifkan di _onLongPressStart → tidak ada state
    // long-press yang perlu di-resume/reset di sini. Guard simetris supaya
    // tak ada ctrl.play/setPlaybackSpeed/seek langsung saat managed.
    if (_managed) return;
    final ctrl = _videoController;
    if (_longPressPaused) {
      setState(() {
        _longPressPaused = false;
        _hideOverlayForLongPress = false;
      });
      if (ctrl != null && _canAutoplayNow(userInitiated: true)) {
        // Resume cuma kalau user tidak previously tap-paused juga.
        unawaited(
          _playLegacy(ctrl, 'longpress-end', userInitiated: true),
        );
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
          await _seekWithDiscontinuity(ctrl, pos);
        }
      } catch (_) {}
    }
  }

  Future<void> _toggleMuteWhilePaused() async {
    final ctrl = _videoController;
    if (ctrl == null || !_isPaused || widget.post.hasAudio == false) return;
    AppHaptics.tap();
    final nextMuted = !appSettingsStore.feedMuted;
    await appSettingsStore.setFeedMuted(nextMuted);
    await ctrl.setVolume(
      !nextMuted && _postHasAudio && (_audioClaim?.isCurrent ?? false) ? 1 : 0,
    );
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
        // Managed (§2.1): visibilitas jadi laporan intent ke coordinator,
        // bukan panggilan play/pause langsung. Coordinator yang memutuskan
        // (aktif + tidak user-pause + tidak suspend → resume).
        if (_managed) {
          final visibleEnough = info.visibleFraction > 0.7 && widget.isActive;
          widget.onVisibleChanged?.call(visibleEnough);
          return;
        }
        if (ctrl == null) return;
        if (info.visibleFraction > 0.7 && _canAutoplayNow()) {
          if (!ctrl.value.isPlaying) {
            // GAP #3: kembalikan volume saat kembali terlihat & aktif. Init
            // yang selesai di bawah cover memaksa setVolume(0); jalur VD-resume
            // dulu play() TANPA unmute → video main senyap. _canAutoplayNow
            // sudah menjamin aktif + tak covered + tak user-pause, jadi ini
            // hanya menyentuh video yang benar-benar akan main (bukan inactive).
            unawaited(_playLegacy(ctrl, 'visibility'));
          }
        } else {
          _releaseAudio();
          ctrl.setVolume(0);
          ctrl.pause();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          final commentSheetHostHeight = math.max(
            1.0,
            constraints.biggest.height - keyboard,
          );
          final commentSheetMaxExtent = _commentSheetMaxExtentFor(
            context,
            commentSheetHostHeight,
          );
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
          // Rail sengaja 12dp lebih rendah dari caption supaya action terbawah
          // sejajar metadata bawah, sama seperti foto carousel.
          // Dulu video +32 (di atas seluruh box scrubber) → melayang jauh
          // di atas garis progress, beda 28px dari foto. Sekarang overlap
          // 12px ke atas hit-area scrub (zona transparan) — sisa 16px +
          // area garis tetap bisa di-scrub, persis kompromi IG.
          final feedInfoInset = navClearance + feedPostOverlayBottomGap;
          final actionRailInset = navClearance + feedPostActionRailBottomGap;
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
                  AnimatedPadding(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.only(bottom: keyboard),
                    child:
                        NotificationListener<DraggableScrollableNotification>(
                      onNotification: (notification) {
                        // A drag that starts inside the comment list is owned
                        // by DraggableScrollableSheet, so the custom handle's
                        // onDragEnd is not called. Once the sheet has actually
                        // opened, reaching its minimum must still complete the
                        // overlay teardown instead of leaving an invisible
                        // backdrop that intercepts all taps.
                        if (_commentSheetReachedVisibleExtent &&
                            !_commentSheetClosingFromDrag &&
                            notification.extent <= 0.01) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _closeComments();
                          });
                        }
                        return false;
                      },
                      child: DraggableScrollableSheet(
                        controller: _commentSheetController,
                        initialChildSize: _commentSheetMinExtent,
                        minChildSize: _commentSheetMinExtent,
                        maxChildSize: commentSheetMaxExtent,
                        snap: true,
                        snapSizes:
                            commentSheetMaxExtent > _commentSheetInitialExtent
                                ? [
                                    _commentSheetInitialExtent,
                                    commentSheetMaxExtent,
                                  ]
                                : const [_commentSheetInitialExtent],
                        builder: (context, scrollController) {
                          return PrimaryScrollController(
                            controller: scrollController,
                            child: FeedCommentSheet(
                              post: widget.post,
                              applyKeyboardInset: false,
                              sheetScrollController: scrollController,
                              onClose: _closeComments,
                              onCloseAndWait: _closeCommentsAndWait,
                              onDragUpdate: _onCommentDragUpdate,
                              onDragEnd: _onCommentDragEnd,
                            ),
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
                        child: Semantics(
                          container: true,
                          label: post.mediaAccessibilityLabel,
                          hint: 'Ketuk untuk menjeda atau memutar video',
                          child: GestureDetector(
                            onTap: () => unawaited(_onTapMedia()),
                            onDoubleTapDown: _onMediaDoubleTapDown,
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
                      ),
                      // Error surface — jalur legacy (_videoLoadFailed) ATAU
                      // managed (sesi coordinator error, T8). Tombol "Coba lagi"
                      // memanggil retry yang tepat: legacy → _maybeInitVideo
                      // (bikin controller sendiri); managed → session.retry()
                      // (coordinator yang re-init + tetap pemilik controller).
                      if (_videoLoadFailed || _managedHasError)
                        Positioned.fill(
                          child: Center(
                            child: _VideoRetryButton(
                              onRetry: _managedHasError
                                  ? _retryManagedSession
                                  : _maybeInitVideo,
                            ),
                          ),
                        ),
                      // Managed loading (T8): sesi terikat sedang init awal /
                      // retry (controller belum siap) → spinner LANGSUNG (tanpa
                      // delay) sebagai feedback sesudah user tap "Coba lagi".
                      // Thumbnail _MediaBackground tetap di baliknya.
                      if (_managedLoading)
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
                            hasAudio: post.hasAudio,
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
                          child: IgnorePointer(child: FeedPostScrim()),
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
                              // Klaim drag vertikal supaya PageView feed di
                              // atasnya tidak ikut pindah post saat user
                              // menarik di area scrim (mode baca = modal
                              // gesture). No-op: panel tetap, tidak paging.
                              onVerticalDragStart: (_) {},
                              onVerticalDragUpdate: (_) {},
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
                        if (widget.isActive &&
                            _videoController != null &&
                            post.subtitleUrl?.trim().isNotEmpty == true)
                          Positioned(
                            left: 40,
                            right: 84,
                            bottom: constraints.maxHeight * 0.28,
                            child: FeedWebVttSubtitleOverlay(
                              controller: _videoController!,
                              subtitleUrl: post.subtitleUrl,
                              trustedMediaUrl: post.videoPlaybackUrl,
                              visible: !_commentSheetOpen &&
                                  !_hideOverlayForPinchZoom,
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
                              // §2.1: managed → scrubber seek-only (nol
                              // ctrl.play/pause; tak ada resume yang menembus
                              // suspend coordinator).
                              managed: _managed,
                              onScrubbingChanged: (scrubbing) {
                                if (!mounted) return;
                                if (scrubbing && !_isScrubbing) {
                                  _playbackDiscontinuitySequence++;
                                }
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
                                saved: _saved,
                                onLike: _onLikePressed,
                                onComment: _onComment,
                                onShare: _onShare,
                                onSave: _onSavePressed,
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
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        child: AnimatedSlide(
                                          offset: _captionExpanded
                                              ? const Offset(0, 0.12)
                                              : Offset.zero,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          child: AnimatedOpacity(
                                            opacity: _captionExpanded ? 0 : 1,
                                            duration: const Duration(
                                              milliseconds: 220,
                                            ),
                                            curve: Curves.easeOut,
                                            child: IgnorePointer(
                                              ignoring: _captionExpanded,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 12,
                                                ),
                                                child:
                                                    _ProductCommerceOverlayGroup(
                                                  featuredProduct:
                                                      featuredProduct!,
                                                  showProductCard:
                                                      _endOfVideoCtaVisible &&
                                                          !_commentSheetOpen,
                                                  onTap: () => _onProductsTap(
                                                    products,
                                                  ),
                                                  onBuy: () => _quickAddProduct(
                                                    featuredProduct,
                                                  ),
                                                  onQuickAdd: () =>
                                                      _quickAddProduct(
                                                    featuredProduct,
                                                  ),
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
                                    onMentionTap: (handle) => Navigator.of(
                                      context,
                                    ).pushNamed('/u', arguments: handle),
                                  ),
                                  FeedPostSocialProof(post: post),
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

  /// Aturan fit ala IG Reels: video portrait 9:16 dipertahankan sebagai
  /// canvas terpusat tanpa crop horizontal. Video yang lebih "pendek"
  /// (4:5, square, landscape) memakai letterbox agar tidak terasa zoom.
  /// The fallback ratio is used when metadata is unavailable so thumbnail
  /// and player framing remain stable while the video initializes.
  static const double _reelsAspect = 9 / 16;

  static double _normalizedAspect({double? postAspect, Size? videoSize}) {
    final measured = videoSize == null || videoSize.height <= 0
        ? null
        : videoSize.width / videoSize.height;
    final candidate = measured ?? postAspect;
    return candidate != null && candidate.isFinite && candidate > 0
        ? candidate
        : _reelsAspect;
  }

  static BoxFit _fitForAspect(double aspect, Size viewport) {
    // Keep every feed video inside its source canvas. This is especially
    // important for portrait media that is taller than 9:16: using `cover`
    // there crops the sides on a tall phone viewport and makes the subject
    // appear zoomed. The viewport argument remains part of the helper API so
    // thumbnail/player framing stays centralized and consistent.
    return BoxFit.contain;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = videoController;

    if (ctrl != null && ctrl.value.isInitialized) {
      final size = ctrl.value.size;
      // Rasio dari dimensi AKTUAL player (metadata server bisa salah).
      final aspect = _normalizedAspect(videoSize: size);
      final fit = compactPreview
          ? BoxFit.contain
          : _fitForAspect(aspect, MediaQuery.sizeOf(context));
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
      final fit = compactPreview
          ? BoxFit.contain
          : _fitForAspect(
              _normalizedAspect(postAspect: post.aspectRatio),
              MediaQuery.sizeOf(context),
            );
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
  final bool? hasAudio;

  const _FullScreenVideoPage({required this.controller, this.hasAudio});

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
    appSettingsStore.addListener(_onAppSettingsChanged);
    widget.controller.setVolume(
      widget.hasAudio == false || appSettingsStore.feedMuted ? 0 : 1,
    );
    if (!widget.controller.value.isPlaying) {
      widget.controller.play();
    }
  }

  void _onAppSettingsChanged() {
    unawaited(
      widget.controller.setVolume(
        widget.hasAudio == false || appSettingsStore.feedMuted ? 0 : 1,
      ),
    );
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    appSettingsStore.removeListener(_onAppSettingsChanged);
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
  final bool? hasAudio;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePlayPause;

  const _PausedVideoControls({
    required this.hasAudio,
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
        if (hasAudio == false)
          const FeedNoAudioIndicator()
        else
          _PausedControlButton(
            semanticLabel: muted ? 'Aktifkan suara' : 'Matikan suara',
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
          semanticLabel: 'Putar video',
          diameter: 52,
          scrimAlpha: 0.40,
          inkRadius: 36,
          onTap: onTogglePlayPause,
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 28,
            shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
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
  final String semanticLabel;
  final double diameter;
  final double scrimAlpha;
  final double inkRadius;
  final VoidCallback onTap;
  final Widget child;

  const _PausedControlButton({
    required this.semanticLabel,
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
    final tapSize = math.max(48.0, widget.diameter);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: Material(
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
            child: SizedBox(
              height: tapSize,
              width: tapSize,
              child: Center(
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
    return const CustomPaint(size: Size(22, 10), painter: _DownArrowPainter());
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

  const _FeedCartSheet({required this.onOpenFullCart});

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
                                      color: const Color(0xFF2A2F36),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: const Color(0xFF2A2F36),
                                    ),
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
                                        color: Colors.white.withValues(
                                          alpha: 0.45,
                                        ),
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
                  colors: [Color(0xFF5FBFFF), Color(0xFF1E87FF)],
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
            color: const Color(
              0xFF1E5BFF,
            ).withValues(alpha: enabled ? 0.65 : 0.15),
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
