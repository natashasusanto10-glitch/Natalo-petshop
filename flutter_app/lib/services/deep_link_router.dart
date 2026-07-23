/// Pure parsing for the public links emitted by [ShareLinkBuilder].
///
/// Query parameters are deliberately excluded from navigation identity: `v`
/// changes preview cache state, while analytics parameters are owned by the
/// browser and must never create a second in-app route.
sealed class NataloDeepLinkTarget {
  const NataloDeepLinkTarget(this.value);

  final String value;

  String get dedupeKey;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is NataloDeepLinkTarget &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

final class FeedPostDeepLink extends NataloDeepLinkTarget {
  const FeedPostDeepLink(this.postId) : super(postId);

  final String postId;

  @override
  String get dedupeKey => 'feed:$postId';
}

final class ProductDeepLink extends NataloDeepLinkTarget {
  const ProductDeepLink(this.slug) : super(slug);

  final String slug;

  @override
  String get dedupeKey => 'product:$slug';
}

final class ProfileDeepLink extends NataloDeepLinkTarget {
  const ProfileDeepLink(this.username) : super(username);

  final String username;

  @override
  String get dedupeKey => 'profile:$username';
}

const Set<String> _officialHosts = <String>{
  'natalopetshop.com',
  'www.natalopetshop.com',
};

/// Parses only production HTTPS links that represent a public shared object.
///
/// A malformed URL returns null rather than falling back to an unrelated
/// screen. Dart's [Uri.pathSegments] decodes percent-encoded segments, so the
/// native route receives the exact opaque Feed ID, product slug, or username.
NataloDeepLinkTarget? parseNataloDeepLink(Uri uri) {
  if (!_isOfficialHttpsUrl(uri)) return null;

  final segments = uri.pathSegments;
  if (segments.length != 2 || !_isSafeSegment(segments[1])) return null;

  final value = segments[1];
  return switch (segments.first) {
    'feed' => FeedPostDeepLink(value),
    'products' => ProductDeepLink(value),
    'u' => ProfileDeepLink(value.toLowerCase()),
    _ => null,
  };
}

bool isOfficialNataloHttpsUrl(Uri uri) => _isOfficialHttpsUrl(uri);

bool _isOfficialHttpsUrl(Uri uri) {
  return uri.scheme.toLowerCase() == 'https' &&
      _officialHosts.contains(uri.host.toLowerCase()) &&
      uri.userInfo.isEmpty &&
      !uri.hasPort;
}

bool _isSafeSegment(String segment) {
  final normalized = segment.trim();
  return normalized.isNotEmpty &&
      normalized.length <= 256 &&
      normalized != '.' &&
      normalized != '..' &&
      !normalized.contains('/') &&
      !RegExp(r'[\u0000-\u001F\u007F]').hasMatch(normalized);
}
