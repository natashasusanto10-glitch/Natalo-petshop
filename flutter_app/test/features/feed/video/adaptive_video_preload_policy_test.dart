import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/adaptive_video_preload_policy.dart';
import 'package:natalo_petshop_flutter/services/video_quality_service.dart';

void main() {
  const policy = AdaptiveVideoPreloadPolicy();

  List<int> offsets({
    String quality = 'auto',
    NetworkTier tier = NetworkTier.unknown,
    bool autoplay = true,
    VideoSwipeDirection direction = VideoSwipeDirection.forward,
    bool locked = false,
    Duration bufferAhead = Duration.zero,
  }) {
    return policy.offsets(
      qualityPreference: quality,
      networkTier: tier,
      autoplayEnabled: autoplay,
      swipeDirection: direction,
      activeBufferAhead: bufferAhead,
      interactionLocked: locked,
    );
  }

  test('data saver, offline, autoplay off, and interaction lock disable', () {
    expect(offsets(quality: 'data_saver'), isEmpty);
    expect(offsets(quality: 'off'), isEmpty);
    expect(offsets(tier: NetworkTier.offline), isEmpty);
    expect(offsets(autoplay: false), isEmpty);
    expect(offsets(locked: true), isEmpty);
  });

  test('cellular waits for three buffered seconds then preloads one', () {
    for (final tier in [NetworkTier.cellularFast, NetworkTier.cellularSlow]) {
      expect(offsets(tier: tier), isEmpty);
      expect(
        offsets(tier: tier, bufferAhead: const Duration(milliseconds: 2999)),
        isEmpty,
      );
      expect(
        offsets(tier: tier, bufferAhead: const Duration(seconds: 3)),
        [1],
      );
      expect(
        offsets(
          tier: tier,
          direction: VideoSwipeDirection.backward,
          bufferAhead: const Duration(seconds: 3),
        ),
        [-1],
      );
    }
  });

  test('unknown preserves immediate one-item directional preload', () {
    expect(offsets(tier: NetworkTier.unknown), [1]);
  });

  test('wifi auto/high preload two ahead and one behind, capped at three', () {
    expect(offsets(tier: NetworkTier.wifi), [1, 2, -1]);
    expect(offsets(tier: NetworkTier.wifi, quality: 'high'), [1, 2, -1]);
    expect(
      offsets(
        tier: NetworkTier.wifi,
        direction: VideoSwipeDirection.backward,
      ),
      [-1, -2, 1],
    );
    expect(offsets(tier: NetworkTier.wifi).length, 3);
  });
}
