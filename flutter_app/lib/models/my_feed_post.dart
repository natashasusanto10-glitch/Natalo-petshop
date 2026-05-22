enum MyFeedPostStatus { pending, active, rejected, unknown }

enum MyFeedPostType { photo, carousel, video }

enum MyFeedMediaType { image, video }

class MyFeedMediaItem {
  final String id;
  final String mediaUrl;
  final String? thumbnailUrl;
  final MyFeedMediaType mediaType;
  final int? durationSeconds;

  const MyFeedMediaItem({
    required this.id,
    required this.mediaUrl,
    this.thumbnailUrl,
    required this.mediaType,
    this.durationSeconds,
  });

  factory MyFeedMediaItem.fromJson(Map<String, dynamic> json, int index) {
    final mediaUrl = _string(json['mediaUrl']) ??
        _string(json['url']) ??
        _string(json['videoUrl']) ??
        '';
    final rawType =
        (_string(json['contentType']) ?? _string(json['mediaType']) ?? '')
            .toLowerCase();
    final mediaType = rawType == 'video' || _looksLikeVideoUrl(mediaUrl)
        ? MyFeedMediaType.video
        : MyFeedMediaType.image;
    return MyFeedMediaItem(
      id: _string(json['id']) ?? 'media-$index',
      mediaUrl: mediaUrl,
      thumbnailUrl: _string(json['thumbnailUrl']),
      mediaType: mediaType,
      durationSeconds: _int(
        json['durationSeconds'] ??
            json['durationSec'] ??
            json['videoDurationSec'],
      ),
    );
  }
}

extension MyFeedPostStatusX on MyFeedPostStatus {
  String get label {
    return switch (this) {
      MyFeedPostStatus.active => 'Tayang',
      MyFeedPostStatus.rejected => 'Ditolak',
      MyFeedPostStatus.pending => 'Menunggu Review',
      MyFeedPostStatus.unknown => '-',
    };
  }

  String get description {
    return switch (this) {
      MyFeedPostStatus.active => 'Sudah tayang di Feed',
      MyFeedPostStatus.rejected => 'Ditolak oleh admin',
      MyFeedPostStatus.pending => 'Sedang menunggu review admin',
      MyFeedPostStatus.unknown => '',
    };
  }
}

/// Feed post yang dipost user — dipakai di Member > Postingan + detail + edit.
/// Page result untuk cursor-paginated fetchMyPosts. `nextCursor` null
/// kalau sudah end-of-list — caller stop loadMore.
class MyFeedPostPage {
  final List<MyFeedPost> items;
  final String? nextCursor;

  const MyFeedPostPage({required this.items, this.nextCursor});

  static const empty = MyFeedPostPage(items: [], nextCursor: null);
}

class MyFeedPost {
  final String id;
  final String slug;
  final String? caption;
  final String mediaUrl;
  final String? thumbnailUrl;
  final MyFeedPostType type;
  final List<MyFeedMediaItem> mediaItems;
  final String? blurhash;
  final int durationSec;
  final int aspectWidth;
  final int aspectHeight;
  final String status;
  final String? rejectionReason;
  final int likeCount;
  final int commentCount;
  final int viewCount;

  /// True kalau viewer (session user) sudah pernah klik like post ini —
  /// source of truth dari backend (FeedLike row exists untuk session.sub).
  /// Dipakai initialize _likedCache di My Posts screen supaya tombol like
  /// match dengan DB state. Tanpa field ini, cache start `false` dan tap
  /// pertama bisa accidentally UN-LIKE post yang sebelumnya di-like (lihat
  /// bug "klik 1x hilang" — backend toggle berdasar DB, bukan trust
  /// `currentlyLiked` param dari client).
  final bool viewerLiked;
  final List<String> productIds;
  final DateTime createdAt;
  final DateTime? approvedAt;

  const MyFeedPost({
    required this.id,
    required this.slug,
    this.caption,
    required this.mediaUrl,
    this.thumbnailUrl,
    this.type = MyFeedPostType.video,
    this.mediaItems = const [],
    this.blurhash,
    this.durationSec = 0,
    this.aspectWidth = 9,
    this.aspectHeight = 16,
    this.status = 'PENDING_REVIEW',
    this.rejectionReason,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.viewerLiked = false,
    this.productIds = const [],
    required this.createdAt,
    this.approvedAt,
  });

  bool get isApproved => status.toUpperCase() == 'PUBLISHED';
  bool get isPending => status.toUpperCase() == 'PENDING_REVIEW';
  bool get isRejected => status.toUpperCase() == 'REJECTED';
  String? get title => caption;
  String? get description => caption;
  int get shareCount => 0;
  bool get isVideo => type == MyFeedPostType.video;
  bool get isCarousel => type == MyFeedPostType.carousel;
  bool get isPhoto => type == MyFeedPostType.photo;
  String get previewMediaUrl {
    if (mediaUrl.trim().isNotEmpty) return mediaUrl;
    for (final item in mediaItems) {
      if (item.mediaUrl.isNotEmpty) return item.mediaUrl;
    }
    return '';
  }

  String get durationLabel {
    final total = durationSec.clamp(0, 999999);
    final minutes = total ~/ 60;
    final rest = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }

  MyFeedPostStatus get statusInfo {
    return switch (status.toUpperCase()) {
      'ACTIVE' || 'PUBLISHED' => MyFeedPostStatus.active,
      'REJECTED' => MyFeedPostStatus.rejected,
      'PENDING_REVIEW' || 'PENDING' => MyFeedPostStatus.pending,
      _ => MyFeedPostStatus.unknown,
    };
  }

  factory MyFeedPost.fromJson(Map<String, dynamic> json) {
    final rawMediaItems = json['mediaItems'] ?? json['media'];
    final mediaItems = rawMediaItems is List
        ? rawMediaItems
            .asMap()
            .entries
            .where((entry) => entry.value is Map<String, dynamic>)
            .map(
              (entry) => MyFeedMediaItem.fromJson(
                entry.value as Map<String, dynamic>,
                entry.key,
              ),
            )
            .where((item) => item.mediaUrl.isNotEmpty)
            .toList()
        : <MyFeedMediaItem>[];
    final mediaUrl = _string(json['mediaUrl']) ??
        _string(json['videoUrl']) ??
        (mediaItems.isNotEmpty ? mediaItems.first.mediaUrl : '');
    final durationSec =
        _int(json['durationSec'] ?? json['videoDurationSec']) ?? 0;
    final type = _resolvePostType(json, mediaUrl, mediaItems, durationSec);
    return MyFeedPost(
      id: json['id'] as String,
      slug: json['slug'] as String? ?? json['id'] as String,
      caption: _string(json['caption']) ??
          _string(json['title']) ??
          _string(json['description']),
      mediaUrl: mediaUrl,
      thumbnailUrl: _string(json['thumbnailUrl']),
      type: type,
      mediaItems: mediaItems,
      blurhash: json['blurhash'] as String?,
      durationSec: durationSec,
      aspectWidth: (json['aspectWidth'] as num?)?.toInt() ??
          (type == MyFeedPostType.video ? 9 : 4),
      aspectHeight: (json['aspectHeight'] as num?)?.toInt() ??
          (type == MyFeedPostType.video ? 16 : 5),
      status: json['status'] as String? ?? 'PENDING_REVIEW',
      rejectionReason:
          _string(json['rejectionReason'] ?? json['moderationNote']),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      viewerLiked: json['viewerLiked'] as bool? ?? false,
      productIds: (json['productIds'] as List?)?.cast<String>() ?? const [],
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      approvedAt: DateTime.tryParse(json['approvedAt']?.toString() ?? ''),
    );
  }

  factory MyFeedPost.fromApiJson(Map<String, dynamic> json) =>
      MyFeedPost.fromJson(json);
}

MyFeedPostType _resolvePostType(
  Map<String, dynamic> json,
  String mediaUrl,
  List<MyFeedMediaItem> mediaItems,
  int durationSec,
) {
  final raw = (_string(json['type']) ??
          _string(json['contentType']) ??
          _string(json['postType']) ??
          _string(json['kind']) ??
          _string(json['mediaType']) ??
          '')
      .toUpperCase();
  if (raw == 'VIDEO' ||
      raw == 'COMMUNITY' ||
      raw == 'VIDEO_ONLY' ||
      raw == 'VIDEO_PRODUCT' ||
      raw == 'PROMO') {
    return MyFeedPostType.video;
  }
  if (raw == 'CAROUSEL' || raw == 'PHOTO_CAROUSEL') {
    return mediaItems.length > 1
        ? MyFeedPostType.carousel
        : MyFeedPostType.photo;
  }
  if (raw == 'PHOTO' || raw == 'IMAGE') return MyFeedPostType.photo;

  if (mediaItems.any((item) => item.mediaType == MyFeedMediaType.video)) {
    return MyFeedPostType.video;
  }
  if (mediaItems.length > 1) return MyFeedPostType.carousel;
  if (durationSec > 0 || _looksLikeVideoUrl(mediaUrl)) {
    return MyFeedPostType.video;
  }
  return MyFeedPostType.photo;
}

String? _string(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

int? _int(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
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
