import 'dart:async';

import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../services/video_quality_service.dart';
import '../../../state/settings_store.dart';
import 'post_video_coordinator.dart';

/// Implementasi nyata [PlaybackSession] (T3) — membungkus satu
/// [VideoPlayerController] (+ optional wrapper cache MP4). Sesi ini DIMILIKI
/// oleh [PostVideoCoordinator]: hanya coordinator yang memanggil [dispose],
/// dan dispose sesi = dispose wrapper/controller (point 5 kontrak KUNCI USER).
///
/// Aturan URL (samakan pola feed utama, feed_video_post_view :467-469):
///  - `.m3u8` (HLS) → [VideoPlayerController.networkUrl] LANGSUNG, tanpa
///    wrapper cache (segmen HLS tidak ter-cache; wrapper malah bikin
///    "Video belum bisa diputar").
///  - MP4 → [CachedVideoPlayerPlus] (repeat-view benefit disk cache).
///
/// Init berjalan otomatis saat konstruksi (coordinator butuh sesi hidup
/// segera saat `attach`). Perintah playback yang datang sebelum init selesai
/// (coordinator memanggil `pause()`/`setVolume(0)` sinkron di `_ensureEntry`)
/// disimpan sebagai "desired state" dan diterapkan begitu controller siap.
///
/// Retry mendalam + refresh signed URL (D4) = T4; di sini cukup HLS-direct /
/// MP4-cache supaya T4 tinggal menambah retry di jalur ini.
class VideoPlayerSession implements PlaybackSession {
  VideoPlayerSession({
    required String url,
    String? userQualityPreference,
  })  : _rawUrl = url,
        _userQualityPreference =
            userQualityPreference ?? appSettingsStore.feedVideoQuality {
    unawaited(_init());
  }

  final String _rawUrl;
  final String _userQualityPreference;

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

  /// Bump tiap perubahan state penting (init selesai / error) supaya view
  /// pemakai bisa `addListener` dan rebuild (merender VideoPlayer / thumbnail
  /// / pesan error). TIDAK di-dispose oleh sesi: view melepas listener sendiri
  /// saat detach; ValueNotifier tanpa listener di-GC.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Controller untuk di-attach oleh view (`VideoPlayer(controller)`). Null
  /// sampai init selesai atau kalau init gagal.
  VideoPlayerController? get controller => _controller;

  bool get isInitialized => _initialized;
  bool get hasError => _error != null;
  Object? get error => _error;

  Future<void> _init() async {
    if (_initInFlight || _disposed || _initialized) return;
    _initInFlight = true;
    _error = null;
    CachedVideoPlayerPlus? wrapper;
    VideoPlayerController? controller;
    try {
      if (_rawUrl.trim().isEmpty) {
        throw StateError('URL video kosong');
      }
      final resolved = videoQualityService.resolvePlaybackUrl(
        _rawUrl,
        userPreference: _userQualityPreference,
      );
      final isHls = resolved.contains('.m3u8');
      if (isHls) {
        controller = VideoPlayerController.networkUrl(Uri.parse(resolved));
        await controller.initialize();
      } else {
        wrapper = CachedVideoPlayerPlus.networkUrl(
          Uri.parse(resolved),
          invalidateCacheIfOlderThan: const Duration(days: 7),
        );
        await wrapper.initialize();
        controller = wrapper.controller;
      }
      // Hasil kedaluwarsa: sesi keburu di-dispose selama init async → buang
      // resource, jangan simpan (mencegah controller yatim + audio hantu).
      if (_disposed) {
        if (wrapper != null) {
          await wrapper.dispose();
        } else {
          await controller.dispose();
        }
        return;
      }
      _wrapper = wrapper;
      _controller = controller;
      _initialized = true;
      await controller.setLooping(true);
      await controller.setVolume(_wantVolume);
      if (_wantSeek > Duration.zero) {
        await controller.seekTo(_wantSeek);
      }
      if (_wantPlay) {
        await controller.play();
      } else {
        await controller.pause();
      }
      revision.value++;
    } catch (error) {
      // Cleanup partial init.
      try {
        if (wrapper != null) {
          await wrapper.dispose();
        } else {
          await controller?.dispose();
        }
      } catch (_) {}
      if (_disposed) return;
      _error = error;
      _initialized = false;
      revision.value++;
    } finally {
      _initInFlight = false;
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    _wantPlay = true;
    final ctrl = _controller;
    if (_initialized && ctrl != null) {
      await ctrl.play();
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

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final wrapper = _wrapper;
    final controller = _controller;
    _wrapper = null;
    _controller = null;
    _initialized = false;
    // Prefer dispose via wrapper (handle cache reference + underlying
    // controller sekaligus). Kalau init masih in-flight, `_init` mendeteksi
    // `_disposed` dan membuang hasilnya sendiri.
    try {
      if (wrapper != null) {
        await wrapper.dispose();
      } else {
        await controller?.dispose();
      }
    } catch (_) {}
  }
}
