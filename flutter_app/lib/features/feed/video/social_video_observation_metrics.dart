import '../../../services/app_analytics.dart';
import 'social_video_session_observer.dart';

typedef SocialVideoEventWriter = Future<void> Function(
  String name,
  Map<String, Object> parameters,
);

String anonymousSocialPostKey(String postId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in postId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

class SocialVideoCollisionMetricSink {
  SocialVideoCollisionMetricSink({
    SocialVideoEventWriter? writeEvent,
  }) : _writeEvent = writeEvent ??
            ((name, parameters) => AppAnalytics.logEvent(name, parameters));

  static const _eventName = 'social_video_controller_collision';
  static const _allowedSurfaceNames = <String>{
    'main_feed',
    'profile_grid',
    'post_detail',
    'fullscreen',
  };

  final SocialVideoEventWriter _writeEvent;
  String? _lastSampledSummary;

  Future<void> record(
    SocialVideoCollision collision, {
    Iterable<String> surfaceNames = const <String>[],
  }) async {
    final sanitizedSurfaceNames = surfaceNames
        .where(_allowedSurfaceNames.contains)
        .toSet()
        .toList()
      ..sort();
    final summaryKey = [
      collision.mediaKey,
      collision.controllerCount,
      ...sanitizedSurfaceNames,
    ].join('|');
    if (_lastSampledSummary == summaryKey) return;
    _lastSampledSummary = summaryKey;

    await _writeEvent(_eventName, {
      'media_key': collision.mediaKey,
      'controller_count': collision.controllerCount,
      'surface_names': sanitizedSurfaceNames,
    });
  }
}
