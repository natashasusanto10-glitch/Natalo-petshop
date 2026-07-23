/// Public data allowed in a share message. Rich preview data stays on the
/// server; these payloads only build the canonical deep link and short copy.
sealed class ShareContent {
  const ShareContent({this.shareVersion});

  final String? shareVersion;
}

final class FeedShareContent extends ShareContent {
  const FeedShareContent({
    required this.postId,
    required this.authorName,
    required this.caption,
    super.shareVersion,
  });

  final String postId;
  final String authorName;
  final String caption;
}

final class ProductShareContent extends ShareContent {
  const ProductShareContent({
    required this.slug,
    required this.productName,
    required this.price,
    super.shareVersion,
  });

  final String slug;
  final String productName;
  final num price;
}

final class ProfileShareContent extends ShareContent {
  const ProfileShareContent({
    required this.username,
    required this.displayName,
    super.shareVersion,
  });

  final String username;
  final String displayName;
}

final class SharePayload {
  const SharePayload({
    required this.url,
    required this.text,
    this.subject,
  });

  final Uri url;
  final String text;
  final String? subject;
}
