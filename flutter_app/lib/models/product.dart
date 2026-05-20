/// Product + variant model.
///
/// Field naming: backend Prisma pakai `name`, tapi screen Flutter di-port
/// dari Next.js source pakai `title`. Constructor primary pakai `title`,
/// dengan `name` getter alias supaya kedua naming style work.
import '../config/api_config.dart';

/// Navigation args untuk ProductsScreen — opsi filter awal.
class ProductCatalogArgs {
  final String? selectedBrand;
  final String? initialQuery;
  final String? initialCategory;

  const ProductCatalogArgs({
    this.selectedBrand,
    this.initialQuery,
    this.initialCategory,
  });
}

/// Convert relative URL backend (mis. `/uploads/abc.jpg`) ke absolute
/// origin yang bisa di-load Flutter (mis. `https://natalopetshop.com/uploads/abc.jpg`).
/// Idempotent — kalau sudah absolute, return as-is.
String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http')) return url;
  final base = Uri.parse(ApiConfig.baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}

class ProductVariantAttribute {
  final String id;
  final String name;
  final int position;
  final List<VariantOption> options;

  const ProductVariantAttribute({
    required this.id,
    required this.name,
    this.position = 0,
    this.options = const [],
  });

  factory ProductVariantAttribute.fromJson(Map<String, dynamic> json) {
    return ProductVariantAttribute(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      position: _asInt(json['position']),
      options: (json['options'] as List?)
              ?.map((e) => VariantOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'position': position,
        'options': options.map((o) => o.toJson()).toList(),
      };
}

class VariantOption {
  final String id;
  final String value;
  final int position;

  const VariantOption({
    required this.id,
    required this.value,
    this.position = 0,
  });

  factory VariantOption.fromJson(Map<String, dynamic> json) {
    return VariantOption(
      id: json['id'] as String,
      value: json['value'] as String? ?? '',
      position: _asInt(json['position']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'value': value,
        'position': position,
      };
}

class ProductVariant {
  final String id;
  final String? sku;
  final int price;
  final int stock;
  final int weightGram;
  final String? imageUrl;
  final List<String> optionIds;

  /// Default true — backend kasih `isActive: false` untuk variant yang
  /// di-soft-delete. `_parseVariants` filter ke `where((v) => v.isActive)`.
  final bool isActive;

  const ProductVariant({
    required this.id,
    this.sku,
    required this.price,
    this.stock = 0,
    this.weightGram = 500,
    this.imageUrl,
    this.optionIds = const [],
    this.isActive = true,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    final options = json['options'] as List?;
    final ids = <String>[];
    if (options != null) {
      for (final opt in options) {
        if (opt is Map<String, dynamic>) {
          final id = opt['optionId'] ?? opt['option']?['id'];
          if (id is String) ids.add(id);
        }
      }
    }
    return ProductVariant(
      id: json['id'] as String,
      sku: json['sku'] as String?,
      price: _asInt(json['price']),
      stock: _asInt(json['stock']),
      weightGram: _asInt(json['weightGram'] ?? 500),
      imageUrl: json['imageUrl'] as String?,
      optionIds: ids,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'price': price,
        'stock': stock,
        'weightGram': weightGram,
        'imageUrl': imageUrl,
        'optionIds': optionIds,
        'isActive': isActive,
      };
}

class ProductVoucherPreview {
  final String id;
  final String title;
  final String? description;
  final String badgeLabel;
  final String sheetTitle;
  final String sheetSubtitle;
  final double? discountPercent;
  final double? discountAmount;
  final double? maxDiscountAmount;
  final double minimumOrder;
  final double? savingAmount;
  final String? expiresAt;
  final String targetUser;
  final bool loginRequired;

  const ProductVoucherPreview({
    required this.id,
    required this.title,
    this.description,
    required this.badgeLabel,
    required this.sheetTitle,
    required this.sheetSubtitle,
    this.discountPercent,
    this.discountAmount,
    this.maxDiscountAmount,
    required this.minimumOrder,
    this.savingAmount,
    this.expiresAt,
    this.targetUser = 'ALL_MEMBERS',
    required this.loginRequired,
  });

  bool get isNewMemberOnly {
    final normalizedTarget = targetUser.trim().toUpperCase();
    if (normalizedTarget == 'NEW_MEMBER') return true;
    final combinedCopy = '$title ${description ?? ''}'.toLowerCase();
    return combinedCopy.contains('new member') ||
        combinedCopy.contains('member baru');
  }

  factory ProductVoucherPreview.fromJson(Map<String, dynamic> json) {
    return ProductVoucherPreview(
      id: _string(json['id']),
      title: _string(json['title'], fallback: 'Voucher Natalo'),
      description: _stringOrNull(json['description']),
      badgeLabel: _string(
        json['badgeLabel'] ?? json['badge_label'],
        fallback: 'Voucher hemat',
      ),
      sheetTitle: _string(
        json['sheetTitle'] ?? json['sheet_title'],
        fallback: 'Voucher Produk',
      ),
      sheetSubtitle: _string(
        json['sheetSubtitle'] ?? json['sheet_subtitle'],
        fallback: 'Cek syarat voucher saat checkout',
      ),
      discountPercent: _nullableDouble(
        json['discountPercent'] ?? json['discount_percent'],
      ),
      discountAmount: _nullableDouble(
        json['discountAmount'] ?? json['discount_amount'],
      ),
      maxDiscountAmount: _nullableDouble(
        json['maxDiscountAmount'] ?? json['max_discount_amount'],
      ),
      minimumOrder: _asDouble(
        json['minimumOrder'] ?? json['minimum_order'],
      ),
      savingAmount: _nullableDouble(
        json['savingAmount'] ?? json['saving_amount'],
      ),
      expiresAt: _stringOrNull(json['expiresAt'] ?? json['expires_at']),
      targetUser: _string(
        json['targetUser'] ?? json['target_user'],
        fallback: 'ALL_MEMBERS',
      ),
      loginRequired: json['loginRequired'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'badgeLabel': badgeLabel,
        'sheetTitle': sheetTitle,
        'sheetSubtitle': sheetSubtitle,
        'discountPercent': discountPercent,
        'discountAmount': discountAmount,
        'maxDiscountAmount': maxDiscountAmount,
        'minimumOrder': minimumOrder,
        'savingAmount': savingAmount,
        'expiresAt': expiresAt,
        'targetUser': targetUser,
        'loginRequired': loginRequired,
      };
}

class Product {
  final String id;
  final String slug;
  final String title;
  final String category;
  final String brand;
  final String imageUrl;
  final double price;
  final double? discountPrice;
  final double? memberPrice;
  final double rating;
  final int reviewCount;
  final int stock;
  final int weightGram;
  final bool isNew;
  final bool isTrending;
  final bool hasVariants;
  final ProductVoucherPreview? voucherPreview;
  final List<String> gallery;
  final String description;

  /// Atribut + variants — hanya terisi dari /api/products/{slug}.
  /// List/recommendations endpoint return [] supaya size payload kecil.
  final List<ProductVariantAttribute> variantAttrs;
  final List<ProductVariant> variants;

  /// soldCount diisi dari /api/products/{slug}; endpoint lain return 0.
  final int soldCount;

  /// Flash Sale explicit end timestamp. Kalau di-set, produk WAJIB
  /// masuk Flash Sale section di home dengan countdown. Kalau null,
  /// produk masuk Flash Sale section hanya kalau discount >= 20% (auto).
  /// ISO UTC dari backend, parsed sebagai DateTime.toLocal() di sini.
  final DateTime? flashSaleEndsAt;

  Product({
    required this.id,
    required this.slug,
    required this.title,
    required this.category,
    required this.brand,
    required this.imageUrl,
    required this.price,
    this.discountPrice,
    this.memberPrice,
    required this.rating,
    required this.reviewCount,
    required this.stock,
    this.weightGram = 500,
    this.isNew = false,
    this.isTrending = false,
    this.hasVariants = false,
    this.voucherPreview,
    this.gallery = const [],
    required this.description,
    this.variantAttrs = const [],
    this.variants = const [],
    this.soldCount = 0,
    this.flashSaleEndsAt,
  });

  /// Alias `rating` untuk legacy reference `Product.avgRating`.
  double get avgRating => rating;

  /// Alias `fromApiJson` — legacy code (mis. cart_item) pakai `Product.fromJson(...)`.
  factory Product.fromJson(Map<String, dynamic> json) =>
      Product.fromApiJson(json);

  factory Product.fromApiJson(Map<String, dynamic> json) {
    final rawPrice = _asDouble(json['price_min'] ?? json['price']);
    final normalPrice = _nullableDouble(
      json['normal_price'] ??
          json['normalPrice'] ??
          json['original_price'] ??
          json['originalPrice'],
    );
    final explicitDiscountPrice = _nullableDouble(
      json['discount_price'] ?? json['discountPrice'],
    );
    final hasNormalPrice = normalPrice != null && normalPrice > rawPrice;
    final price = hasNormalPrice ? normalPrice : rawPrice;
    final discountPrice =
        explicitDiscountPrice ?? (hasNormalPrice ? rawPrice : null);
    // Endpoint /api/cart/recommendations & /api/cart/recently-viewed return
    // field 'image' (bukan 'image_url'). Tambah fallback.
    final image = _absoluteUrl(
      _string(json['image_url'] ?? json['imageUrl'] ?? json['image']),
    );
    final galleryRaw = json['gallery'];

    return Product(
      id: _string(json['id'], fallback: _string(json['slug'])),
      slug: _string(json['slug'], fallback: _string(json['id'])),
      title: _string(json['name'] ?? json['title'], fallback: 'Produk Natalo'),
      category: _string(
        // recommendations & recently-viewed API return 'category' sebagai string.
        json['category_name'] ??
            json['categorySlug'] ??
            json['category_slug'] ??
            json['category'],
        fallback: 'Produk',
      ),
      brand: _string(
        json['brand_name'] ??
            json['brandName'] ??
            json['brand_slug'] ??
            json['brand'],
        fallback: 'Natalo',
      ),
      imageUrl: image,
      price: price,
      discountPrice: discountPrice,
      memberPrice: _nullableDouble(json['memberPrice'] ?? json['member_price']),
      rating: _asDouble(
        json['avg_rating'] ?? json['avgRating'] ?? json['rating'],
      ),
      reviewCount: _asInt(json['review_count'] ?? json['reviewCount']),
      stock: _asInt(json['total_stock'] ?? json['stock']),
      weightGram:
          _asInt(json['weight_grams'] ?? json['weightGram'], fallback: 500),
      isNew: false,
      isTrending: _asInt(json['review_count'] ?? json['reviewCount']) >= 10,
      hasVariants: json['has_variants'] == true || json['hasVariants'] == true,
      voucherPreview: _parseVoucherPreview(
        json['voucherPreview'] ??
            json['voucher_preview'] ??
            json['bestVoucherPreview'],
      ),
      gallery: galleryRaw is List
          ? galleryRaw.map((item) => item.toString()).toList()
          : const [],
      description: _string(json['description']),
      variantAttrs: _parseVariantAttrs(json['variantAttrs']),
      variants: _parseVariants(json['variants']),
      soldCount: _asInt(
        json['soldCount'] ??
            json['totalSold'] ??
            json['sold_count'] ??
            json['total_sold'] ??
            json['salesCount'] ??
            json['jumlahTerjual'] ??
            json['sold'],
      ),
      // Flash Sale explicit end timestamp dari backend (ISO 8601 UTC).
      // Convert ke local time supaya countdown display benar di timezone
      // user. Field accept beberapa naming variation untuk compat dengan
      // berbagai endpoint (PWA store vs admin vs Flutter API).
      flashSaleEndsAt: _parseDateTime(
        json['flashSaleEndsAt'] ?? json['flash_sale_ends_at'],
      ),
    );
  }

  /// Serialize untuk persist ke local storage (cart cache).
  /// Key naming match `fromApiJson` accept format supaya bisa round-trip.
  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'name': title,
        'category_name': category,
        'brand_name': brand,
        'image_url': imageUrl,
        'price': price,
        'discount_price': discountPrice,
        'memberPrice': memberPrice,
        'avgRating': rating,
        'reviewCount': reviewCount,
        'stock': stock,
        'weightGram': weightGram,
        'hasVariants': hasVariants,
        'voucherPreview': voucherPreview?.toJson(),
        'gallery': gallery,
        'description': description,
        'variantAttrs': variantAttrs.map((a) => a.toJson()).toList(),
        'variants': variants.map((v) => v.toJson()).toList(),
        'soldCount': soldCount,
        'flashSaleEndsAt': flashSaleEndsAt?.toUtc().toIso8601String(),
      };

  double get finalPrice {
    final member = memberPrice;
    if (member != null && member < price) return member;

    final discount = discountPrice;
    if (discount != null && discount < price) return discount;

    return price;
  }

  bool get hasDiscount => finalPrice < price;

  int? get discountPercent {
    if (!hasDiscount || price <= 0) return null;
    return (((price - finalPrice) / price) * 100).round();
  }

  /// Threshold default — mirror dari backend FLASH_SALE_MIN_DISCOUNT_PERCENT.
  /// Bump bareng kalau business decision ubah ambang.
  static const int flashSaleMinDiscountPercent = 20;

  /// 3-tier Flash Sale eligibility check — mirror dari backend
  /// getFlashSaleProducts() di app/page.tsx.
  ///   Tier 1: flashSaleEndsAt set + di future → always include
  ///   Tier 2: flashSaleEndsAt null + discount >= 20% → include (no timer)
  ///   Tier 3: flashSaleEndsAt set + expired → exclude
  bool get isFlashSaleEligible {
    if (!hasDiscount) return false;
    final endsAt = flashSaleEndsAt;
    if (endsAt != null) {
      return endsAt.isAfter(DateTime.now()); // Tier 1 (active) or Tier 3 (expired)
    }
    // Tier 2: tidak ada explicit endsAt, cek threshold.
    final pct = discountPercent;
    return pct != null && pct >= flashSaleMinDiscountPercent;
  }

  /// True kalau admin explicit tag produk ini Flash Sale (Tier 1).
  /// Dipakai untuk decide apakah show countdown timer (vs auto-included
  /// di Tier 2 yang tidak punya end time).
  bool get hasFlashSaleCountdown {
    final endsAt = flashSaleEndsAt;
    return endsAt != null && endsAt.isAfter(DateTime.now());
  }
}

/// Parse ISO 8601 string ke DateTime local — graceful fallback null
/// kalau format invalid atau input bukan string.
DateTime? _parseDateTime(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toLocal();
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    return parsed?.toLocal();
  }
  return null;
}

List<ProductVariantAttribute> _parseVariantAttrs(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(ProductVariantAttribute.fromJson)
      .toList()
    ..sort((a, b) => a.position.compareTo(b.position));
}

List<ProductVariant> _parseVariants(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(ProductVariant.fromJson)
      .where((v) => v.isActive)
      .toList();
}

ProductVoucherPreview? _parseVoucherPreview(Object? raw) {
  if (raw is Map<String, dynamic>) {
    return ProductVoucherPreview.fromJson(raw);
  }
  if (raw is Map) {
    return ProductVoucherPreview.fromJson(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
  return null;
}

String _string(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

String? _stringOrNull(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
