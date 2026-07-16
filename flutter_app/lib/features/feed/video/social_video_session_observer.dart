enum SocialVideoSurface { mainFeed, profileGrid, postDetail, fullscreen }

enum SocialVideoLifecycleType {
  created,
  initialized,
  attached,
  activated,
  dormant,
  released,
  disposed,
  failed,
}

class SocialVideoObservation {
  const SocialVideoObservation({
    required this.type,
    required this.postId,
    required this.surface,
    required this.ownerId,
  });

  final SocialVideoLifecycleType type;
  final String postId;
  final SocialVideoSurface surface;
  final String ownerId;
}

class SocialVideoCollision {
  const SocialVideoCollision({
    required this.postId,
    required this.controllerCount,
  });

  final String postId;
  final int controllerCount;
}

class SocialVideoObserverSnapshot {
  const SocialVideoObserverSnapshot({
    required this.liveControllerCount,
    required this.events,
    required this.collisions,
  });

  final int liveControllerCount;
  final List<SocialVideoObservation> events;
  final List<SocialVideoCollision> collisions;
}

class SocialVideoSessionObserver {
  SocialVideoSessionObserver({
    required bool enabled,
    int eventLimit = 256,
    void Function(SocialVideoCollision collision)? onCollision,
  })  : _enabled = enabled,
        _eventLimit = eventLimit,
        _onCollision = onCollision {
    if (eventLimit < 0) {
      throw ArgumentError.value(
          eventLimit, 'eventLimit', 'must not be negative');
    }
  }

  final bool _enabled;
  final int _eventLimit;
  final void Function(SocialVideoCollision collision)? _onCollision;
  final Expando<int> _controllerIds = Expando<int>();
  final Map<int, _LiveController> _liveControllers = <int, _LiveController>{};
  final List<SocialVideoObservation> _events = <SocialVideoObservation>[];
  final Map<String, SocialVideoCollision> _collisions =
      <String, SocialVideoCollision>{};
  final Set<String> _reportedCollisionPosts = <String>{};
  int _nextControllerId = 0;

  void observeController({
    required SocialVideoLifecycleType type,
    required String postId,
    required SocialVideoSurface surface,
    required String ownerId,
    required Object controllerIdentity,
  }) {
    if (!_enabled) return;
    if (postId.trim().isEmpty) {
      throw ArgumentError.value(postId, 'postId', 'must not be blank');
    }

    final controllerId = _idFor(controllerIdentity);
    _recordEvent(
      SocialVideoObservation(
        type: type,
        postId: postId,
        surface: surface,
        ownerId: ownerId,
      ),
    );

    if (type == SocialVideoLifecycleType.released ||
        type == SocialVideoLifecycleType.disposed) {
      _removeController(controllerId);
    } else {
      _liveControllers[controllerId] = _LiveController(
        postId: postId,
        surface: surface,
        ownerId: ownerId,
      );
    }
    _refreshCollisions();
  }

  SocialVideoObserverSnapshot get snapshot => SocialVideoObserverSnapshot(
        liveControllerCount: _liveControllers.length,
        events: List<SocialVideoObservation>.unmodifiable(_events),
        collisions: List<SocialVideoCollision>.unmodifiable(_collisions.values),
      );

  void clear() {
    _liveControllers.clear();
    _events.clear();
    _collisions.clear();
    _reportedCollisionPosts.clear();
  }

  int _idFor(Object controllerIdentity) {
    final existing = _controllerIds[controllerIdentity];
    if (existing != null) return existing;
    final id = ++_nextControllerId;
    _controllerIds[controllerIdentity] = id;
    return id;
  }

  void _recordEvent(SocialVideoObservation event) {
    if (_eventLimit == 0) return;
    _events.add(event);
    if (_events.length > _eventLimit) _events.removeAt(0);
  }

  void _removeController(int controllerId) {
    _liveControllers.remove(controllerId);
  }

  void _refreshCollisions() {
    final counts = <String, int>{};
    final controllerIdsByPost = <String, Set<int>>{};
    _liveControllers.forEach((controllerId, liveController) {
      controllerIdsByPost
          .putIfAbsent(liveController.postId, () => <int>{})
          .add(controllerId);
    });

    controllerIdsByPost.forEach((postId, controllerIds) {
      if (controllerIds.length > 1) counts[postId] = controllerIds.length;
    });

    _collisions
      ..clear()
      ..addAll(
        counts.map(
          (postId, controllerCount) => MapEntry(
            postId,
            SocialVideoCollision(
              postId: postId,
              controllerCount: controllerCount,
            ),
          ),
        ),
      );

    for (final entry in counts.entries) {
      if (_reportedCollisionPosts.add(entry.key)) {
        _onCollision?.call(_collisions[entry.key]!);
      }
    }
    _reportedCollisionPosts
        .removeWhere((postId) => !counts.containsKey(postId));
  }
}

class _LiveController {
  const _LiveController({
    required this.postId,
    required this.surface,
    required this.ownerId,
  });

  final String postId;
  final SocialVideoSurface surface;
  final String ownerId;
}
