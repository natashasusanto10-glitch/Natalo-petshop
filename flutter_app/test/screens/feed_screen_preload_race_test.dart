import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:natalo_petshop_flutter/services/video_quality_service.dart';

void main() {
  test('stale completion cannot initialize a replaced preload slot', () {
    final oldSlot = Object();
    final replacement = Object();

    expect(
      feedPreloadCompletionIsCurrent(
        registeredSlot: replacement,
        candidate: oldSlot,
        registeredGeneration: 2,
        startedGeneration: 1,
      ),
      isFalse,
    );
  });

  test('new pass can safely adopt the same in-flight preload slot', () {
    final slot = Object();

    expect(
      feedPreloadCompletionIsCurrent(
        registeredSlot: slot,
        candidate: slot,
        registeredGeneration: 2,
        startedGeneration: 1,
      ),
      isTrue,
    );
  });

  test('tier-selected URL change requires preload replacement', () {
    expect(
      feedPreloadUrlNeedsReplacement(
        'https://cdn.example/video/playlist.m3u8',
        'https://cdn.example/video/play_480p.mp4',
      ),
      isTrue,
    );
    expect(
      feedPreloadUrlNeedsReplacement(
        'https://cdn.example/video/play_480p.mp4',
        'https://cdn.example/video/play_480p.mp4',
      ),
      isFalse,
    );
  });

  group('Feed preload URL resolution', () {
    const fallback480 =
        'https://cdn.example/video/play_480p.mp4?token=signed&expires=1';

    test('cellular Auto can preload fallback-only video', () {
      expect(
        feedResolvePreloadUrl(
          canonicalUrl: '',
          dataSaverUrl: fallback480,
          qualityPreference: 'auto',
          networkTier: NetworkTier.cellularFast,
        ),
        fallback480,
      );
    });

    test('Data Saver can preload fallback-only video', () {
      expect(
        feedResolvePreloadUrl(
          canonicalUrl: '',
          dataSaverUrl: fallback480,
          qualityPreference: 'data_saver',
          networkTier: NetworkTier.wifi,
        ),
        fallback480,
      );
    });

    test('WiFi Auto and High still skip when canonical URL is absent', () {
      expect(
        feedResolvePreloadUrl(
          canonicalUrl: '',
          dataSaverUrl: fallback480,
          qualityPreference: 'auto',
          networkTier: NetworkTier.wifi,
        ),
        isEmpty,
      );
      expect(
        feedResolvePreloadUrl(
          canonicalUrl: '',
          dataSaverUrl: fallback480,
          qualityPreference: 'high',
          networkTier: NetworkTier.cellularFast,
        ),
        isEmpty,
      );
    });
  });
}
