import '../config/api_config.dart';

/// Kategori produk untuk section "Kategori Populer" di Home.
/// Match response API PWA GET /api/categories.
class HomeCategory {
  final String id;
  final String name;
  final String slug;
  final int productCount;
  /// URL gambar produk pertama di kategori — dipakai sebagai thumbnail
  /// kategori di Home. Kalau null, fallback ke icon Material.
  final String? imageUrl;

  const HomeCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.productCount,
    this.imageUrl,
  });

  factory HomeCategory.fromApiJson(Map<String, dynamic> json) {
    final imageRaw = (json['imageUrl'] ?? '').toString();
    final image = imageRaw.isEmpty
        ? null
        : (imageRaw.startsWith('http') || imageRaw.startsWith('data:'))
            ? imageRaw
            : _absoluteUrl(imageRaw);
    final countRaw = json['productCount'];
    final count = countRaw is int
        ? countRaw
        : countRaw is num
            ? countRaw.round()
            : int.tryParse(countRaw?.toString() ?? '') ?? 0;
    return HomeCategory(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      productCount: count,
      imageUrl: image,
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
