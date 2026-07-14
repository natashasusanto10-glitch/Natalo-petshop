import 'dart:async';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../services/video_quality_service.dart';
import '../../../state/settings_store.dart';
import 'post_video_coordinator.dart';
import 'video_playback_health_monitor.dart';

/// Satu percobaan init (plugin-free seam). Melempar bila gagal; pada sukses,
/// implementasi nyata sudah menyimpan controller/wrapper. Di-inject di test
/// supaya orkestrasi retry (T4) bisa diuji tanpa plugin.
typedef VideoInitAttempt = Future<void> Function(String url);

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
    String? userQualityPreference,
    Future<String?> Function()? urlRefresher,
    String? analyticsPostId,
    String analyticsSurface = 'postingan',
    @visibleForTesting VideoPlaybackMetricSink? debugMetricSink,
    @visibleForTesting NetworkTier? debugNetworkTier,
    @visibleForTesting VideoInitAttempt? debugInitAttempt,
    @visibleForTesting Future<void> Function(Duration)? debugDelay,
  })  : _currentUrl = url,
        _userQualityPreference =
            userQualityPreference ?? appSettingsStore.feedVideoQuality,
        _urlRefresher = urlRefresher,
        _debugInitAttempt = debugInitAttempt,
        _debugDelay = debugDelay,
        _analyticsPostId = analyticsPostId,
        _analyticsSurface = analyticsSurface {
    _healthMonitor = VideoPlaybackHealthMonitor(
      readSnapshot: _healthSnapshot,
      onRecover: _recoverFromStall,
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
  final String _userQualityPreference;
  final Future<String?> Function()? _urlRefresher;
  final VideoInitAttempt? _debugInitAttempt;
  final Future<void> Function(Duration)? _debugDelay;
  final String? _analyticsPostId;
  final String _analyticsSurface;
  late final VideoPlaybackHealthMonitor _healthMonitor;
  final Stopwatch _startupStopwatch = Stopwatch()..start();
  bool _playStartedRecorded = false;

  CachedVideoPlayerPlus? _wrapper;
  VideoPlayerController? _controller;

  bool _disposed = false;
  bool _initInFlight = false;
  bool _initialized = false;
  Object? _error;

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

  /// True selama percobaan init sedang berjalan (loading). View pakai ini +
  /// [hasError] untuk membedakan spinner vs pesan error.
  bool get isLoading => _initInFlight;

  Future<void> _init() async {
    if (_initInFlight || _disposed || _initialized) return;
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
          _initialized = true;
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
            _healthMonitor.record('video_init_failed', {
              'duration_ms': _startupStopwatch.elapsedMilliseconds,
              'error_type': error.runtimeType.toString(),
            });
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
    }
  }

  /// Satu percobaan init. Melempar bila gagal. Pada sukses menyimpan
  /// `_wrapper`/`_controller`. Di test, seam [_debugInitAttempt] menggantikan
  /// jalur plugin.
  Future<void> _attemptInit(String url) async {
    final attempt = _debugInitAttempt;
    if (attempt != null) {
      await attempt(url);
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
      );
      await wrapper.initialize();
      _wrapper = wrapper;
      _controller = wrapper.controller;
      _controller!.addListener(_observePlaybackStateTransition);
    }
  }

  Future<void> _applyDesiredState() async {
    final ctrl = _controller;
    if (ctrl == null) return; // seam test: tak ada controller nyata.
    await ctrl.setLooping(true);
    await ctrl.setVolume(_wantVolume);
    if (_wantSeek > Duration.zero) {
      await ctrl.seekTo(_wantSeek);
    }
    if (_wantPlay) {
      await ctrl.play();
      _recordPlayStarted();
    } else {
      await ctrl.pause();
    }
  }

  /// Buang controller/wrapper parsial (dipakai saat cleanup gagal-init ATAU
  /// saat dispose menyalip init sukses). Setelah ini `_controller`/`_wrapper`
  /// null → retry mulai bersih.
  Future<void> _cleanupResources() async {
    final wrapper = _wrapper;
    final controller = _controller;
    _wrapper = null;
    _controller = null;
    controller?.removeListener(_observePlaybackStateTransition);
    try {
      if (wrapper != null) {
        await wrapper.dispose();
      } else {
        await controller?.dispose();
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
    if (_disposed || _initialized || _initInFlight) return;
    _error = null;
    await _init();
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    _wantPlay = true;
    final ctrl = _controller;
    if (_initialized && ctrl != null) {
      await ctrl.play();
      _recordPlayStarted();
    }
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    _wantPlay = false;
    final ctrl = _controller;
    if (_initialized && ctrl != null) {
      await ctrl.pause();
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (_disposed) return;
    _wantSeek = position;
    final ctrl = _controller;
    if (_initialized && ctrl != null) {
      await ctrl.seekTo(position);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    _wantVolume = volume;
    final ctrl = _controller;
    if (_initialized && ctrl != null) {
      await ctrl.setVolume(volume);
    }
  }

  @override
  Duration get position => _controller?.value.position ?? _wantSeek;

  VideoPlaybackSnapshot _healthSnapshot() {
    final value = _controller?.value;
    return VideoPlaybackSnapshot(
      shouldMonitor: shouldMonitorIntendedPlayback(
        intendsPlayback: !_disposed && _wantPlay,
        isInitialized: value?.isInitialized ?? false,
      ),
      isBuffering: value?.isBuffering ?? false,
      position: value?.position ?? _wantSeek,
      duration: value?.duration ?? Duration.zero,
      bufferAhead: _bufferAhead(value),
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
    await ctrl.pause();
    await ctrl.seekTo(position);
    await ctrl.play();
  }

  void _recordPlayStarted() {
    if (_playStartedRecorded) return;
    _playStartedRecorded = true;
    _healthMonitor.record('video_play_started', {
      'startup_ms': _startupStopwatch.elapsedMilliseconds,
    });
  }

  static String _anonymousMediaKey(String postId) =>
      postId.hashCode.toUnsigned(32).toRadixString(16);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _healthMonitor.dispose();
    _initialized = false;
    // Prefer dispose via wrapper (handle cache reference + underlying
    // controller sekaligus). Kalau init masih in-flight, `_init` mendeteksi
    // `_disposed` dan membuang hasilnya sendiri.
    await _cleanupResources();
  }
}
