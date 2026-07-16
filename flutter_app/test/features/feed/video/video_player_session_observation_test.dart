import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/social_video_session_observer.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';

const _context = SocialVideoObservationContext(
  postId: 'post-a',
  surface: SocialVideoSurface.postDetail,
  ownerId: 'coordinator-post-a',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('successful initialization records created then initialized', () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    final session = VideoPlayerSession(
      url: 'https://example.com/video.mp4',
      observationObserver: observer,
      observationContext: _context,
      debugInitAttempt: (_) async {},
    );

    await _settle();

    expect(session.isInitialized, isTrue);
    expect(
      observer.snapshot.events.map((event) => event.type),
      equals(<SocialVideoLifecycleType>[
        SocialVideoLifecycleType.created,
        SocialVideoLifecycleType.initialized,
      ]),
    );

    await session.dispose();
  });

  test('terminal initialization failure records failed', () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    final session = VideoPlayerSession(
      url: 'https://example.com/video.mp4',
      observationObserver: observer,
      observationContext: _context,
      debugInitAttempt: (_) async => throw UnsupportedError('codec'),
    );

    await _settle();

    expect(session.hasError, isTrue);
    expect(
      observer.snapshot.events.map((event) => event.type),
      equals(<SocialVideoLifecycleType>[SocialVideoLifecycleType.failed]),
    );

    await session.dispose();
  });

  test('native initialization failure retains its created identity', () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    final session = VideoPlayerSession(
      url: 'https://example.com/video.mp4',
      observationObserver: observer,
      observationContext: _context,
      debugNativeControllerIdentity: Object(),
      debugInitAttempt: (_) async => throw UnsupportedError('codec'),
    );

    await _settle();

    expect(
      observer.snapshot.events.map((event) => event.type),
      equals(<SocialVideoLifecycleType>[
        SocialVideoLifecycleType.created,
        SocialVideoLifecycleType.failed,
        SocialVideoLifecycleType.released,
      ]),
    );

    await session.dispose();
  });

  test('transient native retry releases the discarded controller identity',
      () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    var attempts = 0;
    final session = VideoPlayerSession(
      url: 'https://example.com/video.mp4',
      observationObserver: observer,
      observationContext: _context,
      debugNativeControllerIdentityFactory: Object.new,
      debugDelay: (_) async {},
      debugInitAttempt: (_) async {
        if (attempts++ == 0) throw StateError('temporary network failure');
      },
    );

    await _settle();

    expect(
      observer.snapshot.events.map((event) => event.type),
      equals(<SocialVideoLifecycleType>[
        SocialVideoLifecycleType.created,
        SocialVideoLifecycleType.released,
        SocialVideoLifecycleType.created,
        SocialVideoLifecycleType.initialized,
      ]),
    );
    expect(observer.snapshot.liveControllerCount, 1);

    await session.dispose();
  });

  test('idempotent disposal records disposed once', () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    var disposeCalls = 0;
    final session = VideoPlayerSession(
      url: 'https://example.com/video.mp4',
      observationObserver: observer,
      observationContext: _context,
      debugInitAttempt: (_) async {},
      debugDisposePlayer: () async => disposeCalls++,
    );

    await _settle();
    await session.dispose();
    await session.dispose();

    expect(disposeCalls, 1);
    expect(
      observer.snapshot.events.map((event) => event.type),
      equals(<SocialVideoLifecycleType>[
        SocialVideoLifecycleType.created,
        SocialVideoLifecycleType.initialized,
        SocialVideoLifecycleType.disposed,
      ]),
    );
  });

  test('observation does not invoke player command callbacks', () async {
    final observer = SocialVideoSessionObserver(enabled: true);
    var playCalls = 0;
    var pauseCalls = 0;
    var seekCalls = 0;
    var volumeCalls = 0;
    var retryInitCalls = 0;
    var disposeCalls = 0;
    final session = VideoPlayerSession(
      url: 'https://example.com/video.mp4',
      observationObserver: observer,
      observationContext: _context,
      debugInitAttempt: (_) async => retryInitCalls++,
      debugPlay: () async => playCalls++,
      debugPause: () async => pauseCalls++,
      debugSeek: (_) async => seekCalls++,
      debugSetVolume: (_) async => volumeCalls++,
      debugDisposePlayer: () async => disposeCalls++,
    );

    await _settle();
    final before = <int>[
      playCalls,
      pauseCalls,
      seekCalls,
      volumeCalls,
      retryInitCalls,
      disposeCalls,
    ];

    observer.snapshot;
    observer.clear();
    observer.snapshot;

    expect(
      <int>[
        playCalls,
        pauseCalls,
        seekCalls,
        volumeCalls,
        retryInitCalls,
        disposeCalls,
      ],
      equals(before),
    );

    await session.dispose();
  });
}
