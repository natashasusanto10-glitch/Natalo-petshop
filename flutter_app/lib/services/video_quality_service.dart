import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Sprint 2 #6 #7 — Network-aware video quality + HLS adaptive untuk
/// feed video player.
///
/// Decision tree per playback:
///   - Auto / High → HLS playlist (Bunny adaptive bitrate, switch quality
///     mid-clip berdasarkan bandwidth; master playlist fallback sendiri ke
///     720p kalau 1080 belum cocok).
///   - Data saver → URL MP4 480p signed dari backend kalau tersedia.
///
/// HLS unggul saat koneksi stabil (WiFi) karena adaptive bitrate worth
/// overhead manifest fetch. Untuk clip ≤60s di mobile, MP4 progressive
/// lebih efisien (1 file = 1 cache, no manifest parse latency).
///
/// video_player package (Flutter) support HLS native di iOS (AVPlayer)
/// + Android (ExoPlayer) — tidak butuh package tambahan untuk parse
/// .m3u8 playlist.

enum NetworkTier {
  wifi,
  cellularFast, // 4G+
  cellularSlow, // 3G/2G/edge
  offline,
  unknown,
}

enum VideoQuality {
  q240,
  q360,
  q480,
  q720,
  q1080;

  int get height => switch (this) {
        VideoQuality.q240 => 240,
        VideoQuality.q360 => 360,
        VideoQuality.q480 => 480,
        VideoQuality.q720 => 720,
        VideoQuality.q1080 => 1080,
      };
}

/// Service untuk detect network tier + decide playback URL. Stateful —
/// listen ke connectivity changes supaya video quality bisa re-derive
/// dynamic saat user pindah dari WiFi ke 4G di tengah scroll feed.
class VideoQualityService {
  final Connectivity _connectivity = Connectivity();

  NetworkTier _currentTier = NetworkTier.unknown;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  final _controller = StreamController<NetworkTier>.broadcast();

  /// Stream tier changes — UI subscribe via StreamBuilder.
  Stream<NetworkTier> get tierChanges => _controller.stream;

  NetworkTier get currentTier => _currentTier;

  Future<void> initialize() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      _currentTier = _resolveTier(initial);
      _sub = _connectivity.onConnectivityChanged.listen((results) {
        final next = _resolveTier(results);
        if (next != _currentTier) {
          _currentTier = next;
          _controller.add(next);
          if (kDebugMode) {
            debugPrint('[video-quality] tier changed → $next');
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[video-quality] init failed: $e');
      }
    }
  }

  NetworkTier _resolveTier(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return NetworkTier.offline;
    }
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return NetworkTier.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      // connectivity_plus tidak expose 3G vs 4G vs 5G detail.
      // Default ke cellularFast — sebagian besar Indonesia 4G LTE.
      // Kalau user laporkan slow, bisa expose manual override di settings.
      return NetworkTier.cellularFast;
    }
    return NetworkTier.unknown;
  }

  /// Pilih quality recommendation untuk current tier. Single source of
  /// truth supaya consistent across player + thumbnail rendering.
  VideoQuality recommendedQuality() {
    switch (_currentTier) {
      case NetworkTier.wifi:
        // Auto memakai HLS playlist; nilai ini hanya fallback untuk legacy
        // MP4 URL yang belum punya canonical playlist.
        return VideoQuality.q720;
      case NetworkTier.cellularFast:
        return VideoQuality.q720;
      case NetworkTier.cellularSlow:
        return VideoQuality.q480;
      case NetworkTier.offline:
        return VideoQuality.q240;
      case NetworkTier.unknown:
        return VideoQuality.q720;
    }
  }

  /// Rewrite Bunny URL berdasarkan network tier + user preference.
  ///
  /// IMPORTANT: Saat URL sudah mengandung signed token (`token=...&expires=...`)
  /// dari server, **rewrite di-skip** karena token Bunny CDN signature
  /// terikat ke path SPESIFIK (mis. `/play_480p.mp4`). Rewrite path ke
  /// `/playlist.m3u8` atau quality lain bikin signature gak match path baru →
  /// CDN 403. Server mengirim URL kualitas yang sudah signed — pakai apa
  /// adanya.
  ///
  /// Untuk legacy URL (tidak signed): rewrite sesuai user preference (kalau
  /// `data_saver` / `high`) atau network tier (kalau `auto` / null).
  ///
  /// Pattern matching:
  ///   - HLS playlist `<origin>/<guid>/playlist.m3u8` → keep as is (WiFi)
  ///     atau rewrite ke MP4 `play_<NNN>p.mp4` (mobile / data_saver)
  ///   - MP4 `<origin>/<guid>/play_<NNN>p.mp4` → rewrite quality digit
  ///   - Non-Bunny URL → return as-is (legacy / external)
  ///
  /// userPreference values (dari appSettingsStore.feedVideoQuality):
  ///   - `null` / `'auto'`  → canonical HLS adaptive
  ///   - `'data_saver'`     → backend-signed MP4 480p jika caller memberi URL itu
  ///   - `'high'`           → canonical HLS Full HD; player/Bunny fallback 720
  String resolvePlaybackUrl(String url, {String? userPreference}) {
    if (url.isEmpty) return url;

    // Signed URL — server sudah pre-sign path SPECIFIC. Rewrite path bikin
    // signature gak match → CDN reject 403. Skip rewrite, pakai apa adanya.
    if (url.contains('token=') && url.contains('expires=')) {
      return url;
    }

    // User override beats tier. data_saver memakai URL MP4 480p signed
    // dari backend (`FeedPost.videoDataSaverUrl`). Kalau caller masih
    // memberi canonical HLS, jangan rewrite path di client karena signed HLS
    // directory token tidak bisa dipindah ke MP4 variant.
    if (userPreference == 'data_saver') {
      final isHls = url.contains('.m3u8');
      if (isHls) {
        return url;
      }
      return _rewriteBunnyMp4Quality(url, 480) ?? url;
    }

    // high = HLS Full HD. Jangan paksa track tertentu di client; ExoPlayer /
    // AVPlayer memilih rendition dari Bunny master playlist dan fallback 720
    // otomatis saat bandwidth/device belum cocok.
    if (userPreference == 'high') {
      final isHls = url.contains('.m3u8');
      if (isHls) {
        return url;
      }
      return _bunnyMp4ToHls(url) ?? url;
    }

    // auto / null → tier-based behavior lama.
    final tier = _currentTier;
    final quality = recommendedQuality();

    final isHls = url.contains('.m3u8');

    if (isHls) {
      // Canonical feed playback is HLS adaptive for every tier. Hemat Data
      // is handled by a separate backend-signed 480p URL, not by rewriting
      // this playlist path locally.
      return url;
    }

    // Stored as MP4 — di WiFi try upgrade ke HLS untuk adaptive.
    if (tier == NetworkTier.wifi) {
      final hlsUrl = _bunnyMp4ToHls(url);
      if (hlsUrl != null) return hlsUrl;
    }

    // Mobile / fallback — rewrite quality.
    return _rewriteBunnyMp4Quality(url, quality.height) ?? url;
  }

  /// Pattern: `<origin>/<guid>/play_<NNN>p.mp4` → `<origin>/<guid>/playlist.m3u8`
  String? _bunnyMp4ToHls(String url) {
    final match = RegExp(
      r'^(https?:\/\/[^/]+\/[a-f0-9-]+\/)play_\d{3,4}p\.mp4(\?.*)?$',
      caseSensitive: false,
    ).firstMatch(url);
    if (match == null) return null;
    final query = match.group(2) ?? '';
    return '${match.group(1)}playlist.m3u8$query';
  }

  /// Rewrite quality digit di Bunny MP4 URL.
  String? _rewriteBunnyMp4Quality(String url, int height) {
    final match = RegExp(
      r'^(https?:\/\/[^/]+\/[a-f0-9-]+\/)play_\d{3,4}p\.mp4(\?.*)?$',
      caseSensitive: false,
    ).firstMatch(url);
    if (match == null) return null;
    final query = match.group(2) ?? '';
    return '${match.group(1)}play_${height}p.mp4$query';
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}

final videoQualityService = VideoQualityService();
