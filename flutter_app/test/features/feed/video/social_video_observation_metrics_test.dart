import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_observation_metrics.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_registry_config.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_session_observer.dart';

SocialVideoCollision collisionFixture({
  String postId = 'private-post',
  int controllerCount = 2,
}) =>
    SocialVideoCollision(
      mediaKey: anonymousSocialPostKey(postId),
      controllerCount: controllerCount,
    );

void main() {
  test('observation is disabled by default', () {
    expect(socialVideoRegistryObservationEnabled, isFalse);
  });

  test('post keys are stable and do not expose source text', () {
    final first = anonymousSocialPostKey('post-secret-123');
    final second = anonymousSocialPostKey('post-secret-123');

    expect(first, second);
    expect(first, isNot(contains('post-secret-123')));
  });

  test('collision metric contains no URL or raw post id', () async {
    final events = <Map<String, Object>>[];
    final sink = SocialVideoCollisionMetricSink(
      writeEvent: (name, params) async => events.add({'name': name, ...params}),
    );

    await sink.record(collisionFixture());

    expect(events.single['name'], 'social_video_controller_collision');
    expect(events.single['media_key'], isNot('private-post'));
    expect(events.single.keys, isNot(contains('url')));
    expect(events.single.keys, isNot(contains('post_id')));
  });

  test('collision metric includes controller count and serialized surfaces',
      () async {
    final events = <Map<String, Object>>[];
    final sink = SocialVideoCollisionMetricSink(
      writeEvent: (name, params) async => events.add({'name': name, ...params}),
    );

    await sink.record(
      collisionFixture(controllerCount: 3),
      surfaces: const {
        SocialVideoSurface.postDetail,
        SocialVideoSurface.mainFeed,
      },
    );

    expect(events.single['controller_count'], 3);
    expect(events.single['surface_names'], 'main_feed|post_detail');
    expect(
      events.single.values.every((value) => value is String || value is num),
      isTrue,
    );
  });

  test('repeated identical collision summaries are coalesced', () async {
    final events = <Map<String, Object>>[];
    final sink = SocialVideoCollisionMetricSink(
      writeEvent: (name, params) async => events.add({'name': name, ...params}),
    );
    final collision = collisionFixture();

    await sink.record(collision, surfaces: const {SocialVideoSurface.mainFeed});
    await sink.record(collision, surfaces: const {SocialVideoSurface.mainFeed});
    await sink.record(collisionFixture(controllerCount: 3),
        surfaces: const {SocialVideoSurface.mainFeed});
    await sink.record(collision, surfaces: const {SocialVideoSurface.mainFeed});

    expect(events, hasLength(3));
    expect(events[1]['controller_count'], 3);
    expect(events[2]['controller_count'], 2);
  });

  test('writer failure does not sample collision and allows retry', () async {
    var attempts = 0;
    final events = <Map<String, Object>>[];
    final sink = SocialVideoCollisionMetricSink(
      writeEvent: (name, params) async {
        attempts++;
        if (attempts == 1) throw StateError('writer unavailable');
        events.add({'name': name, ...params});
      },
    );

    await sink.record(collisionFixture());
    await sink.record(collisionFixture());

    expect(attempts, 2);
    expect(events, hasLength(1));
  });

  test('unsafe media keys are rejected without telemetry', () async {
    final events = <Map<String, Object>>[];
    final sink = SocialVideoCollisionMetricSink(
      writeEvent: (name, params) async => events.add({'name': name, ...params}),
    );

    await sink.record(const SocialVideoCollision(
      mediaKey: 'https://example.com/video?token=secret',
      controllerCount: 2,
    ));
    await sink.record(const SocialVideoCollision(
      mediaKey: '',
      controllerCount: 2,
    ));
    await sink.record(const SocialVideoCollision(
      mediaKey: 'ABCDEF12',
      controllerCount: 2,
    ));

    expect(events, isEmpty);
  });

  test('rejects hex-like raw ids longer than eight characters', () async {
    final events = <Map<String, Object>>[];
    final sink = SocialVideoCollisionMetricSink(
      writeEvent: (name, params) async => events.add({'name': name, ...params}),
    );

    await sink.record(const SocialVideoCollision(
      mediaKey: 'deadbeefcafebabe',
      controllerCount: 2,
    ));
    await sink.record(const SocialVideoCollision(
      mediaKey: 'deadbeef',
      controllerCount: 2,
    ));

    expect(events, hasLength(1));
    expect(events.single['media_key'], 'deadbeef');
  });
}
