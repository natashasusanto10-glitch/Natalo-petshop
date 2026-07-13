import 'video_player_session.dart';

/// One-shot ownership transfer for a profile-grid video session.
class PostVideoWarmHandoff {
  PostVideoWarmHandoff({
    required String postId,
    required String url,
    required VideoPlayerSession session,
  })  : _postId = postId.trim(),
        _canonicalUrl = canonicalVideoUrl(url),
        _session = session;

  factory PostVideoWarmHandoff.create(
      {required String postId, required String url}) {
    return PostVideoWarmHandoff(
      postId: postId,
      url: url,
      session: VideoPlayerSession(
        url: url,
        analyticsPostId: postId,
        analyticsSurface: 'profile_grid',
      ),
    );
  }

  static PostVideoWarmHandoff? createIfVideo({
    required bool isVideo,
    required String postId,
    required String url,
  }) {
    if (!isVideo || postId.trim().isEmpty || url.trim().isEmpty) return null;
    return PostVideoWarmHandoff.create(postId: postId, url: url);
  }

  final String _postId;
  final String _canonicalUrl;
  VideoPlayerSession? _session;
  bool _disposed = false;

  VideoPlayerSession? claim({required String postId, required String url}) {
    if (_disposed || _session == null) return null;
    if (postId.trim() != _postId || canonicalVideoUrl(url) != _canonicalUrl) {
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
