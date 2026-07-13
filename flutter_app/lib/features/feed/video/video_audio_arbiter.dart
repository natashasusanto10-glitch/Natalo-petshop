import 'package:flutter/foundation.dart';

typedef VideoAudioFocusLost = void Function();

/// App-wide audio focus for video playback. It deliberately knows nothing
/// about player controllers or playback positions.
class VideoAudioArbiter {
  int _nextToken = 0;
  _ActiveClaim? _current;

  VideoAudioClaim claim({
    required Object owner,
    required VideoAudioFocusLost onFocusLost,
  }) {
    final previous = _current;
    final active = _ActiveClaim(++_nextToken, owner, onFocusLost);
    _current = active;

    // Refreshing the same owner invalidates old async work without making the
    // owner pause itself. A different owner receives focus immediately.
    if (previous != null && !identical(previous.owner, owner)) {
      previous.onFocusLost();
    }
    return VideoAudioClaim._(this, active.token, owner);
  }

  bool _isCurrent(int token, Object owner) {
    final current = _current;
    return current != null &&
        current.token == token &&
        identical(current.owner, owner);
  }

  void _release(int token, Object owner) {
    if (_isCurrent(token, owner)) _current = null;
  }

  @visibleForTesting
  Object? get currentOwner => _current?.owner;
}

class VideoAudioClaim {
  VideoAudioClaim._(this._arbiter, this.token, this.owner);

  final VideoAudioArbiter _arbiter;
  final int token;
  final Object owner;

  bool get isCurrent => _arbiter._isCurrent(token, owner);

  void release() => _arbiter._release(token, owner);
}

class _ActiveClaim {
  const _ActiveClaim(this.token, this.owner, this.onFocusLost);

  final int token;
  final Object owner;
  final VideoAudioFocusLost onFocusLost;
}

final VideoAudioArbiter videoAudioArbiter = VideoAudioArbiter();
