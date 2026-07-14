import 'dart:async';

import '../../../services/app_analytics.dart';

class VideoPlaybackSnapshot {
  final bool shouldMonitor;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final Duration bufferAhead;
  final int? frameOutputCount;
  final int playbackDiscontinuitySequence;

  const VideoPlaybackSnapshot({
    required this.shouldMonitor,
    required this.isBuffering,
    required this.position,
    required this.duration,
    this.bufferAhead = Duration.zero,
    this.frameOutputCount,
    this.playbackDiscontinuitySequence = 0,
  });
}

typedef VideoPlaybackMetricSink = void Function(
  String event,
  Map<String, Object> parameters,
);

typedef FrameOutputStallRecover = Future<void> Function(
  Duration position,
  int attempt,
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
    this.onFrameOutputStallRecover,
    this.frameOutputStaleSamplesBeforeRecovery = 2,
    this.maxFrameOutputRecoveries = 2,
    this.frameOutputRecoveryCooldown = const Duration(seconds: 15),
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
  final FrameOutputStallRecover? onFrameOutputStallRecover;
  final int frameOutputStaleSamplesBeforeRecovery;
  final int maxFrameOutputRecoveries;
  final Duration frameOutputRecoveryCooldown;
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
  int? _lastFrameOutputCount;
  Duration? _lastFrameOutputPosition;
  DateTime? _lastFrameOutputRecoveryAt;
  int _frameOutputStaleSamples = 0;
  int _frameOutputRecoveryCount = 0;
  bool _recoveringFrameOutput = false;
  bool _sampling = false;
  int? _lastPlaybackDiscontinuitySequence;

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
    if (_sampling) return;
    _sampling = true;
    try {
      await _sampleOnce();
    } finally {
      _sampling = false;
    }
  }

  Future<void> _sampleOnce() async {
    final snapshot = readSnapshot();
    _bufferAhead = snapshot.bufferAhead;
    _recordBuffering(snapshot.shouldMonitor && snapshot.isBuffering);

    final previousSequence = _lastPlaybackDiscontinuitySequence;
    _lastPlaybackDiscontinuitySequence = snapshot.playbackDiscontinuitySequence;
    final discontinuityChanged = previousSequence != null &&
        previousSequence != snapshot.playbackDiscontinuitySequence;
    if (discontinuityChanged) {
      _resetProgress(snapshot.position);
      _resetFrameOutputProgress();
    }

    final nearEnd = snapshot.duration > Duration.zero &&
        snapshot.position >= snapshot.duration - const Duration(seconds: 1);
    final frameRecoveryStarted =
        await _sampleFrameOutput(snapshot, nearEnd: nearEnd);
    if (frameRecoveryStarted || discontinuityChanged) return;

    if (!snapshot.shouldMonitor ||
        snapshot.isBuffering ||
        _recovering ||
        _recoveringFrameOutput) {
      _resetProgress(snapshot.position);
      return;
    }
    if (nearEnd) {
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

  Future<bool> _sampleFrameOutput(
    VideoPlaybackSnapshot snapshot, {
    required bool nearEnd,
  }) async {
    final count = snapshot.frameOutputCount;
    if (!snapshot.shouldMonitor ||
        snapshot.isBuffering ||
        nearEnd ||
        count == null) {
      _resetFrameOutputProgress();
      return false;
    }

    final previousCount = _lastFrameOutputCount;
    final previousPosition = _lastFrameOutputPosition;
    _lastFrameOutputCount = count;
    _lastFrameOutputPosition = snapshot.position;

    if (previousCount == null ||
        previousPosition == null ||
        count != previousCount) {
      _frameOutputStaleSamples = 0;
      return false;
    }

    // A visual-output stall requires the playback clock to keep moving.
    final positionDelta = snapshot.position - previousPosition;
    if (positionDelta > interval * 2) {
      _resetFrameOutputProgress();
      _lastFrameOutputCount = count;
      _lastFrameOutputPosition = snapshot.position;
      return false;
    }
    if (positionDelta < const Duration(milliseconds: 200)) {
      _frameOutputStaleSamples = 0;
      return false;
    }

    _frameOutputStaleSamples++;
    final recover = onFrameOutputStallRecover;
    if (_frameOutputStaleSamples < frameOutputStaleSamplesBeforeRecovery ||
        recover == null ||
        _recovering ||
        _recoveringFrameOutput ||
        _frameOutputRecoveryCount >= maxFrameOutputRecoveries) {
      return false;
    }

    final now = _now();
    if (_lastFrameOutputRecoveryAt != null &&
        now.difference(_lastFrameOutputRecoveryAt!) <
            frameOutputRecoveryCooldown) {
      return false;
    }

    _recoveringFrameOutput = true;
    _frameOutputStaleSamples = 0;
    _lastFrameOutputRecoveryAt = now;
    final attempt = ++_frameOutputRecoveryCount;
    final metricParameters = {
      'position_ms': snapshot.position.inMilliseconds,
      'recovery_attempt': attempt,
    };
    _emit('video_frame_output_stall_detected', metricParameters);
    try {
      await recover(snapshot.position, attempt);
      _emit('video_frame_output_stall_recovery', {
        ...metricParameters,
        'result': 'requested',
      });
    } catch (_) {
      _emit('video_frame_output_stall_recovery', {
        ...metricParameters,
        'result': 'failed',
      });
    } finally {
      _lastFrameOutputCount = null;
      _lastFrameOutputPosition = null;
      _recoveringFrameOutput = false;
    }
    return true;
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

  void _resetFrameOutputProgress() {
    _lastFrameOutputCount = null;
    _lastFrameOutputPosition = null;
    _frameOutputStaleSamples = 0;
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
