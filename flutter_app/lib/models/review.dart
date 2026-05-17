import '../config/api_config.dart';

class ReviewSummary {
  final double avgRating;
  final int reviewCount;
  final Map<int, int> ratingBreakdown;

  const ReviewSummary({
    required this.avgRating,
    required this.reviewCount,
    required this.ratingBreakdown,
  });

  factory ReviewSummary.fromJson(Map<String, dynamic> json) {
    final rawBreakdown = json['ratingBreakdown'];
    final breakdown = <int, int>{};
    if (rawBreakdown is Map) {
      for (final entry in rawBreakdown.entries) {
        final key = int.tryParse(entry.key.toString());
        if (key == null) continue;
        breakdown[key] = _asInt(entry.value);
      }
    }

    return ReviewSummary(
      avgRating: _asDouble(json['avgRating']),
      reviewCount: _asInt(json['reviewCount']),
      ratingBreakdown: breakdown,
    );
  }
}

class ProductReviewPage {
  final List<ProductReview> reviews;
  final String? nextCursor;

  const ProductReviewPage({required this.reviews, this.nextCursor});

  factory ProductReviewPage.fromJson(Map<String, dynamic> json) {
    final raw = json['reviews'];
    return ProductReviewPage(
      reviews: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(ProductReview.fromJson)
              .toList()
          : const [],
      nextCursor: json['nextCursor']?.toString(),
    );
  }
}

class ReviewableItem {
  final String orderItemId;
  final String productId;
  final String productName;
  final String? productImage;
  final String? variantLabel;
  final int quantity;
  final double price;
  final String? orderNumber;
  final DateTime? orderDate;
  final bool hasReviewed;
  final int? reviewRating;
  final String? reviewText;
  final DateTime? reviewedAt;

  const ReviewableItem({
    required this.orderItemId,
    required this.productId,
    required this.productName,
    this.productImage,
    this.variantLabel,
    required this.quantity,
    this.price = 0,
    this.orderNumber,
    this.orderDate,
    this.hasReviewed = false,
    this.reviewRating,
    this.reviewText,
    this.reviewedAt,
  });

  factory ReviewableItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    final order = json['order'];
    final review = json['review'];
    final productMap = product is Map<String, dynamic> ? product : null;
    final orderMap = order is Map<String, dynamic> ? order : null;
    final reviewMap = review is Map<String, dynamic> ? review : null;
    final image =
        json['productImage'] ?? productMap?['imageUrl'] ?? json['imageUrl'];
    final hasReviewed = json['hasReviewed'] == true ||
        json['reviewed'] == true ||
        json['isReviewed'] == true ||
        reviewMap != null;

    return ReviewableItem(
      orderItemId: _string(json['id'] ?? json['orderItemId']),
      productId: _string(json['productId'] ?? productMap?['id']),
      productName: _string(json['name'] ?? json['productName'],
          fallback: 'Produk Natalo'),
      productImage: image == null ? null : _absoluteUrl(image.toString()),
      variantLabel: _nullableString(json['variantLabel']),
      quantity: _asInt(json['quantity'], fallback: 1),
      price: _asDouble(json['price'] ??
          json['unitPrice'] ??
          json['productPrice'] ??
          productMap?['price']),
      orderNumber: _nullableString(orderMap?['orderNumber']),
      orderDate: DateTime.tryParse(_string(orderMap?['createdAt'])),
      hasReviewed: hasReviewed,
      reviewRating: reviewMap == null
          ? _asNullableInt(json['reviewRating'] ?? json['rating'])
          : _asNullableInt(reviewMap['rating']),
      reviewText: reviewMap == null
          ? _nullableString(json['reviewText'] ?? json['reviewContent'])
          : _nullableString(reviewMap['content'] ?? reviewMap['title']),
      reviewedAt: DateTime.tryParse(
        _string(reviewMap?['createdAt'] ?? json['reviewedAt']),
      ),
    );
  }
}

class ProductReview {
  final String id;
  final int rating;
  final String? title;
  final String? content;
  final String? variantLabel;
  final int helpfulCount;
  final DateTime createdAt;
  final String userName;
  final List<String> images;
  final ReviewReply? reply;

  /// True kalau review ini milik user yang sedang login. Backend Capacitor
  /// belum return field ini secara default — tetapi kalau di-update untuk
  /// include `isMine: boolean` di response /api/products/{slug}/reviews,
  /// UI akan otomatis nampilkan menu edit/hapus. Default false (safe).
  final bool isMine;

  const ProductReview({
    required this.id,
    required this.rating,
    this.title,
    this.content,
    this.variantLabel,
    required this.helpfulCount,
    required this.createdAt,
    required this.userName,
    required this.images,
    this.reply,
    this.isMine = false,
  });

  ProductReview copyWith({int? helpfulCount}) {
    return ProductReview(
      id: id,
      rating: rating,
      title: title,
      content: content,
      variantLabel: variantLabel,
      helpfulCount: helpfulCount ?? this.helpfulCount,
      createdAt: createdAt,
      userName: userName,
      images: images,
      reply: reply,
      isMine: isMine,
    );
  }

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'];
    final rawReply = json['reply'];

    return ProductReview(
      id: _string(json['id']),
      rating: _asInt(json['rating']),
      title: _nullableString(json['title']),
      content: _nullableString(json['content']),
      variantLabel: _nullableString(json['variantLabel']),
      helpfulCount: _asInt(json['helpfulCount']),
      createdAt: DateTime.tryParse(_string(json['createdAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      userName: _string(json['userName'], fallback: 'Pembeli Natalo'),
      images: rawImages is List
          ? rawImages.map((item) => _absoluteUrl(item.toString())).toList()
          : const [],
      reply: rawReply is Map<String, dynamic>
          ? ReviewReply.fromJson(rawReply)
          : null,
      // Backend boleh return `isMine: true/false` di response. Kalau tidak
      // ada (Capacitor default belum support), fallback ke false — UI tidak
      // tampilkan menu edit/delete (safe). Backend update untuk include flag
      // = UI otomatis nampilkan menu tanpa client release baru.
      isMine: json['isMine'] == true,
    );
  }
}

class ReviewReply {
  final String content;
  final DateTime createdAt;

  const ReviewReply({required this.content, required this.createdAt});

  factory ReviewReply.fromJson(Map<String, dynamic> json) {
    return ReviewReply(
      content: _string(json['content']),
      createdAt: DateTime.tryParse(_string(json['createdAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http') || url.startsWith('assets/')) {
    return url;
  }
  final base = Uri.parse(ApiConfig.baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}

String _string(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = _string(value);
  return text.isEmpty ? null : text;
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}
