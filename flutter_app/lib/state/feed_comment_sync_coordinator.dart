import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

typedef FeedCommentRefreshCallback = Future<void> Function();

/// A disposable registration for one visible comment drawer.
class FeedCommentSyncLease {
  FeedCommentSyncLease._(this._release);

  VoidCallback? _release;

  void dispose() {
    final release = _release;
    if (release == null) return;
    _release = null;
    release();
  }
}

/// Runs near-realtime comment revalidation only while a drawer is visible.
///
/// One coordinator owns one timer for the whole process. Multiple widgets for
/// the same viewer/post share a key, so they never create duplicate requests.
/// The network implementation remains in the sheet/repository layer; this
/// class only coordinates visibility, lifecycle, and request serialization.
class FeedCommentSyncCoordinator with WidgetsBindingObserver {
  FeedCommentSyncCoordinator({
    this.interval = const Duration(seconds: 10),
  });

  final Duration interval;
  final Map<String, LinkedHashMap<Object, FeedCommentRefreshCallback>>
      _registrations = {};
  final Map<String, Object> _inFlight = {};
  Timer? _timer;
  bool _observingLifecycle = false;
  bool _resumed = true;
  int _generation = 0;

  int get activeKeyCount => _registrations.length;

  FeedCommentSyncLease register({
    required String viewerId,
    required String postId,
    required FeedCommentRefreshCallback refresh,
  }) {
    final key = _key(viewerId, postId);
    final token = Object();
    (_registrations[key] ??=
        LinkedHashMap<Object, FeedCommentRefreshCallback>())[token] = refresh;
    _ensureRunning();
    return FeedCommentSyncLease._(() => _release(key, token));
  }

  void _release(String key, Object token) {
    final callbacks = _registrations[key];
    callbacks?.remove(token);
    if (callbacks == null || callbacks.isEmpty) {
      _registrations.remove(key);
    }
    if (_registrations.isEmpty) _stop();
  }

  void _ensureRunning() {
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    if (!_resumed || _registrations.isEmpty || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (!_resumed || _registrations.isEmpty) return;
    final generation = _generation;
    final entries = _registrations.entries.toList(growable: false);
    await Future.wait(entries.map((entry) async {
      final key = entry.key;
      if (generation != _generation ||
          _inFlight.containsKey(key) ||
          entry.value.isEmpty) {
        return;
      }
      final token = Object();
      _inFlight[key] = token;
      try {
        if (generation != _generation) return;
        // The most recently mounted surface is authoritative for invoking the
        // refresh, while the shared session publishes the result to everyone.
        await entry.value.values.last();
      } catch (_) {
        // Revalidation is best-effort; the drawer keeps cached content and its
        // explicit pull-to-refresh error handling.
      } finally {
        if (generation == _generation && identical(_inFlight[key], token)) {
          _inFlight.remove(key);
        }
      }
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      _ensureRunning();
      unawaited(_tick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
  }

  void clear() {
    _generation++;
    _registrations.clear();
    _inFlight.clear();
    _stop();
  }

  @visibleForTesting
  Future<void> debugTick() => _tick();

  String _key(String viewerId, String postId) => '$viewerId\u0000$postId';
}

final FeedCommentSyncCoordinator feedCommentSyncCoordinator =
    FeedCommentSyncCoordinator();
