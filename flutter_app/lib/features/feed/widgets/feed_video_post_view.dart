import 'dart:async';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../config/api_config.dart';
import '../../../theme/natalo_text.dart';
import '../../../models/feed_post.dart';
import '../../../models/product.dart';
import '../../../services/api_client.dart';
import '../../../services/block_service.dart';
import '../../../services/feed_service.dart';
import '../../../services/product_service.dart';
import '../../../services/report_service.dart';
import '../../../services/video_quality_service.dart';
import '../../../state/feed_comment_session_store.dart';
import '../../../state/feed_local_store.dart';
import '../../../state/feed_store.dart';
import '../../../state/member_store.dart';
import '../../../state/settings_store.dart';
import '../../../utils/android_back_overlays.dart';
import '../../../utils/app_route_observer.dart';
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
import 'double_tap_burst_guard.dart';
import 'feed_action_rail.dart';
import 'feed_accessibility_overlay.dart';
import 'feed_creator_overlay.dart';
import 'feed_link_cart_actions.dart';
import 'feed_post_scrim.dart';
import 'feed_post_shared_widgets.dart';
import 'feed_product_links_sheet.dart';
import 'feed_video_scrubber.dart';

/// D4 legacy — seam test: override fetch post segar untuk refresh signed-URL
/// (default produksi: `feedService.fetchPostById`). Pola sama dengan
/// `debugScopedFeedPostFetcher` di member_post_detail_screen.dart.
@visibleForTesting
Future<FeedPost?> Function(String id)? debugLegacyFeedPostFetcher;

typedef FeedVideoHealthMonitorFactory = VideoPlaybackHealthMonitor Function({
  required VideoPlaybackSnapshot Function() readSnapshot,
  required Future<void> Function(Duration position) onPlaybackStall,
  required FrameOutputStallRecover onFrameOutputStall,
  required Map<String, Object> metricContext,
});

enum FeedVideoFraming {
  immersive,
  mainFeed,
  fullscreenFeed,
}

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
///  - [productSheet] → `pauseAll` (sheet Links produk terbuka menutup video).
enum CoverPauseReason {
  routePush,
  appBackground,
  commentSheetFull,
  productSheet
}

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

  /// Main Feed owns a fixed media viewport that ends above its bottom
  /// navigation. Other surfaces retain the existing immersive fit-width
  /// framing so this visual change cannot leak into scoped fullscreen.
  final FeedVideoFraming framing;

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
    this.framing = FeedVideoFraming.immersive,
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
      final observer = _observationObserver;
      final postId = widget.post.id;
      await _localWrapperDisposeGuard.dispose(wrapper, () async {
        if (!wrapper.isInitialized && initialization != null) {
          await wrapper.dispose();
          unawaited(() async {
            try {
              await initialization;
              if (!wrapper.isInitialized) return;
              final controllerIdentity = wrapper.controller;
              await wrapper.dispose();
              observeFeedControllerDisposed(
                observer,
                postId: postId,
                controller: controllerIdentity,
                ownerId: feedLocalOwnerId(postId),
              );
            } catch (_) {}
          }());
          return;
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

  /// D4 legacy — override URL playback segar hasil refresh signed-URL
  /// (init gagal + URL bertanda-tangan basi → re-fetch post). Null = pakai
  /// data widget.post apa adanya. Di-reset di didUpdateWidget kalau parent
  /// mengirim URL playback baru (data parent menang).
  String? _refreshedVideoPlaybackUrl;
  String? _refreshedDataSaverUrl;

  String get _effectivePlaybackUrl =>
      _refreshedVideoPlaybackUrl ?? widget.post.videoPlaybackUrl;

  String? get _effectiveDataSaverUrl => _refreshedVideoPlaybackUrl != null
      ? _refreshedDataSaverUrl
      : widget.post.videoDataSaverUrl;
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
  bool _pausedByProductSheet = false;
  int _commentSheetTransitionEpoch = 0;
  int _featuredProductIndex = 0;
  Timer? _productRotationTimer;
  Timer? _commentDrawerOpenWatchdog;
  Timer? _commentStrandedSettleTimer;
  int _activeCommentDrawerPointers = 0;
  final Map<int, VelocityTracker> _commentDrawerVelocityTrackers =
      <int, VelocityTracker>{};
  double _commentDragOffset = 0;

  bool get _commentDrawerMounted =>
      _commentDrawerPhase != _CommentDrawerPhase.closed;

  // Keep the existing visual treatment through the closing animation. The
  // explicit phase, rather than this presentation getter, owns transitions.
  bool get _commentSheetOpen => _commentDrawerMounted;

  bool get _commentSheetClosingFromDrag =>
      _commentDrawerPhase == _CommentDrawerPhase.closing;

  // Panel caption ala IG: saat terbuka, scrim gelap naik + pill produk
  // fade menghilang (mode baca fokus). State di-lift ke sini supaya semua
  // elemen ber-transisi serempak dan tap area video bisa menutup panel.
  bool _captionExpanded = false;

  void _setCaptionExpanded(bool value) {
    if (_captionExpanded == value || !mounted) return;
    setState(() => _captionExpanded = value);
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
    var initializationObservedAfterAdoption = false;
    void observeInitializedAfterAdoption() {
      if (initializationObservedAfterAdoption) return;
      initializationObservedAfterAdoption = true;
      observeFeedControllerInitialized(
        _observationObserver,
        postId: widget.post.id,
        controller: ctrl,
        ownerId: feedLocalOwnerId(widget.post.id),
      );
    }

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
    // Pasang listener SEBELUM command playback pertama. HLS dapat selesai
    // initialize ketika play/setVolume masih menunggu platform; bila listener
    // dipasang sesudah await tersebut, lifecycle initialized bisa terlewat.
    if (!ctrl.value.isInitialized) {
      void onInit() {
        if (!ctrl.value.isInitialized) return;
        ctrl.removeListener(onInit);
        if (!mounted || _videoController != ctrl) return;
        observeInitializedAfterAdoption();
        _cancelLoadingSpinnerDelay();
        if (!_managed) {
          _registerFrameOutput(ctrl);
          // Controller yang selesai init setelah route/app tertutup harus
          // tetap senyap. Playback hanya dilanjutkan lewat gate existing.
          ctrl.setVolume(0);
          if (_canAutoplayNow()) {
            unawaited(_playLegacy(ctrl, 'adopt-oninit'));
          }
        }
        if (mounted) setState(() {});
      }

      ctrl.addListener(onInit);
    }
    // Managed (§2.1): coordinator yang set volume + play (via setActive).
    // Widget cuma merender VideoPlayer + overlay. Jangan sentuh controller.
    if (!_managed) {
      if (ctrl.value.isInitialized) _registerFrameOutput(ctrl);
      if (_canAutoplayNow()) {
        await _playLegacy(ctrl, 'adopt');
      } else {
        await ctrl.setVolume(0);
      }
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

  /// Listener position video → observe playback health/buffer/play metric.
  /// Dipanggil tiap frame video (puluhan kali/detik). Cepat-keluar untuk
  /// kondisi yang gak perlu re-render supaya gak ngabisin frame budget.
  void _handleVideoPositionForCta() {
    final ctrl = _videoController;
    if (ctrl == null || !mounted) return;
    _playbackHealthMonitor.observePlaybackStateTransition();
    _reportBufferAhead(ctrl.value);
    if (ctrl.value.isPlaying) _recordPlayMetric();
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
    // D4 legacy: parent kirim URL playback baru (post segar) → data parent
    // menang atas override hasil refresh internal.
    if (oldWidget.post.videoPlaybackUrl != widget.post.videoPlaybackUrl) {
      _refreshedVideoPlaybackUrl = null;
      _refreshedDataSaverUrl = null;
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
        // Managed: post tak lagi aktif (swipe) → akhiri gesture TANPA resume.
        _endManagedGesture(allowResume: false);
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
      _effectivePlaybackUrl,
      dataSaverUrl: _effectiveDataSaverUrl,
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
      _effectivePlaybackUrl,
      dataSaverUrl: _effectiveDataSaverUrl,
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

    // Attempt 3 (D4, port dari jalur managed VideoPlayerSession
    // `_maybeRefreshSignedUrl`): signed-URL Bunny (expiry 6 jam) bisa basi
    // (cache offline feed lama, sesi panjang, clock skew) → CDN 403 →
    // kedua attempt di atas gagal SELAMANYA untuk URL yang sama. Kalau URL
    // tampak bertanda-tangan, fetch post segar (`GET /api/feed/posts/:id`
    // di-sign ulang server tiap request) lalu SATU retry dengan URL baru.
    // Maks sekali per siklus _runInitVideo (tap "Coba lagi" = siklus baru).
    final looksSigned =
        resolvedUrl.contains('token=') && resolvedUrl.contains('expires=');
    if (looksSigned && await _maybeRefreshSignedPlaybackUrl()) {
      if (!mounted) return;
      final refreshedUrl = videoQualityService.resolvePlaybackUrl(
        _effectivePlaybackUrl,
        dataSaverUrl: _effectiveDataSaverUrl,
        userPreference: appSettingsStore.feedVideoQuality,
      );
      if (refreshedUrl.isNotEmpty && refreshedUrl != resolvedUrl) {
        _playbackHealthMonitor.record('video_url_refreshed');
        // Bypass cache wrapper: URL beda query = cache-miss, wrapper tak
        // memberi benefit di retry ini.
        final thirdAttempt = await _tryInitVideoController(
          resolvedUrl: refreshedUrl,
          useCacheWrapper: false,
          userInitiated: userInitiated,
        );
        if (thirdAttempt || !mounted) return;
      }
    }
    if (!mounted) return;

    setState(() => _videoLoadFailed = true);
    _playbackHealthMonitor.record('video_init_failed', {
      'duration_ms': _startupStopwatch.elapsedMilliseconds,
    });
  }

  /// D4 legacy best-effort: fetch post segar dan simpan URL playback baru ke
  /// override [_refreshedVideoPlaybackUrl]. True hanya bila dapat URL yang
  /// non-kosong dan BERBEDA dari yang sekarang dipakai; selain itu (null,
  /// kosong, sama, error apa pun) → false tanpa efek samping.
  Future<bool> _maybeRefreshSignedPlaybackUrl() async {
    try {
      final fetchById = debugLegacyFeedPostFetcher ?? feedService.fetchPostById;
      final fresh = await fetchById(widget.post.id);
      if (!mounted || fresh == null) return false;
      final freshUrl = fresh.videoPlaybackUrl.trim();
      if (freshUrl.isEmpty || freshUrl == _effectivePlaybackUrl) return false;
      final freshSaver = fresh.videoDataSaverUrl?.trim();
      _refreshedVideoPlaybackUrl = freshUrl;
      _refreshedDataSaverUrl =
          (freshSaver == null || freshSaver.isEmpty) ? null : freshSaver;
      return true;
    } catch (_) {
      return false;
    }
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
      _effectivePlaybackUrl,
      dataSaverUrl: _effectiveDataSaverUrl,
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
    _commentStrandedSettleTimer?.cancel();
    _commentStrandedSettleTimer = null;
    _resetCommentDrawerPointerTracking();
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
    // Managed: teardown selagi gesture aktif → akhiri lease TANPA resume
    // (widget lenyap, tak boleh ada resume/speed nyangkut). Coordinator tetap
    // pemilik sesi; ini cuma melepas gesture, bukan dispose sesi.
    _endManagedGesture(allowResume: false);
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
    _doubleTapBurstGuard.dispose();
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
    // Sesi hanya menyimpan DETENT VALID (initial / expanded), bukan partial
    // extent — kontrak state machine. Dulu setiap tick >= dismiss (0.30)
    // ditulis mentah, sehingga band terlarang [0.30, 0.60) ikut tersimpan
    // dan hanya "aman" karena pembaca kebetulan meng-clamp. Live tracking
    // di antara detent tidak ditulis; drag-end/settle menulis detent final.
    if (!_commentSheetClosingFromDrag) {
      if ((extent - _commentSheetInitialExtent).abs() <=
          feedCommentTerminalExtentEpsilon) {
        _activeCommentSession?.sheetExtent = _commentSheetInitialExtent;
      } else if (extent >= maxExtent - feedCommentTerminalExtentEpsilon) {
        _activeCommentSession?.sheetExtent = maxExtent;
      }
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
    // Tekan single-tap nyasar dari burst-like (tap ganjil) — lihat
    // [DoubleTapBurstGuard].
    _doubleTapBurstGuard.registerDoubleTap();
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
    // Listener pointer ikut unmount bersama drawer sebelumnya — mulai sesi
    // pointer-tracking bersih.
    _resetCommentDrawerPointerTracking();
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
    // Nilai tersimpan bisa berasal dari konteks maxExtent BERBEDA (keyboard
    // terbuka menyusutkan max). Snap ke detent terdekat KONTEKS SEKARANG —
    // reopen wajib mendarat di initial atau expanded, bukan di antara.
    final stored = _activeCommentSession?.sheetExtent;
    final targetExtent = stored == null
        ? _commentSheetInitialExtent
        : (stored >= (_commentSheetInitialExtent + maxExtent) / 2
            ? maxExtent
            : _commentSheetInitialExtent);
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
    _commentStrandedSettleTimer?.cancel();
    _commentStrandedSettleTimer = null;
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

  /// Pointer cancellation di handle = release berkecepatan nol — policy
  /// [commentSnapTargetFor] yang sama (kontrak Release Policy). Tanpa ini,
  /// drag yang dibatalkan sistem meninggalkan sheet di extent jumpTo terakhir
  /// yang arbitrer, tanpa snap framework sebagai fallback.
  void _onCommentDragCancel() {
    _onCommentDragEnd(DragEndDetails());
  }

  // ── Release-settle content-drag (paritas dengan FeedReelsCommentSurface) ──
  // Pointer di area drawer di-track mentah (Listener, bukan gesture arena):
  // pelepasan pointer TERAKHIR diselesaikan lewat policy bersama
  // [commentSnapTargetFor] dengan velocity dari VelocityTracker. Settle tidak
  // pernah berjalan selama masih ada pointer aktif — drawer wajib tetap
  // mengikuti jari (tidak boleh disambar dari genggaman yang masih menahan).

  void _onCommentDrawerPointerDown(PointerDownEvent event) {
    _activeCommentDrawerPointers++;
    _commentStrandedSettleTimer?.cancel();
    _commentStrandedSettleTimer = null;
    _commentDrawerVelocityTrackers[event.pointer] =
        VelocityTracker.withKind(event.kind);
  }

  void _onCommentDrawerPointerMove(PointerMoveEvent event) {
    _commentDrawerVelocityTrackers[event.pointer]
        ?.addPosition(event.timeStamp, event.position);
  }

  void _onCommentDrawerPointerUp(PointerUpEvent event) {
    final tracker = _commentDrawerVelocityTrackers.remove(event.pointer);
    _activeCommentDrawerPointers =
        math.max(0, _activeCommentDrawerPointers - 1);
    if (_activeCommentDrawerPointers > 0) return;
    _scheduleCommentReleaseSettle(
      tracker?.getVelocity().pixelsPerSecond.dy ?? 0,
    );
  }

  void _onCommentDrawerPointerCancel(PointerCancelEvent event) {
    _commentDrawerVelocityTrackers.remove(event.pointer);
    _activeCommentDrawerPointers =
        math.max(0, _activeCommentDrawerPointers - 1);
    if (_activeCommentDrawerPointers > 0) return;
    // Cancellation = release berkecepatan nol (Release Policy).
    _scheduleCommentReleaseSettle(0);
  }

  void _resetCommentDrawerPointerTracking() {
    _activeCommentDrawerPointers = 0;
    _commentDrawerVelocityTrackers.clear();
  }

  /// Timer Duration.zero menunda satu putaran event-loop supaya arena
  /// gesture (drag-end handle / ballistic framework) berjalan dulu; kalau
  /// jalur itu sudah mengambil alih, pemeriksaan applicable menolak.
  void _scheduleCommentReleaseSettle(double velocity) {
    _commentStrandedSettleTimer?.cancel();
    _commentStrandedSettleTimer = Timer(Duration.zero, () {
      if (!_commentStrandedSettleApplicable()) return;
      final size = _commentSheetController.size;
      // Di/atas initial: framework snap initial<->max sudah sesuai policy.
      // Di bawah initial: policy bersama yang memutuskan (paritas handle).
      if (size >=
          _commentSheetInitialExtent - feedCommentTerminalExtentEpsilon) {
        return;
      }
      _onCommentDragEnd(
        DragEndDetails(
          velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
          primaryVelocity: velocity,
        ),
      );
    });
  }

  bool _commentStrandedSettleApplicable() {
    return mounted &&
        _commentDrawerMounted &&
        _commentDrawerPhase != _CommentDrawerPhase.closing &&
        _commentDrawerPhase != _CommentDrawerPhase.opening &&
        _activeCommentDrawerPointers == 0 &&
        _commentSheetAnimationController == null &&
        _commentSheetController.isAttached;
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

  Future<void> _openProductLinksSheet(List<FeedProductLink> products) async {
    if (products.isEmpty) return;
    AppHaptics.tap();
    await showFeedProductLinksSheet(
      context,
      products: products,
      onOpenProduct: (link) => _openProductLinkDetail(link),
      onAddToCart: (link) => _addFeedLinkToCart(link),
      onOpened: () {
        widget.onOverlayStateChanged(true);
        _pauseForProductSheet();
      },
      onClosed: () {
        widget.onOverlayStateChanged(false);
        _resumeAfterProductSheet();
      },
    );
  }

  void _pauseForProductSheet() {
    if (_managed) {
      if (!_pausedByProductSheet) {
        _pausedByProductSheet = true;
        widget.onRequestPause?.call(CoverPauseReason.productSheet);
      }
      return;
    }
    final ctrl = _videoController;
    if (!_pausedByProductSheet &&
        ctrl != null &&
        ctrl.value.isInitialized &&
        ctrl.value.isPlaying) {
      _pausedByProductSheet = true;
      ctrl.pause();
    }
  }

  void _resumeAfterProductSheet() {
    if (!_pausedByProductSheet) return;
    _pausedByProductSheet = false;
    if (_managed) {
      widget.onRequestPlay?.call();
      return;
    }
    final ctrl = _videoController;
    if (_canAutoplayNow() && ctrl != null && ctrl.value.isInitialized) {
      unawaited(_playLegacy(ctrl, 'product-sheet-close'));
    }
  }

  Future<void> _openProductLinkDetail(FeedProductLink link) async {
    final product = await productService.fetchProductBySlug(link.slug);
    if (!mounted) return;
    if (product == null) {
      AppToast.showBanner(
        context,
        'Produk tidak ditemukan.',
        kind: ToastKind.info,
      );
      return;
    }
    _openProductDetail(product);
  }

  void _addFeedLinkToCart(FeedProductLink link, {int quantity = 1}) {
    unawaited(addFeedLinkToCart(context, link, quantity: quantity));
  }

  void _openProductDetail(Product product) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/product-detail', arguments: product);
  }

  Future<void> _onTapMedia() async {
    // Burst-like guard: single-tap yang datang tepat sesudah double-tap-like
    // (tap ganjil dalam burst) adalah noise — jangan toggle play/pause.
    if (_doubleTapBurstGuard.shouldSuppressSingleTap) return;
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

  /// Menekan single-tap nyasar dari burst double-tap-like (tap ganjil).
  final DoubleTapBurstGuard _doubleTapBurstGuard = DoubleTapBurstGuard();

  /// Lease gesture transien AKTIF saat managed (long-press → coordinator).
  /// Non-null hanya selama jari menahan di mode managed. SELURUH otoritas
  /// resume/speed ada di coordinator; widget cuma memegang handle untuk
  /// mengakhiri gesture (lepas jari / teardown).
  TransientGestureLease? _activeGestureLease;

  /// Akhiri gesture managed yang sedang aktif (bila ada). [allowResume] false
  /// dipakai saat teardown/swipe (post tak lagi aktif → jangan resume); true
  /// saat lepas jari natural.
  void _endManagedGesture({required bool allowResume}) {
    final lease = _activeGestureLease;
    if (lease == null) return;
    _activeGestureLease = null;
    unawaited(lease.end(allowResume: allowResume));
  }

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

    // Zone detection: 0-0.4 = left, 0.4-0.6 = center, 0.6-1.0 = right.
    // Center zone dibuat lebih kecil supaya 2x speed lebih mudah
    // di-trigger (zona kiri/kanan luas).
    final width = _mediaAreaWidth > 0
        ? _mediaAreaWidth
        : MediaQuery.of(context).size.width;
    final ratio = (details.localPosition.dx / width).clamp(0.0, 1.0);
    final isCenterZone = ratio >= 0.4 && ratio <= 0.6;

    // Managed (§2.1): playback dikuasai coordinator. Peek-pause & 2x-speed
    // TIDAK boleh menyentuh controller pinjaman langsung (race: resume nembus
    // _suspended = audio hantu; speed 2x nyangkut kalau disposed mid-press).
    // Delegasikan ke coordinator via lease — SELURUH otoritas/gate resume di
    // sana. Coordinator menolak (null) kalau post tak aktif/tak eligible.
    if (_managed) {
      final coordinator = widget.coordinator;
      if (coordinator == null) return;
      final kind = isCenterZone
          ? TransientGestureKind.peekPause
          : TransientGestureKind.doubleSpeed;
      final lease = coordinator.beginTransientGesture(widget.post.id, kind);
      if (lease == null) return; // coordinator menolak → no-op.
      AppHaptics.impact();
      setState(() {
        _activeGestureLease = lease;
        _hideOverlayForLongPress = true;
      });
      return;
    }

    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;

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
    // Managed: lepas jari natural → akhiri lease dengan allowResume:true.
    // Coordinator yang memutuskan boleh-resume atau tidak (post masih aktif &
    // eligible). Widget TIDAK menyentuh controller/speed langsung.
    if (_managed) {
      if (_activeGestureLease != null) {
        if (mounted) {
          setState(() => _hideOverlayForLongPress = false);
        }
        _endManagedGesture(allowResume: true);
      }
      return;
    }
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
          final mainFeedFraming =
              widget.framing == FeedVideoFraming.mainFeed && !minimized;
          final mediaBottomInset =
              mainFeedFraming ? MediaQuery.paddingOf(context).bottom : 0.0;

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
                  // Listener pointer mentah: melacak pointer aktif + velocity
                  // supaya pelepasan pointer TERAKHIR diselesaikan lewat
                  // policy bersama (release-settle) — paritas handle vs
                  // content-drag + pertahanan untuk recognizer/scrollable
                  // yang mati mid-gesture tanpa pernah memanggil drag-end.
                  Listener(
                    onPointerDown: _onCommentDrawerPointerDown,
                    onPointerMove: _onCommentDrawerPointerMove,
                    onPointerUp: _onCommentDrawerPointerUp,
                    onPointerCancel: _onCommentDrawerPointerCancel,
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.only(bottom: keyboard),
                      child:
                          NotificationListener<DraggableScrollableNotification>(
                        onNotification: (notification) {
                          // A drag that starts inside the comment list is
                          // owned by DraggableScrollableSheet, so the custom
                          // handle's onDragEnd is not called. Once the sheet
                          // has actually opened, reaching its minimum must
                          // still complete the overlay teardown instead of
                          // leaving an invisible backdrop that intercepts all
                          // taps. depth == 0 = hanya sheet drawer ini, bukan
                          // scrollable nested lain (kontrak design).
                          if (notification.depth != 0) return false;
                          if (notification.extent >=
                              _commentSheetDismissExtent) {
                            _commentSheetReachedVisibleExtent = true;
                          }
                          if (_commentSheetReachedVisibleExtent &&
                              !_commentSheetClosingFromDrag &&
                              notification.extent <=
                                  _commentSheetMinExtent +
                                      feedCommentTerminalExtentEpsilon) {
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
                            // scrollController TIDAK dipasang ke daftar komentar
                            // (yang bikin scroll komentar menyeret sheet naik →
                            // video pause). Ia di-anchor oleh
                            // CommentSheetScrollAnchor supaya
                            // DraggableScrollableController tetap isAttached;
                            // FeedCommentSheet memakai controller list sendiri
                            // (sheetScrollController: null). Overscroll list di
                            // tepi atas → pull-to-dismiss via policy handle.
                            return CommentSheetScrollAnchor(
                              controller: scrollController,
                              onPullDown: _onCommentDragUpdate,
                              onPullSettle: _onCommentDragCancel,
                              child: FeedCommentSheet(
                                post: widget.post,
                                applyKeyboardInset: false,
                                sheetScrollController: null,
                                onClose: _closeComments,
                                onCloseAndWait: _closeCommentsAndWait,
                                onDragUpdate: _onCommentDragUpdate,
                                onDragEnd: _onCommentDragEnd,
                                onDragCancel: _onCommentDragCancel,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                FeedCommentMediaFrame(
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
                        key: const ValueKey('feed-video-media-viewport'),
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: mediaBottomInset,
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
                                framing: widget.framing,
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
                              // userInitiated:true WAJIB — tanpa ini, user
                              // dgn Mode Hemat Data ON tap "Coba lagi" jadi
                              // no-op diam (guard data-saver di
                              // _maybeInitVideo menolak init non-user-
                              // initiated), padahal tombol ini SELALU aksi
                              // eksplisit user.
                              onRetry: _managedHasError
                                  ? _retryManagedSession
                                  : () => unawaited(
                                      _maybeInitVideo(userInitiated: true)),
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
                            // Fade bareng rail aksi + bottom nav saat
                            // pinch-zoom (sebelumnya scrubber diam total,
                            // tak terpengaruh zoom sama sekali — beda dari
                            // rail aksi/info yang sudah fade). Durasi 200ms
                            // disamakan dgn FeedActionRail supaya ketiganya
                            // (nav, rail aksi, scrubber) melebur serempak.
                            child: AnimatedOpacity(
                              opacity: _hideOverlayForPinchZoom ? 0 : 1,
                              duration: const Duration(milliseconds: 200),
                              child: IgnorePointer(
                                ignoring: _hideOverlayForPinchZoom,
                                child: FeedVideoScrubber(
                                  controller: _videoController!,
                                  isCurrent: widget.isActive,
                                  // §2.1: managed → scrubber seek-only (nol
                                  // ctrl.play/pause; tak ada resume yang
                                  // menembus suspend coordinator).
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
                                                child: feedProductPillFor(
                                                  products,
                                                  _featuredProductIndex,
                                                  onTap: () =>
                                                      _openProductLinksSheet(
                                                    products,
                                                  ),
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

/// Menjembatani state reaktif (memberStore + followOverrides + follow
/// service) dengan widget bersama `FeedCreatorIdentity`
/// (features/feed/widgets/feed_creator_overlay.dart) — tetap di
/// feed_screen.dart karena terikat langsung ke model FeedAuthor & service
/// layer, bukan bagian widget presentasional yang di-share.

/// Fit lapisan media untuk framing "feed" (mainFeed / fullscreenFeed).
///
/// Semua orientasi → [BoxFit.contain] (letterbox, bar hitam mengisi sisa
/// ruang) supaya video tampil UTUH — `cover` memotong sisi yang kelebihan
/// (landscape: kiri-kanan; portrait/persegi non-9:16: atas-bawah, mis.
/// creative iklan brand yang bukan native 9:16). Paritas IG: grid & viewer
/// IG tidak pernah cover-crop video (dibuktikan screenshot device), dan
/// Postingan sudah dibetulkan ke prinsip sama — Beranda & fullscreen feed
/// menyusul supaya konsisten satu app, bukan cuma di landscape.
BoxFit resolveFeedCoverFit({
  required FeedVideoFraming framing,
  required bool isLandscape,
}) {
  if (framing == FeedVideoFraming.mainFeed ||
      framing == FeedVideoFraming.fullscreenFeed) {
    return BoxFit.contain;
  }
  return BoxFit.cover;
}

class _MediaBackground extends StatelessWidget {
  final FeedPost post;
  final VideoPlayerController? videoController;
  final bool compactPreview;
  final FeedVideoFraming framing;

  const _MediaBackground({
    required this.post,
    required this.videoController,
    this.compactPreview = false,
    this.framing = FeedVideoFraming.immersive,
  });

  /// Fit lapisan media: selalu penuhi LEBAR layar. Ini menjaga video pada
  /// skala naturalnya tanpa terasa "zoom" — beda dengan `cover` yang memaksa
  /// tinggi & memotong sisi pada media yang lebih lebar dari 9:16.
  static const BoxFit _foregroundFit = BoxFit.fitWidth;

  /// Rata ATAS: video mulai penuh dari tepi atas layar persis IG. Untuk media
  /// yang lebih pendek dari layar (non-9:16) sisa ruang jatuh SELURUHNYA di
  /// bawah — di belakang chrome (kartu produk, caption) — bukan terbagi rata
  /// atas-bawah yang menurunkan komposisi. Latar dasar tetap hitam polos;
  /// tidak ada blurred backdrop di Feed/fullscreen normal.
  static const Alignment _foregroundAlign = Alignment.topCenter;

  /// Susun media di atas latar hitam. `media` sudah fit-lebar + rata atas
  /// sendiri; StackFit.expand memberi constraint fullscreen sehingga sisa
  /// ruang bawah = area hitam (ala IG), bukan letterbox terbagi.
  static Widget _mediaStack(Widget media) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        media,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = videoController;

    if (ctrl != null && ctrl.value.isInitialized) {
      final size = ctrl.value.size;
      // Preview kompak (drawer komentar minimized): pertahankan contain
      // sederhana & terpusat, terpisah dari kebijakan Feed/fullscreen.
      if (compactPreview) {
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            FittedBox(
              fit: BoxFit.contain,
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
      Widget videoLayer(
        BoxFit fit, {
        Alignment alignment = _foregroundAlign,
      }) =>
          FittedBox(
            fit: fit,
            alignment: alignment,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(ctrl),
            ),
          );
      if (framing == FeedVideoFraming.mainFeed ||
          framing == FeedVideoFraming.fullscreenFeed) {
        final fit = resolveFeedCoverFit(
          framing: framing,
          isLandscape: size.width > size.height,
        );
        // Contain (landscape fullscreen) rata tengah supaya bar hitam terbagi
        // atas-bawah; cover tetap rata atas (ala IG).
        return _mediaStack(
          videoLayer(
            fit,
            alignment:
                fit == BoxFit.contain ? Alignment.center : _foregroundAlign,
          ),
        );
      }
      return _mediaStack(
        videoLayer(_foregroundFit),
      );
    }
    final thumb = post.thumbnailUrl;
    if (thumb != null) {
      if (compactPreview) {
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            CachedNetworkImage(
              imageUrl: thumb,
              fit: BoxFit.contain,
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ],
        );
      }
      if (framing == FeedVideoFraming.mainFeed ||
          framing == FeedVideoFraming.fullscreenFeed) {
        // Samakan fit dgn video (pakai aspect post — thumbnail tampil sebelum
        // controller siap) supaya tak ada lompatan cover→contain saat player
        // ready untuk video landscape.
        final fit = resolveFeedCoverFit(
          framing: framing,
          isLandscape: post.aspectWidthInt > post.aspectHeightInt,
        );
        return _mediaStack(
          CachedNetworkImage(
            imageUrl: thumb,
            fit: fit,
            alignment:
                fit == BoxFit.contain ? Alignment.center : Alignment.topCenter,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        );
      }
      // Thumbnail mengikuti framing yang sama dengan video (fit-lebar + rata
      // atas) → tidak ada lompatan saat player siap.
      return _mediaStack(
        CachedNetworkImage(
          imageUrl: thumb,
          fit: _foregroundFit,
          alignment: _foregroundAlign,
          placeholder: (_, __) => const SizedBox.shrink(),
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        ),
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
                  fontWeight: NataloWeight.strong,
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

/// Keep Product import referenced (untuk type-safety navigation arguments).
// ignore: unused_element
Product? _typeHint() => null;

// Note: _UploadChoiceSheet (split video/photo dulu) di-remove. Flow upload
// sekarang unified via FeedMediaPickerScreen.open() yang handle photo +
// video di satu picker IG-style. Konsisten dengan entry point dari
// member_screen + member_posts_screen.
