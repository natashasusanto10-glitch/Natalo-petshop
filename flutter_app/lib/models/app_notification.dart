class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? shortDescription;
  final String? url;
  final String type;
  final String? category;
  final String? source;
  final String? eventType;
  final String? feedPostId;
  final String? commentId;
  final String? status;
  final String? ctaLabel;
  final String? importantTitle;
  final String? importantValue;
  final String? importantDescription;
  final String? infoNote;
  final String? imageUrl;
  final String? actorAvatarUrl;
  final String? actorName;
  final List<String> actorAvatarUrls;
  final DateTime createdAt;
  final bool read;

  /// Apakah user yang login sudah menyukai komentar yang dirujuk notif ini
  /// (untuk notif komentar). Diisi server dari FeedCommentLike — menyinkronkan
  /// tombol love di baris notifikasi dgn like asli di sheet komentar.
  final bool commentLiked;

  /// Untuk notif "user_followed": apakah viewer sudah follow-balik aktor
  /// notif ini. Diisi server dari UserFollow — supaya pill "Ikuti"/
  /// "Mengikuti" benar sejak render pertama, bukan nunggu tap. Null untuk
  /// notif non-follow atau baris lama pra-migration (actorId belum ada).
  final bool? isFollowing;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.shortDescription,
    this.url,
    required this.type,
    this.category,
    this.source,
    this.eventType,
    this.feedPostId,
    this.commentId,
    this.status,
    this.ctaLabel,
    this.importantTitle,
    this.importantValue,
    this.importantDescription,
    this.infoNote,
    this.imageUrl,
    this.actorAvatarUrl,
    this.actorName,
    this.actorAvatarUrls = const [],
    required this.createdAt,
    required this.read,
    this.commentLiked = false,
    this.isFollowing,
  });

  factory AppNotification.fromApiJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Notifikasi').toString(),
      body: (json['body'] ??
              json['content'] ??
              json['message'] ??
              json['description'] ??
              '')
          .toString(),
      shortDescription:
          (json['shortDescription'] ?? json['short_description'])?.toString(),
      url: json['url']?.toString(),
      type: (json['type'] ?? json['segment'] ?? 'info').toString(),
      category: json['category']?.toString(),
      source: json['source']?.toString(),
      eventType: json['eventType']?.toString(),
      feedPostId: (json['feedPostId'] ?? json['videoId'])?.toString(),
      commentId: (json['commentId'] ?? json['comment_id'])?.toString(),
      status: json['status']?.toString(),
      ctaLabel: (json['ctaLabel'] ?? json['cta_label'])?.toString(),
      importantTitle:
          (json['importantTitle'] ?? json['important_title'])?.toString(),
      importantValue:
          (json['importantValue'] ?? json['important_value'])?.toString(),
      importantDescription:
          (json['importantDescription'] ?? json['important_description'])
              ?.toString(),
      infoNote: (json['infoNote'] ?? json['info_note'])?.toString(),
      imageUrl: (json['imageUrl'] ?? json['image_url'] ?? json['thumbnailUrl'])
          ?.toString(),
      actorAvatarUrl:
          (json['actorAvatarUrl'] ?? json['actor_avatar_url'])?.toString(),
      actorName: (json['actorName'] ?? json['actor_name'])?.toString(),
      actorAvatarUrls: ((json['actorAvatarUrls'] ?? json['actor_avatar_urls'])
                  as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      read: json['read'] == true,
      commentLiked: json['commentLiked'] == true,
      isFollowing: json['isFollowing'] as bool?,
    );
  }

  AppNotification copyWith({
    bool? read,
  }) {
    return AppNotification(
      id: id,
      title: title,
      body: body,
      shortDescription: shortDescription,
      url: url,
      type: type,
      category: category,
      source: source,
      eventType: eventType,
      feedPostId: feedPostId,
      commentId: commentId,
      status: status,
      ctaLabel: ctaLabel,
      importantTitle: importantTitle,
      importantValue: importantValue,
      importantDescription: importantDescription,
      infoNote: infoNote,
      imageUrl: imageUrl,
      actorAvatarUrl: actorAvatarUrl,
      actorName: actorName,
      actorAvatarUrls: actorAvatarUrls,
      createdAt: createdAt,
      read: read ?? this.read,
      commentLiked: commentLiked,
      isFollowing: isFollowing,
    );
  }
}
