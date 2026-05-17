import '../config/api_config.dart';

/// Opsi varian (mis. "500g", "1kg", "Merah", "Biru").
class ProductVariantOption {
  final String id;
  final String value;
  final int position;

  const ProductVariantOption({
    required this.id,
    required this.value,
    required this.position,
  });

  factory ProductVariantOption.fromJson(Map<String, dynamic> json) {
    return ProductVariantOption(
      id: (json['id'] ?? '').toString(),
      value: (json['value'] ?? '').toString(),
      position: _asInt(json['position']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'value': value,
        'position': position,
      };
}

/// Atribut varian (mis. "Ukuran" dengan opsi 500g/1kg, "Warna" dengan
/// opsi Merah/Biru). Satu produk bisa punya beberapa atribut — kombinasi
/// option dari semua atribut menentukan satu Variant konkret.
class ProductVariantAttribute {
  final String id;
  final String name;
  final int position;
  final List<ProductVariantOption> options;

  const ProductVariantAttribute({
    required this.id,
    required this.name,
    required this.position,
    required this.options,
  });

  factory ProductVariantAttribute.fromJson(Map<String, dynamic> json) {
    final raw = json['options'];
    final opts = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(ProductVariantOption.fromJson)
            .toList()
        : <ProductVariantOption>[];
    return ProductVariantAttribute(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      position: _asInt(json['position']),
      options: opts,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'position': position,
        'options': options.map((o) => o.toJson()).toList(),
      };
}

/// Variant konkret (kombinasi optionId dari semua attribute).
/// Punya price + stock + SKU spesifik untuk kombinasi itu.
class ProductVariant {
  final String id;
  final String? sku;
  final double price;
  final int stock;
  final int weightGram;
  final String? imageUrl;
  final bool isActive;

  /// List optionId yang membentuk kombinasi varian ini.
  final List<String> optionIds;

  const ProductVariant({
    required this.id,
    required this.sku,
    required this.price,
    required this.stock,
    required this.weightGram,
    required this.imageUrl,
    required this.isActive,
    required this.optionIds,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    final raw = json['options'];
    final ids = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map((entry) => (entry['optionId'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toList()
        : <String>[];
    return ProductVariant(
      id: (json['id'] ?? '').toString(),
      sku: (json['sku'] ?? '').toString().isEmpty
          ? null
          : json['sku'].toString(),
      price: _asDouble(json['price']),
      stock: _asInt(json['stock']),
      weightGram: _asInt(json['weightGram'], fallback: 500),
      imageUrl: (json['imageUrl'] ?? '').toString().isEmpty
          ? null
          : _absoluteUrl(json['imageUrl'].toString()),
      isActive: json['isActive'] != false,
      optionIds: ids,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'price': price,
        'stock': stock,
        'weightGram': weightGram,
        'imageUrl': imageUrl,
        'isActive': isActive,
        'options': optionIds.map((id) => {'optionId': id}).toList(),
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

String _string(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
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
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http')) return url;
  final asset = _localProductAsset(url);
  if (asset != null) return asset;
  final base = Uri.parse(ApiConfig.baseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}

String? _localProductAsset(String url) {
  final filename = url.split('/').last;
  const copiedProductFiles = {
    'angels-creamy-chicken.png',
    'angels-creamy-salmon.jpg',
    'angels-creamy-tuna.png',
  };
  if (!copiedProductFiles.contains(filename)) return null;
  return 'assets/products/$filename';
}
