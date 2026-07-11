import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Sprint 2 #6 #7 — Network-aware video quality + HLS adaptive untuk
/// feed video player.
///
/// Decision tree per playback:
///   - WiFi / Ethernet → HLS playlist (Bunny adaptive bitrate, switch
///     quality mid-clip berdasarkan bandwidth)
///   - Mobile 4G+ / unknown → MP4 progressive 720p (single file CDN
///     cache, lebih cepat start play)
///   - Mobile lemah / data-saver → MP4 480p
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
        // Pakai HLS playlist instead, tapi kalau caller butuh MP4 fallback
        // (HLS playlist rewrite gagal), pakai 720p sebagai aman.
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
  /// IMPORTANT: Perlakuan URL signed tergantung skema token Bunny:
  ///   - **Directory token** (HLS, ada `token_path=`): token berlaku untuk
  ///     seluruh direktori `/<guid>/`, jadi rewrite nama file di dalamnya
  ///     (playlist.m3u8 → play_<NNN>p.mp4) tetap valid. Preferensi eksplisit
  ///     user (`data_saver` / `high`) DIHORMATI; `auto` dibiarkan apa adanya.
  ///   - **File-spesifik token** (query `token=` tanpa `token_path`): signature
  ///     terikat path file persis → rewrite bikin CDN 403. Skip, pakai apa adanya.
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
  ///   - `null` / `'auto'`  → tier-based (WiFi HLS, Mobile 720p, dst)
  ///   - `'data_saver'`     → paksa MP4 480p, skip HLS upgrade
  ///   - `'high'`           → cap di MP4 720p (jangan upgrade ke HLS yang
  ///                          bisa balloon ke 1080p adaptive)
  String resolvePlaybackUrl(String url, {String? userPreference}) {
    if (url.isEmpty) return url;

    // Signed URL — dua skema token Bunny CDN:
    //
    //   1) Directory token (HLS): ditandai `token_path=` di path, mis.
    //      `<origin>/bcdn_token=…&token_path=%2F<guid>%2F&expires=…/<guid>/playlist.m3u8`.
    //      Token ditandatangani atas DIREKTORI (`token_path`), bukan file —
    //      jadi SEMUA file di dalam `/<guid>/` (playlist.m3u8, play_480p.mp4,
    //      segment .ts) valid dengan token yang sama. Rewrite nama file dalam
    //      direktori itu (playlist.m3u8 → play_<NNN>p.mp4) TIDAK bikin 403,
    //      jadi preferensi eksplisit user boleh dihormati.
    //
    //   2) File-spesifik token (query `token=…&expires=…` TANPA `token_path`):
    //      signature terikat path file persis. Rewrite path apa pun → 403.
    //      Skip, pakai apa adanya.
    //
    // Ref: Bunny Token Authentication V2 — directory token via `token_path`
    // (https://docs.bunny.net/cdn/security/token-authentication/advanced).
    final isSigned = url.contains('token=') && url.contains('expires=');
    final isDirectoryToken = isSigned && url.contains('token_path=');

    if (isSigned && !isDirectoryToken) {
      return url;
    }
    // Opsi A: hanya preferensi kualitas EKSPLISIT (data_saver / high) yang
    // men-trigger rewrite pada directory-token URL. `auto` / null tetap pakai
    // signed URL apa adanya supaya perilaku produksi saat ini tidak berubah.
    if (isDirectoryToken &&
        userPreference != 'data_saver' &&
        userPreference != 'high') {
      return url;
    }

    // User override beats tier. data_saver = paksa 480p MP4 (no HLS).
    if (userPreference == 'data_saver') {
      // Directory-token signed URL: rewrite file terminal saja (prefix token
      // dipertahankan, tetap di direktori yang sama → signature valid).
      if (isDirectoryToken) {
        return _rewriteTerminalFile(url, 480) ?? url;
      }
      final isHls = url.contains('.m3u8');
      if (isHls) {
        return _bunnyHlsToMp4(url, 480) ?? url;
      }
      return _rewriteBunnyMp4Quality(url, 480) ?? url;
    }

    // high = cap di 720p MP4, jangan upgrade HLS (HLS bisa adaptive ke 1080p
    // di WiFi cepat — user pilih high biasanya mau predictable 720p).
    if (userPreference == 'high') {
      if (isDirectoryToken) {
        return _rewriteTerminalFile(url, 720) ?? url;
      }
      final isHls = url.contains('.m3u8');
      if (isHls) {
        return _bunnyHlsToMp4(url, 720) ?? url;
      }
      return _rewriteBunnyMp4Quality(url, 720) ?? url;
    }

    // auto / null → tier-based behavior lama.
    final tier = _currentTier;
    final quality = recommendedQuality();

    final isHls = url.contains('.m3u8');

    if (isHls) {
      // Stored as HLS — pakai HLS langsung di WiFi, rewrite ke MP4 di mobile
      // supaya tidak ada manifest overhead.
      if (tier == NetworkTier.wifi || tier == NetworkTier.unknown) {
        return url;
      }
      // Convert HLS → MP4 quality
      final mp4Url = _bunnyHlsToMp4(url, quality.height);
      return mp4Url ?? url;
    }

    // Stored as MP4 — di WiFi try upgrade ke HLS untuk adaptive.
    if (tier == NetworkTier.wifi) {
      final hlsUrl = _bunnyMp4ToHls(url);
      if (hlsUrl != null) return hlsUrl;
    }

    // Mobile / fallback — rewrite quality.
    return _rewriteBunnyMp4Quality(url, quality.height) ?? url;
  }

  /// Pattern: `<origin>/<guid>/playlist.m3u8` → `<origin>/<guid>/play_<NNN>p.mp4`
  String? _bunnyHlsToMp4(String url, int height) {
    final match = RegExp(
      r'^(https?:\/\/[^/]+\/[a-f0-9-]+\/)playlist\.m3u8(\?.*)?$',
      caseSensitive: false,
    ).firstMatch(url);
    if (match == null) return null;
    final query = match.group(2) ?? '';
    return '${match.group(1)}play_${height}p.mp4$query';
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

  /// Rewrite file terminal (`playlist.m3u8` atau `play_<NNN>p.mp4`) → MP4
  /// quality target, TANPA menyentuh prefix di depannya.
  ///
  /// Dipakai untuk URL signed directory-token (HLS) yang bentuknya:
  ///   `<origin>/bcdn_token=…&token_path=…&expires=…/<guid>/playlist.m3u8`
  /// Regex `_bunnyHlsToMp4` biasa tidak cocok karena prefix token menambah
  /// satu segmen path. Di sini kita hanya ganti segmen file paling akhir,
  /// jadi token/token_path/expires + direktori `/<guid>/` tetap utuh →
  /// signature Bunny tetap valid (token berlaku untuk seluruh direktori).
  String? _rewriteTerminalFile(String url, int height) {
    final match = RegExp(
      r'/(?:playlist\.m3u8|play_\d{3,4}p\.mp4)(\?[^/]*)?$',
      caseSensitive: false,
    ).firstMatch(url);
    if (match == null) return null;
    final query = match.group(1) ?? '';
    return '${url.substring(0, match.start)}/play_${height}p.mp4$query';
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
