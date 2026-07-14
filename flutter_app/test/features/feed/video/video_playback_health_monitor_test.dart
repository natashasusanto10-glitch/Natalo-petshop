import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_playback_health_monitor.dart';

void main() {
  late VideoPlaybackSnapshot snapshot;
  late List<String> events;
  late int recoveries;
  late List<Map<String, Object>> parameters;
  late DateTime now;

  VideoPlaybackHealthMonitor createMonitor({int maxRecoveries = 2}) {
    return VideoPlaybackHealthMonitor(
      readSnapshot: () => snapshot,
      onRecover: (_) async => recoveries++,
      metricContext: const {'surface': 'test'},
      metricSink: (event, payload) {
        events.add(event);
        parameters.add(payload);
      },
      now: () => now,
      stagnantSamplesBeforeRecovery: 3,
      maxRecoveries: maxRecoveries,
      recoveryCooldown: Duration.zero,
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
}
