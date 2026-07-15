import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_warm_handoff.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';

FeedPost _post(String id, {bool video = true}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': video ? 'USER_VIDEO' : 'USER_PHOTO',
    if (video) 'videoUrl': 'https://example.com/$id.mp4',
    'mediaUrl': 'https://example.com/$id.jpg',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'createdAt': DateTime(2026).toIso8601String(),
  });
}

PostVideoWarmHandoff _handoff(
  FeedPost post, {
  Future<void> Function(String url)? initialize,
  required void Function() onDispose,
}) {
  return PostVideoWarmHandoff(
    postId: post.id,
    url: post.videoPlaybackUrl,
    session: VideoPlayerSession(
      url: post.videoPlaybackUrl,
      analyticsPostId: post.id,
      analyticsSurface: 'profile_grid_test',
      debugInitAttempt: initialize ?? (_) async {},
      debugDisposePlayer: () async => onDispose(),
    ),
  );
}

Future<void> _flushAsync() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tap-down then cancel waits for in-flight init and disposes once',
      () async {
    final initGate = Completer<void>();
    final disposed = Completer<void>();
    var disposeCount = 0;
    final prewarmer = ProfileVideoPrewarmer(
      factory: (post) => _handoff(
        post,
        initialize: (_) => initGate.future,
        onDispose: () {
          disposeCount++;
          if (!disposed.isCompleted) disposed.complete();
        },
      ),
    );

    prewarmer.prepare(_post('video-a'));
    prewarmer.cancel('video-a');
    await _flushAsync();
    expect(disposeCount, 0,
        reason: 'cancel must mark disposal but not race an unfinished init');

    initGate.complete();
    await disposed.future.timeout(const Duration(seconds: 1));
    prewarmer.cancel('video-a');
    await prewarmer.dispose();
    expect(disposeCount, 1,
        reason: 'init completion and repeated cancel share one disposal');
  });

  test('tap-down then tap claim survives a late pointer cancel', () async {
    var disposeCount = 0;
    final post = _post('video-a');
    final prewarmer = ProfileVideoPrewarmer(
      factory: (post) => _handoff(
        post,
        onDispose: () => disposeCount++,
      ),
    );

    prewarmer.prepare(post);
    final handoff = prewarmer.take(post);
    expect(handoff, isNotNull);

    // Gesture arena may deliver cleanup callbacks around pointer-up. Once the
    // tap has taken ownership, a late cancel must be a harmless no-op.
    prewarmer.cancel(post.id);
    await _flushAsync();
    expect(disposeCount, 0);

    final claimed = handoff!.claim(
      postId: post.id,
      url: post.videoPlaybackUrl,
    );
    expect(claimed, isNotNull);
    await prewarmer.dispose();
    expect(disposeCount, 0,
        reason: 'claimed session belongs to the Postingan coordinator');

    await claimed!.dispose();
    await claimed.dispose();
    expect(disposeCount, 1,
        reason: 'VideoPlayerSession.dispose itself must be idempotent');
  });

  test('rapid repeated interactions keep one candidate and dispose each once',
      () async {
    final disposeCounts = <String, int>{};
    final prewarmer = ProfileVideoPrewarmer(
      factory: (post) => _handoff(
        post,
        onDispose: () {
          disposeCounts[post.id] = (disposeCounts[post.id] ?? 0) + 1;
        },
      ),
    );

    for (var i = 0; i < 12; i++) {
      final post = _post('video-$i');
      prewarmer.prepare(post);
      if (i.isEven) {
        prewarmer.cancel(post.id);
        prewarmer.cancel(post.id);
      }
    }
    // Touching non-video content also clears the last pending video.
    prewarmer.prepare(_post('photo', video: false));
    await prewarmer.dispose();
    await _flushAsync();

    expect(disposeCounts.keys, hasLength(12));
    for (var i = 0; i < 12; i++) {
      expect(disposeCounts['video-$i'], 1,
          reason: 'video-$i must be disposed exactly once');
    }
  });
}
