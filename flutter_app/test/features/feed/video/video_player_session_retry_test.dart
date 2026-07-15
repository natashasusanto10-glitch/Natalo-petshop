import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/frame_output_heartbeat_service.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';
import 'package:natalo_petshop_flutter/services/video_quality_service.dart';
import 'package:video_player/video_player.dart';

/// T4 — orkestrasi retry/refresh [VideoPlayerSession] diuji via seam
/// `debugInitAttempt` (tanpa plugin video_player). Controller nyata null di
/// jalur test; kita hanya memverifikasi budget retry, klasifikasi permanen,
/// refresh signed URL (D4), dan reset budget lewat `retry()`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Delay backoff jadi no-op supaya test cepat & deterministik.
  Future<void> noDelay(Duration _) async {}

  test('buffer ahead merges adjacent ranges', () {
    final ahead = VideoPlayerSession.contiguousBufferAhead(
      position: const Duration(seconds: 1),
      buffered: [
        DurationRange(Duration.zero, const Duration(seconds: 2)),
        DurationRange(
          const Duration(seconds: 2),
          const Duration(seconds: 5),
        ),
      ],
    );

    expect(ahead, const Duration(seconds: 4));
  });

  test('buffer ahead stops at the first gap after playback position', () {
    final ahead = VideoPlayerSession.contiguousBufferAhead(
      position: const Duration(seconds: 1),
      buffered: [
        DurationRange(Duration.zero, const Duration(seconds: 2)),
        DurationRange(
          const Duration(seconds: 3),
          const Duration(seconds: 8),
        ),
      ],
    );

    expect(ahead, const Duration(seconds: 1));
  });

  test('metrics include network, quality, and startup context', () async {
    final metrics = <String, Map<String, Object>>{};
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'data_saver',
      debugNetworkTier: NetworkTier.cellularSlow,
      debugMetricSink: (event, parameters) => metrics[event] = parameters,
      debugInitAttempt: (_) async {},
    );

    await pumpEventQueue();

    expect(metrics['video_init_started'],
        containsPair('network_tier', 'cellularSlow'));
    expect(metrics['video_init_started'],
        containsPair('quality_preference', 'data_saver'));
    expect(metrics['video_init_ready'], contains('duration_ms'));
    expect(metrics['video_init_ready'], containsPair('buffer_ahead_ms', 0));
    await session.dispose();
  });

  test('gagal sekali lalu sukses → retry TEPAT 1× lalu ready', () async {
    var attempts = 0;
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      debugInitAttempt: (url) async {
        attempts++;
        if (attempts == 1) {
          throw Exception('network timeout');
        }
        // sukses percobaan ke-2.
      },
    );

    await pumpEventQueue();

    expect(attempts, 2, reason: 'satu percobaan awal + satu retry');
    expect(session.isInitialized, isTrue);
    expect(session.hasError, isFalse);
  });

  test('gagal terus → error final, budget retry TIDAK terlampaui (2 attempt)',
      () async {
    var attempts = 0;
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      debugInitAttempt: (url) async {
        attempts++;
        throw Exception('network unreachable');
      },
    );

    await pumpEventQueue();

    expect(attempts, 2, reason: 'awal + tepat 1 retry, tidak lebih');
    expect(session.isInitialized, isFalse);
    expect(session.hasError, isTrue);
  });

  test('error permanen (format) → TIDAK di-retry (1 attempt saja)', () async {
    var attempts = 0;
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      debugInitAttempt: (url) async {
        attempts++;
        throw Exception('unsupported format');
      },
    );

    await pumpEventQueue();

    expect(attempts, 1, reason: 'error permanen tak boleh memicu retry');
    expect(session.hasError, isTrue);
  });

  test('D4 — signed URL expired: refresh sekali, retry pakai URL segar',
      () async {
    var attempts = 0;
    var refreshCalls = 0;
    final seenUrls = <String>[];
    const signed = 'https://cdn/play_720p.mp4?token=abc&expires=123';
    const fresh = 'https://cdn/play_720p.mp4?token=NEW&expires=999';

    final session = VideoPlayerSession(
      url: signed,
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      urlRefresher: () async {
        refreshCalls++;
        return fresh;
      },
      debugInitAttempt: (url) async {
        attempts++;
        seenUrls.add(url);
        if (attempts == 1) {
          throw Exception('403 forbidden'); // expired signature
        }
        // sukses dengan URL segar.
      },
    );

    await pumpEventQueue();

    expect(attempts, 2);
    expect(refreshCalls, 1, reason: 'refresh best-effort tepat sekali');
    expect(seenUrls.first, signed);
    expect(seenUrls.last, fresh,
        reason: 'retry memakai URL bertanda-tangan segar');
    expect(session.isInitialized, isTrue);
    expect(session.hasError, isFalse);
  });

  test('D4 — URL tak bertanda-tangan: refresher TIDAK dipanggil', () async {
    var refreshCalls = 0;
    var attempts = 0;
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      urlRefresher: () async {
        refreshCalls++;
        return 'https://other';
      },
      debugInitAttempt: (url) async {
        attempts++;
        throw Exception('network');
      },
    );

    await pumpEventQueue();

    expect(refreshCalls, 0, reason: 'refresh hanya untuk URL signed');
    expect(attempts, 2);
    expect(session.hasError, isTrue);
  });

  test('retry() manual mereset budget → percobaan baru setelah error final',
      () async {
    var attempts = 0;
    var failUntilRetry = true;
    final session = VideoPlayerSession(
      url: 'https://cdn/play_720p.mp4',
      userQualityPreference: 'auto',
      debugDelay: noDelay,
      debugInitAttempt: (url) async {
        attempts++;
        if (failUntilRetry) throw Exception('network');
      },
    );

    await pumpEventQueue();
    expect(attempts, 2);
    expect(session.hasError, isTrue);

    // Manual "Coba lagi": izinkan sukses, budget di-reset.
    failUntilRetry = false;
    await session.retry();
    await pumpEventQueue();

    expect(attempts, 3, reason: 'retry manual = satu percobaan baru');
    expect(session.isInitialized, isTrue);
    expect(session.hasError, isFalse);
  });

  group('managed frame-output recovery', () {
    late StreamController<dynamic> heartbeats;
    late FrameOutputHeartbeatService heartbeatService;
    late _FakeManagedPlayer player;

    setUp(() {
      heartbeats = StreamController<dynamic>.broadcast(sync: true);
      heartbeatService = FrameOutputHeartbeatService(
        streamFactory: () => heartbeats.stream,
      );
      player = _FakeManagedPlayer();
    });

    tearDown(() async {
      await heartbeats.close();
    });

    VideoPlayerSession createSession({
      Future<void>? recreateGate,
      void Function(String, Map<String, Object>)? metricSink,
      bool hasAudio = true,
    }) {
      return VideoPlayerSession(
        url: 'https://cdn/video.mp4',
        hasAudio: hasAudio,
        debugMetricSink: metricSink,
        debugHeartbeatService: heartbeatService,
        debugInitAttempt: (_) async {
          if (player.initCount == 1 && recreateGate != null) {
            await recreateGate;
          }
          player.initializeNext();
        },
        debugPlayerId: () => player.playerId,
        debugPosition: () => player.position,
        debugPlay: player.play,
        debugPause: player.pause,
        debugSeek: player.seek,
        debugSetVolume: player.setVolume,
        debugDisposePlayer: player.dispose,
      );
    }

    test('registers after init, snapshots frames, and unregisters on dispose',
        () async {
      final session = createSession();
      await pumpEventQueue();

      heartbeats.add(_heartbeat(player.playerId, 7));
      expect(session.debugHealthSnapshot.frameOutputCount, 7);

      await session.dispose();
      expect(heartbeatService.latestFor(player.playerId), isNull);
      expect(player.log.sublist(player.log.length - 3),
          <String>['volume:0.0', 'pause', 'dispose:1']);
    });

    test('requested audio stays muted until a fresh visual frame arrives',
        () async {
      final session = createSession();
      await pumpEventQueue();
      player.log.clear();

      await session.setVolume(0.75);
      await session.play();

      expect(session.isAwaitingVisualOutput, isTrue);
      expect(session.hasVisualOutput, isFalse);
      expect(player.log, ['volume:0.0', 'volume:0.0', 'play']);
      expect(player.log, isNot(contains('volume:0.75')));

      heartbeats.add(_heartbeat(player.playerId, 1));
      await pumpEventQueue();

      expect(session.isAwaitingVisualOutput, isFalse);
      expect(session.hasVisualOutput, isTrue);
      expect(player.log.last, 'volume:0.75');

      player.log.clear();
      await session.pause();
      expect(player.log, ['volume:0.0', 'pause']);

      player.log.clear();
      await session.play();
      expect(player.log, ['volume:0.0', 'play']);
      expect(session.isAwaitingVisualOutput, isTrue);

      heartbeats.add(_heartbeat(player.playerId, 2));
      await pumpEventQueue();
      expect(player.log.last, 'volume:0.75');
      await session.dispose();
    });

    test('media marked without audio never opens the volume gate', () async {
      final session = createSession(hasAudio: false);
      await pumpEventQueue();
      player.log.clear();

      await session.setVolume(1);
      await session.play();
      heartbeats.add(_heartbeat(player.playerId, 1));
      await pumpEventQueue();

      expect(player.log, isNot(contains('volume:1.0')));
      expect(player.log.where((entry) => entry.startsWith('volume:')).toSet(),
          {'volume:0.0'});
      await session.dispose();
    });

    test('heartbeat before play command cannot open the audio gate', () async {
      final session = createSession();
      await pumpEventQueue();
      await session.setVolume(0.9);
      player.log.clear();
      player.volumeGate = Completer<void>();

      final play = session.play();
      await pumpEventQueue();
      heartbeats.add(_heartbeat(player.playerId, 1));
      await pumpEventQueue();

      expect(session.hasVisualOutput, isTrue);
      expect(session.isAwaitingVisualOutput, isTrue);
      expect(player.log, isNot(contains('volume:0.9')));

      player.volumeGate!.complete();
      await play;
      expect(player.log, containsAllInOrder(['volume:0.0', 'play']));
      expect(player.log, isNot(contains('volume:0.9')));

      heartbeats.add(_heartbeat(player.playerId, 2));
      await pumpEventQueue();
      expect(session.isAwaitingVisualOutput, isFalse);
      expect(player.log.last, 'volume:0.9');
      await session.dispose();
    });

    test('missing heartbeat recovers while keeping actual volume closed',
        () async {
      final metrics = <String>[];
      final session = createSession(
        metricSink: (event, _) => metrics.add(event),
      );
      await pumpEventQueue();
      await session.setVolume(1);
      await session.play();
      player.log.clear();

      var sampleIndex = 0;
      for (final position in [
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 1500),
      ]) {
        player.position = position;
        final snapshot = session.debugHealthSnapshot;
        expect(snapshot.shouldMonitor, isTrue);
        expect(snapshot.position, position);
        expect(snapshot.frameOutputCount, isNull);
        await session.debugSampleHealth();
        if (sampleIndex < 2) {
          expect(
            session.debugFrameOutputStaleSamples,
            sampleIndex == 0 ? 0 : sampleIndex,
          );
        }
        sampleIndex++;
      }

      expect(metrics, contains('video_frame_output_stall_detected'));
      expect(
        player.log,
        containsAllInOrder([
          'volume:0.0',
          'pause',
          'seek:1500',
          'volume:0.0',
          'play',
        ]),
      );
      expect(player.log, isNot(contains('volume:1.0')));
      expect(session.isRecoveringVisualOutput, isTrue);
      await session.dispose();
    });

    test('attempt 1 pause-seeks-plays and preserves desired volume', () async {
      final session = createSession();
      await pumpEventQueue();
      await session.setVolume(0.35);
      await session.play();
      player.log.clear();

      await session.debugRecoverFrameOutput(const Duration(seconds: 4), 1);

      expect(
        player.log,
        ['volume:0.0', 'pause', 'seek:4000', 'volume:0.0', 'play'],
      );
      expect(player.log, isNot(contains('volume:0.35')));
      heartbeats.add(_heartbeat(player.playerId, 1));
      await pumpEventQueue();
      expect(player.log.last, 'volume:0.35');
      expect(session.debugHealthSnapshot.playbackDiscontinuitySequence, 1);
      await session.dispose();
    });

    test('attempt 1 cannot overwrite a user seek while pause is pending',
        () async {
      final session = createSession();
      await pumpEventQueue();
      await session.play();
      player.log.clear();
      player.pauseGate = Completer<void>();

      final recovery = session.debugRecoverFrameOutput(
        const Duration(seconds: 4),
        1,
      );
      await pumpEventQueue();
      await session.seekTo(const Duration(seconds: 8));
      player.pauseGate!.complete();
      await recovery;

      expect(player.log, isNot(contains('seek:4000')));
      expect(
        player.log,
        containsAllInOrder(
          ['volume:0.0', 'pause', 'seek:8000', 'volume:0.0', 'play'],
        ),
      );
      expect(session.position, const Duration(seconds: 8));
      await session.dispose();
    });

    test('attempt 2 disposes old owner before recreate and preserves state',
        () async {
      final session = createSession();
      await pumpEventQueue();
      await session.setVolume(0.6);
      await session.play();
      player.log.clear();

      await session.debugRecoverFrameOutput(const Duration(seconds: 9), 2);

      expect(player.maxLivePlayers, 1);
      expect(player.log.take(3), ['volume:0.0', 'pause', 'dispose:1']);
      expect(
          player.log,
          containsAllInOrder(
            ['init:2', 'volume:0.0', 'seek:9000', 'volume:0.0', 'play'],
          ));
      expect(player.log, isNot(contains('volume:0.6')));
      expect(session.isInitialized, isTrue);
      expect(session.debugHealthSnapshot.playbackDiscontinuitySequence, 1);
      expect(heartbeatService.latestFor(1), isNull);
      heartbeats.add(_heartbeat(2, 11));
      await pumpEventQueue();
      expect(session.debugHealthSnapshot.frameOutputCount, 11);
      expect(player.log.last, 'volume:0.6');
      await session.dispose();
    });

    test('attempt 2 abort restores desired state changed during quiesce',
        () async {
      final session = createSession();
      await pumpEventQueue();
      await session.setVolume(0.6);
      await session.play();
      player.log.clear();
      player.volumeGate = Completer<void>();

      final recovery = session.debugRecoverFrameOutput(
        const Duration(seconds: 9),
        2,
      );
      await pumpEventQueue();
      await session.seekTo(const Duration(seconds: 7));
      unawaited(session.setVolume(0.25));
      await session.pause();
      player.volumeGate!.complete();
      await recovery;

      expect(player.livePlayers, 1);
      expect(player.initCount, 1);
      expect(player.position, const Duration(seconds: 7));
      expect(
        player.log,
        containsAllInOrder([
          'volume:0.0',
          'pause',
          'volume:0.0',
          'seek:7000',
          'pause',
        ]),
      );
      expect(player.log, isNot(contains('volume:0.25')),
          reason: 'paused session must retain desired volume without output');
      await session.dispose();
    });

    test('dispose during recreate leaves no owner and does not resume',
        () async {
      final gate = Completer<void>();
      final session = createSession(recreateGate: gate.future);
      await pumpEventQueue();
      await session.play();

      final recovery = session.debugRecoverFrameOutput(
        const Duration(seconds: 2),
        2,
      );
      await pumpEventQueue();
      final disposing = session.dispose();
      gate.complete();
      await Future.wait([recovery, disposing]);

      expect(player.livePlayers, 0);
      expect(player.maxLivePlayers, 1);
      expect(player.log.where((event) => event == 'play').length, 1);
    });

    test('does not recover while paused or after dispose', () async {
      final session = createSession();
      await pumpEventQueue();
      player.log.clear();

      await session.debugRecoverFrameOutput(Duration.zero, 1);
      expect(player.log, isEmpty);
      await session.dispose();
      player.log.clear();
      await session.debugRecoverFrameOutput(Duration.zero, 2);
      expect(player.log, isEmpty);
    });

    test('visual failure is silent and manual retry reopens only after frame',
        () async {
      final session = createSession();
      await pumpEventQueue();
      await session.setVolume(0.8);
      await session.play();
      heartbeats.add(_heartbeat(1, 1));
      await pumpEventQueue();
      expect(player.log.last, 'volume:0.8');

      player.log.clear();
      await session.debugMarkVisualOutputFailed(const Duration(seconds: 3));
      expect(session.hasError, isTrue);
      expect(player.log, ['volume:0.0', 'pause']);

      player.log.clear();
      await session.retry();
      expect(player.initCount, 2);
      expect(player.log, isNot(contains('volume:0.8')));
      expect(session.isAwaitingVisualOutput, isTrue);

      heartbeats.add(_heartbeat(2, 1));
      await pumpEventQueue();
      expect(session.hasError, isFalse);
      expect(player.log.last, 'volume:0.8');
      await session.dispose();
    });
  });
}

Map<String, Object> _heartbeat(int playerId, int frameCount) => {
      'playerId': playerId,
      'textureId': playerId + 100,
      'frameCount': frameCount,
      'mediaTimeUs': 1000,
      'monotonicTimeUs': 2000,
      'platform': 'test',
    };

class _FakeManagedPlayer {
  int initCount = 0;
  int playerId = -1;
  int livePlayers = 0;
  int maxLivePlayers = 0;
  Duration position = Duration.zero;
  final List<String> log = [];
  Completer<void>? pauseGate;
  Completer<void>? volumeGate;

  void initializeNext() {
    initCount++;
    playerId = initCount;
    livePlayers++;
    if (livePlayers > maxLivePlayers) maxLivePlayers = livePlayers;
    log.add('init:$playerId');
  }

  Future<void> play() async => log.add('play');
  Future<void> pause() async {
    log.add('pause');
    await pauseGate?.future;
  }

  Future<void> seek(Duration value) async {
    position = value;
    log.add('seek:${value.inMilliseconds}');
  }

  Future<void> setVolume(double value) async {
    await volumeGate?.future;
    log.add('volume:$value');
  }

  Future<void> dispose() async {
    if (livePlayers == 0) return;
    log.add('dispose:$playerId');
    livePlayers--;
  }
}
