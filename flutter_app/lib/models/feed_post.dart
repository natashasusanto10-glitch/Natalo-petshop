/// Models untuk feed module — port dari Prisma FeedPost + relations.
///
/// **UNIFIED MODEL (post-total-rewrite untuk like/comment sync):**
/// FeedPost adalah single source of truth untuk semua feed-related screen
/// (Feed/Reels, Detail Postingan, Postingan Saya, Public Profile). Schema
/// adalah superset gabungan kebutuhan reels (video + products) DAN owner
/// moderation pipeline (status, rejection reason, approvedAt).
///
/// Dipakai oleh:
///   - /api/feed/posts        (reels feed)
///   - /api/feed/my-posts     (postingan saya grid)
///   - /api/u/{username}      (public profile grid)
///   - /api/feed/posts/{id}   (single post detail)
///
/// MyFeedPost legacy class sudah di-delete — semua callers pakai FeedPost.

import '../constants/official_brand.dart';

class FeedAuthor {
  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String? profilePhotoUrl;
  final String role;
  final bool isAdmin;
  final bool isOfficial;

  /// Per-viewer: apakah viewer sudah follow author ini — snapshot dari
  /// payload feed saat fetch (server compute batch, anon = false).
  /// Toggle SETELAH fetch di-track terpisah via followOverrides
  /// (state/follow_override_store.dart) supaya konsisten antar post.
  final bool isFollowing;

  const FeedAuthor({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
    this.profilePhotoUrl,
    this.role = 'CUSTOMER',
    this.isAdmin = false,
    this.isOfficial = false,
    this.isFollowing = false,
  });

  bool get isOfficialAccount => isAdmin || isOfficial;

  String get displayName => isOfficialAccount ? kOfficialBrandName : name;

  /// Public handle untuk feed/komentar header — bare `username` kalau
  /// set, fallback ke `displayName`. Official account tampil brand
  /// name. Match IG/TikTok: identity label TIDAK pakai `@` — `@` cuma
  /// muncul saat username dipakai sebagai mention di dalam text body
  /// (lihat MentionText widget + buildMentionSpans helper).
  String get displayHandle {
    if (isOfficialAccount) return displayName;
    final u = username;
    return (u != null && u.isNotEmpty) ? u : name;
  }

  // Official account KINI punya username kanonik brand ("natalopetshop"),
  // jadi profilnya bisa dituju /u/{username} & di-follow — sama seperti
  // user biasa. Server mengembalikan username brand (bukan nama pemilik),
  // jadi tidak ada kebocoran identitas.
  bool get hasUsername => username != null && username!.isNotEmpty;

  String get initial =>
      name.trim().isEmpty ? 'N' : name.trim().substring(0, 1).toUpperCase();

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
      isFollowing: json['isFollowing'] == true,
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

  /// Sumber diskon dari backend (resolveActiveDiscount): 'FLASH_SALE' atau
  /// 'PROMO_TOKO'. null kalau tidak ada diskon aktif. Dipakai untuk label:
  /// Flash Sale → "Flash Sale X%", Promo Toko → "Diskon X%". Tanpa ini app
  /// dulu hardcode "Flash Sale" untuk semua diskon (salah untuk Promo Toko).
  final String? discountSource;
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
    this.discountSource,
    this.stock = 0,
    this.weightGram = 500,
    this.hasVariants = false,
    this.isActive = true,
    this.avgRating = 0,
    this.reviewCount = 0,
    this.soldCount = 0,
  });

  bool get isAvailable => isActive && stock > 0;

  /// True kalau diskon aktif berasal dari Flash Sale (bukan Promo Toko).
  /// Dipakai untuk pilih label badge.
  bool get isFlashSale => discountSource == 'FLASH_SALE';

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
      discountSource: json['discountSource'] as String?,
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

/// Moderation status — owner-only concern (badge di Postingan Saya/Detail
/// owner). Viewer non-owner tidak peduli (kalau post tampil di public
/// endpoint, status pasti PUBLISHED).
enum FeedPostStatus { pending, active, rejected, unknown }

extension FeedPostStatusX on FeedPostStatus {
  String get label {
    return switch (this) {
      FeedPostStatus.active => 'Tayang',
      FeedPostStatus.rejected => 'Ditolak',
      FeedPostStatus.pending => 'Menunggu Review',
      FeedPostStatus.unknown => '-',
    };
  }

  String get description {
    return switch (this) {
      FeedPostStatus.active => 'Sudah tayang di Feed',
      FeedPostStatus.rejected => 'Ditolak oleh admin',
      FeedPostStatus.pending => 'Sedang menunggu review admin',
      FeedPostStatus.unknown => '',
    };
  }
}

/// Tipe konten — derive dari `kind` + media items + duration + URL.
/// Hanya untuk UI rendering choice (video player vs carousel vs image).
enum FeedContentType { photo, carousel, video }

/// Single feed post — superset semua use case (reels + grid + detail +
/// public profile + edit). Fields tertentu hanya relevan untuk owner
/// (status, rejectionReason, approvedAt) — viewer non-owner abaikan.
class FeedPost {
  final String id;
  final String slug;

  /// Non-nullable — default '' supaya screen yang akses `.isNotEmpty` aman.
  final String title;
  final String description;
  final String? caption;

  /// Untuk video kind: source video URL. Untuk photo/carousel: kosong
  /// (gunakan mediaItems.first.mediaUrl).
  final String videoUrl;
  final String? videoDataSaverUrl;
  final String? thumbnailUrl;
  final String? blurhash;
  final String? thumbnailBlurhash;
  final int durationSec;
  final double aspectRatio;
  final int videoWidth;
  final int videoHeight;
  final String? videoAltText;
  final bool? hasAudio;
  final String? subtitleUrl;
  final String? subtitleLanguage;

  /// Kind dari backend: USER_VIDEO / VIDEO_ONLY / VIDEO_PRODUCT / PROMO /
  /// COMMUNITY / PHOTO_CAROUSEL / PHOTO. Drives type detection via
  /// [contentType] getter.
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
  final bool viewerSaved;
  final List<FeedAuthor> recentLikers;
  final DateTime createdAt;

  /// FeedMedia rows ordered by sortOrder. Untuk PHOTO_CAROUSEL = 1-8
  /// foto. Untuk POST tunggal kadang single media item. Empty untuk
  /// pure video post yang pakai videoUrl + thumbnailUrl saja.
  final List<FeedMedia> mediaItems;

  // ───── Moderation fields (owner-only concerns) ─────

  /// Backend status string. Owner pipeline:
  ///   PENDING_REVIEW → PUBLISHED (atau REJECTED)
  /// Public endpoint hanya kembalikan PUBLISHED posts, jadi default
  /// 'PUBLISHED' di fromJson aman untuk viewer-side.
  final String status;
  final String? rejectionReason;
  final DateTime? approvedAt;

  const FeedPost({
    required this.id,
    required this.slug,
    this.title = '',
    this.description = '',
    this.caption,
    required this.videoUrl,
    this.videoDataSaverUrl,
    this.thumbnailUrl,
    this.blurhash,
    this.thumbnailBlurhash,
    this.durationSec = 0,
    this.aspectRatio = 9 / 16,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.videoAltText,
    this.hasAudio,
    this.subtitleUrl,
    this.subtitleLanguage,
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
    this.viewerSaved = false,
    this.recentLikers = const [],
    required this.createdAt,
    this.mediaItems = const [],
    this.status = 'PUBLISHED',
    this.rejectionReason,
    this.approvedAt,
  });

  // ───────── Content type ─────────

  /// Detect PHOTO_CAROUSEL post — render harus pakai _PhotoCarouselPostView,
  /// bukan _FeedPostView (yang assume video controller). Defensive cek media
  /// non-empty supaya gak crash kalau backend bug return PHOTO_CAROUSEL
  /// tanpa media (mis. legacy data atau partial migration).
  bool get isPhotoCarousel => kind == 'PHOTO_CAROUSEL' && mediaItems.isNotEmpty;

  /// Pakai untuk grid render — apakah post ini video (perlu play icon
  /// overlay) atau photo/carousel (langsung thumb).
  FeedContentType get contentType {
    final upper = kind.toUpperCase();
    if (upper == 'PHOTO_CAROUSEL' || upper == 'CAROUSEL') {
      return mediaItems.length > 1
          ? FeedContentType.carousel
          : FeedContentType.photo;
    }
    if (upper == 'PHOTO' || upper == 'IMAGE') return FeedContentType.photo;
    if (upper == 'VIDEO' ||
        upper == 'USER_VIDEO' ||
        upper == 'VIDEO_ONLY' ||
        upper == 'VIDEO_PRODUCT' ||
        upper == 'COMMUNITY' ||
        upper == 'PROMO') {
      return FeedContentType.video;
    }
    // Fallback via heuristics — useful kalau backend variant tak terduga.
    if (mediaItems.any((m) => m.mediaType.toLowerCase() == 'video')) {
      return FeedContentType.video;
    }
    if (mediaItems.length > 1) return FeedContentType.carousel;
    if (durationSec > 0 || _looksLikeVideoUrl(videoUrl)) {
      return FeedContentType.video;
    }
    return FeedContentType.photo;
  }

  bool get isVideo => contentType == FeedContentType.video;
  bool get isCarousel => contentType == FeedContentType.carousel;
  bool get isPhoto => contentType == FeedContentType.photo;

  /// Spoken description for the primary media surface. Explicit alt text
  /// wins; existing user-authored copy remains a useful legacy fallback.
  String get mediaAccessibilityLabel {
    final explicit = videoAltText?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return _withAudioAccessibilityStatus(explicit);
    }
    if (!isVideo && mediaItems.isNotEmpty) {
      final mediaAltText = mediaItems.first.altText?.trim();
      if (mediaAltText != null && mediaAltText.isNotEmpty) {
        return _withAudioAccessibilityStatus(mediaAltText);
      }
    }
    final postCaption = caption?.trim();
    if (postCaption != null && postCaption.isNotEmpty) {
      return _withAudioAccessibilityStatus(postCaption);
    }
    final postDescription = description.trim();
    if (postDescription.isNotEmpty) {
      return _withAudioAccessibilityStatus(postDescription);
    }
    return _withAudioAccessibilityStatus(
      '${isVideo ? 'Video' : 'Foto'} dari ${author.displayHandle}',
    );
  }

  String _withAudioAccessibilityStatus(String label) {
    if (isVideo && hasAudio == false) return '$label. Video tanpa suara.';
    return label;
  }

  /// Thumbnail URL untuk grid tile dengan fallback chain:
  ///   thumbnailUrl → first mediaItem.thumbnailUrl → first mediaItem.mediaUrl
  ///   → videoUrl (last resort)
  ///
  /// **PENTING:** ini untuk PREVIEW/THUMBNAIL (gambar), BUKAN untuk source
  /// video player. Untuk playback video pakai [videoPlaybackUrl] — getter
  /// ini return thumbnailUrl (JPG) duluan, kalau di-feed ke VideoPlayer
  /// akan gagal initialize ("Video belum bisa diputar").
  String get previewMediaUrl {
    final t = thumbnailUrl?.trim();
    if (t != null && t.isNotEmpty) return t;
    for (final m in mediaItems) {
      final mt = m.thumbnailUrl?.trim();
      if (mt != null && mt.isNotEmpty) return mt;
      if (m.mediaUrl.isNotEmpty) return m.mediaUrl;
    }
    return videoUrl;
  }

  /// URL untuk PLAYBACK video (bukan thumbnail). Source untuk
  /// VideoPlayerController / CachedVideoPlayerPlus. Chain:
  ///   videoUrl → first video mediaItem.mediaUrl → first mediaItem.mediaUrl
  ///
  /// Beda dari [previewMediaUrl] yang sengaja thumbnail-first untuk grid.
  /// Bug "Video belum bisa diputar" muncul saat player keliru di-feed
  /// previewMediaUrl (thumbnail JPG) — pakai getter ini untuk video source.
  String get videoPlaybackUrl {
    if (videoUrl.trim().isNotEmpty) return videoUrl;
    for (final m in mediaItems) {
      if (m.isVideo && m.mediaUrl.trim().isNotEmpty) return m.mediaUrl;
    }
    for (final m in mediaItems) {
      if (m.mediaUrl.trim().isNotEmpty) return m.mediaUrl;
    }
    return '';
  }

  String videoPlaybackUrlForQuality(String? qualityPreference) {
    if (qualityPreference == 'data_saver') {
      final dataSaver = videoDataSaverUrl?.trim();
      if (dataSaver != null && dataSaver.isNotEmpty) return dataSaver;
    }
    return videoPlaybackUrl;
  }

  // ───────── Moderation helpers (owner-only) ─────────

  FeedPostStatus get statusInfo {
    return switch (status.toUpperCase()) {
      'ACTIVE' || 'PUBLISHED' => FeedPostStatus.active,
      'REJECTED' => FeedPostStatus.rejected,
      'PENDING_REVIEW' || 'PENDING' => FeedPostStatus.pending,
      _ => FeedPostStatus.unknown,
    };
  }

  bool get isApproved => statusInfo == FeedPostStatus.active;
  bool get isPending => statusInfo == FeedPostStatus.pending;
  bool get isRejected => statusInfo == FeedPostStatus.rejected;

  // ───────── Derived ─────────

  /// Subset product IDs — useful untuk legacy callers yang dulu pakai
  /// MyFeedPost.productIds (list of string).
  List<String> get productIds =>
      products.map((p) => p.id).toList(growable: false);

  /// Whether this post links to at least one product in any supported API
  /// shape. Saved Posts uses this for the "Belanja" tab.
  bool get hasLinkedProducts =>
      products.isNotEmpty ||
      productsInVideo.isNotEmpty ||
      taggedProducts.isNotEmpty;

  /// Duration label mm:ss — dipakai badge video di grid.
  String get durationLabel {
    final total = durationSec.clamp(0, 999999);
    final minutes = total ~/ 60;
    final rest = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }

  /// Aspect width/height int pair — legacy MyFeedPost API.
  /// Derive dari aspectRatio kalau backend tidak include explicit pair.
  int get aspectWidthInt {
    if (videoWidth > 0) return videoWidth;
    return aspectRatio >= 1 ? 16 : 9;
  }

  int get aspectHeightInt {
    if (videoHeight > 0) return videoHeight;
    return aspectRatio >= 1 ? 9 : 16;
  }

  // ───────── copyWith ─────────

  FeedPost copyWith({
    String? id,
    String? slug,
    String? title,
    String? description,
    String? caption,
    String? videoUrl,
    String? videoDataSaverUrl,
    String? thumbnailUrl,
    String? blurhash,
    String? thumbnailBlurhash,
    int? durationSec,
    double? aspectRatio,
    int? videoWidth,
    int? videoHeight,
    String? videoAltText,
    bool? hasAudio,
    String? subtitleUrl,
    String? subtitleLanguage,
    String? kind,
    FeedAuthor? author,
    List<FeedProductLink>? products,
    List<FeedProductLink>? productsInVideo,
    List<FeedProductLink>? taggedProducts,
    int? likeCount,
    int? commentCount,
    int? viewCount,
    int? shareCount,
    bool? isLiked,
    bool? viewerLiked,
    bool? viewerSaved,
    List<FeedAuthor>? recentLikers,
    DateTime? createdAt,
    List<FeedMedia>? mediaItems,
    String? status,
    String? rejectionReason,
    DateTime? approvedAt,
  }) {
    // isLiked dan viewerLiked selalu sinkron — kalau caller cuma kasih
    // satu, pakai itu untuk keduanya.
    final liked = isLiked ?? viewerLiked;
    return FeedPost(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      title: title ?? this.title,
      description: description ?? this.description,
      caption: caption ?? this.caption,
      videoUrl: videoUrl ?? this.videoUrl,
      videoDataSaverUrl: videoDataSaverUrl ?? this.videoDataSaverUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      blurhash: blurhash ?? this.blurhash,
      thumbnailBlurhash: thumbnailBlurhash ?? this.thumbnailBlurhash,
      durationSec: durationSec ?? this.durationSec,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      videoAltText: videoAltText ?? this.videoAltText,
      hasAudio: hasAudio ?? this.hasAudio,
      subtitleUrl: subtitleUrl ?? this.subtitleUrl,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      kind: kind ?? this.kind,
      author: author ?? this.author,
      products: products ?? this.products,
      productsInVideo: productsInVideo ?? this.productsInVideo,
      taggedProducts: taggedProducts ?? this.taggedProducts,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      shareCount: shareCount ?? this.shareCount,
      isLiked: liked ?? this.isLiked,
      viewerLiked: liked ?? this.viewerLiked,
      viewerSaved: viewerSaved ?? this.viewerSaved,
      recentLikers: recentLikers ?? this.recentLikers,
      createdAt: createdAt ?? this.createdAt,
      mediaItems: mediaItems ?? this.mediaItems,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      approvedAt: approvedAt ?? this.approvedAt,
    );
  }

  // ───────── JSON ─────────

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
    final liked = json['isLikedByMe'] as bool? ??
        json['viewerLiked'] as bool? ??
        json['isLiked'] as bool? ??
        false;
    final blurhash = (json['thumbnailBlurhash'] ?? json['blurhash']) as String?;

    // mediaItems: accept BOTH `mediaItems` (newer my-posts/public profile
    // shape) AND `media` (existing reels feed shape).
    final mediaJson =
        (json['mediaItems'] as List?) ?? (json['media'] as List?) ?? const [];
    final mediaItems = mediaJson
        .whereType<Map<String, dynamic>>()
        .map(FeedMedia.fromJson)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final recentLikersJson = json['recentLikers'] as List? ?? const [];
    final recentLikers = recentLikersJson
        .whereType<Map<String, dynamic>>()
        .map(FeedAuthor.fromJson)
        .where((liker) => liker.id.isNotEmpty)
        .toList();

    // kind: accept `kind` (reels) atau derive dari `type` (my-posts) atau
    // fallback ke USER_VIDEO. type field di my-posts: 'video' | 'photo' |
    // 'carousel' atau uppercase variant.
    final rawKind = json['kind'] as String?;
    final rawType = (json['type'] as String?)?.toUpperCase();
    final kind = rawKind ??
        (rawType == 'CAROUSEL' || rawType == 'PHOTO_CAROUSEL'
            ? 'PHOTO_CAROUSEL'
            : rawType == 'PHOTO' || rawType == 'IMAGE'
                ? 'PHOTO'
                : rawType == 'VIDEO'
                    ? 'USER_VIDEO'
                    : 'USER_VIDEO');

    // aspectRatio: prefer explicit aspectRatio double; else derive dari
    // aspectWidth/aspectHeight pair (my-posts shape); else fallback ke
    // width/height media item pertama — beberapa shape (mis. my-posts lama)
    // taruh dimensi video di mediaItems, bukan di post-level. Tanpa fallback
    // ini video landscape jatuh ke default 9/16 (portrait) → grid gagal
    // letterbox (lihat gridShowsLetterbox di gallery_post_tile.dart).
    final firstMedia = mediaItems.isNotEmpty ? mediaItems.first : null;
    final aspectRatio = (json['aspectRatio'] as num?)?.toDouble() ??
        _aspectFromIntPair(
          (json['aspectWidth'] as num?)?.toInt(),
          (json['aspectHeight'] as num?)?.toInt(),
        ) ??
        _aspectFromIntPair(firstMedia?.width, firstMedia?.height) ??
        (9 / 16);

    // duration: accept `durationSec` ATAU `videoDurationSec`.
    final durationSec = (json['durationSec'] as num?)?.toInt() ??
        (json['videoDurationSec'] as num?)?.toInt() ??
        0;

    // status default PUBLISHED — backend public endpoints (feed list,
    // public profile) tidak include status, dan post yang tampil di sana
    // sudah PUBLISHED toh.
    final status = (json['status'] as String?) ?? 'PUBLISHED';

    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw const FormatException('FeedPost.id missing in API response');
    }

    return FeedPost(
      id: id,
      slug: (json['slug'] ?? json['id']) as String? ?? id,
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      // Fallback chain — backend TIDAK kirim field `caption` (cuma
      // `description` full + `title` truncated). description = caption
      // penuh yang user tulis, prefer itu; title fallback terakhir.
      // Tanpa fallback ini post.caption selalu null → caption hilang di
      // Detail Postingan + edit box mulai kosong (regresi unify FeedPost).
      caption: _firstNonEmpty([
        json['caption'] as String?,
        json['description'] as String?,
        json['title'] as String?,
      ]),
      videoUrl: (json['videoUrl'] ?? json['mediaUrl']) as String? ?? '',
      videoDataSaverUrl: json['videoDataSaverUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      blurhash: blurhash,
      thumbnailBlurhash: blurhash,
      durationSec: durationSec,
      aspectRatio: aspectRatio,
      videoWidth: (json['videoWidth'] as num?)?.toInt() ??
          (json['aspectWidth'] as num?)?.toInt() ??
          0,
      videoHeight: (json['videoHeight'] as num?)?.toInt() ??
          (json['aspectHeight'] as num?)?.toInt() ??
          0,
      videoAltText: _firstNonEmpty([json['videoAltText'] as String?]),
      hasAudio: json['hasAudio'] as bool?,
      subtitleUrl: _firstNonEmpty([json['subtitleUrl'] as String?]),
      subtitleLanguage: _firstNonEmpty([json['subtitleLanguage'] as String?]),
      kind: kind,
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
      viewerSaved: json['viewerSaved'] == true,
      recentLikers: recentLikers,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      mediaItems: mediaItems,
      status: status,
      rejectionReason:
          (json['rejectionReason'] ?? json['moderationNote']) as String?,
      approvedAt: DateTime.tryParse(json['approvedAt']?.toString() ?? ''),
    );
  }

  /// Convenience untuk persistence (offline cache, dll) — minimal shape
  /// yang round-trip via fromJson.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'title': title,
      'description': description,
      'caption': caption,
      'videoUrl': videoUrl,
      'videoDataSaverUrl': videoDataSaverUrl,
      'thumbnailUrl': thumbnailUrl,
      'thumbnailBlurhash': thumbnailBlurhash,
      'durationSec': durationSec,
      'aspectRatio': aspectRatio,
      'videoWidth': videoWidth,
      'videoHeight': videoHeight,
      'videoAltText': videoAltText,
      'hasAudio': hasAudio,
      'subtitleUrl': subtitleUrl,
      'subtitleLanguage': subtitleLanguage,
      'kind': kind,
      'author': {
        'id': author.id,
        'name': author.name,
        'username': author.username,
        'avatarUrl': author.avatarUrl,
        'profilePhotoUrl': author.profilePhotoUrl,
        'role': author.role,
        'isAdmin': author.isAdmin,
        'isOfficial': author.isOfficial,
      },
      'products': products
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'slug': p.slug,
                'price': p.price,
                'imageUrl': p.imageUrl,
                'stock': p.stock,
                'isActive': p.isActive
              })
          .toList(),
      'likeCount': likeCount,
      'commentCount': commentCount,
      'viewCount': viewCount,
      'shareCount': shareCount,
      'viewerLiked': viewerLiked || isLiked,
      'isLiked': viewerLiked || isLiked,
      'isLikedByMe': viewerLiked || isLiked,
      'viewerSaved': viewerSaved,
      'recentLikers': recentLikers
          .map((liker) => {
                'id': liker.id,
                'name': liker.name,
                'username': liker.username,
                'avatarUrl': liker.avatarUrl,
                'profilePhotoUrl': liker.profilePhotoUrl,
                'role': liker.role,
                'isAdmin': liker.isAdmin,
                'isOfficial': liker.isOfficial,
              })
          .toList(),
      'createdAt': createdAt.toIso8601String(),
      'mediaItems': mediaItems.map((m) => m.toJson()).toList(),
      'status': status,
      'rejectionReason': rejectionReason,
      'approvedAt': approvedAt?.toIso8601String(),
    };
  }
}

/// Return string non-empty pertama dari list (trim-aware), null kalau
/// semua null/kosong. Untuk fallback chain caption → description → title.
String? _firstNonEmpty(List<String?> candidates) {
  for (final c in candidates) {
    final t = c?.trim();
    if (t != null && t.isNotEmpty) return t;
  }
  return null;
}

double? _aspectFromIntPair(int? w, int? h) {
  if (w == null || h == null || w <= 0 || h <= 0) return null;
  return w / h;
}

bool _looksLikeVideoUrl(String url) {
  final lower = url.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.m3u8') ||
      lower.contains('/video/');
}

/// 1 row dari FeedMedia table. Untuk feed post, PHOTO_CAROUSEL berisi 1-8
/// image-only rows; video post memakai top-level `videoUrl`/`videoGuid`.
/// Parser tetap menerima `video` untuk backward-compat shape lama/detail
/// fallback lokal, tapi tidak ada kontrak data-saver per-media.
class FeedMedia {
  final String id;
  final String mediaType; // "image" | "video"
  final String mediaUrl;
  final String? videoDataSaverUrl;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final int sortOrder;
  final int? durationSeconds;
  final String? altText;

  const FeedMedia({
    required this.id,
    required this.mediaType,
    required this.mediaUrl,
    this.videoDataSaverUrl,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.sortOrder = 0,
    this.durationSeconds,
    this.altText,
  });

  /// Backward-compat alias — kode lama pakai `.url`.
  String get url => mediaUrl;

  /// Aspect ratio untuk pre-compute layout sebelum image fully load. Default
  /// 1:1 (square) supaya gak ada layout shift kalau width/height null.
  double get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 1.0;
    return w / h;
  }

  bool get isVideo => mediaType.toLowerCase() == 'video';
  bool get isImage => !isVideo;

  String mediaPlaybackUrlForQuality(String? qualityPreference) {
    if (isVideo && qualityPreference == 'data_saver') {
      final dataSaver = videoDataSaverUrl?.trim();
      if (dataSaver != null && dataSaver.isNotEmpty) return dataSaver;
    }
    return mediaUrl;
  }

  factory FeedMedia.fromJson(Map<String, dynamic> json) {
    final mediaUrl = (json['mediaUrl'] as String?) ??
        (json['url'] as String?) ??
        (json['videoUrl'] as String?) ??
        '';
    final rawType =
        (json['mediaType'] as String?) ?? (json['contentType'] as String?);
    final mediaType =
        rawType?.toLowerCase() == 'video' || _looksLikeVideoUrl(mediaUrl)
            ? 'video'
            : 'image';
    return FeedMedia(
      id: (json['id'] as String?) ?? '',
      mediaType: mediaType,
      mediaUrl: mediaUrl,
      videoDataSaverUrl: json['videoDataSaverUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ??
          (json['durationSec'] as num?)?.toInt() ??
          (json['videoDurationSec'] as num?)?.toInt(),
      altText: _firstNonEmpty([json['altText'] as String?]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mediaType': mediaType,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
      'width': width,
      'height': height,
      'sortOrder': sortOrder,
      'durationSeconds': durationSeconds,
      'altText': altText,
    };
  }
}

/// Cursor-paginated feed page.
class FeedPage {
  final List<FeedPost> items;
  final String? nextCursor;

  const FeedPage({this.items = const [], this.nextCursor});
}
