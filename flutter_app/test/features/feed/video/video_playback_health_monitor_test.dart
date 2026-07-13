import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_playback_health_monitor.dart';

void main() {
  late VideoPlaybackSnapshot snapshot;
  late List<String> events;
  late int recoveries;

  VideoPlaybackHealthMonitor createMonitor({int maxRecoveries = 2}) {
    return VideoPlaybackHealthMonitor(
      readSnapshot: () => snapshot,
      onRecover: (_) async => recoveries++,
      metricContext: const {'surface': 'test'},
      metricSink: (event, _) => events.add(event),
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
