import 'video_player_session.dart';

typedef WarmVideoSessionFactory = VideoPlayerSession Function({
  required String postId,
  required String url,
  required bool hasAudio,
});

/// One-shot ownership transfer for a profile-grid video session.
class PostVideoWarmHandoff {
  PostVideoWarmHandoff({
    required String postId,
    required String url,
    required bool hasAudio,
    required VideoPlayerSession session,
  })  : _postId = postId.trim(),
        _canonicalUrl = canonicalVideoUrl(url),
        _hasAudio = hasAudio,
        _session = session;

  factory PostVideoWarmHandoff.create(
      {required String postId,
      required String url,
      required bool hasAudio,
      WarmVideoSessionFactory? sessionFactory}) {
    return PostVideoWarmHandoff(
      postId: postId,
      url: url,
      hasAudio: hasAudio,
      session: sessionFactory?.call(
            postId: postId,
            url: url,
            hasAudio: hasAudio,
          ) ??
          VideoPlayerSession(
            url: url,
            hasAudio: hasAudio,
            analyticsPostId: postId,
            analyticsSurface: 'profile_grid',
          ),
    );
  }

  static PostVideoWarmHandoff? createIfVideo({
    required bool isVideo,
    required String postId,
    required String url,
    required bool hasAudio,
    WarmVideoSessionFactory? sessionFactory,
  }) {
    if (!isVideo || postId.trim().isEmpty || url.trim().isEmpty) return null;
    return PostVideoWarmHandoff.create(
      postId: postId,
      url: url,
      hasAudio: hasAudio,
      sessionFactory: sessionFactory,
    );
  }

  final String _postId;
  final String _canonicalUrl;
  final bool _hasAudio;
  VideoPlayerSession? _session;
  bool _disposed = false;

  VideoPlayerSession? claim({
    required String postId,
    required String url,
    required bool hasAudio,
  }) {
    if (_disposed || _session == null) return null;
    if (postId.trim() != _postId ||
        canonicalVideoUrl(url) != _canonicalUrl ||
        hasAudio != _hasAudio) {
      return null;
    }
    final claimed = _session;
    _session = null;
    return claimed;
  }

  Future<void> disposeIfUnclaimed() async {
    if (_disposed) return;
    _disposed = true;
    final session = _session;
    _session = null;
    await session?.dispose();
  }
}

String canonicalVideoUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return value.trim();
  return uri
      .normalizePath()
      .replace(scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase())
      .toString();
}
