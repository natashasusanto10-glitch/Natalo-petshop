import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/feed_video_observation.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_session_observer.dart';

void main() {
  test('adopting a preloaded controller keeps one observed identity', () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final controller = Object();

    observeFeedPreloadCreated(
      observer,
      postId: 'post-a',
      controller: controller,
    );
    observeFeedPreloadAdopted(
      observer,
      postId: 'post-a',
      controller: controller,
    );

    expect(observer.snapshot.liveControllerCount, 1);
    expect(observer.snapshot.collisions, isEmpty);
    expect(
      observer.snapshot.events.map((event) => event.type),
      <SocialVideoLifecycleType>[
        SocialVideoLifecycleType.created,
        SocialVideoLifecycleType.attached,
      ],
    );
  });

  test('disposing one preload removes only its observed identity', () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final first = Object();
    final second = Object();

    observeFeedPreloadCreated(observer, postId: 'post-a', controller: first);
    observeFeedPreloadCreated(observer, postId: 'post-b', controller: second);
    observeFeedControllerDisposed(
      observer,
      postId: 'post-a',
      controller: first,
      ownerId: feedPreloadOwnerId('post-a'),
    );

    expect(observer.snapshot.liveControllerCount, 1);
    expect(observer.snapshot.collisions, isEmpty);
  });

  test('failed preload does not remain live', () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final controller = Object();

    observeFeedPreloadCreated(
      observer,
      postId: 'post-a',
      controller: controller,
    );
    observeFeedControllerFailed(
      observer,
      postId: 'post-a',
      controller: controller,
      ownerId: feedPreloadOwnerId('post-a'),
    );

    expect(observer.snapshot.liveControllerCount, 0);
    expect(
      observer.snapshot.events.map((event) => event.type),
      containsAllInOrder(<SocialVideoLifecycleType>[
        SocialVideoLifecycleType.created,
        SocialVideoLifecycleType.failed,
        SocialVideoLifecycleType.released,
      ]),
    );
  });

  test('distinct local controller collides with a live preload', () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final preload = Object();
    final local = Object();

    observeFeedPreloadCreated(
      observer,
      postId: 'post-a',
      controller: preload,
    );
    observeFeedLocalControllerCreated(
      observer,
      postId: 'post-a',
      controller: local,
    );

    expect(observer.snapshot.liveControllerCount, 2);
    expect(observer.snapshot.collisions.single.controllerCount, 2);
  });
}
