import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

// Mirror of lib/feed/runtime-config.ts (Wave 1).
//
// Web has navigator.connection { effectiveType, downlink, rtt, saveData };
// mobile doesn't — we approximate with connectivity_plus (wifi/mobile/none)
// and conservative defaults. iOS doesn't expose downlink, so we default to
// 720p on WiFi and never auto-pick 1080p (web does on downlink ≥10 Mbps).

enum NetworkTier { wifi, cellularFast, cellularSlow, offline, unknown }

enum PreloadTier { auto, metadata, none }

class NetworkInfo {
  final NetworkTier tier;
  final bool saveData;
  final bool isOnline;
  const NetworkInfo({
    required this.tier,
    required this.saveData,
    required this.isOnline,
  });

  static const unknown = NetworkInfo(
    tier: NetworkTier.unknown,
    saveData: false,
    isOnline: true,
  );
}

class NetworkTierService {
  final Connectivity _connectivity;
  NetworkInfo _last = NetworkInfo.unknown;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  final _controller = StreamController<NetworkInfo>.broadcast();

  NetworkTierService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  NetworkInfo get current => _last;
  Stream<NetworkInfo> get stream => _controller.stream;

  Future<void> init() async {
    final r = await _connectivity.checkConnectivity();
    _last = _classify(r);
    _controller.add(_last);
    _sub = _connectivity.onConnectivityChanged.listen((r) {
      _last = _classify(r);
      _controller.add(_last);
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }

  NetworkInfo _classify(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.none)) {
      return const NetworkInfo(
        tier: NetworkTier.offline,
        saveData: false,
        isOnline: false,
      );
    }
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return const NetworkInfo(
        tier: NetworkTier.wifi,
        saveData: false,
        isOnline: true,
      );
    }
    if (results.contains(ConnectivityResult.mobile)) {
      // We can't differentiate 4G vs 3G via connectivity_plus alone.
      // Assume fast — degrade only if user reports buffering or via
      // adaptive bitrate (HLS) handling itself.
      return const NetworkInfo(
        tier: NetworkTier.cellularFast,
        saveData: false,
        isOnline: true,
      );
    }
    return NetworkInfo.unknown;
  }
}

/// Recommended MP4 quality (Bunny play_{height}p.mp4) given network tier.
/// Mirror of getRecommendedVideoQuality() in runtime-config.ts.
int recommendedVideoQuality(NetworkInfo info) {
  if (info.saveData) return 360;
  switch (info.tier) {
    case NetworkTier.wifi:
      return 720; // web upgrades to 1080 on downlink ≥10 Mbps — skip on mobile
    case NetworkTier.cellularFast:
      return 720;
    case NetworkTier.cellularSlow:
      return 480;
    case NetworkTier.offline:
      return 240;
    case NetworkTier.unknown:
      return 480;
  }
}

/// Whether to use HLS playlist (Wave 2) vs MP4 progressive.
/// HLS adaptive only on WiFi — mobile data falls back to direct MP4 at
/// recommendedVideoQuality() to avoid burning data on adaptation churn.
bool shouldUseHls(NetworkInfo info) => info.tier == NetworkTier.wifi;

/// Preload strategy by distance from active card.
/// Mirror of getPreloadTier(distance) in runtime-config.ts.
PreloadTier preloadTierFor({
  required int distance, // 0 = active, ±1 = next/prev, etc.
  required NetworkInfo info,
}) {
  if (info.tier == NetworkTier.cellularSlow) {
    return distance == 0 ? PreloadTier.auto : PreloadTier.none;
  }
  // WiFi / 4G: aggressive prefetch
  if (distance == 0 || distance.abs() == 1) return PreloadTier.auto;
  if (distance.abs() == 2) return PreloadTier.metadata;
  return PreloadTier.none;
}

// ─────────────────────────────────────────────────────────────────────────────
// Device memory tier — controls virtual window (mount count around active).
// Web uses navigator.deviceMemory; mobile uses device_info_plus.

enum MemoryTier { low, medium, high }

class MemoryTierService {
  MemoryTier _tier = MemoryTier.medium;
  MemoryTier get tier => _tier;

  Future<void> init() async {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        // androidInfo doesn't expose total RAM; fall back to SDK-level heuristic.
        // SDK >= 33 typically ships with ≥4 GB. Adjust if profile data says otherwise.
        _tier = a.version.sdkInt >= 33 ? MemoryTier.high : MemoryTier.medium;
      } else if (Platform.isIOS) {
        // iOS doesn't expose RAM; iPhone 12+ all have ≥4 GB.
        _tier = MemoryTier.high;
      }
    } catch (_) {
      _tier = MemoryTier.medium;
    }
  }

  /// Number of cards to mount around the active one.
  ///   low    → window 1 (3 cards: prev, active, next)
  ///   medium → window 2 (5 cards)
  ///   high   → window 3 (7 cards)
  int get virtualWindow {
    switch (_tier) {
      case MemoryTier.low:
        return 1;
      case MemoryTier.medium:
        return 2;
      case MemoryTier.high:
        return 3;
    }
  }
}

