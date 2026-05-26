import 'package:image_picker/image_picker.dart';

import '../models/review.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

class ReviewFilter {
  final int? rating;
  final bool withImage;
  final String sort;
  final String? cursor;

  const ReviewFilter({
    this.rating,
    this.withImage = false,
    this.sort = 'newest',
    this.cursor,
  });

  ReviewFilter copyWith({
    int? rating,
    bool clearRating = false,
    bool? withImage,
    String? sort,
    String? cursor,
    bool clearCursor = false,
  }) {
    return ReviewFilter(
      rating: clearRating ? null : rating ?? this.rating,
      withImage: withImage ?? this.withImage,
      sort: sort ?? this.sort,
      cursor: clearCursor ? null : cursor ?? this.cursor,
    );
  }

  Map<String, String?> toQuery({int limit = 6}) {
    return {
      'sort': sort,
      'limit': limit.toString(),
      if (rating != null) 'rating': rating.toString(),
      if (withImage) 'with_image': 'true',
      if (cursor != null && cursor!.isNotEmpty) 'cursor': cursor,
    };
  }
}

class ReviewService {
  Future<ReviewSummary> fetchSummary(String productSlug) async {
    final data = await apiClient.getJson(
      '/api/products/${Uri.encodeComponent(productSlug)}/reviews/summary',
    );
    return ReviewSummary.fromJson(data);
  }

  Future<ProductReviewPage> fetchReviews(
    String productSlug, {
    ReviewFilter filter = const ReviewFilter(),
  }) async {
    final data = await apiClient.getJson(
      '/api/products/${Uri.encodeComponent(productSlug)}/reviews',
      query: filter.toQuery(),
    );
    return ProductReviewPage.fromJson(data);
  }

  Future<int> toggleHelpful(String reviewId) async {
    readOnlyMode.assertWritable('review_helpful');
    final data = await apiClient.postJson(
      '/api/reviews/${Uri.encodeComponent(reviewId)}/helpful',
      body: const {},
    );
    final count = data['helpfulCount'];
    if (count is num) return count.round();
    return int.tryParse(count?.toString() ?? '') ?? 0;
  }

  Future<List<ReviewableItem>> fetchReviewableItems() async {
    final data = await apiClient.getJson('/api/me/reviewable-items');
    final raw = data['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ReviewableItem.fromJson)
        .toList();
  }

  /// Submit review baru. Return [ReviewSubmitResult] yang include
  /// `pointsAwarded` — 5 kalau review LENGKAP (bintang + deskripsi min 10
  /// char + min 1 foto), 0 kalau belum lengkap. UI pakai untuk snackbar
  /// conditional.
  Future<ReviewSubmitResult> submitReview({
    required String productId,
    required String orderItemId,
    required int rating,
    String? title,
    String? content,
    List<String> imageUrls = const [],
  }) async {
    readOnlyMode.assertWritable('review_submit');
    final response = await apiClient.postJson(
      '/api/reviews',
      body: {
        'productId': productId,
        'orderItemId': orderItemId,
        'rating': rating,
        'title': title,
        'content': content,
        'imageUrls': imageUrls,
      },
    );
    final data = response is Map<String, dynamic>
        ? response
        : const <String, dynamic>{};
    final points = data['pointsAwarded'];
    return ReviewSubmitResult(
      reviewId: (data['id'] ?? '').toString(),
      pointsAwarded: points is num ? points.toInt() : 0,
    );
  }

  Future<String> uploadReviewPhoto(XFile file) async {
    readOnlyMode.assertWritable('review_photo_upload');
    final data = await apiClient.postMultipartFile(
      '/api/reviews/upload',
      fieldName: 'file',
      filePath: file.path,
      filename: file.name,
      contentType: file.mimeType ?? _mimeTypeFromPath(file.path),
    );
    return (data['url'] ?? '').toString();
  }

  String _mimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Update review user (judul/isi/rating). Match endpoint PATCH
  /// /api/reviews/{id}. Return pointsAwarded — kalau user upgrade
  /// review jadi lengkap (retroactive), dapat 5 poin baru.
  Future<ReviewUpdateResult> updateReview({
    required String reviewId,
    String? title,
    String? content,
    int? rating,
    List<String>? imageUrls,
  }) async {
    readOnlyMode.assertWritable('review_update');
    final response = await apiClient.patchJson(
      '/api/reviews/${Uri.encodeComponent(reviewId)}',
      body: {
        if (title != null) 'title': title,
        if (content != null) 'content': content,
        if (rating != null) 'rating': rating,
        if (imageUrls != null) 'imageUrls': imageUrls,
      },
    );
    final data = response is Map<String, dynamic>
        ? response
        : const <String, dynamic>{};
    final points = data['pointsAwarded'];
    return ReviewUpdateResult(
      pointsAwarded: points is num ? points.toInt() : 0,
    );
  }

  /// Hapus review user sendiri. Return pointsRolledBack > 0 kalau user
  /// kehilangan poin karena delete review yang sebelumnya lengkap.
  Future<ReviewDeleteResult> deleteReview(String reviewId) async {
    readOnlyMode.assertWritable('review_delete');
    final response = await apiClient.deleteJson(
      '/api/reviews/${Uri.encodeComponent(reviewId)}',
    );
    final data = response is Map<String, dynamic>
        ? response
        : const <String, dynamic>{};
    final points = data['pointsRolledBack'];
    return ReviewDeleteResult(
      pointsRolledBack: points is num ? points.toInt() : 0,
    );
  }
}

/// Result dari [ReviewService.submitReview].
/// - [reviewId]: id review yang baru dibuat
/// - [pointsAwarded]: 5 kalau review LENGKAP (bintang+desk>=10char+foto),
///   0 kalau belum lengkap. UI pakai untuk snackbar conditional.
class ReviewSubmitResult {
  final String reviewId;
  final int pointsAwarded;

  const ReviewSubmitResult({
    required this.reviewId,
    required this.pointsAwarded,
  });

  /// True kalau user dapat bonus poin dari submission ini.
  bool get earnedBonus => pointsAwarded > 0;
}

/// Result dari [ReviewService.updateReview]. pointsAwarded > 0 = user
/// upgrade review jadi lengkap via edit (retroactive award).
class ReviewUpdateResult {
  final int pointsAwarded;
  const ReviewUpdateResult({required this.pointsAwarded});
  bool get earnedBonus => pointsAwarded > 0;
}

/// Result dari [ReviewService.deleteReview]. pointsRolledBack > 0 = user
/// kehilangan poin yang pernah di-award karena delete review lengkap.
class ReviewDeleteResult {
  final int pointsRolledBack;
  const ReviewDeleteResult({required this.pointsRolledBack});
  bool get lostPoints => pointsRolledBack > 0;
}

final reviewService = ReviewService();
