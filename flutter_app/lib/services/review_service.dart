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

  Future<void> submitReview({
    required String productId,
    required String orderItemId,
    required int rating,
    String? title,
    String? content,
    List<String> imageUrls = const [],
  }) async {
    readOnlyMode.assertWritable('review_submit');
    await apiClient.postJson(
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

  /// Update review user (judul/isi/rating). Match endpoint PWA
  /// PATCH /api/reviews/{id} dengan body partial fields.
  /// Server validate ownership (review.userId == session.sub).
  Future<void> updateReview({
    required String reviewId,
    String? title,
    String? content,
    int? rating,
    List<String>? imageUrls,
  }) async {
    readOnlyMode.assertWritable('review_update');
    await apiClient.patchJson(
      '/api/reviews/${Uri.encodeComponent(reviewId)}',
      body: {
        if (title != null) 'title': title,
        if (content != null) 'content': content,
        if (rating != null) 'rating': rating,
        if (imageUrls != null) 'imageUrls': imageUrls,
      },
    );
  }

  /// Hapus review user sendiri. Match endpoint PWA DELETE /api/reviews/{id}.
  Future<void> deleteReview(String reviewId) async {
    readOnlyMode.assertWritable('review_delete');
    await apiClient.deleteJson(
      '/api/reviews/${Uri.encodeComponent(reviewId)}',
    );
  }
}

final reviewService = ReviewService();
