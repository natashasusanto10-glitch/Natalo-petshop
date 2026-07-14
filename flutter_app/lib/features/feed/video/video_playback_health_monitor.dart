import 'dart:async';

import '../../../services/app_analytics.dart';

class VideoPlaybackSnapshot {
  final bool shouldMonitor;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final Duration bufferAhead;

  const VideoPlaybackSnapshot({
    required this.shouldMonitor,
    required this.isBuffering,
    required this.position,
    required this.duration,
    this.bufferAhead = Duration.zero,
  });
}

typedef VideoPlaybackMetricSink = void Function(
  String event,
  Map<String, Object> parameters,
);

/// Monitoring follows app playback intent, not the native `isPlaying` flag.
/// Native players may temporarily clear that flag while they are buffering.
bool shouldMonitorIntendedPlayback({
  required bool intendsPlayback,
  required bool isInitialized,
}) =>
    intendsPlayback && isInitialized;

/// Conservative playback watchdog for the active video session.
///
/// It detects a playback-clock stall (not a native rendered-frame stall):
/// three consecutive samples with less than 200 ms progress while the player
/// is expected to be playing and is not buffering. Recovery is capped and
/// cooled down so a broken stream cannot enter a restart loop.
class VideoPlaybackHealthMonitor {
  VideoPlaybackHealthMonitor({
    required this.readSnapshot,
    required this.onRecover,
    required this.metricContext,
    VideoPlaybackMetricSink? metricSink,
    this.interval = const Duration(seconds: 1),
    this.stagnantSamplesBeforeRecovery = 3,
    this.maxRecoveries = 2,
    this.recoveryCooldown = const Duration(seconds: 15),
    DateTime Function()? now,
  })  : metricSink = metricSink ?? _defaultMetricSink,
        _now = now ?? DateTime.now;

  final VideoPlaybackSnapshot Function() readSnapshot;
  final Future<void> Function(Duration position) onRecover;
  final Map<String, Object> metricContext;
  final VideoPlaybackMetricSink metricSink;
  final Duration interval;
  final int stagnantSamplesBeforeRecovery;
  final int maxRecoveries;
  final Duration recoveryCooldown;
  final DateTime Function() _now;

  Timer? _timer;
  Duration? _lastPosition;
  DateTime? _lastRecoveryAt;
  DateTime? _bufferingStartedAt;
  int _stagnantSamples = 0;
  int _recoveryCount = 0;
  int _bufferingCount = 0;
  Duration _bufferingDuration = Duration.zero;
  Duration _bufferAhead = Duration.zero;
  bool _recovering = false;
  bool _wasBuffering = false;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(sample()));
  }

  void record(String event, [Map<String, Object> parameters = const {}]) {
    _emit(event, parameters);
  }

  /// Capture native buffering transitions immediately from a player listener.
  ///
  /// This deliberately does not run stall detection. Player listeners can fire
  /// once per rendered frame, while stall detection is calibrated for the
  /// low-frequency [interval] timer. [_recordBuffering] deduplicates unchanged
  /// states, so calling this from that listener does not create metric storms.
  void observePlaybackStateTransition() {
    final snapshot = readSnapshot();
    _bufferAhead = snapshot.bufferAhead;
    _recordBuffering(snapshot.shouldMonitor && snapshot.isBuffering);
  }

  Future<void> sample() async {
    final snapshot = readSnapshot();
    _bufferAhead = snapshot.bufferAhead;
    _recordBuffering(snapshot.shouldMonitor && snapshot.isBuffering);

    if (!snapshot.shouldMonitor || snapshot.isBuffering || _recovering) {
      _resetProgress(snapshot.position);
      return;
    }
    if (snapshot.duration > Duration.zero &&
        snapshot.position >= snapshot.duration - const Duration(seconds: 1)) {
      _resetProgress(snapshot.position);
      return;
    }

    final previous = _lastPosition;
    _lastPosition = snapshot.position;
    if (previous == null ||
        snapshot.position - previous >= const Duration(milliseconds: 200)) {
      _stagnantSamples = 0;
      return;
    }

    _stagnantSamples++;
    if (_stagnantSamples < stagnantSamplesBeforeRecovery ||
        _recoveryCount >= maxRecoveries) {
      return;
    }
    final now = _now();
    if (_lastRecoveryAt != null &&
        now.difference(_lastRecoveryAt!) < recoveryCooldown) {
      return;
    }

    _recovering = true;
    _stagnantSamples = 0;
    _lastRecoveryAt = now;
    _recoveryCount++;
    _emit('video_stall_detected', {
      'position_ms': snapshot.position.inMilliseconds,
      'recovery_attempt': _recoveryCount,
    });
    try {
      await onRecover(snapshot.position);
      _emit('video_stall_recovery', {
        'result': 'requested',
        'recovery_attempt': _recoveryCount,
      });
    } catch (_) {
      _emit('video_stall_recovery', {
        'result': 'failed',
        'recovery_attempt': _recoveryCount,
      });
    } finally {
      _lastPosition = null;
      _recovering = false;
    }
  }

  void _recordBuffering(bool buffering) {
    if (buffering == _wasBuffering) return;
    _wasBuffering = buffering;
    if (buffering) {
      _bufferingCount++;
      _bufferingStartedAt = _now();
      _emit('video_buffer_started');
    } else {
      final started = _bufferingStartedAt;
      _bufferingStartedAt = null;
      final duration =
          started == null ? Duration.zero : _now().difference(started);
      _bufferingDuration += duration;
      _emit('video_buffer_ended', {
        if (started != null) 'duration_ms': duration.inMilliseconds,
      });
    }
  }

  void _resetProgress(Duration position) {
    _lastPosition = position;
    _stagnantSamples = 0;
  }

  void _emit(String event, [Map<String, Object> parameters = const {}]) {
    metricSink(event, {
      ...metricContext,
      'buffer_ahead_ms': _bufferAhead.inMilliseconds,
      'buffering_count': _bufferingCount,
      'buffering_duration_ms': _bufferingDuration.inMilliseconds,
      ...parameters,
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  static void _defaultMetricSink(
    String event,
    Map<String, Object> parameters,
  ) {
    unawaited(AppAnalytics.logEvent(event, parameters));
  }
}
