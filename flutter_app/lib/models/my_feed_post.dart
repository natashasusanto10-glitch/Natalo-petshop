import '../config/api_config.dart';

/// Status review postingan user — match enum FeedPostStatus di Prisma.
enum MyFeedPostStatus { pending, active, rejected, unknown }

extension MyFeedPostStatusX on MyFeedPostStatus {
  String get label {
    switch (this) {
      case MyFeedPostStatus.active:
        return 'Tayang';
      case MyFeedPostStatus.rejected:
        return 'Ditolak';
      case MyFeedPostStatus.pending:
        return 'Menunggu Review';
      case MyFeedPostStatus.unknown:
        return '—';
    }
  }

  String get description {
    switch (this) {
      case MyFeedPostStatus.active:
        return 'Sudah tayang di Feed';
      case MyFeedPostStatus.rejected:
        return 'Ditolak oleh admin';
      case MyFeedPostStatus.pending:
        return 'Sedang menunggu review admin';
      case MyFeedPostStatus.unknown:
        return '';
    }
  }
}

MyFeedPostStatus _parseStatus(String raw) {
  switch (raw) {
    case 'ACTIVE':
      return MyFeedPostStatus.active;
    case 'REJECTED':
      return MyFeedPostStatus.rejected;
    case 'PENDING_REVIEW':
      return MyFeedPostStatus.pending;
    default:
      return MyFeedPostStatus.unknown;
  }
}

/// Postingan video user di feed — match response API
/// GET /api/feed/my-posts.
class MyFeedPost {
  final String id;
  final String? title;
  final String? description;
  final String? thumbnailUrl;
  final String? videoUrl;
  final int? videoDurationSec;
  final DateTime createdAt;
  final MyFeedPostStatus status;
  final String? moderationNote;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  /// Tag list dari server — mis. `['anjing', 'vitamin']`. Empty kalau belum
  /// ada di response (backward compat dengan API yang belum return tags).
  final List<String> tags;

  const MyFeedPost({
    required this.id,
    this.title,
    this.description,
    this.thumbnailUrl,
    this.videoUrl,
    this.videoDurationSec,
    required this.createdAt,
    required this.status,
    this.moderationNote,
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.tags = const [],
  });

  factory MyFeedPost.fromApiJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse((json['createdAt'] ?? '').toString());
    final thumb = (json['thumbnailUrl'] ?? '').toString();
    final video = (json['videoUrl'] ?? '').toString();
    return MyFeedPost(
      id: (json['id'] ?? '').toString(),
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      thumbnailUrl: thumb.isEmpty ? null : _absoluteUrl(thumb),
      videoUrl: video.isEmpty ? null : _absoluteUrl(video),
      videoDurationSec: _nullableInt(json['videoDurationSec']),
      createdAt: created ?? DateTime.now(),
      status: _parseStatus((json['status'] ?? '').toString()),
      moderationNote: json['moderationNote']?.toString(),
      likeCount: _asInt(json['likeCount']),
      commentCount: _asInt(json['commentCount']),
      shareCount: _asInt(json['shareCount']),
      tags: _parseTags(json['tags']),
    );
  }

  /// Format durasi 00:04 dari videoDurationSec.
  String get durationLabel {
    final total = (videoDurationSec ?? 0).clamp(0, 999999);
    final minutes = total ~/ 60;
    final rest = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _parseTags(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http')) return url;
  final base = Uri.parse(ApiConfig.baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}
