import '../config/api_config.dart';

/// Public feed post — match response API GET /api/feed/posts.
/// Beda dengan MyFeedPost (yang scope user-owned), FeedPost dipakai untuk
/// public feed timeline (TikTok-style fullscreen video feed).
class FeedPost {
  final String id;
  final String kind;
  final String tab;
  final String status;
  final String title;
  final String? description;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? thumbnailBlurhash;
  final int? videoDurationSec;
  final int? videoWidth;
  final int? videoHeight;
  final FeedAuthor author;
  final FeedProductLink? product;
  final List<FeedProductLink> taggedProducts;
  final FeedPromo? promo;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final int shareCount;
  final bool viewerLiked;
  final DateTime? publishedAt;
  final DateTime createdAt;

  const FeedPost({
    required this.id,
    required this.kind,
    required this.tab,
    required this.status,
    required this.title,
    this.description,
    this.videoUrl,
    this.thumbnailUrl,
    this.thumbnailBlurhash,
    this.videoDurationSec,
    this.videoWidth,
    this.videoHeight,
    required this.author,
    this.product,
    this.taggedProducts = const [],
    this.promo,
    required this.likeCount,
    required this.commentCount,
    required this.viewCount,
    required this.shareCount,
    required this.viewerLiked,
    this.publishedAt,
    required this.createdAt,
  });

  factory FeedPost.fromApiJson(Map<String, dynamic> json) {
    final video = (json['videoUrl'] ?? '').toString();
    final thumb = (json['thumbnailUrl'] ?? '').toString();
    final author = json['author'] is Map<String, dynamic>
        ? FeedAuthor.fromJson(json['author'] as Map<String, dynamic>)
        : const FeedAuthor(id: '', name: 'Natalo', role: 'CUSTOMER');
    final productJson = json['product'];
    final taggedJson = json['taggedProducts'];
    final promoJson = json['promo'];
    final product = productJson is Map<String, dynamic>
        ? FeedProductLink.fromJson(productJson)
        : null;
    final taggedProducts = taggedJson is List
        ? taggedJson
            .whereType<Map<String, dynamic>>()
            .map(FeedProductLink.fromJson)
            .toList()
        : <FeedProductLink>[];
    return FeedPost(
      id: (json['id'] ?? '').toString(),
      kind: (json['kind'] ?? 'VIDEO_ONLY').toString(),
      tab: (json['tab'] ?? 'REKOMENDASI').toString(),
      status: (json['status'] ?? 'ACTIVE').toString(),
      title: (json['title'] ?? '').toString(),
      description: json['description']?.toString(),
      videoUrl: video.isEmpty ? null : _absoluteUrl(video),
      thumbnailUrl: thumb.isEmpty ? null : _absoluteUrl(thumb),
      thumbnailBlurhash: _nullableString(json['thumbnailBlurhash']),
      videoDurationSec: _nullableInt(json['videoDurationSec']),
      videoWidth: _nullableInt(json['videoWidth']),
      videoHeight: _nullableInt(json['videoHeight']),
      author: author,
      product: product,
      taggedProducts: taggedProducts.isNotEmpty
          ? taggedProducts
          : [if (product != null) product],
      promo: promoJson is Map<String, dynamic>
          ? FeedPromo.fromJson(promoJson)
          : null,
      likeCount: _asInt(json['likeCount']),
      commentCount: _asInt(json['commentCount']),
      viewCount: _asInt(json['viewCount']),
      shareCount: _asInt(json['shareCount']),
      viewerLiked: json['viewerLiked'] == true,
      publishedAt: DateTime.tryParse((json['publishedAt'] ?? '').toString()),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;
  List<FeedProductLink> get productsInVideo => taggedProducts;
}

class FeedAuthor {
  final String id;
  final String name;
  final String role; // "ADMIN" | "CUSTOMER"
  final String? profilePhotoUrl;

  const FeedAuthor({
    required this.id,
    required this.name,
    required this.role,
    this.profilePhotoUrl,
  });

  factory FeedAuthor.fromJson(Map<String, dynamic> json) {
    final photo = _nullableString(
      json['profilePhotoUrl'] ??
          json['profile_photo_url'] ??
          json['avatarUrl'] ??
          json['avatar_url'] ??
          json['imageUrl'] ??
          json['image_url'],
    );
    return FeedAuthor(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Pengguna Natalo').toString(),
      role: (json['role'] ?? 'CUSTOMER').toString(),
      profilePhotoUrl: photo == null ? null : _absoluteUrl(photo),
    );
  }

  bool get isAdmin => role == 'ADMIN';
}

class FeedProductLink {
  final String id;
  final String slug;
  final String name;
  final double price;
  final double? discountPrice;
  final double? promoPrice;
  final int stock;
  final int weightGram;
  final bool isAvailable;
  final bool hasVariants;
  final int position;
  final String? imageUrl;

  const FeedProductLink({
    required this.id,
    required this.slug,
    required this.name,
    required this.price,
    this.discountPrice,
    this.promoPrice,
    required this.stock,
    this.weightGram = 500,
    this.isAvailable = true,
    this.hasVariants = false,
    this.position = 0,
    this.imageUrl,
  });

  factory FeedProductLink.fromJson(Map<String, dynamic> json) {
    return FeedProductLink(
      id: (json['id'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      name: (json['name'] ?? 'Produk').toString(),
      price: _asDouble(json['price']),
      discountPrice: _nullableDouble(json['discountPrice']),
      promoPrice: _nullableDouble(json['promoPrice']),
      stock: _asInt(json['stock']),
      weightGram:
          _asInt(json['weightGram']) == 0 ? 500 : _asInt(json['weightGram']),
      isAvailable: json['isAvailable'] != false,
      hasVariants: json['hasVariants'] == true,
      position: _asInt(json['position']),
      imageUrl: (json['imageUrl'] ?? '').toString().isEmpty
          ? null
          : _absoluteUrl(json['imageUrl'].toString()),
    );
  }
}

class FeedPromo {
  final double originalPrice;
  final double discountPrice;

  const FeedPromo({
    required this.originalPrice,
    required this.discountPrice,
  });

  factory FeedPromo.fromJson(Map<String, dynamic> json) {
    return FeedPromo(
      originalPrice: _asDouble(json['originalPrice']),
      discountPrice: _asDouble(json['discountPrice']),
    );
  }
}

class FeedPage {
  final List<FeedPost> items;
  final String? nextCursor;

  const FeedPage({required this.items, this.nextCursor});

  static const empty = FeedPage(items: [], nextCursor: null);
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http')) return url;
  final base = Uri.parse(ApiConfig.baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}
