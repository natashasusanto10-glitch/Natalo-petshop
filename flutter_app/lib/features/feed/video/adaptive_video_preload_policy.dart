import '../../../services/video_quality_service.dart';

enum VideoSwipeDirection { forward, backward }

/// Pure, deterministic controller-preload policy.
class AdaptiveVideoPreloadPolicy {
  const AdaptiveVideoPreloadPolicy();

  // Max concurrent preloads. Raised 3→4 to hold the widest velocity-adaptive
  // wifi window (fast-fling = 4 ahead). Coordinator LRU still evicts the
  // oldest so live-session count stays bounded.
  static const int maxPreloads = 4;
  static const Duration cellularBufferAheadThreshold = Duration(seconds: 3);

  // Fling-velocity thresholds (px/s, magnitude) that widen the wifi preload
  // window. Tuned empirically via device-verify — see design doc
  // 2026-07-19-feed-adaptive-preload-velocity-design.md.
  static const double mediumFlingVelocity = 800;
  static const double fastFlingVelocity = 2500;

  List<int> offsets({
    required String qualityPreference,
    required NetworkTier networkTier,
    required bool autoplayEnabled,
    required VideoSwipeDirection swipeDirection,
    required Duration activeBufferAhead,
    bool interactionLocked = false,
    double scrollVelocity = 0,
  }) {
    if (!autoplayEnabled ||
        interactionLocked ||
        qualityPreference == 'data_saver' ||
        qualityPreference == 'off' ||
        networkTier == NetworkTier.offline) {
      return const [];
    }

    final direction = swipeDirection == VideoSwipeDirection.forward ? 1 : -1;
    final isWifi = networkTier == NetworkTier.wifi;
    if (isWifi &&
        (qualityPreference == 'auto' || qualityPreference == 'high')) {
      // Velocity-adaptive window (wifi only). Faster fling → widen ahead of
      // travel; at the fastest tier drop the behind slot since a reversal is
      // unlikely while momentum is high.
      final speed = scrollVelocity.abs();
      if (speed > fastFlingVelocity) {
        return [direction, direction * 2, direction * 3, direction * 4];
      }
      if (speed >= mediumFlingVelocity) {
        return [direction, direction * 2, direction * 3, -direction];
      }
      return [direction, direction * 2, -direction];
    }

    if ((networkTier == NetworkTier.cellularFast ||
            networkTier == NetworkTier.cellularSlow) &&
        activeBufferAhead < cellularBufferAheadThreshold) {
      return const [];
    }

    return [direction];
  }
}

const adaptiveVideoPreloadPolicy = AdaptiveVideoPreloadPolicy();
