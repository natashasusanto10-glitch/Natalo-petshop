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

// ── helpers ──
int _asInt(dynamic value) {
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
