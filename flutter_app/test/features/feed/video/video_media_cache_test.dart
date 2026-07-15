import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_media_cache.dart';

void main() {
  test('rotating CDN signatures keep the same media cache key', () {
    final first = videoMediaCacheKey(
      mediaId: 'post-1',
      url: 'https://CDN.example.com/video/a.mp4?token=old&expires=1',
    );
    final second = videoMediaCacheKey(
      mediaId: 'post-1',
      url: 'https://cdn.example.com/video/a.mp4?expires=2&token=new',
    );

    expect(second, first);
  });

  test('content query, media id, and path remain part of the identity', () {
    final base = videoMediaCacheKey(
      mediaId: 'post-1',
      url: 'https://cdn.example.com/video/a.mp4?version=1&token=old',
    );

    expect(
      videoMediaCacheKey(
        mediaId: 'post-1',
        url: 'https://cdn.example.com/video/a.mp4?version=2&token=new',
      ),
      isNot(base),
    );
    expect(
      videoMediaCacheKey(
        mediaId: 'post-2',
        url: 'https://cdn.example.com/video/a.mp4?version=1',
      ),
      isNot(base),
    );
    expect(
      videoMediaCacheKey(
        mediaId: 'post-1',
        url: 'https://cdn.example.com/video/b.mp4?version=1',
      ),
      isNot(base),
    );
  });

  test('canonical resource sorts stable query and removes fragments', () {
    expect(
      canonicalVideoResourceUrl(
        'HTTPS://CDN.EXAMPLE.COM/a/../video.mp4?b=2&a=1#preview',
      ),
      'https://cdn.example.com/video.mp4?a=1&b=2',
    );
  });
}
