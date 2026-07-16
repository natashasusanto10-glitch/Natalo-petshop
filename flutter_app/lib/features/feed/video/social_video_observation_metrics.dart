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
  static final _safeMediaKey = RegExp(r'^[0-9a-f]{8}$');

  final SocialVideoEventWriter _writeEvent;
  String? _lastSampledSummary;

  Future<void> record(
    SocialVideoCollision collision, {
    Set<SocialVideoSurface> surfaces = const <SocialVideoSurface>{},
  }) async {
    if (!_safeMediaKey.hasMatch(collision.mediaKey)) return;
    final sanitizedSurfaceNames = surfaces.map(_surfaceName).toList()..sort();
    final summaryKey = [
      collision.mediaKey,
      collision.controllerCount,
      ...sanitizedSurfaceNames,
    ].join('|');
    if (_lastSampledSummary == summaryKey) return;

    try {
      await _writeEvent(_eventName, {
        'media_key': collision.mediaKey,
        'controller_count': collision.controllerCount,
        'surface_names': sanitizedSurfaceNames.join('|'),
      });
      _lastSampledSummary = summaryKey;
    } catch (_) {
      // Diagnostics must never interrupt lifecycle observation or block retry.
    }
  }

  String _surfaceName(SocialVideoSurface surface) {
    switch (surface) {
      case SocialVideoSurface.mainFeed:
        return 'main_feed';
      case SocialVideoSurface.profileGrid:
        return 'profile_grid';
      case SocialVideoSurface.postDetail:
        return 'post_detail';
      case SocialVideoSurface.fullscreen:
        return 'fullscreen';
    }
  }
}
