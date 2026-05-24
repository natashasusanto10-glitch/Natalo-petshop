/// Models untuk feed module — port dari Prisma FeedPost + relations.

class FeedAuthor {
  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String? profilePhotoUrl;
  final String role;
  final bool isAdmin;
  final bool isOfficial;

  const FeedAuthor({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
    this.profilePhotoUrl,
    this.role = 'CUSTOMER',
    this.isAdmin = false,
    this.isOfficial = false,
  });

  bool get isOfficialAccount => isAdmin || isOfficial;

  String get displayName => isOfficialAccount ? 'Natalo Petshop' : name;

  /// Public handle untuk feed/komentar header — `@username` kalau set,
  /// fallback `displayName`. Official account selalu skip @ (brand
  /// "Natalo Petshop" tampil sebagai-is). Match IG/TikTok pattern.
  String get displayHandle {
    if (isOfficialAccount) return displayName;
    final u = username;
    return (u != null && u.isNotEmpty) ? '@$u' : name;
  }

  bool get hasUsername =>
      !isOfficialAccount && username != null && username!.isNotEmpty;

  factory FeedAuthor.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatarUrl'] as String?;
    final photo = json['profilePhotoUrl'] as String?;
    final role = (json['role'] as String?) ?? 'CUSTOMER';
    return FeedAuthor(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'User',
      username: json['username'] as String?,
      avatarUrl: avatar ?? photo,
      profilePhotoUrl: photo ?? avatar,
      role: role,
      isAdmin: json['isAdmin'] as bool? ?? (role.toUpperCase() == 'ADMIN'),
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
  // Social proof — dipakai di Feed video product flow (popup preview +
  // bottom sheet card). Default 0 untuk backward-compat kalau backend
  // belum kirim (old client / API rollback). UI hide section kalau 0.
  final double avgRating;
  final int reviewCount;
  final int soldCount;

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
    this.avgRating = 0,
    this.reviewCount = 0,
    this.soldCount = 0,
  });

  bool get isAvailable => isActive && stock > 0;

  /// Diskon aktif → tampilkan badge "Diskon X%" + harga coret di UI.
  bool get hasActiveDiscount {
    final discount = discountPrice;
    final promo = promoPrice;
    final cheapest = [
      if (discount != null && discount > 0) discount,
      if (promo != null && promo > 0) promo,
    ].fold<int?>(null, (acc, v) => acc == null || v < acc ? v : acc);
    return cheapest != null && cheapest < price && price > 0;
  }

  /// Persentase diskon (1-99) — return 0 kalau no discount aktif.
  int get discountPercent {
    if (!hasActiveDiscount) return 0;
    final discount = discountPrice;
    final promo = promoPrice;
    final cheapest = [
      if (discount != null && discount > 0) discount,
      if (promo != null && promo > 0) promo,
    ].fold<int?>(null, (acc, v) => acc == null || v < acc ? v : acc)!;
    return (((price - cheapest) / price) * 100).round().clamp(1, 99);
  }

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
      avgRating: (json['avgRating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      soldCount: (json['soldCount'] as num?)?.toInt() ?? 0,
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

  /// FeedMedia rows untuk PHOTO_CAROUSEL post — 1-8 foto ordered by
  /// sortOrder. Empty untuk VIDEO_ONLY / VIDEO_PRODUCT / COMMUNITY (video
  /// pakai videoUrl + thumbnailUrl).
  final List<FeedMedia> media;

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
    this.media = const [],
  });

  /// Detect PHOTO_CAROUSEL post — render harus pakai _PhotoCarouselPostView,
  /// bukan _FeedPostView (yang assume video controller). Defensive cek media
  /// non-empty supaya gak crash kalau backend bug return PHOTO_CAROUSEL
  /// tanpa media (mis. legacy data atau partial migration).
  bool get isPhotoCarousel => kind == 'PHOTO_CAROUSEL' && media.isNotEmpty;

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
    final videoProductsJson =
        (json['productsInVideo'] as List?) ?? productsJson;
    final productsInVideo = videoProductsJson
        .whereType<Map<String, dynamic>>()
        .map((p) => FeedProductLink.fromJson(
              p['product'] is Map<String, dynamic>
                  ? p['product'] as Map<String, dynamic>
                  : p,
            ))
        .toList();
    final taggedProductsJson =
        (json['taggedProducts'] as List?) ?? productsJson;
    final taggedProducts = taggedProductsJson
        .whereType<Map<String, dynamic>>()
        .map((p) => FeedProductLink.fromJson(
              p['product'] is Map<String, dynamic>
                  ? p['product'] as Map<String, dynamic>
                  : p,
            ))
        .toList();
    final liked =
        json['viewerLiked'] as bool? ?? json['isLiked'] as bool? ?? false;
    final blurhash = (json['thumbnailBlurhash'] ?? json['blurhash']) as String?;
    final mediaJson = (json['media'] as List?) ?? const [];
    final media = mediaJson
        .whereType<Map<String, dynamic>>()
        .map(FeedMedia.fromJson)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
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
      media: media,
    );
  }
}

/// 1 row dari FeedMedia table — image (atau future video) yang di-tag ke
/// FeedPost. Saat ini hanya image yang dipakai untuk PHOTO_CAROUSEL.
class FeedMedia {
  final String id;
  final String mediaType; // "image" | "video"
  final String url;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final int sortOrder;

  const FeedMedia({
    required this.id,
    required this.mediaType,
    required this.url,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.sortOrder = 0,
  });

  /// Aspect ratio untuk pre-compute layout sebelum image fully load. Default
  /// 1:1 (square) supaya gak ada layout shift kalau width/height null.
  double get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 1.0;
    return w / h;
  }

  factory FeedMedia.fromJson(Map<String, dynamic> json) {
    return FeedMedia(
      id: (json['id'] as String?) ?? '',
      mediaType: (json['mediaType'] as String?) ?? 'image',
      url: (json['url'] as String?) ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Cursor-paginated feed page.
class FeedPage {
  final List<FeedPost> items;
  final String? nextCursor;

  const FeedPage({this.items = const [], this.nextCursor});
}
