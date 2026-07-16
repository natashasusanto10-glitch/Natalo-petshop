import 'dart:async';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../services/video_quality_service.dart';
import '../../../state/settings_store.dart';
import 'post_video_coordinator.dart';
import 'frame_output_heartbeat_service.dart';
import 'social_video_session_observer.dart';
import 'video_media_cache.dart';
import 'video_playback_health_monitor.dart';

/// Satu percobaan init (plugin-free seam). Melempar bila gagal; pada sukses,
/// implementasi nyata sudah menyimpan controller/wrapper. Di-inject di test
/// supaya orkestrasi retry (T4) bisa diuji tanpa plugin.
typedef VideoInitAttempt = Future<void> Function(String url);

/// Plugin-free operations for focused ownership/recovery tests.
typedef VideoSessionOperation = Future<void> Function();
typedef VideoSessionSeekOperation = Future<void> Function(Duration position);
typedef VideoSessionVolumeOperation = Future<void> Function(double volume);

/// Implementasi nyata [PlaybackSession] (T3) — membungkus satu
/// [VideoPlayerController] (+ optional wrapper cache MP4). Sesi ini DIMILIKI
/// oleh [PostVideoCoordinator]: hanya coordinator yang memanggil [dispose],
/// dan dispose sesi = dispose wrapper/controller (point 5 kontrak KUNCI USER).
///
/// Aturan URL (samakan pola feed utama, feed_video_post_view :467-469):
///  - `.m3u8` (HLS) → [VideoPlayerController.networkUrl] LANGSUNG, tanpa
///    wrapper cache (segmen HLS tidak ter-cache; wrapper malah bikin
///    "Video belum bisa diputar"). Deteksi `.m3u8` dilakukan SETELAH
///    [VideoQualityService.resolvePlaybackUrl] (resolve bisa mengubah HLS↔MP4).
///  - MP4 → [CachedVideoPlayerPlus] (repeat-view benefit disk cache).
///
/// Init berjalan otomatis saat konstruksi (coordinator butuh sesi hidup
/// segera saat `attach`). Perintah playback yang datang sebelum init selesai
/// (coordinator memanggil `pause()`/`setVolume(0)` sinkron di `_ensureEntry`)
/// disimpan sebagai "desired state" dan diterapkan begitu controller siap.
///
/// Auto-retry (T4): kalau init gagal, coba SEKALI lagi (total maks
/// [_maxRetries] retry). Error yang jelas permanen (format/codec/404) TIDAK
/// di-retry. Kalau URL bertanda-tangan Bunny (`token=&expires=`) — yang tak
/// bisa di-rewrite — retry didahului best-effort refresh URL segar dari API
/// via [urlRefresher] (D4). Retry + refresh berbagi satu budget (tidak
/// berulang tak terbatas). Tombol "Coba lagi" manual memanggil [retry] yang
/// mereset budget.
class VideoPlayerSession implements PlaybackSession {
  VideoPlayerSession({
    required String url,
    bool hasAudio = true,
    String? userQualityPreference,
    Future<String?> Function()? urlRefresher,
    String? analyticsPostId,
    String analyticsSurface = 'postingan',
    @visibleForTesting VideoPlaybackMetricSink? debugMetricSink,
    @visibleForTesting NetworkTier? debugNetworkTier,
    @visibleForTesting VideoInitAttempt? debugInitAttempt,
    @visibleForTesting Future<void> Function(Duration)? debugDelay,
    @visibleForTesting FrameOutputHeartbeatService? debugHeartbeatService,
    @visibleForTesting int Function()? debugPlayerId,
    @visibleForTesting Duration Function()? debugPosition,
    @visibleForTesting VideoSessionOperation? debugPlay,
    @visibleForTesting VideoSessionOperation? debugPause,
    @visibleForTesting VideoSessionSeekOperation? debugSeek,
    @visibleForTesting VideoSessionVolumeOperation? debugSetVolume,
    @visibleForTesting VideoSessionOperation? debugDisposePlayer,
    SocialVideoSessionObserver? observationObserver,
    SocialVideoObservationContext? observationContext,
  })  : _currentUrl = url,
        _hasAudio = hasAudio,
        _userQualityPreference =
            userQualityPreference ?? appSettingsStore.feedVideoQuality,
        _urlRefresher = urlRefresher,
        _debugInitAttempt = debugInitAttempt,
        _debugDelay = debugDelay,
        _heartbeatService =
            debugHeartbeatService ?? FrameOutputHeartbeatService.instance,
        _debugPlayerId = debugPlayerId,
        _debugPosition = debugPosition,
        _debugPlay = debugPlay,
        _debugPause = debugPause,
        _debugSeek = debugSeek,
        _debugSetVolume = debugSetVolume,
        _debugDisposePlayer = debugDisposePlayer,
        _analyticsPostId = analyticsPostId,
        _analyticsSurface = analyticsSurface,
        _observationObserver =
            observationObserver ?? socialVideoSessionObserver,
        _observationContext = observationContext ??
            _legacyObservationContext(analyticsPostId, analyticsSurface) {
    _healthMonitor = VideoPlaybackHealthMonitor(
      readSnapshot: _healthSnapshot,
      onRecover: _recoverFromStall,
      onFrameOutputStallRecover: _recoverFromFrameOutputStall,
      onFrameOutputRecoveryExhausted: _markVisualOutputFailed,
      interval: const Duration(milliseconds: 500),
      frameOutputRecoveryCooldown: const Duration(seconds: 2),
      metricContext: {
        'surface': _analyticsSurface,
        'media_type': _currentUrl.contains('.m3u8') ? 'hls' : 'mp4',
        'network_tier':
            (debugNetworkTier ?? videoQualityService.currentTier).name,
        'quality_preference': _userQualityPreference,
        if (_analyticsPostId != null)
          'media_key': _anonymousMediaKey(_analyticsPostId!),
      },
      metricSink: debugMetricSink,
    );
    _healthMonitor.record('video_init_started');
    unawaited(_init());
  }

  /// Maks jumlah retry OTOMATIS setelah percobaan pertama gagal. TEPAT 1 —
  /// refresh signed URL (D4) menghitung sebagai retry ini (bukan tambahan).
  static const int _maxRetries = 1;

  String _currentUrl;
  final bool _hasAudio;
  final String _userQualityPreference;
  final Future<String?> Function()? _urlRefresher;
  final VideoInitAttempt? _debugInitAttempt;
  final Future<void> Function(Duration)? _debugDelay;
  final FrameOutputHeartbeatService _heartbeatService;
  final int Function()? _debugPlayerId;
  final Duration Function()? _debugPosition;
  final VideoSessionOperation? _debugPlay;
  final VideoSessionOperation? _debugPause;
  final VideoSessionSeekOperation? _debugSeek;
  final VideoSessionVolumeOperation? _debugSetVolume;
  final VideoSessionOperation? _debugDisposePlayer;
  final String? _analyticsPostId;
  final String _analyticsSurface;
  final SocialVideoSessionObserver _observationObserver;
  final SocialVideoObservationContext? _observationContext;
  final Object _debugObservationIdentity = Object();
  Object? _lastObservationIdentity;
  late final VideoPlaybackHealthMonitor _healthMonitor;
  final Stopwatch _startupStopwatch = Stopwatch()..start();
  bool _playStartedRecorded = false;

  CachedVideoPlayerPlus? _wrapper;
  VideoPlayerController? _controller;
  FrameOutputHeartbeatRegistration? _heartbeatRegistration;
  StreamSubscription<FrameOutputHeartbeat>? _heartbeatSubscription;
  Future<void>? _volumeTail;
  int _heartbeatGeneration = 0;
  int _playbackDiscontinuitySequence = 0;
  int _visualIntentGeneration = 0;

  bool _disposed = false;
  bool _initInFlight = false;
  Completer<void>? _initCompletion;
  Future<void>? _disposeFuture;
  bool _debugPlayerReady = false;
  bool _initialized = false;
  Object? _error;
  bool _hasVisualOutput = false;
  bool _awaitingVisualOutput = false;
  bool _recoveringVisualOutput = false;
  bool _visualOutputFailed = false;
  int? _visualBaselineFrameCount;
  int? _visualGateArmedGeneration;

  // Desired state — diterapkan saat init selesai kalau perintah datang lebih
  // dulu (coordinator set pause+volume0 sinkron sebelum controller siap).
  bool _wantPlay = false;
  double _wantVolume = 0;
  Duration _wantSeek = Duration.zero;

  /// Bump tiap perubahan state penting (mulai loading / init selesai / error)
  /// supaya view pemakai bisa `addListener` dan rebuild (merender VideoPlayer
  /// / thumbnail / pesan error + tombol "Coba lagi"). TIDAK di-dispose oleh
  /// sesi: view melepas listener sendiri saat detach; ValueNotifier tanpa
  /// listener di-GC.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Controller untuk di-attach oleh view (`VideoPlayer(controller)`). Null
  /// sampai init selesai atau kalau init gagal.
  VideoPlayerController? get controller => _controller;

  bool get isInitialized => _initialized;
  bool get hasError => _error != null;
  Object? get error => _error;
  bool get hasVisualOutput => _hasVisualOutput;
  bool get isAwaitingVisualOutput => _awaitingVisualOutput;
  bool get isRecoveringVisualOutput => _recoveringVisualOutput;

  /// True selama percobaan init sedang berjalan (loading). View pakai ini +
  /// [hasError] untuk membedakan spinner vs pesan error.
  bool get isLoading => _initInFlight;

  Future<void> _init() async {
    if (_initInFlight || _disposed || _initialized) return;
    final completion = Completer<void>();
    _initCompletion = completion;
    _initInFlight = true;
    // Bump: view merender loading + membersihkan pesan error lama.
    _error = null;
    revision.value++;
    try {
      var retriesLeft = _maxRetries;
      while (true) {
        try {
          await _attemptInit(_currentUrl);
          // Hasil kedaluwarsa: sesi keburu di-dispose selama init async →
          // buang resource (mencegah controller yatim + audio hantu).
          if (_disposed) {
            await _cleanupResources();
            return;
          }
          _observe(SocialVideoLifecycleType.created);
          _initialized = true;
          _observe(SocialVideoLifecycleType.initialized);
          _registerHeartbeat();
          _visualOutputFailed = false;
          _error = null;
          _healthMonitor.record('video_init_ready', {
            'duration_ms': _startupStopwatch.elapsedMilliseconds,
          });
          if (_controller != null) _healthMonitor.start();
          await _applyDesiredState();
          revision.value++;
          return;
        } catch (error) {
          await _cleanupResources();
          if (_disposed) return;
          final permanent = _isPermanentError(error);
          if (retriesLeft <= 0 || permanent) {
            _error = error;
            _initialized = false;
            _awaitingVisualOutput = false;
            _recoveringVisualOutput = false;
            _visualOutputFailed = false;
            _healthMonitor.record('video_init_failed', {
              'duration_ms': _startupStopwatch.elapsedMilliseconds,
              'error_type': error.runtimeType.toString(),
            });
            _observe(SocialVideoLifecycleType.failed);
            revision.value++;
            return;
          }
          retriesLeft--;
          // D4: URL Bunny bertanda-tangan tak bisa di-rewrite; kalau mungkin
          // expired, coba SEKALI ambil URL segar dari API lalu retry dengan
          // URL itu. Refresh gagal / bukan signed → backoff singkat saja.
          final refreshed = await _maybeRefreshSignedUrl();
          if (_disposed) return;
          if (!refreshed) {
            await _delay(const Duration(milliseconds: 500));
          }
          if (_disposed) return;
          // loop → percobaan retry.
        }
      }
    } finally {
      _initInFlight = false;
      if (!completion.isCompleted) completion.complete();
      if (identical(_initCompletion, completion)) {
        _initCompletion = null;
      }
    }
  }

  /// Satu percobaan init. Melempar bila gagal. Pada sukses menyimpan
  /// `_wrapper`/`_controller`. Di test, seam [_debugInitAttempt] menggantikan
  /// jalur plugin.
  Future<void> _attemptInit(String url) async {
    final attempt = _debugInitAttempt;
    if (attempt != null) {
      await attempt(url);
      _debugPlayerReady = true;
      return;
    }
    if (url.trim().isEmpty) {
      throw StateError('URL video kosong');
    }
    final resolved = videoQualityService.resolvePlaybackUrl(
      url,
      userPreference: _userQualityPreference,
    );
    // Deteksi HLS SETELAH resolve (resolve bisa rewrite HLS↔MP4).
    final isHls = resolved.contains('.m3u8');
    if (isHls) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(resolved));
      await controller.initialize();
      _controller = controller;
      controller.addListener(_observePlaybackStateTransition);
    } else {
      final wrapper = CachedVideoPlayerPlus.networkUrl(
        Uri.parse(resolved),
        invalidateCacheIfOlderThan: const Duration(days: 7),
        cacheKey: videoMediaCacheKey(
          mediaId: _analyticsPostId ?? resolved,
          url: resolved,
        ),
      );
      await wrapper.initialize();
      _wrapper = wrapper;
      _controller = wrapper.controller;
      _controller!.addListener(_observePlaybackStateTransition);
    }
  }

  Future<void> _applyDesiredState() async {
    final ctrl = _controller;
    if (ctrl == null && _debugInitAttempt == null) return;
    if (ctrl != null) await ctrl.setLooping(true);
    // Audio is always closed while a controller is attached/re-attached. The
    // requested volume is restored only after a fresh frame heartbeat proves
    // that this playback intent has visual output.
    await _setPlayerVolume(0);
    if (_wantSeek > Duration.zero) {
      await _seekPlayer(_wantSeek);
    }
    if (_wantPlay) {
      await _startPlaybackWithVisualGate(
        recovering: _recoveringVisualOutput,
      );
    } else {
      await _pausePlayer();
    }
  }

  /// Buang controller/wrapper parsial (dipakai saat cleanup gagal-init ATAU
  /// saat dispose menyalip init sukses). Setelah ini `_controller`/`_wrapper`
  /// null → retry mulai bersih.
  Future<void> _cleanupResources() async {
    final wrapper = _wrapper;
    final controller = _controller;
    final disposeDebugPlayer = _debugPlayerReady;
    _wrapper = null;
    _controller = null;
    _debugPlayerReady = false;
    _visualIntentGeneration++;
    _hasVisualOutput = false;
    _awaitingVisualOutput = false;
    _visualBaselineFrameCount = null;
    _visualGateArmedGeneration = null;
    _unregisterHeartbeat();
    controller?.removeListener(_observePlaybackStateTransition);
    try {
      if (wrapper != null) {
        await wrapper.dispose();
      } else {
        if (controller != null) {
          await controller.dispose();
        } else if (disposeDebugPlayer) {
          await _debugDisposePlayer?.call();
        }
      }
    } catch (_) {}
  }

  /// D4 best-effort: kalau URL saat ini bertanda-tangan (Bunny signed) dan ada
  /// [urlRefresher], ambil URL segar SEKALI. True bila `_currentUrl` diganti.
  ///
  /// FOLLOW-UP: kalau endpoint detail post TIDAK mengembalikan URL
  /// bertanda-tangan segar (mis. backend berubah), refresh ini jadi no-op dan
  /// kita jatuh ke tombol "Coba lagi". JANGAN bikin endpoint refresh baru di
  /// jalur ini — server saat ini (`GET /api/feed/posts/:id` → `signBunnyUrl`)
  /// sudah sign ulang tiap request, jadi re-fetch = URL segar.
  Future<bool> _maybeRefreshSignedUrl() async {
    final refresher = _urlRefresher;
    if (refresher == null) return false;
    final looksSigned =
        _currentUrl.contains('token=') && _currentUrl.contains('expires=');
    if (!looksSigned) return false;
    try {
      final fresh = await refresher();
      if (fresh == null || fresh.trim().isEmpty || fresh == _currentUrl) {
        return false;
      }
      _currentUrl = fresh;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Heuristik transient vs permanen. Sengaja KONSERVATIF: hanya error yang
  /// jelas permanen (format/codec tak didukung, 404 not found) yang di-skip
  /// retry; sisanya (network/timeout/IO/unknown) dapat SATU retry. Klasifikasi
  /// PlatformException lintas-platform tak andal, jadi default-nya retry-sekali
  /// dengan cap ketat [_maxRetries].
  bool _isPermanentError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('unsupported') ||
        msg.contains('format') ||
        msg.contains('codec') ||
        msg.contains('not found') ||
        msg.contains('404');
  }

  Future<void> _delay(Duration duration) {
    final delay = _debugDelay;
    if (delay != null) return delay(duration);
    return Future<void>.delayed(duration);
  }

  /// Manual "Coba lagi" dari view: reset budget (via [_init] fresh) dan init
  /// ulang. No-op kalau sudah init / sedang berjalan / sudah dispose.
  Future<void> retry() async {
    if (_disposed || _initInFlight) return;
    if (_visualOutputFailed) {
      _visualOutputFailed = false;
      _error = null;
      _recoveringVisualOutput = false;
      _awaitingVisualOutput = false;
      _healthMonitor.resetFrameOutputRecoveryBudget();
      _initialized = false;
      revision.value++;
      await _quiesceCurrentPlayer();
      await _cleanupResources();
      if (_disposed) return;
      await _init();
      return;
    }
    if (_initialized) return;
    _error = null;
    await _init();
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    final alreadyWanted = _wantPlay;
    _wantPlay = true;
    if (_visualOutputFailed) return;
    final ctrl = _controller;
    if (_initialized && (ctrl != null || _debugInitAttempt != null)) {
      if (alreadyWanted) {
        await _applyEffectiveVolume();
        return;
      }
      await _startPlaybackWithVisualGate();
    }
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    _wantPlay = false;
    _visualIntentGeneration++;
    _setVisualGateState(awaiting: false, recovering: false);
    final ctrl = _controller;
    if (_initialized && (ctrl != null || _debugInitAttempt != null)) {
      await _setPlayerVolume(0);
      await _pausePlayer();
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (_disposed) return;
    _wantSeek = position;
    _playbackDiscontinuitySequence++;
    final shouldResume = _wantPlay && !_visualOutputFailed;
    if (shouldResume) {
      _visualIntentGeneration++;
      _setVisualGateState(
        awaiting: true,
        recovering: _recoveringVisualOutput,
      );
    }
    final ctrl = _controller;
    if (_initialized && (ctrl != null || _debugInitAttempt != null)) {
      if (shouldResume) await _setPlayerVolume(0);
      await _seekPlayer(position);
      if (shouldResume && _wantPlay && !_visualOutputFailed) {
        await _startPlaybackWithVisualGate(reuseCurrentGate: true);
      }
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    _wantVolume = _hasAudio ? volume : 0;
    final ctrl = _controller;
    if (_initialized && (ctrl != null || _debugInitAttempt != null)) {
      await _applyEffectiveVolume();
    }
  }

  @override
  Duration get position =>
      _controller?.value.position ?? _debugPosition?.call() ?? _wantSeek;

  Future<void> _startPlaybackWithVisualGate({
    bool reuseCurrentGate = false,
    bool recovering = false,
  }) async {
    if (_disposed || !_initialized || !_wantPlay || _visualOutputFailed) return;
    final generation =
        reuseCurrentGate ? _visualIntentGeneration : ++_visualIntentGeneration;
    if (!reuseCurrentGate) {
      _visualBaselineFrameCount = _heartbeatRegistration?.latest?.frameCount;
      _setVisualGateState(awaiting: true, recovering: recovering);
    } else if (recovering && !_recoveringVisualOutput) {
      _setVisualGateState(awaiting: true, recovering: true);
    }

    await _setPlayerVolume(0);
    if (!_isCurrentVisualIntent(generation)) return;
    _visualGateArmedGeneration = generation;
    try {
      await _playPlayer();
    } catch (_) {
      if (_visualGateArmedGeneration == generation) {
        _visualGateArmedGeneration = null;
      }
      rethrow;
    }
    if (!_isCurrentVisualIntent(generation)) {
      await _setPlayerVolume(0);
      return;
    }
    _recordPlayStarted();
  }

  bool _isCurrentVisualIntent(int generation) =>
      !_disposed &&
      _initialized &&
      _wantPlay &&
      !_visualOutputFailed &&
      generation == _visualIntentGeneration;

  Future<void> _applyEffectiveVolume({int? expectedGeneration}) async {
    final canOpen = !_disposed &&
        _initialized &&
        _wantPlay &&
        !_awaitingVisualOutput &&
        !_visualOutputFailed &&
        (expectedGeneration == null ||
            expectedGeneration == _visualIntentGeneration);
    final target = canOpen ? _wantVolume : 0.0;
    await _setPlayerVolume(target);
    if (target > 0 &&
        (_disposed ||
            !_wantPlay ||
            _awaitingVisualOutput ||
            _visualOutputFailed ||
            (expectedGeneration != null &&
                expectedGeneration != _visualIntentGeneration))) {
      await _setPlayerVolume(0);
    }
  }

  void _setVisualGateState({
    required bool awaiting,
    required bool recovering,
  }) {
    if (_awaitingVisualOutput == awaiting &&
        _recoveringVisualOutput == recovering) {
      return;
    }
    _awaitingVisualOutput = awaiting;
    _recoveringVisualOutput = recovering;
    if (!awaiting) _visualGateArmedGeneration = null;
    revision.value++;
  }

  void _onFrameOutputHeartbeat(FrameOutputHeartbeat heartbeat) {
    if (_disposed) return;
    final firstVisualOutput = !_hasVisualOutput;
    _hasVisualOutput = true;

    if (!_wantPlay || !_awaitingVisualOutput || _visualOutputFailed) {
      if (firstVisualOutput) revision.value++;
      return;
    }
    final generation = _visualIntentGeneration;
    if (_visualGateArmedGeneration != generation) {
      if (firstVisualOutput) revision.value++;
      return;
    }
    final baseline = _visualBaselineFrameCount;
    if (baseline != null && heartbeat.frameCount <= baseline) return;

    _visualBaselineFrameCount = heartbeat.frameCount;
    _setVisualGateState(awaiting: false, recovering: false);
    _healthMonitor.record('video_visual_output_ready', {
      'frame_count': heartbeat.frameCount,
      'platform': heartbeat.platform,
    });
    unawaited(_applyEffectiveVolume(expectedGeneration: generation));
  }

  VideoPlaybackSnapshot _healthSnapshot() {
    final value = _controller?.value;
    return VideoPlaybackSnapshot(
      shouldMonitor: shouldMonitorIntendedPlayback(
        intendsPlayback: !_disposed && _wantPlay && !_visualOutputFailed,
        isInitialized:
            value?.isInitialized ?? (_debugInitAttempt != null && _initialized),
      ),
      isBuffering: value?.isBuffering ?? false,
      position: value?.position ?? _debugPosition?.call() ?? _wantSeek,
      duration: value?.duration ?? Duration.zero,
      bufferAhead: _bufferAhead(value),
      frameOutputCount: _heartbeatRegistration?.latest?.frameCount,
      playbackDiscontinuitySequence: _playbackDiscontinuitySequence,
    );
  }

  void _observePlaybackStateTransition() {
    if (_disposed) return;
    _healthMonitor.observePlaybackStateTransition();
  }

  Duration _bufferAhead(VideoPlayerValue? value) {
    if (value == null) return Duration.zero;
    return contiguousBufferAhead(
      position: value.position,
      buffered: value.buffered,
    );
  }

  @visibleForTesting
  static Duration contiguousBufferAhead({
    required Duration position,
    required List<DurationRange> buffered,
  }) {
    var furthestEnd = position;
    for (final range in buffered) {
      if (range.end <= position) continue;
      if (range.start > furthestEnd) break;
      if (range.end > furthestEnd) furthestEnd = range.end;
    }
    return furthestEnd - position;
  }

  Future<void> _recoverFromStall(Duration position) async {
    final ctrl = _controller;
    if (_disposed || !_initialized || ctrl == null || !_wantPlay) return;
    _visualIntentGeneration++;
    _visualBaselineFrameCount = _heartbeatRegistration?.latest?.frameCount;
    _setVisualGateState(awaiting: true, recovering: true);
    await _setPlayerVolume(0);
    await ctrl.pause();
    _playbackDiscontinuitySequence++;
    await ctrl.seekTo(position);
    if (_disposed ||
        !_initialized ||
        !_wantPlay ||
        !identical(ctrl, _controller)) {
      return;
    }
    await _startPlaybackWithVisualGate(
      reuseCurrentGate: true,
      recovering: true,
    );
  }

  Future<void> _recoverFromFrameOutputStall(
    Duration position,
    int attempt,
  ) async {
    if (_disposed || !_initialized || !_wantPlay) return;
    if (_controller == null && _debugInitAttempt == null) return;
    final discontinuity = _playbackDiscontinuitySequence;
    final controller = _controller;
    final playerId = _debugPlayerId?.call();
    if (attempt == 1) {
      _visualIntentGeneration++;
      _visualBaselineFrameCount = _heartbeatRegistration?.latest?.frameCount;
      _setVisualGateState(awaiting: true, recovering: true);
      await _setPlayerVolume(0);
      await _pausePlayer();
      if (_disposed ||
          !_wantPlay ||
          discontinuity != _playbackDiscontinuitySequence ||
          !identical(controller, _controller) ||
          playerId != _debugPlayerId?.call()) {
        return;
      }
      _wantSeek = position;
      _playbackDiscontinuitySequence++;
      await _seekPlayer(position);
      if (_disposed || !_wantPlay) return;
      await _startPlaybackWithVisualGate(
        reuseCurrentGate: true,
        recovering: true,
      );
      return;
    }
    if (attempt != 2) return;

    _visualIntentGeneration++;
    _setVisualGateState(awaiting: false, recovering: true);
    _initialized = false;
    revision.value++;
    await _quiesceCurrentPlayer();
    if (_disposed ||
        !_wantPlay ||
        discontinuity != _playbackDiscontinuitySequence ||
        !identical(controller, _controller) ||
        playerId != _debugPlayerId?.call()) {
      _initialized = true;
      _setVisualGateState(awaiting: false, recovering: false);
      await _applyDesiredState();
      revision.value++;
      return;
    }
    _wantSeek = position;
    _playbackDiscontinuitySequence++;
    await _cleanupResources();
    if (_disposed) return;
    await _init();
  }

  Future<void> _markVisualOutputFailed(Duration position) async {
    if (_disposed || !_initialized || !_wantPlay || _visualOutputFailed) return;
    _visualOutputFailed = true;
    _error = StateError('Video frame output tidak tersedia');
    _visualIntentGeneration++;
    _awaitingVisualOutput = false;
    _recoveringVisualOutput = false;
    _healthMonitor.record('video_visual_output_failed', {
      'position_ms': position.inMilliseconds,
    });
    revision.value++;
    await _quiesceCurrentPlayer();
  }

  Future<void> _quiesceCurrentPlayer() async {
    try {
      await _setPlayerVolume(0);
    } catch (_) {}
    try {
      await _pausePlayer();
    } catch (_) {}
  }

  void _registerHeartbeat() {
    _unregisterHeartbeat();
    final player = _controller ?? _debugPlayerId?.call();
    if (player == null) return;
    try {
      final registration = _heartbeatService.register(player);
      final generation = ++_heartbeatGeneration;
      _heartbeatRegistration = registration;
      _heartbeatSubscription = registration.heartbeats.listen(
        (heartbeat) {
          if (generation != _heartbeatGeneration ||
              !identical(_heartbeatRegistration, registration)) {
            return;
          }
          _onFrameOutputHeartbeat(heartbeat);
        },
      );
    } catch (_) {
      _heartbeatRegistration = null;
      _heartbeatSubscription = null;
    }
  }

  void _unregisterHeartbeat() {
    _heartbeatGeneration++;
    unawaited(_heartbeatSubscription?.cancel());
    _heartbeatSubscription = null;
    _heartbeatRegistration?.unregister();
    _heartbeatRegistration = null;
  }

  Future<void> _playPlayer() =>
      _controller?.play() ?? _debugPlay?.call() ?? Future<void>.value();

  Future<void> _pausePlayer() =>
      _controller?.pause() ?? _debugPause?.call() ?? Future<void>.value();

  Future<void> _seekPlayer(Duration position) =>
      _controller?.seekTo(position) ??
      _debugSeek?.call(position) ??
      Future<void>.value();

  Future<void> _setPlayerVolume(double volume) {
    final controller = _controller;
    final debugSetVolume = _debugSetVolume;
    final playerId = _debugPlayerId?.call();

    Future<void> write() {
      // A queued write belongs to the player that requested it. Once recovery
      // replaces that player, silently drop the stale write instead of
      // applying an old unmute to the new controller.
      if (controller != null) {
        if (!identical(controller, _controller)) return Future<void>.value();
        return controller.setVolume(volume);
      }
      if (playerId != null && playerId != _debugPlayerId?.call()) {
        return Future<void>.value();
      }
      return debugSetVolume?.call(volume) ?? Future<void>.value();
    }

    final previous = _volumeTail;
    final next = previous == null
        ? Future<void>.sync(write)
        : previous.catchError((Object _) {}).then((_) => write());
    _volumeTail = next;
    unawaited(next.then(
      (_) {
        if (identical(_volumeTail, next)) _volumeTail = null;
      },
      onError: (Object _) {
        if (identical(_volumeTail, next)) _volumeTail = null;
      },
    ));
    return next;
  }

  @visibleForTesting
  Future<void> debugRecoverFrameOutput(Duration position, int attempt) =>
      _recoverFromFrameOutputStall(position, attempt);

  @visibleForTesting
  Future<void> debugSampleHealth() => _healthMonitor.sample();

  @visibleForTesting
  int get debugFrameOutputStaleSamples =>
      _healthMonitor.debugFrameOutputStaleSamples;

  @visibleForTesting
  int get debugFrameOutputRecoveryCount =>
      _healthMonitor.debugFrameOutputRecoveryCount;

  @visibleForTesting
  Future<void> debugMarkVisualOutputFailed(Duration position) =>
      _markVisualOutputFailed(position);

  @visibleForTesting
  VideoPlaybackSnapshot get debugHealthSnapshot => _healthSnapshot();

  void _recordPlayStarted() {
    if (_playStartedRecorded) return;
    _playStartedRecorded = true;
    _healthMonitor.record('video_play_started', {
      'startup_ms': _startupStopwatch.elapsedMilliseconds,
    });
  }

  static String _anonymousMediaKey(String postId) =>
      postId.hashCode.toUnsigned(32).toRadixString(16);

  static SocialVideoObservationContext? _legacyObservationContext(
    String? postId,
    String surface,
  ) {
    if (postId == null || postId.trim().isEmpty) return null;
    return SocialVideoObservationContext(
      postId: postId,
      surface: surface == 'profile_grid'
          ? SocialVideoSurface.profileGrid
          : SocialVideoSurface.postDetail,
      ownerId: 'coordinator-$postId',
    );
  }

  void recordObservationAttachment(SocialVideoObservationContext context) {
    _observe(SocialVideoLifecycleType.attached, context: context);
  }

  void _observe(
    SocialVideoLifecycleType type, {
    SocialVideoObservationContext? context,
  }) {
    final observationContext = context ?? _observationContext;
    if (observationContext == null) return;
    final identity = _controller ??
        (_debugInitAttempt != null
            ? _debugObservationIdentity
            : _lastObservationIdentity);
    if (identity == null) return;
    _lastObservationIdentity = identity;
    try {
      _observationObserver.observeController(
        type: type,
        postId: observationContext.postId,
        surface: observationContext.surface,
        ownerId: observationContext.ownerId,
        controllerIdentity: identity,
      );
    } catch (_) {
      // Observation must remain unable to affect session ownership or playback.
    }
  }

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    final future = _disposeOnce();
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposeOnce() async {
    _disposed = true;
    _healthMonitor.dispose();
    _initialized = false;
    // Tutup audio segera, lalu tunggu init yang sedang berjalan selesai.
    // Completion init melihat `_disposed` dan tidak boleh menerapkan playback;
    // setelah completion, cleanup terakhir menjadi idempoten karena resource
    // diambil+dinolkan secara atomik oleh `_cleanupResources`.
    await _quiesceCurrentPlayer();
    while (_initInFlight) {
      final completion = _initCompletion;
      if (completion == null) break;
      await completion.future;
    }
    await _cleanupResources();
    _observe(SocialVideoLifecycleType.disposed);
  }
}
