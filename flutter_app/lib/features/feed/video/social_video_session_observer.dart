import 'dart:collection';

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
    required this.mediaKey,
    required this.surface,
  });

  final SocialVideoLifecycleType type;
  final String mediaKey;
  final SocialVideoSurface surface;
}

class SocialVideoCollision {
  const SocialVideoCollision({
    required this.mediaKey,
    required this.controllerCount,
  });

  final String mediaKey;
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
  static const int maxLiveControllerCount = 256;

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
  final LinkedHashMap<int, _LiveController> _liveControllers =
      LinkedHashMap<int, _LiveController>();
  final List<SocialVideoObservation> _events = <SocialVideoObservation>[];
  final Map<String, SocialVideoCollision> _collisions =
      <String, SocialVideoCollision>{};
  final Map<String, Set<int>> _reportedCollisionSets = <String, Set<int>>{};
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
        mediaKey: _anonymousMediaKey(postId),
        surface: surface,
      ),
    );

    if (type == SocialVideoLifecycleType.released ||
        type == SocialVideoLifecycleType.disposed) {
      _removeController(controllerId);
    } else {
      _evictIfNeeded(controllerId);
      _liveControllers[controllerId] = _LiveController(
        postId: postId,
        surface: surface,
        dormant: type == SocialVideoLifecycleType.dormant,
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
    _reportedCollisionSets.clear();
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

  void _evictIfNeeded(int controllerId) {
    if (_liveControllers.containsKey(controllerId) ||
        _liveControllers.length < maxLiveControllerCount) {
      return;
    }

    MapEntry<int, _LiveController>? dormant;
    for (final entry in _liveControllers.entries) {
      if (entry.value.dormant) {
        dormant = entry;
        break;
      }
    }
    _liveControllers.remove((dormant ?? _liveControllers.entries.first).key);
  }

  void _refreshCollisions() {
    final controllerIdsByPost = <String, Set<int>>{};
    _liveControllers.forEach((controllerId, liveController) {
      controllerIdsByPost
          .putIfAbsent(liveController.postId, () => <int>{})
          .add(controllerId);
    });

    final activeSets = <String, Set<int>>{
      for (final entry in controllerIdsByPost.entries)
        if (entry.value.length > 1) entry.key: entry.value,
    };

    _collisions
      ..clear()
      ..addAll(
        activeSets.map(
          (postId, controllerIds) => MapEntry(
            postId,
            SocialVideoCollision(
              mediaKey: _anonymousMediaKey(postId),
              controllerCount: controllerIds.length,
            ),
          ),
        ),
      );

    for (final entry in activeSets.entries) {
      final previous = _reportedCollisionSets[entry.key];
      if (!_sameControllerSet(previous, entry.value)) {
        _reportedCollisionSets[entry.key] = Set<int>.of(entry.value);
        try {
          _onCollision?.call(_collisions[entry.key]!);
        } catch (_) {
          // Diagnostics must never interrupt lifecycle observation.
        }
      }
    }
    _reportedCollisionSets
        .removeWhere((postId, _) => !activeSets.containsKey(postId));
  }

  bool _sameControllerSet(Set<int>? first, Set<int> second) =>
      first != null &&
      first.length == second.length &&
      first.containsAll(second);
}

class _LiveController {
  const _LiveController({
    required this.postId,
    required this.surface,
    required this.dormant,
  });

  final String postId;
  final SocialVideoSurface surface;
  final bool dormant;
}

String _anonymousMediaKey(String postId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in postId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
