import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_playback_health_monitor.dart';

void main() {
  late VideoPlaybackSnapshot snapshot;
  late List<String> events;
  late int recoveries;
  late List<Map<String, Object>> parameters;
  late DateTime now;
  late List<(Duration, int)> frameOutputRecoveries;

  VideoPlaybackHealthMonitor createMonitor({
    int maxRecoveries = 2,
    int maxFrameOutputRecoveries = 2,
    Duration frameOutputCooldown = Duration.zero,
    Future<void> Function(Duration)? onRecover,
    FrameOutputStallRecover? onFrameOutputStallRecover,
    FrameOutputRecoveryExhausted? onFrameOutputRecoveryExhausted,
  }) {
    return VideoPlaybackHealthMonitor(
      readSnapshot: () => snapshot,
      onRecover: onRecover ?? (_) async => recoveries++,
      metricContext: const {'surface': 'test'},
      metricSink: (event, payload) {
        events.add(event);
        parameters.add(payload);
      },
      now: () => now,
      stagnantSamplesBeforeRecovery: 3,
      maxRecoveries: maxRecoveries,
      recoveryCooldown: Duration.zero,
      onFrameOutputStallRecover: onFrameOutputStallRecover ??
          (position, attempt) async {
            frameOutputRecoveries.add((position, attempt));
          },
      onFrameOutputRecoveryExhausted: onFrameOutputRecoveryExhausted,
      maxFrameOutputRecoveries: maxFrameOutputRecoveries,
      frameOutputRecoveryCooldown: frameOutputCooldown,
    );
  }

  setUp(() {
    snapshot = const VideoPlaybackSnapshot(
      shouldMonitor: true,
      isBuffering: false,
      position: Duration.zero,
      duration: Duration(seconds: 30),
    );
    events = [];
    recoveries = 0;
    parameters = [];
    frameOutputRecoveries = [];
    now = DateTime(2026, 1, 1);
  });

  test('monitoring follows playback intent while native playback is stalled',
      () {
    expect(
      shouldMonitorIntendedPlayback(
        intendsPlayback: true,
        isInitialized: true,
      ),
      isTrue,
      reason: 'native isPlaying is intentionally not part of this decision',
    );
    expect(
      shouldMonitorIntendedPlayback(
        intendsPlayback: false,
        isInitialized: true,
      ),
      isFalse,
      reason: 'user/app pause must still disable monitoring',
    );
  });

  test('buffer metrics include count, duration, and buffer ahead', () async {
    final monitor = createMonitor();
    snapshot = const VideoPlaybackSnapshot(
      shouldMonitor: true,
      isBuffering: true,
      position: Duration(seconds: 2),
      duration: Duration(seconds: 30),
      bufferAhead: Duration(milliseconds: 1750),
    );
    await monitor.sample();
    now = now.add(const Duration(milliseconds: 650));
    snapshot = const VideoPlaybackSnapshot(
      shouldMonitor: true,
      isBuffering: false,
      position: Duration(seconds: 2),
      duration: Duration(seconds: 30),
      bufferAhead: Duration(milliseconds: 3100),
    );
    await monitor.sample();

    expect(parameters.first, containsPair('buffering_count', 1));
    expect(parameters.first, containsPair('buffer_ahead_ms', 1750));
    expect(parameters.last, containsPair('duration_ms', 650));
    expect(parameters.last, containsPair('buffering_duration_ms', 650));
    expect(parameters.last, containsPair('buffer_ahead_ms', 3100));
    monitor.dispose();
  });

  test('listener observation captures short buffering between timer samples',
      () {
    final monitor = createMonitor();
    snapshot = const VideoPlaybackSnapshot(
      shouldMonitor: true,
      isBuffering: true,
      position: Duration(seconds: 2),
      duration: Duration(seconds: 30),
      bufferAhead: Duration(milliseconds: 900),
    );
    monitor.observePlaybackStateTransition();
    // Repeated native player notifications must not duplicate the transition.
    monitor.observePlaybackStateTransition();

    now = now.add(const Duration(milliseconds: 120));
    snapshot = const VideoPlaybackSnapshot(
      shouldMonitor: true,
      isBuffering: false,
      position: Duration(seconds: 2),
      duration: Duration(seconds: 30),
      bufferAhead: Duration(milliseconds: 1400),
    );
    monitor.observePlaybackStateTransition();
    monitor.observePlaybackStateTransition();

    expect(events, ['video_buffer_started', 'video_buffer_ended']);
    expect(parameters.last, containsPair('duration_ms', 120));
    expect(parameters.last, containsPair('buffering_count', 1));
    expect(parameters.last, containsPair('buffer_ahead_ms', 1400));
    monitor.dispose();
  });

  test('progress normal tidak memicu recovery', () async {
    final monitor = createMonitor();
    for (var second = 0; second < 6; second++) {
      snapshot = VideoPlaybackSnapshot(
        shouldMonitor: true,
        isBuffering: false,
        position: Duration(seconds: second),
        duration: const Duration(seconds: 30),
      );
      await monitor.sample();
    }
    expect(recoveries, 0);
    expect(events, isNot(contains('video_stall_detected')));
    monitor.dispose();
  });

  test('buffering dan inactive tidak dianggap stall', () async {
    final monitor = createMonitor();
    snapshot = const VideoPlaybackSnapshot(
      shouldMonitor: true,
      isBuffering: true,
      position: Duration(seconds: 2),
      duration: Duration(seconds: 30),
    );
    for (var i = 0; i < 5; i++) {
      await monitor.sample();
    }
    snapshot = const VideoPlaybackSnapshot(
      shouldMonitor: false,
      isBuffering: false,
      position: Duration(seconds: 2),
      duration: Duration(seconds: 30),
    );
    for (var i = 0; i < 5; i++) {
      await monitor.sample();
    }
    expect(recoveries, 0);
    expect(events, containsAll(['video_buffer_started', 'video_buffer_ended']));
    monitor.dispose();
  });

  test('stagnan tiga sampel memicu recovery dengan batas keras', () async {
    final monitor = createMonitor(maxRecoveries: 2);
    for (var i = 0; i < 12; i++) {
      await monitor.sample();
    }
    expect(recoveries, 2);
    expect(events.where((e) => e == 'video_stall_detected'), hasLength(2));
    expect(events.where((e) => e == 'video_stall_recovery'), hasLength(2));
    monitor.dispose();
  });

  group('frame-output stall detector', () {
    VideoPlaybackSnapshot frameSnapshot({
      required int seconds,
      int? count = 10,
      bool shouldMonitor = true,
      bool isBuffering = false,
      int durationSeconds = 30,
      int discontinuitySequence = 0,
    }) {
      return VideoPlaybackSnapshot(
        shouldMonitor: shouldMonitor,
        isBuffering: isBuffering,
        position: Duration(seconds: seconds),
        duration: Duration(seconds: durationSeconds),
        frameOutputCount: count,
        playbackDiscontinuitySequence: discontinuitySequence,
      );
    }

    test('recovers after baseline and two stale samples while clock advances',
        () async {
      final monitor = createMonitor();
      for (var second = 0; second <= 2; second++) {
        snapshot = frameSnapshot(seconds: second);
        await monitor.sample();
      }

      expect(frameOutputRecoveries, [(const Duration(seconds: 2), 1)]);
      expect(
        events.where((event) => event == 'video_frame_output_stall_detected'),
        hasLength(1),
      );
      final recoveryIndex = events.indexOf('video_frame_output_stall_recovery');
      expect(parameters[recoveryIndex], containsPair('recovery_attempt', 1));
      expect(parameters[recoveryIndex], containsPair('position_ms', 2000));
      expect(recoveries, 0, reason: 'playback-clock recovery stays separate');
    });

    test('pause, buffering, end, and one missing signal reset the baseline',
        () async {
      final monitor = createMonitor();
      snapshot = frameSnapshot(seconds: 0);
      await monitor.sample();

      final suppressed = [
        frameSnapshot(seconds: 1, shouldMonitor: false),
        frameSnapshot(seconds: 2, isBuffering: true),
        frameSnapshot(seconds: 29, durationSeconds: 30),
        frameSnapshot(seconds: 3, count: null),
      ];
      for (final value in suppressed) {
        snapshot = value;
        await monitor.sample();
        snapshot = frameSnapshot(seconds: 4);
        await monitor.sample();
        snapshot = frameSnapshot(seconds: 5);
        await monitor.sample();
        expect(frameOutputRecoveries, isEmpty);
      }
    });

    test('missing heartbeat recovers when playback clock keeps advancing',
        () async {
      final monitor = createMonitor();
      for (var second = 0; second <= 2; second++) {
        snapshot = frameSnapshot(seconds: second, count: null);
        await monitor.sample();
      }

      expect(frameOutputRecoveries, [(const Duration(seconds: 2), 1)]);
      final detectedIndex = events.indexOf('video_frame_output_stall_detected');
      expect(
          parameters[detectedIndex], containsPair('frame_signal', 'missing'));
    });

    test('exhausted visual recovery reports once instead of looping', () async {
      final exhaustedAt = <Duration>[];
      final monitor = createMonitor(
        maxFrameOutputRecoveries: 0,
        onFrameOutputRecoveryExhausted: (position) async {
          exhaustedAt.add(position);
        },
      );

      for (var second = 0; second <= 4; second++) {
        snapshot = frameSnapshot(seconds: second, count: null);
        await monitor.sample();
      }

      expect(exhaustedAt, [const Duration(seconds: 2)]);
      expect(
        events.where(
          (event) => event == 'video_frame_output_recovery_exhausted',
        ),
        hasLength(1),
      );
    });

    test('advancing and regressing counts establish a new baseline', () async {
      final monitor = createMonitor();
      for (final value in [
        frameSnapshot(seconds: 0, count: 10),
        frameSnapshot(seconds: 1, count: 10),
        frameSnapshot(seconds: 2, count: 11),
        frameSnapshot(seconds: 3, count: 11),
        frameSnapshot(seconds: 4, count: 2),
        frameSnapshot(seconds: 5, count: 2),
      ]) {
        snapshot = value;
        await monitor.sample();
      }
      expect(frameOutputRecoveries, isEmpty);

      snapshot = frameSnapshot(seconds: 6, count: 2);
      await monitor.sample();
      expect(frameOutputRecoveries.single.$2, 1);
    });

    test('forward seek resets stale frame-output evidence', () async {
      final monitor = createMonitor();
      snapshot = frameSnapshot(seconds: 0);
      await monitor.sample();
      snapshot = frameSnapshot(seconds: 1);
      await monitor.sample();
      snapshot = frameSnapshot(seconds: 15);
      await monitor.sample();
      snapshot = frameSnapshot(seconds: 16);
      await monitor.sample();

      expect(frameOutputRecoveries, isEmpty);
      snapshot = frameSnapshot(seconds: 17);
      await monitor.sample();
      expect(frameOutputRecoveries, hasLength(1));
    });

    test('source replacement resets both detector baselines', () async {
      final monitor = createMonitor();
      snapshot = frameSnapshot(seconds: 0);
      await monitor.sample();
      snapshot = frameSnapshot(seconds: 1);
      await monitor.sample();

      snapshot = frameSnapshot(seconds: 0, discontinuitySequence: 1);
      await monitor.sample();
      snapshot = frameSnapshot(seconds: 1, discontinuitySequence: 1);
      await monitor.sample();
      expect(frameOutputRecoveries, isEmpty);

      // The clock detector also needs three fresh stagnant samples.
      snapshot = frameSnapshot(seconds: 1, discontinuitySequence: 2);
      await monitor.sample();
      await monitor.sample();
      await monitor.sample();
      expect(recoveries, 0);
      await monitor.sample();
      expect(recoveries, 1);
    });

    test('recovery has an independent cap and cooldown', () async {
      final monitor = createMonitor(
        maxRecoveries: 0,
        frameOutputCooldown: const Duration(seconds: 10),
      );

      for (var second = 0; second <= 2; second++) {
        snapshot = frameSnapshot(seconds: second);
        await monitor.sample();
      }
      expect(frameOutputRecoveries, hasLength(1));

      for (var second = 3; second <= 6; second++) {
        snapshot = frameSnapshot(seconds: second);
        await monitor.sample();
      }
      expect(frameOutputRecoveries, hasLength(1), reason: 'cooldown applies');

      now = now.add(const Duration(seconds: 10));
      snapshot = frameSnapshot(seconds: 7);
      await monitor.sample();
      expect(frameOutputRecoveries, hasLength(2));
      expect(frameOutputRecoveries.last.$2, 2);

      now = now.add(const Duration(seconds: 10));
      for (var second = 8; second <= 12; second++) {
        snapshot = frameSnapshot(seconds: second);
        await monitor.sample();
      }
      expect(frameOutputRecoveries, hasLength(2), reason: 'cap applies');
      expect(recoveries, 0, reason: 'playback-clock cap is independent');
    });

    test('slow frame recovery serializes samples and cannot trigger clock',
        () async {
      final recoveryStarted = Completer<void>();
      final releaseRecovery = Completer<void>();
      final monitor = createMonitor(
        onFrameOutputStallRecover: (position, attempt) async {
          frameOutputRecoveries.add((position, attempt));
          recoveryStarted.complete();
          await releaseRecovery.future;
        },
      );
      for (var second = 0; second < 2; second++) {
        snapshot = frameSnapshot(seconds: second);
        await monitor.sample();
      }
      snapshot = frameSnapshot(seconds: 2);
      final slowSample = monitor.sample();
      await recoveryStarted.future;

      snapshot = frameSnapshot(seconds: 2);
      await monitor.sample();
      expect(frameOutputRecoveries, hasLength(1));
      expect(recoveries, 0);

      releaseRecovery.complete();
      await slowSample;
      expect(recoveries, 0);
    });

    test('slow clock recovery serializes samples and cannot trigger frame',
        () async {
      final recoveryStarted = Completer<void>();
      final releaseRecovery = Completer<void>();
      final monitor = createMonitor(
        onRecover: (_) async {
          recoveries++;
          recoveryStarted.complete();
          await releaseRecovery.future;
        },
      );
      for (var i = 0; i < 3; i++) {
        await monitor.sample();
      }
      final slowSample = monitor.sample();
      await recoveryStarted.future;

      snapshot = frameSnapshot(seconds: 1);
      await monitor.sample();
      snapshot = frameSnapshot(seconds: 2);
      await monitor.sample();
      expect(recoveries, 1);
      expect(frameOutputRecoveries, isEmpty);

      releaseRecovery.complete();
      await slowSample;
      expect(frameOutputRecoveries, isEmpty);
    });
  });
}
