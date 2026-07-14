import 'dart:async';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

const String frameOutputHeartbeatChannelName =
    'com.natalopetshop/video_rendered_frames';

typedef FrameOutputStreamFactory = Stream<dynamic> Function();

/// A native frame-output heartbeat emitted after a decoder produced a frame.
///
/// This is deliberately named frame-output: it does not claim that the frame
/// was presented by the GPU or became visible on screen.
class FrameOutputHeartbeat {
  const FrameOutputHeartbeat({
    required this.playerId,
    required this.textureId,
    required this.frameCount,
    required this.mediaTimeUs,
    required this.monotonicTimeUs,
    required this.platform,
    required this.receivedAt,
  });

  final int playerId;
  final int? textureId;
  final int frameCount;
  final int mediaTimeUs;
  final int monotonicTimeUs;
  final String platform;
  final DateTime receivedAt;
}

/// Ownership token for one player ID's frame-output heartbeat route.
class FrameOutputHeartbeatRegistration {
  FrameOutputHeartbeatRegistration._(
    this._service,
    this.playerId,
    this._generation,
    this._heartbeats,
  );

  final FrameOutputHeartbeatService _service;
  final int playerId;
  final int _generation;
  final Stream<FrameOutputHeartbeat> _heartbeats;

  bool _unregistered = false;

  Stream<FrameOutputHeartbeat> get heartbeats => _heartbeats;

  FrameOutputHeartbeat? get latest =>
      _service._latestFor(playerId, _generation);

  bool get isRegistered =>
      !_unregistered && _service._isRegistered(playerId, _generation);

  void unregister() {
    if (_unregistered) return;
    _unregistered = true;
    _service._unregister(playerId, _generation);
  }
}

class FrameOutputHeartbeatService {
  FrameOutputHeartbeatService({
    FrameOutputStreamFactory? streamFactory,
    DateTime Function()? now,
    Future<void> Function(Duration)? retryDelay,
  })  : _streamFactory = streamFactory ?? _defaultStreamFactory,
        _now = now ?? DateTime.now,
        _retryDelay = retryDelay ?? Future<void>.delayed;

  static final FrameOutputHeartbeatService instance =
      FrameOutputHeartbeatService();

  final FrameOutputStreamFactory _streamFactory;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _retryDelay;
  final Map<int, _FrameOutputRoute> _routes = <int, _FrameOutputRoute>{};
  final Map<int, FrameOutputHeartbeat> _latest = <int, FrameOutputHeartbeat>{};

  StreamSubscription<dynamic>? _subscription;
  int _nextGeneration = 0;
  int _subscriptionGeneration = 0;
  int _consecutiveFailures = 0;

  FrameOutputHeartbeatRegistration register(
    Object player,
  ) {
    final playerId = switch (player) {
      // The plugin exposes the native routing ID through this getter.
      // ignore: invalid_use_of_visible_for_testing_member
      VideoPlayerController controller => controller.playerId,
      int id => id,
      _ => throw ArgumentError.value(
          player,
          'player',
          'Must be a VideoPlayerController or int player ID.',
        ),
    };
    if (playerId < 0) {
      throw ArgumentError.value(playerId, 'player', 'Must be initialized.');
    }

    final generation = ++_nextGeneration;
    final route = _FrameOutputRoute(generation);
    final replaced = _routes[playerId];
    _routes[playerId] = route;
    _latest.remove(playerId);
    replaced?.close();
    _ensureSubscribed();

    return FrameOutputHeartbeatRegistration._(
      this,
      playerId,
      generation,
      route.controller.stream,
    );
  }

  FrameOutputHeartbeat? latestFor(int playerId) => _latest[playerId];

  void _ensureSubscribed() {
    if (_subscription != null || _routes.isEmpty) return;
    final generation = ++_subscriptionGeneration;
    try {
      _subscription = _streamFactory().listen(
        (event) {
          if (generation == _subscriptionGeneration) {
            _consecutiveFailures = 0;
            _onEvent(event);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (generation == _subscriptionGeneration) {
            _onChannelError(error, stackTrace);
          }
        },
        onDone: () {
          if (generation == _subscriptionGeneration) _onChannelDone();
        },
      );
    } on MissingPluginException catch (_) {
      _subscription = null;
    } on PlatformException catch (_) {
      _subscription = null;
    } catch (_) {
      _subscription = null;
    }
  }

  void _onEvent(dynamic payload) {
    final heartbeat = _parse(payload);
    if (heartbeat == null) return;
    final route = _routes[heartbeat.playerId];
    if (route == null) return;

    final previous = _latest[heartbeat.playerId];
    if (previous != null && heartbeat.frameCount <= previous.frameCount) return;

    _latest[heartbeat.playerId] = heartbeat;
    route.controller.add(heartbeat);
  }

  void _onChannelError(Object _, [StackTrace? __]) {
    _restartSubscription();
  }

  void _onChannelDone() {
    _restartSubscription();
  }

  void _restartSubscription() {
    final subscription = _subscription;
    _subscription = null;
    final generation = ++_subscriptionGeneration;
    unawaited(subscription?.cancel());
    if (_routes.isEmpty) return;

    final failure = _consecutiveFailures++;
    final delayMs = 100 * (1 << failure.clamp(0, 4));
    unawaited(_retryAfter(
      Duration(milliseconds: delayMs),
      generation,
    ));
  }

  Future<void> _retryAfter(Duration delay, int generation) async {
    await _retryDelay(delay);
    if (generation != _subscriptionGeneration || _routes.isEmpty) return;
    _ensureSubscribed();
  }

  FrameOutputHeartbeat? _parse(dynamic payload) {
    if (payload is! Map) return null;
    final playerId = payload['playerId'];
    final textureId = payload['textureId'];
    final frameCount = payload['frameCount'];
    final mediaTimeUs = payload['mediaTimeUs'];
    final monotonicTimeUs = payload['monotonicTimeUs'];
    final platform = payload['platform'];
    if (playerId is! int ||
        (textureId != null && textureId is! int) ||
        frameCount is! int ||
        mediaTimeUs is! int ||
        monotonicTimeUs is! int ||
        platform is! String ||
        playerId < 0 ||
        (textureId is int && textureId < 0) ||
        frameCount < 0 ||
        mediaTimeUs < 0 ||
        monotonicTimeUs < 0 ||
        platform.isEmpty) {
      return null;
    }
    return FrameOutputHeartbeat(
      playerId: playerId,
      textureId: textureId as int?,
      frameCount: frameCount,
      mediaTimeUs: mediaTimeUs,
      monotonicTimeUs: monotonicTimeUs,
      platform: platform,
      receivedAt: _now(),
    );
  }

  bool _isRegistered(int playerId, int generation) =>
      _routes[playerId]?.generation == generation;

  FrameOutputHeartbeat? _latestFor(int playerId, int generation) =>
      _isRegistered(playerId, generation) ? _latest[playerId] : null;

  void _unregister(int playerId, int generation) {
    final route = _routes[playerId];
    if (route == null || route.generation != generation) return;
    _routes.remove(playerId);
    _latest.remove(playerId);
    route.close();
    if (_routes.isEmpty) {
      final subscription = _subscription;
      _subscription = null;
      _subscriptionGeneration++;
      _consecutiveFailures = 0;
      unawaited(subscription?.cancel());
    }
  }

  static Stream<dynamic> _defaultStreamFactory() =>
      const EventChannel(frameOutputHeartbeatChannelName)
          .receiveBroadcastStream();
}

class _FrameOutputRoute {
  _FrameOutputRoute(this.generation);

  final int generation;
  final StreamController<FrameOutputHeartbeat> controller =
      StreamController<FrameOutputHeartbeat>.broadcast(sync: true);

  void close() {
    if (!controller.isClosed) unawaited(controller.close());
  }
}
