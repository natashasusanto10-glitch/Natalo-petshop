import '../config/api_config.dart';

/// Hero banner untuk Home — match response API PWA GET /api/banners.
/// Saat ini cuma support type 'image' (content banner di-flatten ke
/// fields umum, dijaga tipe-nya supaya bisa render basic).
class HomeBanner {
  final String id;
  /// Image URL absolute (resolved via ApiConfig.baseUrl untuk path relatif).
  final String imageUrl;
  /// Alt text — dipakai untuk accessibility + fallback display.
  final String imageAlt;
  /// Deep link target (mis. `/products?kategori=ikan`). Null = no action.
  final String? href;

  const HomeBanner({
    required this.id,
    required this.imageUrl,
    required this.imageAlt,
    this.href,
  });

  factory HomeBanner.fromApiJson(Map<String, dynamic> json) {
    final imageRaw = (json['image'] ?? '').toString();
    return HomeBanner(
      id: (json['id'] ?? '').toString(),
      imageUrl: _absoluteUrl(imageRaw),
      imageAlt: (json['imageAlt'] ?? '').toString(),
      href: (json['href']?.toString().trim().isEmpty ?? true)
          ? null
          : json['href'].toString(),
    );
  }
}

String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http')) return url;
  final base = Uri.parse(ApiConfig.baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}
