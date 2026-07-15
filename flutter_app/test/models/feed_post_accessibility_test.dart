import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';

Map<String, dynamic> _postJson({
  String? videoAltText,
  String? caption,
  String description = '',
}) {
  return {
    'id': 'post-1',
    'slug': 'post-1',
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/video.mp4',
    'videoAltText': videoAltText,
    'hasAudio': false,
    'subtitleUrl': 'https://cdn.example.com/subtitles/id.vtt',
    'subtitleLanguage': 'id',
    'caption': caption,
    'description': description,
    'author': {'id': 'author-1', 'name': 'Natalo Petshop'},
    'mediaItems': [
      {
        'id': 'media-1',
        'mediaType': 'image',
        'mediaUrl': 'https://example.com/image.jpg',
        'altText': 'Kemasan makanan kucing berwarna biru',
      },
    ],
    'createdAt': '2026-07-15T00:00:00.000Z',
  };
}

void main() {
  test('accessibility metadata round-trips through FeedPost JSON', () {
    final post = FeedPost.fromJson(
      _postJson(videoAltText: 'Kucing bermain dengan bola'),
    );

    expect(post.videoAltText, 'Kucing bermain dengan bola');
    expect(post.hasAudio, isFalse);
    expect(post.subtitleUrl, 'https://cdn.example.com/subtitles/id.vtt');
    expect(post.subtitleLanguage, 'id');
    expect(
        post.mediaItems.single.altText, 'Kemasan makanan kucing berwarna biru');

    final restored = FeedPost.fromJson(post.toJson());
    expect(restored.videoAltText, post.videoAltText);
    expect(restored.hasAudio, post.hasAudio);
    expect(restored.subtitleUrl, post.subtitleUrl);
    expect(restored.subtitleLanguage, post.subtitleLanguage);
    expect(restored.mediaItems.single.altText, post.mediaItems.single.altText);
    expect(post.mediaItems.single.toJson()['altText'],
        'Kemasan makanan kucing berwarna biru');
  });

  test('media label prefers alt text, then caption, description, and author',
      () {
    expect(
      FeedPost.fromJson(
        _postJson(
          videoAltText: 'Alt eksplisit',
          caption: 'Caption',
          description: 'Deskripsi',
        ),
      ).mediaAccessibilityLabel,
      'Alt eksplisit',
    );
    expect(
      FeedPost.fromJson(
        _postJson(caption: 'Caption', description: 'Deskripsi'),
      ).mediaAccessibilityLabel,
      'Caption',
    );
    expect(
      FeedPost.fromJson(_postJson(description: 'Deskripsi'))
          .mediaAccessibilityLabel,
      'Deskripsi',
    );
    expect(
      FeedPost.fromJson(_postJson()).mediaAccessibilityLabel,
      'Video dari Natalo Petshop',
    );
  });
}
