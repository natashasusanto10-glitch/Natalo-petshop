import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_warm_handoff.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';

class _CountingSession extends VideoPlayerSession {
  _CountingSession()
      : super(
          url: 'https://example.com/video.mp4',
          debugInitAttempt: (_) async {},
        );

  int disposeCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount++;
    await super.dispose();
  }
}

void main() {
  test('profile-grid factory keeps photos cold', () {
    expect(
      PostVideoWarmHandoff.createIfVideo(
        isVideo: false,
        postId: 'photo-1',
        url: 'https://example.com/photo.jpg',
      ),
      isNull,
    );
  });

  test('profile-grid factory keeps invalid videos cold', () {
    expect(
      PostVideoWarmHandoff.createIfVideo(
        isVideo: true,
        postId: 'post-1',
        url: '   ',
      ),
      isNull,
    );
  });

  test('claim validates post and canonical URL and is one-shot', () async {
    final session = _CountingSession();
    final handoff = PostVideoWarmHandoff(
      postId: 'post-1',
      url: 'HTTPS://EXAMPLE.COM/a/../video.mp4',
      session: session,
    );

    expect(
      handoff.claim(postId: 'wrong', url: 'https://example.com/video.mp4'),
      isNull,
    );
    expect(
      handoff.claim(postId: 'post-1', url: 'https://example.com/video.mp4'),
      same(session),
    );
    expect(
      handoff.claim(postId: 'post-1', url: 'https://example.com/video.mp4'),
      isNull,
    );
    await handoff.disposeIfUnclaimed();
    await handoff.disposeIfUnclaimed();
    expect(session.disposeCount, 0);
    await session.dispose();
  });

  test('disposeIfUnclaimed disposes exactly once', () async {
    final session = _CountingSession();
    final handoff = PostVideoWarmHandoff(
      postId: 'post-1',
      url: 'https://example.com/video.mp4',
      session: session,
    );

    await handoff.disposeIfUnclaimed();
    await handoff.disposeIfUnclaimed();
    expect(session.disposeCount, 1);
  });
}
