/// Product + variant model.
///
/// Field naming: backend Prisma pakai `name`, tapi screen Flutter di-port
/// dari Next.js source pakai `title`. Constructor primary pakai `title`,
/// dengan `name` getter alias supaya kedua naming style work.
class Product {
  final String id;
  final String title;
  final String slug;
  final String description;
  final int price;
  final int? memberPrice;
  final int? discountPrice;
  final int stock;
  final int weightGram;
  /// Non-nullable — kalau backend kasih null, default ke '' supaya screen
  /// code yang akses .isEmpty / .startsWith tetap aman.
  final String imageUrl;
  final List<String> gallery;
  final bool isActive;
  final bool hasVariants;
  final double rating;
  final int reviewCount;
  final String category;
  final String brand;
  final List<VariantAttribute> variantAttrs;
  final List<ProductVariant> variants;

  const Product({
    required this.id,
    required this.title,
    required this.slug,
    this.description = '',
    required this.price,
    this.memberPrice,
    this.discountPrice,
    this.stock = 0,
    this.weightGram = 500,
    this.imageUrl = '',
    this.gallery = const [],
    this.isActive = true,
    this.hasVariants = false,
    this.rating = 0,
    this.reviewCount = 0,
    this.category = '',
    this.brand = '',
    this.variantAttrs = const [],
    this.variants = const [],
  });

  /// Alias — beberapa code pakai `name`, beberapa pakai `title`. Provide both.
  String get name => title;

  /// Backward-compat — some old code may call `avgRating`.
  double get avgRating => rating;

  /// Harga final yang ditampilkan: prioritas discountPrice → memberPrice → price.
  int get finalPrice {
    if (discountPrice != null && discountPrice! > 0) return discountPrice!;
    if (memberPrice != null && memberPrice! > 0) return memberPrice!;
    return price;
  }

  /// True kalau ada selisih price → finalPrice.
  bool get hasDiscount => finalPrice < price;

  /// Persentase diskon (0–99). 0 kalau no discount.
  int get discountPercent {
    if (!hasDiscount || price <= 0) return 0;
    final pct = ((price - finalPrice) / price) * 100;
    return pct.round().clamp(1, 99);
  }

  /// Apakah barang masih bisa dibeli (stok > 0 + active).
  bool get isAvailable => isActive && stock > 0;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      title: (json['title'] ?? json['name']) as String? ?? '',
      slug: json['slug'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: _asInt(json['price']),
      memberPrice: _asNullableInt(json['memberPrice']),
      discountPrice: _asNullableInt(json['discountPrice']),
      stock: _asInt(json['stock']),
      weightGram: _asInt(json['weightGram'] ?? 500),
      imageUrl: (json['imageUrl'] as String?) ?? '',
      gallery: (json['gallery'] as List?)?.cast<String>() ?? const [],
      isActive: json['isActive'] as bool? ?? true,
      hasVariants: json['hasVariants'] as bool? ?? false,
      rating: (json['rating'] ?? json['avgRating'] as num?)?.toDouble() ?? 0,
      reviewCount: _asInt(json['reviewCount']),
      category: _categoryFrom(json['category']) ?? '',
      brand: _brandFrom(json['brand']) ?? '',
      variantAttrs: (json['variantAttrs'] as List?)
              ?.map((e) => VariantAttribute.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      variants: (json['variants'] as List?)
              ?.map((e) => ProductVariant.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'slug': slug,
        'description': description,
        'price': price,
        if (memberPrice != null) 'memberPrice': memberPrice,
        if (discountPrice != null) 'discountPrice': discountPrice,
        'stock': stock,
        'weightGram': weightGram,
        if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        'gallery': gallery,
        'isActive': isActive,
        'hasVariants': hasVariants,
        'rating': rating,
        'reviewCount': reviewCount,
        if (category.isNotEmpty) 'category': category,
        if (brand.isNotEmpty) 'brand': brand,
      };
}

class VariantAttribute {
  final String id;
  final String name;
  final int position;
  final List<VariantOption> options;

  const VariantAttribute({
    required this.id,
    required this.name,
    this.position = 0,
    this.options = const [],
  });

  factory VariantAttribute.fromJson(Map<String, dynamic> json) {
    return VariantAttribute(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      position: _asInt(json['position']),
      options: (json['options'] as List?)
              ?.map((e) => VariantOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
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
}

class ProductVariant {
  final String id;
  final String? sku;
  final int price;
  final int stock;
  final int weightGram;
  final String? imageUrl;
  final List<String> optionIds;

  const ProductVariant({
    required this.id,
    this.sku,
    required this.price,
    this.stock = 0,
    this.weightGram = 500,
    this.imageUrl,
    this.optionIds = const [],
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
    );
  }
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
    required this.loginRequired,
  });

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
  });

  factory Product.fromApiJson(Map<String, dynamic> json) {
    final price = _asDouble(json['price_min'] ?? json['price']);
    final discountPrice = _nullableDouble(
      json['discount_price'] ?? json['discountPrice'],
    );
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
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _asNullableInt(dynamic value) {
  if (value == null) return null;
  return _asInt(value);
}

String? _categoryFrom(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) return raw;
  if (raw is Map) return raw['name']?.toString();
  return null;
}

String? _brandFrom(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) return raw;
  if (raw is Map) return raw['name']?.toString();
  return null;
}
