import '../../../services/video_quality_service.dart';

enum VideoSwipeDirection { forward, backward }

/// Pure, deterministic controller-preload policy.
class AdaptiveVideoPreloadPolicy {
  const AdaptiveVideoPreloadPolicy();

  static const int maxPreloads = 3;
  static const Duration cellularBufferAheadThreshold = Duration(seconds: 3);

  List<int> offsets({
    required String qualityPreference,
    required NetworkTier networkTier,
    required bool autoplayEnabled,
    required VideoSwipeDirection swipeDirection,
    required Duration activeBufferAhead,
    bool interactionLocked = false,
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
