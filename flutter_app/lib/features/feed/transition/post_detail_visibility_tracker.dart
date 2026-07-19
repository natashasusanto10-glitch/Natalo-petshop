import 'package:flutter/foundation.dart';

@immutable
class PostVisibilitySample {
  const PostVisibilitySample({
    required this.postId,
    required this.visibleFraction,
    required this.visibleArea,
    required this.mediaCenterDistance,
  });

  final String postId;
  final double visibleFraction;
  final double visibleArea;
  final double mediaCenterDistance;
}

class PostDetailVisibilityTracker {
  PostDetailVisibilityTracker({required String initialPostId})
    : _activePostId = initialPostId;

  static const double _preferredVisibleFraction = .55;
  static const double _minimumSwitchLead = .10;
  static const double _comparisonEpsilon = 1e-12;

  String _activePostId;

  String get activePostId => _activePostId;

  String? update(
    Iterable<PostVisibilitySample> samples, {
    required bool scrollInProgress,
  }) {
    final ordered = samples.where(_hasValidVisibility).toList()
      ..sort(_compareDominance);
    if (ordered.isEmpty) return null;

    PostVisibilitySample? current;
    for (final sample in ordered) {
      if (sample.postId == _activePostId) {
        current = sample;
        break;
      }
    }

    final dominant = ordered.first;
    final canSwitch =
        dominant.postId != _activePostId &&
        _reachesPreferredVisibleFraction(dominant) &&
        _fraction(dominant) -
                (current == null ? 0 : _fraction(current)) +
                _comparisonEpsilon >=
            _minimumSwitchLead;

    PostVisibilitySample? candidate;
    if (canSwitch) {
      candidate = dominant;
    } else if (!scrollInProgress &&
        ordered.every((sample) => !_reachesPreferredVisibleFraction(sample))) {
      final centered = ordered.where(_hasValidCenterDistance).toList()
        ..sort(_compareCentered);
      if (centered.isNotEmpty) candidate = centered.first;
    }

    if (candidate == null || candidate.postId == _activePostId) return null;
    _activePostId = candidate.postId;
    return _activePostId;
  }

  bool _hasValidVisibility(PostVisibilitySample sample) =>
      sample.visibleFraction.isFinite &&
      sample.visibleFraction >= 0 &&
      sample.visibleArea.isFinite &&
      sample.visibleArea >= 0;

  bool _hasValidCenterDistance(PostVisibilitySample sample) =>
      sample.mediaCenterDistance.isFinite && sample.mediaCenterDistance >= 0;

  double _fraction(PostVisibilitySample sample) =>
      sample.visibleFraction.clamp(0.0, 1.0);

  bool _reachesPreferredVisibleFraction(PostVisibilitySample sample) =>
      _fraction(sample) >= _preferredVisibleFraction - _comparisonEpsilon;

  int _compareDominance(
    PostVisibilitySample first,
    PostVisibilitySample second,
  ) {
    final areaComparison = second.visibleArea.compareTo(first.visibleArea);
    if (areaComparison != 0) return areaComparison;

    final fractionComparison = _fraction(second).compareTo(_fraction(first));
    if (fractionComparison != 0) return fractionComparison;

    final centerComparison = _compareCenterDistance(first, second);
    if (centerComparison != 0) return centerComparison;

    if (first.postId == _activePostId && second.postId != _activePostId) {
      return -1;
    }
    if (second.postId == _activePostId && first.postId != _activePostId) {
      return 1;
    }
    return first.postId.compareTo(second.postId);
  }

  int _compareCentered(
    PostVisibilitySample first,
    PostVisibilitySample second,
  ) {
    final centerComparison = first.mediaCenterDistance.compareTo(
      second.mediaCenterDistance,
    );
    if (centerComparison != 0) return centerComparison;

    if (first.postId == _activePostId && second.postId != _activePostId) {
      return -1;
    }
    if (second.postId == _activePostId && first.postId != _activePostId) {
      return 1;
    }
    return _compareDominance(first, second);
  }

  int _compareCenterDistance(
    PostVisibilitySample first,
    PostVisibilitySample second,
  ) {
    final firstIsValid = _hasValidCenterDistance(first);
    final secondIsValid = _hasValidCenterDistance(second);
    if (firstIsValid != secondIsValid) return firstIsValid ? -1 : 1;
    if (!firstIsValid) return 0;
    return first.mediaCenterDistance.compareTo(second.mediaCenterDistance);
  }
}
