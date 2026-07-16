import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_observation_metrics.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_registry_config.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_session_observer.dart';

void main() {
  test('application singleton follows startup observation flag', () {
    socialVideoSessionObserver.clear();
    socialVideoSessionObserver.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'startup-post',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: Object(),
    );

    expect(
      socialVideoSessionObserver.snapshot.liveControllerCount,
      socialVideoRegistryObservationEnabled ? 1 : 0,
    );
    socialVideoSessionObserver.clear();
  });

  test('startup observer disabled mode retains no lifecycle state', () {
    final observer = createSocialVideoSessionObserver(enabled: false);

    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'private-post',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: Object(),
    );

    expect(observer.snapshot.liveControllerCount, 0);
    expect(observer.snapshot.events, isEmpty);
  });

  test('startup observer enabled mode observes and reports anonymous collision',
      () async {
    final telemetry = <Map<String, Object>>[];
    final sink = SocialVideoCollisionMetricSink(
      writeEvent: (name, parameters) async {
        telemetry.add(<String, Object>{'name': name, ...parameters});
      },
    );
    final observer = createSocialVideoSessionObserver(
      enabled: true,
      collisionSink: sink,
    );

    for (final identity in <Object>[Object(), Object()]) {
      observer.observeController(
        type: SocialVideoLifecycleType.created,
        postId: 'private-post',
        surface: SocialVideoSurface.mainFeed,
        ownerId: 'feed',
        controllerIdentity: identity,
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(observer.snapshot.liveControllerCount, 2);
    expect(observer.snapshot.collisions, hasLength(1));
    expect(telemetry, hasLength(1));
    expect(telemetry.single['media_key'], isNot('private-post'));
    expect(telemetry.single.keys, isNot(contains('post_id')));
    expect(telemetry.single.keys, isNot(contains('url')));
  });

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

    expect(observer.snapshot.collisions.single.mediaKey, isNot('post-a'));
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
    expect(observer.snapshot.events.first.mediaKey, _mediaKeyFor('post-44'));
    expect(observer.snapshot.events.last.mediaKey, _mediaKeyFor('post-299'));
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

  test('diagnostics expose only anonymous media keys and surface', () {
    final controller = Object();
    final observer = SocialVideoSessionObserver(enabled: true);
    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed',
      controllerIdentity: controller,
    );

    final event = observer.snapshot.events.single;
    expect(event.mediaKey, _mediaKeyFor('post-a'));
    expect(event.mediaKey, isNot('post-a'));
    expect(event.surface, SocialVideoSurface.mainFeed);
    expect(event.toString(), isNot(contains('post-a')));
    expect(event.toString(), isNot(contains('feed')));
    expect(event.toString(), isNot(contains(controller.toString())));
  });

  test('same post id produces the same anonymous media key', () {
    final first = SocialVideoSessionObserver(enabled: true);
    final second = SocialVideoSessionObserver(enabled: true);

    first.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed-a',
      controllerIdentity: Object(),
    );
    second.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.postDetail,
      ownerId: 'detail-a',
      controllerIdentity: Object(),
    );

    expect(first.snapshot.events.single.mediaKey,
        second.snapshot.events.single.mediaKey);
  });

  test('evicts the oldest live controller at the hard registry bound', () {
    final observer = SocialVideoSessionObserver(enabled: true);
    final firstController = Object();

    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-first',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed-first',
      controllerIdentity: firstController,
    );
    for (var index = 1;
        index < SocialVideoSessionObserver.maxLiveControllerCount;
        index++) {
      observer.observeController(
        type: SocialVideoLifecycleType.created,
        postId: 'post-$index',
        surface: SocialVideoSurface.mainFeed,
        ownerId: 'feed-$index',
        controllerIdentity: Object(),
      );
    }

    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-overflow',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed-overflow',
      controllerIdentity: Object(),
    );

    expect(observer.snapshot.liveControllerCount,
        SocialVideoSessionObserver.maxLiveControllerCount);
    observer.observeController(
      type: SocialVideoLifecycleType.disposed,
      postId: 'post-first',
      surface: SocialVideoSurface.mainFeed,
      ownerId: 'feed-first',
      controllerIdentity: firstController,
    );
    expect(observer.snapshot.liveControllerCount,
        SocialVideoSessionObserver.maxLiveControllerCount);
  });

  test('collision callback re-fires when the active controller set changes',
      () {
    final collisions = <SocialVideoCollision>[];
    final observer = SocialVideoSessionObserver(
      enabled: true,
      onCollision: collisions.add,
    );
    final first = Object();
    final second = Object();
    final third = Object();

    for (final controller in [first, second]) {
      observer.observeController(
        type: SocialVideoLifecycleType.created,
        postId: 'post-a',
        surface: SocialVideoSurface.mainFeed,
        ownerId: 'feed',
        controllerIdentity: controller,
      );
    }
    observer.observeController(
      type: SocialVideoLifecycleType.created,
      postId: 'post-a',
      surface: SocialVideoSurface.postDetail,
      ownerId: 'detail',
      controllerIdentity: third,
    );

    expect(collisions, hasLength(2));
    expect(collisions.last.controllerCount, 3);
  });

  test('callback exceptions do not interrupt observation or lifecycle state',
      () {
    final observer = SocialVideoSessionObserver(
      enabled: true,
      onCollision: (_) => throw StateError('diagnostic failure'),
    );

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

    expect(observer.snapshot.liveControllerCount, 2);
    expect(observer.snapshot.collisions.single.controllerCount, 2);
  });
}

String _mediaKeyFor(String postId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in postId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
