import 'package:flutter/foundation.dart';

import '../services/feed_service.dart';
import 'member_store.dart';

typedef SetCommentLiked = Future<int> Function(
  String commentId, {
  required bool liked,
});

class FeedCommentLikeState {
  const FeedCommentLikeState({required this.liked, required this.count});

  final bool liked;
  final int count;
}

/// Canonical optimistic like state shared by all comment drawers.
class FeedCommentInteractionStore extends ChangeNotifier {
  FeedCommentInteractionStore({
    SetCommentLiked? setCommentLiked,
    Listenable? viewerChanges,
    int Function()? viewerGeneration,
  })  : _setCommentLiked = setCommentLiked ?? feedService.setCommentLiked,
        _viewerChanges = viewerChanges ?? memberStore,
        _viewerGeneration =
            viewerGeneration ?? (() => memberStore.viewerGeneration) {
    _knownViewerGeneration = _viewerGeneration();
    _viewerChanges.addListener(_onViewerChanged);
  }

  final SetCommentLiked _setCommentLiked;
  final Listenable _viewerChanges;
  final int Function() _viewerGeneration;
  final Map<String, FeedCommentLikeState> _likes = {};
  final Map<String, FeedCommentLikeState> _confirmed = {};
  final Map<String, bool> _desired = {};
  final Map<String, int> _intentRevisions = {};
  final Map<String, _CommentLikeFlight> _inFlight = {};
  late int _knownViewerGeneration;

  FeedCommentLikeState? likeState(String postId, String commentId) =>
      _likes[_key(postId, commentId)];

  Set<String> pendingCommentIdsForPost(String postId) {
    final prefix = '$postId\u0000';
    return _inFlight.keys
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .toSet();
  }

  void seed({
    required String postId,
    required String commentId,
    required bool liked,
    required int count,
  }) {
    final key = _key(postId, commentId);
    if (_likes.containsKey(key) || _inFlight.containsKey(key)) return;
    _likes[key] = FeedCommentLikeState(liked: liked, count: count);
  }

  Future<FeedCommentLikeState> toggle({
    required String postId,
    required String commentId,
    required bool currentlyLiked,
    required int currentCount,
  }) {
    final key = _key(postId, commentId);
    final current = _likes[key] ??
        FeedCommentLikeState(liked: currentlyLiked, count: currentCount);
    _confirmed.putIfAbsent(key, () => current);
    final nextLiked = !current.liked;
    _likes[key] = FeedCommentLikeState(
      liked: nextLiked,
      count:
          nextLiked ? current.count + 1 : (current.count - 1).clamp(0, 1 << 30),
    );
    _desired[key] = nextLiked;
    _intentRevisions[key] = (_intentRevisions[key] ?? 0) + 1;
    notifyListeners();

    final existingFlight = _inFlight[key];
    if (existingFlight != null) return Future.value(_likes[key]!);

    final flight = _CommentLikeFlight();
    _inFlight[key] = flight;
    flight.result = _drain(key, flight, _confirmed[key]!);
    return flight.result;
  }

  Future<FeedCommentLikeState> _drain(
    String key,
    _CommentLikeFlight flight,
    FeedCommentLikeState confirmed,
  ) async {
    try {
      while (_isActiveFlight(key, flight)) {
        final requestedLiked = _desired[key] ?? confirmed.liked;
        final requestedRevision = _intentRevisions[key] ?? 0;

        final split = key.split('\u0000');
        final count = await _setCommentLiked(
          split[1],
          liked: requestedLiked,
        );
        if (!_isActiveFlight(key, flight)) return confirmed;

        confirmed = FeedCommentLikeState(
          liked: requestedLiked,
          count: count,
        );
        _confirmed[key] = confirmed;
        if ((_intentRevisions[key] ?? 0) != requestedRevision) continue;

        _likes[key] = confirmed;
        notifyListeners();
        return confirmed;
      }
      return confirmed;
    } catch (_) {
      if (_isActiveFlight(key, flight)) {
        _likes[key] = confirmed;
        notifyListeners();
      }
      rethrow;
    } finally {
      if (_isActiveFlight(key, flight)) {
        _inFlight.remove(key);
        _desired.remove(key);
        _intentRevisions.remove(key);
        _confirmed.remove(key);
      }
    }
  }

  void clearForViewer() {
    final hadState = _likes.isNotEmpty ||
        _confirmed.isNotEmpty ||
        _desired.isNotEmpty ||
        _intentRevisions.isNotEmpty ||
        _inFlight.isNotEmpty;
    _likes.clear();
    _confirmed.clear();
    _desired.clear();
    _intentRevisions.clear();
    _inFlight.clear();
    if (hadState) notifyListeners();
  }

  void _onViewerChanged() {
    final generation = _viewerGeneration();
    if (generation == _knownViewerGeneration) return;
    _knownViewerGeneration = generation;
    clearForViewer();
  }

  bool _isActiveFlight(String key, _CommentLikeFlight flight) =>
      identical(_inFlight[key], flight);

  String _key(String postId, String commentId) => '$postId\u0000$commentId';

  @override
  void dispose() {
    _viewerChanges.removeListener(_onViewerChanged);
    super.dispose();
  }
}

class _CommentLikeFlight {
  late Future<FeedCommentLikeState> result;
}

final FeedCommentInteractionStore feedCommentInteractionStore =
    FeedCommentInteractionStore();
