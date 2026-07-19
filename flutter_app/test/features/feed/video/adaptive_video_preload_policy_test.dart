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
    double velocity = 0,
  }) {
    return policy.offsets(
      qualityPreference: quality,
      networkTier: tier,
      autoplayEnabled: autoplay,
      swipeDirection: direction,
      activeBufferAhead: bufferAhead,
      interactionLocked: locked,
      scrollVelocity: velocity,
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

  group('velocity-adaptive window (wifi only)', () {
    test('velocity 0 keeps legacy window (backward compatible)', () {
      // Default velocity=0 must be byte-for-byte identical to pre-feature.
      expect(offsets(tier: NetworkTier.wifi, velocity: 0), [1, 2, -1]);
      expect(
        offsets(
          tier: NetworkTier.wifi,
          direction: VideoSwipeDirection.backward,
          velocity: 0,
        ),
        [-1, -2, 1],
      );
    });

    test('slow fling (<800) keeps legacy window', () {
      expect(offsets(tier: NetworkTier.wifi, velocity: 799), [1, 2, -1]);
      expect(offsets(tier: NetworkTier.wifi, velocity: -799), [1, 2, -1]);
    });

    test('medium fling (800-2500) widens one ahead, keeps one behind', () {
      expect(offsets(tier: NetworkTier.wifi, velocity: 800), [1, 2, 3, -1]);
      expect(offsets(tier: NetworkTier.wifi, velocity: 2500), [1, 2, 3, -1]);
      // Magnitude only — negative velocity (physical scroll direction) does
      // not flip the logical swipeDirection.
      expect(offsets(tier: NetworkTier.wifi, velocity: -1500), [1, 2, 3, -1]);
      expect(
        offsets(
          tier: NetworkTier.wifi,
          direction: VideoSwipeDirection.backward,
          velocity: 1500,
        ),
        [-1, -2, -3, 1],
      );
    });

    test('fast fling (>2500) widens further and drops the behind slot', () {
      expect(offsets(tier: NetworkTier.wifi, velocity: 2501), [1, 2, 3, 4]);
      expect(offsets(tier: NetworkTier.wifi, velocity: 5000), [1, 2, 3, 4]);
      expect(
        offsets(
          tier: NetworkTier.wifi,
          direction: VideoSwipeDirection.backward,
          velocity: 5000,
        ),
        [-1, -2, -3, -4],
      );
    });

    test('velocity never widens cellular window', () {
      for (final tier in [NetworkTier.cellularFast, NetworkTier.cellularSlow]) {
        expect(
          offsets(
            tier: tier,
            velocity: 5000,
            bufferAhead: const Duration(seconds: 3),
          ),
          [1],
        );
      }
    });

    test('velocity never widens unknown-tier single preload', () {
      expect(offsets(tier: NetworkTier.unknown, velocity: 5000), [1]);
    });

    test('velocity does not resurrect a disabled window', () {
      expect(offsets(quality: 'data_saver', velocity: 5000), isEmpty);
      expect(offsets(tier: NetworkTier.offline, velocity: 5000), isEmpty);
      expect(offsets(locked: true, velocity: 5000), isEmpty);
    });
  });
}
