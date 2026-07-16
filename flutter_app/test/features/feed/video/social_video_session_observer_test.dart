import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_session_observer.dart';

void main() {
  test('tracks one live controller without reporting a collision', () {
    final observer = SocialVideoSessionObserver(enabled: true);

    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed-slot-a',
      controllerIdentity: Object(),
    );

    expect(observer.snapshot.liveControllerCount, 1);
    expect(observer.snapshot.collisions, isEmpty);
  });

  test('reports different live controller identities for one post', () {
    final observer = SocialVideoSessionObserver(enabled: true);

    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: Object(),
    );
    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.postDetail,
      ownerId: 'detail',
      controllerIdentity: Object(),
    );

    expect(observer.snapshot.collisions.single.postId, 'post-a');
    expect(observer.snapshot.collisions.single.controllerCount, 2);
  });

  test('disabled observer is a strict no-op', () {
    final observer = SocialVideoSessionObserver(enabled: false);

    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: Object(),
    );

    expect(observer.snapshot.liveControllerCount, 0);
    expect(observer.snapshot.events, isEmpty);
  });

  test(
      'disposal is idempotent and stale disposal does not remove a new live controller',
      () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final oldController = Object();
    final newController = Object();

    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: oldController,
    );
    observer.observeController(
      type: SocialVideoLifecycleType.disposed,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: oldController,
    );
    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: newController,
    );
    observer.observeController(
      type: SocialVideoLifecycleType.disposed,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: oldController,
    );

    expect(observer.snapshot.liveControllerCount, 1);
    expect(
        observer.snapshot.events
            .where((event) => event.type == SocialVideoLifecycleType.disposed),
        hasLength(2));
  });

  test('same controller attached across surfaces is not a collision', () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final controller = Object();

    for (final surface in [
      SocialVideoSurface.mainFeed,
      SocialVideoSurface.postDetail
    ]) {
      observer.observeController(
        type: SocialVideoLifecycleType.attached,
        postId: 'post-a',
        surface: surface,
        ownerId: surface.name,
        controllerIdentity: controller,
      );
    }

    expect(observer.snapshot.liveControllerCount, 1);
    expect(observer.snapshot.collisions, isEmpty);
  });

  test('rejects a blank post id without recording it', () {
    final observer = SocialVideoSessionObserver(enabled: true);

    expect(
      () => observer.observeController(
        type: SocialVideoLifecycleType.created,
        postId: '  ',
        surface: SocialVideoSurface.mainFeed,
        ownerId: 'feed',
        controllerIdentity: Object(),
      ),
      throwsArgumentError,
    );
    expect(observer.snapshot.events, isEmpty);
  });

  test(
      'returns immutable snapshots that do not change after later observations',
      () {
    final observer = SocialVideoSessionObserver(enabled: true);
    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: Object(),
    );
    final snapshot = observer.snapshot;

    expect(() => snapshot.events.clear(), throwsUnsupportedError);
    expect(() => snapshot.collisions.clear(), throwsUnsupportedError);

    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-b',
      surface: SocialVideoSurface.profileGrid,
      ownerId: 'profile',
      controllerIdentity: Object(),
    );

    expect(snapshot.events, hasLength(1));
    expect(observer.snapshot.events, hasLength(2));
  });

  test('keeps only the newest 256 events', () {
    final observer = SocialVideoSessionObserver(enabled: true);

    for (var index = 0; index < 300; index++) {
      observer.observeController(
        type: SocialVideoLifecycleType.created,
        postId: 'post-$index',
        surface: SocialVideoSurface.mainFeed,
        ownerId: 'feed',
        controllerIdentity: Object(),
      );
    }

    expect(observer.snapshot.events, hasLength(256));
    expect(observer.snapshot.events.first.postId, 'post-44');
    expect(observer.snapshot.events.last.postId, 'post-299');
  });

  test('coalesces repeated identical collision sets and invokes callback once',
      () {
    final collisions = <SocialVideoCollision>[];
    final observer = SocialVideoSessionObserver(
      enabled: true,
      onCollision: collisions.add,
    );
    final first = Object();
    final second = Object();

    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: first,
    );
    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.postDetail,
      ownerId: 'detail',
      controllerIdentity: second,
    );
    observer.observeController(
      type: SocialVideoLifecycleType.attached,
      postId: 'post-a',
      surface: SocialVideoSurface.postDetail,
      ownerId: 'detail',
      controllerIdentity: second,
    );

    expect(observer.snapshot.collisions, hasLength(1));
    expect(collisions, hasLength(1));
  });

  test('does not expose controller identities in observations or collisions',
      () {
    final controller = Object();
    final observer = SocialVideoSessionObserver(enabled: true);
    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: controller,
    );

    expect(observer.snapshot.events.single.toString(),
        isNot(contains(controller.toString())));
    expect(observer.snapshot.collisions.toString(),
        isNot(contains(controller.toString())));
  });
}
