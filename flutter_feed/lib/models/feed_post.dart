// Mirror of prisma/schema.prisma:681-775 (FeedPost)
// Plus FeedPostProduct (782-799) embedded as taggedProducts list.

enum FeedPostKind { videoOnly, productOnly, videoProduct, promo, community }

enum FeedPostTab { rekomendasi, promo, komunitas }

enum FeedPostStatus { pendingReview, active, rejected, hidden }

enum FeedAuthorRole { admin, customer }

enum FeedEncodingStatus { uploading, processing, ready, failed }

class FeedPostProduct {
  final String productId;
  final int position;
  final int? promoPrice;
  final String? productName;
  final String? productImageUrl;
  final int? productBasePrice;

  const FeedPostProduct({
    required this.productId,
    required this.position,
    this.promoPrice,
    this.productName,
    this.productImageUrl,
    this.productBasePrice,
  });

  factory FeedPostProduct.fromJson(Map<String, dynamic> json) =>
      FeedPostProduct(
        productId: json['productId'] as String,
        position: json['position'] as int,
        promoPrice: json['promoPrice'] as int?,
        productName: json['productName'] as String?,
        productImageUrl: json['productImageUrl'] as String?,
        productBasePrice: json['productBasePrice'] as int?,
      );
}

class FeedPost {
  final String id;
  final String authorId;
  final String? authorName;
  final String? authorAvatarUrl;
  final FeedAuthorRole authorRole;

  final FeedPostKind kind;
  final FeedPostTab tab;
  final FeedPostStatus status;

  final String? title;
  final String? description;

  // Video fields
  final String? videoUrl;          // MP4 or m3u8 (Bunny CDN)
  final String? videoMimeType;
  final int? videoSizeBytes;
  final double? videoDurationSec;
  final int? videoWidth;
  final int? videoHeight;
  final String? thumbnailUrl;
  final String? thumbnailBlurhash; // Wave 2 LQIP (~30 byte)

  // Bunny integration
  final String? videoGuid;
  final FeedEncodingStatus? encodingStatus;

  // Promo fields (PROMO kind)
  final int? promoOriginalPrice;
  final int? promoDiscountPrice;
  final DateTime? promoStartsAt;
  final DateTime? promoEndsAt;

  // Engagement (denormalized)
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final int shareCount;

  final bool viewerLiked; // computed server-side via session

  final List<FeedPostProduct> taggedProducts;

  final DateTime? publishedAt;
  final DateTime createdAt;

  const FeedPost({
    required this.id,
    required this.authorId,
    this.authorName,
    this.authorAvatarUrl,
    required this.authorRole,
    required this.kind,
    required this.tab,
    required this.status,
    this.title,
    this.description,
    this.videoUrl,
    this.videoMimeType,
    this.videoSizeBytes,
    this.videoDurationSec,
    this.videoWidth,
    this.videoHeight,
    this.thumbnailUrl,
    this.thumbnailBlurhash,
    this.videoGuid,
    this.encodingStatus,
    this.promoOriginalPrice,
    this.promoDiscountPrice,
    this.promoStartsAt,
    this.promoEndsAt,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.shareCount = 0,
    this.viewerLiked = false,
    this.taggedProducts = const [],
    this.publishedAt,
    required this.createdAt,
  });

  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;
  bool get isHls => videoUrl?.endsWith('.m3u8') ?? false;
  bool get isReady => encodingStatus == FeedEncodingStatus.ready;

  FeedPost copyWith({
    int? likeCount,
    int? commentCount,
    int? shareCount,
    bool? viewerLiked,
  }) => FeedPost(
        id: id,
        authorId: authorId,
        authorName: authorName,
        authorAvatarUrl: authorAvatarUrl,
        authorRole: authorRole,
        kind: kind,
        tab: tab,
        status: status,
        title: title,
        description: description,
        videoUrl: videoUrl,
        videoMimeType: videoMimeType,
        videoSizeBytes: videoSizeBytes,
        videoDurationSec: videoDurationSec,
        videoWidth: videoWidth,
        videoHeight: videoHeight,
        thumbnailUrl: thumbnailUrl,
        thumbnailBlurhash: thumbnailBlurhash,
        videoGuid: videoGuid,
        encodingStatus: encodingStatus,
        promoOriginalPrice: promoOriginalPrice,
        promoDiscountPrice: promoDiscountPrice,
        promoStartsAt: promoStartsAt,
        promoEndsAt: promoEndsAt,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        viewCount: viewCount,
        shareCount: shareCount ?? this.shareCount,
        viewerLiked: viewerLiked ?? this.viewerLiked,
        taggedProducts: taggedProducts,
        publishedAt: publishedAt,
        createdAt: createdAt,
      );

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    return FeedPost(
      id: json['id'] as String,
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String?,
      authorAvatarUrl: json['authorAvatarUrl'] as String?,
      authorRole: _parseAuthorRole(json['authorRole'] as String?),
      kind: _parseKind(json['kind'] as String?),
      tab: _parseTab(json['tab'] as String?),
      status: _parseStatus(json['status'] as String?),
      title: json['title'] as String?,
      description: json['description'] as String?,
      videoUrl: json['videoUrl'] as String?,
      videoMimeType: json['videoMimeType'] as String?,
      videoSizeBytes: (json['videoSizeBytes'] as num?)?.toInt(),
      videoDurationSec: (json['videoDurationSec'] as num?)?.toDouble(),
      videoWidth: (json['videoWidth'] as num?)?.toInt(),
      videoHeight: (json['videoHeight'] as num?)?.toInt(),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      thumbnailBlurhash: json['thumbnailBlurhash'] as String?,
      videoGuid: json['videoGuid'] as String?,
      encodingStatus: _parseEncodingStatus(json['encodingStatus'] as String?),
      promoOriginalPrice: (json['promoOriginalPrice'] as num?)?.toInt(),
      promoDiscountPrice: (json['promoDiscountPrice'] as num?)?.toInt(),
      promoStartsAt: _parseDate(json['promoStartsAt']),
      promoEndsAt: _parseDate(json['promoEndsAt']),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      shareCount: (json['shareCount'] as num?)?.toInt() ?? 0,
      viewerLiked: (json['viewerLiked'] as bool?) ?? false,
      taggedProducts: ((json['taggedProducts'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(FeedPostProduct.fromJson)
          .toList(),
      publishedAt: _parseDate(json['publishedAt']),
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
    );
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

FeedAuthorRole _parseAuthorRole(String? s) {
  switch (s) {
    case 'ADMIN':
      return FeedAuthorRole.admin;
    default:
      return FeedAuthorRole.customer;
  }
}

FeedPostKind _parseKind(String? s) {
  switch (s) {
    case 'VIDEO_ONLY':
      return FeedPostKind.videoOnly;
    case 'PRODUCT_ONLY':
      return FeedPostKind.productOnly;
    case 'VIDEO_PRODUCT':
      return FeedPostKind.videoProduct;
    case 'PROMO':
      return FeedPostKind.promo;
    case 'COMMUNITY':
    default:
      return FeedPostKind.community;
  }
}

FeedPostTab _parseTab(String? s) {
  switch (s) {
    case 'PROMO':
      return FeedPostTab.promo;
    case 'KOMUNITAS':
      return FeedPostTab.komunitas;
    case 'REKOMENDASI':
    default:
      return FeedPostTab.rekomendasi;
  }
}

FeedPostStatus _parseStatus(String? s) {
  switch (s) {
    case 'PENDING_REVIEW':
      return FeedPostStatus.pendingReview;
    case 'REJECTED':
      return FeedPostStatus.rejected;
    case 'HIDDEN':
      return FeedPostStatus.hidden;
    case 'ACTIVE':
    default:
      return FeedPostStatus.active;
  }
}

FeedEncodingStatus? _parseEncodingStatus(String? s) {
  switch (s) {
    case 'ready':
      return FeedEncodingStatus.ready;
    case 'processing':
      return FeedEncodingStatus.processing;
    case 'failed':
      return FeedEncodingStatus.failed;
    case 'uploading':
      return FeedEncodingStatus.uploading;
    default:
      return null;
  }
}
