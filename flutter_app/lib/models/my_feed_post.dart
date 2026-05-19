enum MyFeedPostStatus { pending, active, rejected, unknown }

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
class MyFeedPost {
  final String id;
  final String slug;
  final String? caption;
  final String mediaUrl;
  final String? thumbnailUrl;
  final String? blurhash;
  final int durationSec;
  final int aspectWidth;
  final int aspectHeight;
  final String status;
  final String? rejectionReason;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final List<String> productIds;
  final DateTime createdAt;
  final DateTime? approvedAt;

  const MyFeedPost({
    required this.id,
    required this.slug,
    this.caption,
    required this.mediaUrl,
    this.thumbnailUrl,
    this.blurhash,
    this.durationSec = 0,
    this.aspectWidth = 9,
    this.aspectHeight = 16,
    this.status = 'PENDING_REVIEW',
    this.rejectionReason,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
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
    return MyFeedPost(
      id: json['id'] as String,
      slug: json['slug'] as String? ?? json['id'] as String,
      caption: json['caption'] as String?,
      mediaUrl:
          json['mediaUrl'] as String? ?? json['videoUrl'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      blurhash: json['blurhash'] as String?,
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      aspectWidth: (json['aspectWidth'] as num?)?.toInt() ?? 9,
      aspectHeight: (json['aspectHeight'] as num?)?.toInt() ?? 16,
      status: json['status'] as String? ?? 'PENDING_REVIEW',
      rejectionReason: json['rejectionReason'] as String?,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      productIds: (json['productIds'] as List?)?.cast<String>() ?? const [],
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      approvedAt: DateTime.tryParse(json['approvedAt']?.toString() ?? ''),
    );
  }

  factory MyFeedPost.fromApiJson(Map<String, dynamic> json) =>
      MyFeedPost.fromJson(json);
}
