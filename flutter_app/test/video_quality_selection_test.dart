import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/services/video_quality_service.dart';

void main() {
  group('Feed video quality selection', () {
    test('data_saver prefers backend 480p URL', () {
      final post = FeedPost.fromJson({
        'id': 'post-1',
        'videoUrl': 'https://cdn.example.com/post-1/playlist.m3u8',
        'videoDataSaverUrl': 'https://cdn.example.com/post-1/play_480p.mp4',
        'createdAt': '2026-07-13T00:00:00.000Z',
      });

      expect(
        post.videoPlaybackUrlForQuality('data_saver'),
        'https://cdn.example.com/post-1/play_480p.mp4',
      );
      expect(
        post.videoPlaybackUrlForQuality('auto'),
        'https://cdn.example.com/post-1/playlist.m3u8',
      );
      expect(
        post.videoPlaybackUrlForQuality('high'),
        'https://cdn.example.com/post-1/playlist.m3u8',
      );
    });

    test('data_saver falls back to canonical HLS when optional URL is absent',
        () {
      final post = FeedPost.fromJson({
        'id': 'post-1',
        'videoUrl': 'https://cdn.example.com/post-1/playlist.m3u8',
        'createdAt': '2026-07-13T00:00:00.000Z',
      });

      expect(
        post.videoPlaybackUrlForQuality('data_saver'),
        'https://cdn.example.com/post-1/playlist.m3u8',
      );
    });

    test('FeedMedia data_saver prefers optional 480p URL for video only', () {
      final video = FeedMedia.fromJson({
        'id': 'media-1',
        'mediaType': 'video',
        'mediaUrl': 'https://cdn.example.com/media-1/playlist.m3u8',
        'videoDataSaverUrl': 'https://cdn.example.com/media-1/play_480p.mp4',
      });
      final image = FeedMedia.fromJson({
        'id': 'media-2',
        'mediaType': 'image',
        'mediaUrl': 'https://cdn.example.com/media-2.jpg',
        'videoDataSaverUrl': 'https://cdn.example.com/media-2/play_480p.mp4',
      });

      expect(
        video.mediaPlaybackUrlForQuality('data_saver'),
        'https://cdn.example.com/media-1/play_480p.mp4',
      );
      expect(
        video.mediaPlaybackUrlForQuality('high'),
        'https://cdn.example.com/media-1/playlist.m3u8',
      );
      expect(
        image.mediaPlaybackUrlForQuality('data_saver'),
        'https://cdn.example.com/media-2.jpg',
      );
    });

    test('VideoQualityService does not rewrite canonical HLS for any mode', () {
      const hls = 'https://cdn.example.com/post-1/playlist.m3u8';

      expect(
        videoQualityService.resolvePlaybackUrl(
          hls,
          userPreference: 'data_saver',
        ),
        hls,
      );
      expect(
        videoQualityService.resolvePlaybackUrl(hls, userPreference: 'auto'),
        hls,
      );
      expect(
        videoQualityService.resolvePlaybackUrl(hls, userPreference: 'high'),
        hls,
      );
    });

    test('auto uses backend 480p MP4 on fast and slow cellular', () {
      const hls = 'https://cdn.example.com/post-1/playlist.m3u8';
      const mp4 = 'https://cdn.example.com/post-1/play_480p.mp4';

      for (final tier in [
        NetworkTier.cellularFast,
        NetworkTier.cellularSlow,
      ]) {
        expect(
          videoQualityService.resolvePlaybackUrl(
            hls,
            dataSaverUrl: mp4,
            userPreference: 'auto',
            networkTier: tier,
          ),
          mp4,
        );
      }
    });

    test('auto cellular falls back to canonical HLS without backend 480p', () {
      const hls = 'https://cdn.example.com/post-1/playlist.m3u8';

      expect(
        videoQualityService.resolvePlaybackUrl(
          hls,
          dataSaverUrl: '   ',
          userPreference: 'auto',
          networkTier: NetworkTier.cellularFast,
        ),
        hls,
      );
    });

    test('wifi auto and cellular high retain canonical HLS', () {
      const hls = 'https://cdn.example.com/post-1/playlist.m3u8';
      const mp4 = 'https://cdn.example.com/post-1/play_480p.mp4';

      expect(
        videoQualityService.resolvePlaybackUrl(
          hls,
          dataSaverUrl: mp4,
          userPreference: 'auto',
          networkTier: NetworkTier.wifi,
        ),
        hls,
      );
      expect(
        videoQualityService.resolvePlaybackUrl(
          hls,
          dataSaverUrl: mp4,
          userPreference: 'high',
          networkTier: NetworkTier.cellularSlow,
        ),
        hls,
      );
    });

    test('explicit data saver keeps preferring backend 480p on wifi', () {
      const hls = 'https://cdn.example.com/post-1/playlist.m3u8';
      const mp4 = 'https://cdn.example.com/post-1/play_480p.mp4';

      expect(
        videoQualityService.resolvePlaybackUrl(
          hls,
          dataSaverUrl: mp4,
          userPreference: 'data_saver',
          networkTier: NetworkTier.wifi,
        ),
        mp4,
      );
    });

    test('blank canonical URL still permits only eligible backend fallback',
        () {
      const mp4 = 'https://cdn.example.com/post-1/play_480p.mp4';

      expect(
        videoQualityService.resolvePlaybackUrl(
          '',
          dataSaverUrl: mp4,
          userPreference: 'data_saver',
          networkTier: NetworkTier.wifi,
        ),
        mp4,
      );

      for (final tier in [
        NetworkTier.cellularFast,
        NetworkTier.cellularSlow,
      ]) {
        expect(
          videoQualityService.resolvePlaybackUrl(
            '',
            dataSaverUrl: mp4,
            userPreference: 'auto',
            networkTier: tier,
          ),
          mp4,
        );
      }

      expect(
        videoQualityService.resolvePlaybackUrl(
          '',
          dataSaverUrl: mp4,
          userPreference: 'auto',
          networkTier: NetworkTier.wifi,
        ),
        isEmpty,
      );
      expect(
        videoQualityService.resolvePlaybackUrl(
          '',
          dataSaverUrl: mp4,
          userPreference: 'high',
          networkTier: NetworkTier.cellularFast,
        ),
        isEmpty,
      );
    });

    test('legacy unsigned MP4 quality uses the injected effective tier', () {
      const mp4 =
          'https://cdn.example.com/01234567-89ab-cdef-0123-456789abcdef/play_1080p.mp4';

      expect(
        videoQualityService.resolvePlaybackUrl(
          mp4,
          userPreference: 'auto',
          networkTier: NetworkTier.cellularSlow,
        ),
        'https://cdn.example.com/01234567-89ab-cdef-0123-456789abcdef/play_480p.mp4',
      );
      expect(
        videoQualityService.resolvePlaybackUrl(
          mp4,
          userPreference: 'auto',
          networkTier: NetworkTier.offline,
        ),
        'https://cdn.example.com/01234567-89ab-cdef-0123-456789abcdef/play_240p.mp4',
      );
    });
  });
}
