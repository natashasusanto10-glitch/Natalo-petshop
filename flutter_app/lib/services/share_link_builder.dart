import '../config/api_config.dart';
import '../models/share_content.dart';
import '../utils/formatters.dart';

/// Forms public, production deep links for the native system share sheet.
/// It deliberately has no Flutter context, state mutation, or network work.
class ShareLinkBuilder {
  const ShareLinkBuilder({this.baseUrl = ApiConfig.publicSiteUrl});

  final String baseUrl;

  SharePayload build(ShareContent content) {
    return switch (content) {
      FeedShareContent feed => _feed(feed),
      ProductShareContent product => _product(product),
      ProfileShareContent profile => _profile(profile),
    };
  }

  SharePayload _feed(FeedShareContent content) {
    final url = _uri(['feed', content.postId], content.shareVersion);
    final authorName = _safeLabel(content.authorName, fallback: 'Natalo');
    return SharePayload(
      url: url,
      subject: 'Postingan $authorName di Natalo',
      text: 'Lihat postingan $authorName di Natalo.\n${url.toString()}',
    );
  }

  SharePayload _product(ProductShareContent content) {
    final url = _uri(['products', content.slug], content.shareVersion);
    final productName =
        _safeLabel(content.productName, fallback: 'Produk Natalo');
    return SharePayload(
      url: url,
      subject: '$productName | Natalo Petshop',
      text:
          'Temukan $productName seharga ${formatRupiah(content.price)} di Natalo Petshop.\n${url.toString()}',
    );
  }

  SharePayload _profile(ProfileShareContent content) {
    final username = content.username.trim().toLowerCase();
    final url = _uri(['u', username], content.shareVersion);
    final displayName = _safeLabel(content.displayName, fallback: username);
    return SharePayload(
      url: url,
      subject: '$displayName di Natalo',
      text:
          'Lihat profil $displayName (@$username) di Natalo.\n${url.toString()}',
    );
  }

  Uri _uri(List<String> segments, String? version) {
    final base = Uri.parse(baseUrl);
    final cleanVersion = version?.trim();
    return base.replace(
      pathSegments: [...base.pathSegments, ...segments],
      queryParameters: cleanVersion == null || cleanVersion.isEmpty
          ? null
          : {'v': cleanVersion},
    );
  }

  String _safeLabel(String value, {required String fallback}) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.isEmpty ? fallback : normalized;
  }
}
