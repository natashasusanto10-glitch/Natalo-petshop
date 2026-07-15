import 'package:cached_video_player_plus/cached_video_player_plus.dart';

/// Stable disk-cache identity shared by Feed, Profile/Postingan, and preload.
///
/// Signed CDN URLs rotate authentication query parameters even when the
/// underlying media is unchanged. Keying the cache by the complete URL turns
/// every token refresh into a cache miss. This identity keeps content-bearing
/// query parameters while removing known volatile signature parameters.
String videoMediaCacheKey({required String mediaId, required String url}) {
  final identity = '${mediaId.trim()}|${canonicalVideoResourceUrl(url)}';
  final first = _fnv1a32(identity, 0x811c9dc5);
  final second = _fnv1a32(identity, 0x9747b28c);
  return 'natalo_video_v1_$first$second';
}

String canonicalVideoResourceUrl(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return trimmed;

  final stableQuery = <String, List<String>>{};
  final keys = uri.queryParametersAll.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  for (final key in keys) {
    if (_isVolatileSignatureParameter(key)) continue;
    final values = [...uri.queryParametersAll[key] ?? const <String>[]]..sort();
    stableQuery[key] = values;
  }

  final normalized = uri.normalizePath();
  return Uri(
    scheme: uri.scheme.toLowerCase(),
    userInfo: normalized.userInfo,
    host: uri.host.toLowerCase(),
    port: normalized.hasPort ? normalized.port : null,
    path: normalized.path,
    queryParameters: stableQuery.isEmpty ? null : stableQuery,
  ).toString();
}

Future<void> evictVideoMediaCache({
  required String mediaId,
  required String url,
}) {
  return CachedVideoPlayerPlus.removeFileFromCacheByKey(
    videoMediaCacheKey(mediaId: mediaId, url: url),
  );
}

bool _isVolatileSignatureParameter(String key) {
  final normalized = key.toLowerCase();
  return normalized == 'token' ||
      normalized == 'expires' ||
      normalized == 'expiry' ||
      normalized == 'signature' ||
      normalized == 'policy' ||
      normalized == 'key-pair-id' ||
      normalized == 'authorization' ||
      normalized == 'auth' ||
      normalized == 'hmac' ||
      normalized == 'hash' ||
      normalized.startsWith('token_') ||
      normalized.startsWith('bcdn_') ||
      normalized.startsWith('x-amz-') ||
      normalized.startsWith('x-goog-');
}

String _fnv1a32(String input, int seed) {
  var hash = seed;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
