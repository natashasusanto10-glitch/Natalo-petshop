import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/frame_output_heartbeat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<dynamic> channel;
  late int listenCount;
  late int cancelCount;
  late FrameOutputHeartbeatService service;

  setUp(() {
    listenCount = 0;
    cancelCount = 0;
    channel = StreamController<dynamic>.broadcast(
      onListen: () => listenCount++,
      onCancel: () => cancelCount++,
      sync: true,
    );
    service = FrameOutputHeartbeatService(
      streamFactory: () => channel.stream,
      now: () => DateTime.utc(2026, 7, 14, 4, 5, 6),
    );
  });

  tearDown(() async {
    await channel.close();
  });

  test('routes valid frame-output heartbeats only to the registered ID', () {
    final first = service.register(11);
    final second = service.register(22);
    final firstEvents = <FrameOutputHeartbeat>[];
    final secondEvents = <FrameOutputHeartbeat>[];
    first.heartbeats.listen(firstEvents.add);
    second.heartbeats.listen(secondEvents.add);

    channel.add(_payload(playerId: 22, textureId: null, frameCount: 7));

    expect(firstEvents, isEmpty);
    expect(secondEvents, hasLength(1));
    expect(secondEvents.single.playerId, 22);
    expect(secondEvents.single.textureId, isNull);
    expect(secondEvents.single.frameCount, 7);
    expect(secondEvents.single.mediaTimeUs, 123000);
    expect(secondEvents.single.monotonicTimeUs, 456000);
    expect(secondEvents.single.platform, 'ios');
    expect(secondEvents.single.receivedAt, DateTime.utc(2026, 7, 14, 4, 5, 6));
    expect(second.latest, same(secondEvents.single));
    expect(service.latestFor(22), same(secondEvents.single));

    first.unregister();
    second.unregister();
  });

  test('rejects malformed payloads and unknown player IDs', () {
    final registration = service.register(1);
    final events = <FrameOutputHeartbeat>[];
    registration.heartbeats.listen(events.add);

    channel
      ..add(null)
      ..add(<String, Object?>{'playerId': 1})
      ..add(_payload(playerId: 1)..['frameCount'] = 1.5)
      ..add(_payload(playerId: 1)..['textureId'] = '4')
      ..add(_payload(playerId: 1)..['platform'] = '')
      ..add(_payload(playerId: 1)..['monotonicTimeUs'] = -1)
      ..add(_payload(playerId: 99));

    expect(events, isEmpty);
    expect(registration.latest, isNull);
    registration.unregister();
  });

  test('rejects duplicate and decreasing frame counts', () {
    final registration = service.register(3);
    final counts = <int>[];
    registration.heartbeats.listen((event) => counts.add(event.frameCount));

    channel
      ..add(_payload(playerId: 3, frameCount: 10))
      ..add(_payload(playerId: 3, frameCount: 10))
      ..add(_payload(playerId: 3, frameCount: 9))
      ..add(_payload(playerId: 3, frameCount: 11));

    expect(counts, <int>[10, 11]);
    expect(registration.latest?.frameCount, 11);
    registration.unregister();
  });

  test('subscribes globally while any registration remains', () async {
    final first = service.register(1);
    final second = service.register(2);

    expect(listenCount, 1);
    first.unregister();
    await Future<void>.delayed(Duration.zero);
    expect(cancelCount, 0);

    second.unregister();
    await Future<void>.delayed(Duration.zero);
    expect(cancelCount, 1);

    final third = service.register(3);
    expect(listenCount, 2);
    third.unregister();
  });

  test('ignores events after unregister and clears the latest heartbeat', () {
    final registration = service.register(4);
    final events = <FrameOutputHeartbeat>[];
    registration.heartbeats.listen(events.add);
    channel.add(_payload(playerId: 4, frameCount: 1));
    expect(events, hasLength(1));

    registration.unregister();
    channel.add(_payload(playerId: 4, frameCount: 2));

    expect(events, hasLength(1));
    expect(registration.latest, isNull);
    expect(service.latestFor(4), isNull);
    expect(registration.isRegistered, isFalse);
  });

  test('replacement invalidates old handle without unregistering the new one',
      () {
    final oldRegistration = service.register(8);
    final replacement = service.register(8);
    final oldEvents = <FrameOutputHeartbeat>[];
    final replacementEvents = <FrameOutputHeartbeat>[];
    oldRegistration.heartbeats.listen(oldEvents.add);
    replacement.heartbeats.listen(replacementEvents.add);

    expect(oldRegistration.isRegistered, isFalse);
    oldRegistration.unregister();
    expect(replacement.isRegistered, isTrue);

    channel.add(_payload(playerId: 8, frameCount: 1));
    expect(oldEvents, isEmpty);
    expect(replacementEvents, hasLength(1));
    replacement.unregister();
  });

  test('contains stream factory and channel errors', () {
    final errors = <Object>[];
    runZonedGuarded(() {
      final registration = service.register(1);
      channel.addError(PlatformException(code: 'unavailable'));
      registration.unregister();

      final missingPluginService = FrameOutputHeartbeatService(
        streamFactory: () => throw MissingPluginException('not installed'),
      );
      final missingRegistration = missingPluginService.register(2);
      expect(missingRegistration.isRegistered, isTrue);
      missingRegistration.unregister();
    }, (error, _) => errors.add(error));

    expect(errors, isEmpty);
  });

  test('resubscribes after stream error while a registration remains',
      () async {
    final streams = <StreamController<dynamic>>[];
    final retry = Completer<void>();
    service = FrameOutputHeartbeatService(
      streamFactory: () {
        final stream = StreamController<dynamic>.broadcast(sync: true);
        streams.add(stream);
        return stream.stream;
      },
      retryDelay: (_) => retry.future,
    );
    final registration = service.register(9);
    expect(streams, hasLength(1));

    streams.single.addError(StateError('channel failed'));
    await Future<void>.delayed(Duration.zero);
    expect(streams, hasLength(1));
    retry.complete();
    await Future<void>.delayed(Duration.zero);
    expect(streams, hasLength(2));

    streams.last.add(_payload(playerId: 9, frameCount: 3));
    expect(registration.latest?.frameCount, 3);
    registration.unregister();
    for (final stream in streams) {
      await stream.close();
    }
  });

  test('resubscribes after stream done while a registration remains', () async {
    final streams = <StreamController<dynamic>>[];
    service = FrameOutputHeartbeatService(
      streamFactory: () {
        final stream = StreamController<dynamic>.broadcast(sync: true);
        streams.add(stream);
        return stream.stream;
      },
      retryDelay: (_) async {},
    );
    final registration = service.register(10);
    await streams.single.close();
    await Future<void>.delayed(Duration.zero);

    expect(streams, hasLength(2));
    streams.last.add(_payload(playerId: 10, frameCount: 4));
    expect(registration.latest?.frameCount, 4);
    registration.unregister();
    await streams.last.close();
  });

  test('cancels a pending retry after the last unregister', () async {
    final streams = <StreamController<dynamic>>[];
    final retry = Completer<void>();
    service = FrameOutputHeartbeatService(
      streamFactory: () {
        final stream = StreamController<dynamic>.broadcast(sync: true);
        streams.add(stream);
        return stream.stream;
      },
      retryDelay: (_) => retry.future,
    );
    final registration = service.register(12);
    streams.single.addError(StateError('channel failed'));
    await Future<void>.delayed(Duration.zero);

    registration.unregister();
    retry.complete();
    await Future<void>.delayed(Duration.zero);
    expect(streams, hasLength(1));
    await streams.single.close();
  });

  test('continues retrying after backoff reaches its capped delay', () async {
    final streams = <StreamController<dynamic>>[];
    final delays = <Duration>[];
    final retryGates = <Completer<void>>[];
    service = FrameOutputHeartbeatService(
      streamFactory: () {
        final stream = StreamController<dynamic>.broadcast(sync: true);
        streams.add(stream);
        return stream.stream;
      },
      retryDelay: (delay) {
        delays.add(delay);
        final gate = Completer<void>();
        retryGates.add(gate);
        return gate.future;
      },
    );
    final registration = service.register(13);

    for (var failure = 0; failure < 7; failure++) {
      streams.last.addError(StateError('failure $failure'));
      await Future<void>.delayed(Duration.zero);
      expect(retryGates, hasLength(failure + 1));
      retryGates.last.complete();
      await Future<void>.delayed(Duration.zero);
      expect(streams, hasLength(failure + 2));
    }

    expect(
      delays,
      const <Duration>[
        Duration(milliseconds: 100),
        Duration(milliseconds: 200),
        Duration(milliseconds: 400),
        Duration(milliseconds: 800),
        Duration(milliseconds: 1600),
        Duration(milliseconds: 1600),
        Duration(milliseconds: 1600),
      ],
    );
    streams.last.add(_payload(playerId: 13, frameCount: 8));
    expect(registration.latest?.frameCount, 8);
    registration.unregister();
    for (final stream in streams) {
      await stream.close();
    }
  });
}

Map<String, Object?> _payload({
  required int playerId,
  int? textureId = 12,
  int frameCount = 1,
}) =>
    <String, Object?>{
      'playerId': playerId,
      'textureId': textureId,
      'frameCount': frameCount,
      'mediaTimeUs': 123000,
      'monotonicTimeUs': 456000,
      'platform': 'ios',
    };
