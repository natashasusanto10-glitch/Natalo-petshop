import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_warm_handoff.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_session_observer.dart';
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
        hasAudio: true,
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
        hasAudio: true,
      ),
      isNull,
    );
  });

  test('profile-grid factory preserves silent-video audio metadata', () async {
    bool? receivedHasAudio;
    final testSession = _CountingSession();
    final handoff = PostVideoWarmHandoff.createIfVideo(
      isVideo: true,
      postId: 'silent-post',
      url: 'https://example.com/silent.mp4',
      hasAudio: false,
      sessionFactory: ({
        required postId,
        required url,
        required hasAudio,
        observationObserver,
        observationContext,
      }) {
        receivedHasAudio = hasAudio;
        return testSession;
      },
    );

    final session = handoff!.claim(
      postId: 'silent-post',
      url: 'https://example.com/silent.mp4',
      hasAudio: false,
    );
    final claimedSession = session!;
    expect(receivedHasAudio, isFalse);
    expect(claimedSession, same(testSession));
    await claimedSession.dispose();
  });

  test('profile-grid factory supplies the prewarm observation context',
      () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    SocialVideoObservationContext? receivedContext;
    final handoff = PostVideoWarmHandoff.create(
      postId: 'post-a',
      url: 'https://example.com/video.mp4',
      hasAudio: true,
      observationObserver: observer,
      sessionFactory: ({
        required postId,
        required url,
        required hasAudio,
        observationObserver,
        observationContext,
      }) {
        receivedContext = observationContext;
        return VideoPlayerSession(
          url: url,
          observationObserver: observationObserver,
          observationContext: observationContext,
          debugInitAttempt: (_) async {},
        );
      },
    );

    expect(receivedContext!.postId, 'post-a');
    expect(receivedContext!.surface, SocialVideoSurface.profileGrid);
    expect(receivedContext!.ownerId, 'coordinator-post-a');

    await Future<void>.delayed(Duration.zero);
    final claimed = handoff.claim(
      postId: 'post-a',
      url: 'https://example.com/video.mp4',
      hasAudio: true,
    );

    expect(claimed, isNotNull);
    expect(
      observer.snapshot.events.map((event) => event.type),
      equals(<SocialVideoLifecycleType>[
        SocialVideoLifecycleType.created,
        SocialVideoLifecycleType.initialized,
        SocialVideoLifecycleType.attached,
      ]),
    );
    expect(
      observer.snapshot.events.last.surface,
      SocialVideoSurface.postDetail,
    );

    await claimed!.dispose();
  });

  test('claim validates post and canonical URL and is one-shot', () async {
    final session = _CountingSession();
    final handoff = PostVideoWarmHandoff(
      postId: 'post-1',
      url: 'HTTPS://EXAMPLE.COM/a/../video.mp4',
      hasAudio: true,
      session: session,
    );

    expect(
      handoff.claim(
        postId: 'wrong',
        url: 'https://example.com/video.mp4',
        hasAudio: true,
      ),
      isNull,
    );
    expect(
      handoff.claim(
        postId: 'post-1',
        url: 'https://example.com/video.mp4',
        hasAudio: false,
      ),
      isNull,
    );
    expect(
      handoff.claim(
        postId: 'post-1',
        url: 'https://example.com/video.mp4',
        hasAudio: true,
      ),
      same(session),
    );
    expect(
      handoff.claim(
        postId: 'post-1',
        url: 'https://example.com/video.mp4',
        hasAudio: true,
      ),
      isNull,
    );
    await handoff.disposeIfUnclaimed();
    await handoff.disposeIfUnclaimed();
    expect(session.disposeCount, 0);
    await session.dispose();
  });

  test('claim accepts a refreshed signature for the same media', () async {
    final session = _CountingSession();
    final handoff = PostVideoWarmHandoff(
      postId: 'post-1',
      url: 'https://cdn.example.com/video.mp4?token=old&expires=1',
      hasAudio: true,
      session: session,
    );

    expect(
      handoff.claim(
        postId: 'post-1',
        url: 'https://cdn.example.com/video.mp4?expires=2&token=new',
        hasAudio: true,
      ),
      same(session),
    );
    await session.dispose();
  });

  test('disposeIfUnclaimed disposes exactly once', () async {
    final session = _CountingSession();
    final handoff = PostVideoWarmHandoff(
      postId: 'post-1',
      url: 'https://example.com/video.mp4',
      hasAudio: true,
      session: session,
    );

    await handoff.disposeIfUnclaimed();
    await handoff.disposeIfUnclaimed();
    expect(session.disposeCount, 1);
  });
}
