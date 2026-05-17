/// Models untuk feed module — port dari Prisma FeedPost + relations.

class FeedAuthor {
  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String? profilePhotoUrl;
  final bool isAdmin;
  final bool isOfficial;

  const FeedAuthor({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
    this.profilePhotoUrl,
    this.isAdmin = false,
    this.isOfficial = false,
  });

  factory FeedAuthor.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatarUrl'] as String?;
    final photo = json['profilePhotoUrl'] as String?;
    return FeedAuthor(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'User',
      username: json['username'] as String?,
      avatarUrl: avatar ?? photo,
      profilePhotoUrl: photo ?? avatar,
      isAdmin: json['isAdmin'] as bool? ??
          (json['role']?.toString().toUpperCase() == 'ADMIN'),
      isOfficial: json['isOfficial'] as bool? ?? false,
    );
  }
}

class FeedProductLink {
  final String id;
  final String slug;
  final String name;
  final String? imageUrl;
  final int price;
  final int? discountPrice;
  final int? promoPrice;
  final int stock;
  final int weightGram;
  final bool hasVariants;
  final bool isActive;

  const FeedProductLink({
    required this.id,
    required this.slug,
    required this.name,
    this.imageUrl,
    required this.price,
    this.discountPrice,
    this.promoPrice,
    this.stock = 0,
    this.weightGram = 500,
    this.hasVariants = false,
    this.isActive = true,
  });

  bool get isAvailable => isActive && stock > 0;

  factory FeedProductLink.fromJson(Map<String, dynamic> json) {
    return FeedProductLink(
      id: json['id'] as String,
      slug: json['slug'] as String? ?? '',
      name: (json['name'] ?? json['title']) as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      price: (json['price'] as num?)?.toInt() ?? 0,
      discountPrice: (json['discountPrice'] as num?)?.toInt(),
      promoPrice: (json['promoPrice'] as num?)?.toInt(),
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      weightGram: (json['weightGram'] as num?)?.toInt() ?? 500,
      hasVariants: json['hasVariants'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

/// Single feed post — video/image dengan optional product tags + author.
class FeedPost {
  final String id;
  final String slug;
  /// Non-nullable — default '' supaya screen yang akses `.isNotEmpty` aman.
  final String title;
  final String description;
  final String? caption;
  final String videoUrl;
  final String? thumbnailUrl;
  final String? blurhash;
  final String? thumbnailBlurhash;
  final int durationSec;
  final double aspectRatio;
  final int videoWidth;
  final int videoHeight;
  final String kind;
  final FeedAuthor author;
  final List<FeedProductLink> products;
  final List<FeedProductLink> productsInVideo;
  final List<FeedProductLink> taggedProducts;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final int shareCount;
  final bool isLiked;
  final bool viewerLiked;
  final DateTime createdAt;

  const FeedPost({
    required this.id,
    required this.slug,
    this.title = '',
    this.description = '',
    this.caption,
    required this.videoUrl,
    this.thumbnailUrl,
    this.blurhash,
    this.thumbnailBlurhash,
    this.durationSec = 0,
    this.aspectRatio = 9 / 16,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.kind = 'USER_VIDEO',
    required this.author,
    this.products = const [],
    this.productsInVideo = const [],
    this.taggedProducts = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.shareCount = 0,
    this.isLiked = false,
    this.viewerLiked = false,
    required this.createdAt,
  });

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    final productsJson = (json['products'] as List?) ??
        (json['feedPostProducts'] as List?) ??
        const [];
    final products = productsJson
        .whereType<Map<String, dynamic>>()
        .map((p) => FeedProductLink.fromJson(
              p['product'] is Map<String, dynamic>
                  ? p['product'] as Map<String, dynamic>
                  : p,
            ))
        .toList();
    final videoProductsJson = (json['productsInVideo'] as List?) ?? productsJson;
    final productsInVideo = videoProductsJson
        .whereType<Map<String, dynamic>>()
        .map((p) => FeedProductLink.fromJson(
              p['product'] is Map<String, dynamic>
                  ? p['product'] as Map<String, dynamic>
                  : p,
            ))
        .toList();
    final taggedProductsJson = (json['taggedProducts'] as List?) ?? productsJson;
    final taggedProducts = taggedProductsJson
        .whereType<Map<String, dynamic>>()
        .map((p) => FeedProductLink.fromJson(
              p['product'] is Map<String, dynamic>
                  ? p['product'] as Map<String, dynamic>
                  : p,
            ))
        .toList();
    final liked = json['viewerLiked'] as bool? ?? json['isLiked'] as bool? ?? false;
    final blurhash =
        (json['thumbnailBlurhash'] ?? json['blurhash']) as String?;
    return FeedPost(
      id: json['id'] as String,
      slug: (json['slug'] ?? json['id']) as String,
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      caption: json['caption'] as String?,
      videoUrl: (json['videoUrl'] ?? json['mediaUrl']) as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      blurhash: blurhash,
      thumbnailBlurhash: blurhash,
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      aspectRatio: (json['aspectRatio'] as num?)?.toDouble() ?? (9 / 16),
      videoWidth: (json['videoWidth'] as num?)?.toInt() ?? 0,
      videoHeight: (json['videoHeight'] as num?)?.toInt() ?? 0,
      kind: json['kind'] as String? ?? 'USER_VIDEO',
      author: json['author'] is Map<String, dynamic>
          ? FeedAuthor.fromJson(json['author'] as Map<String, dynamic>)
          : const FeedAuthor(id: '', name: 'User'),
      products: products,
      productsInVideo: productsInVideo,
      taggedProducts: taggedProducts,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      shareCount: (json['shareCount'] as num?)?.toInt() ?? 0,
      isLiked: liked,
      viewerLiked: liked,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Cursor-paginated feed page.
class FeedPage {
  final List<FeedPost> items;
  final String? nextCursor;

  const FeedPage({this.items = const [], this.nextCursor});
}
