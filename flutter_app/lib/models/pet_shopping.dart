/// Model kolom Belanja profil pet (spec
/// docs/superpowers/specs/2026-07-25-pets-belanja-design.md).
/// `slug` dibawa karena ProductVariantPickerSheet & fetchProductBySlug
/// keduanya mengambil produk penuh lewat slug.
class PetShoppingProduct {
  final String productId;
  final String slug;
  final String name;
  final String? imageUrl;
  final int effectivePrice;
  final bool inStock;
  final bool hasVariants;

  /// Hanya terisi untuk item di grup "Pernah dipakai".
  final int? usageCount;
  final DateTime? lastUsedAt;

  const PetShoppingProduct({
    required this.productId,
    required this.slug,
    required this.name,
    required this.imageUrl,
    required this.effectivePrice,
    required this.inStock,
    required this.hasVariants,
    this.usageCount,
    this.lastUsedAt,
  });

  factory PetShoppingProduct.fromJson(Map<String, dynamic> json) {
    final raw = json['lastUsedAt'] as String?;
    return PetShoppingProduct(
      productId: json['productId'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      effectivePrice: (json['effectivePrice'] as num?)?.toInt() ?? 0,
      inStock: json['inStock'] as bool? ?? false,
      hasVariants: json['hasVariants'] as bool? ?? false,
      usageCount: (json['usageCount'] as num?)?.toInt(),
      lastUsedAt: raw == null ? null : DateTime.tryParse(raw),
    );
  }
}

class PetShoppingManual {
  final String brandText;
  final int usageCount;
  final DateTime lastUsedAt;

  const PetShoppingManual({
    required this.brandText,
    required this.usageCount,
    required this.lastUsedAt,
  });

  factory PetShoppingManual.fromJson(Map<String, dynamic> json) {
    return PetShoppingManual(
      brandText: json['brandText'] as String? ?? '',
      usageCount: (json['usageCount'] as num?)?.toInt() ?? 1,
      lastUsedAt:
          DateTime.tryParse(json['lastUsedAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class PetShopping {
  final int usedCount;
  final List<PetShoppingProduct> used;
  final List<PetShoppingManual> manual;
  final List<PetShoppingProduct> suggested;

  const PetShopping({
    required this.usedCount,
    required this.used,
    required this.manual,
    required this.suggested,
  });

  /// Section Belanja disembunyikan penuh saat ini true (spec Keputusan 13).
  bool get isEmpty => used.isEmpty && manual.isEmpty && suggested.isEmpty;

  static List<PetShoppingProduct> _products(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(PetShoppingProduct.fromJson)
        .toList();
  }

  factory PetShopping.fromJson(Map<String, dynamic> json) {
    final rawManual = json['manual'];
    return PetShopping(
      usedCount: (json['usedCount'] as num?)?.toInt() ?? 0,
      used: _products(json['used']),
      manual: rawManual is List
          ? rawManual
              .whereType<Map<String, dynamic>>()
              .map(PetShoppingManual.fromJson)
              .toList()
          : const [],
      suggested: _products(json['suggested']),
    );
  }
}

/// "Dipakai 2x, terakhir 3 bulan lalu" — framing BELANJA, sengaja beda dari
/// section Perawatan di atasnya yang sudah menampilkan "kategori — tanggal"
/// (spec Keputusan 12).
String petShoppingUsageLabel(
  int usageCount,
  DateTime lastUsedAt, {
  DateTime? now,
}) {
  final base = now ?? DateTime.now();
  final days = base.difference(lastUsedAt).inDays;
  final String when;
  if (days <= 0) {
    when = 'hari ini';
  } else if (days < 30) {
    when = '$days hari lalu';
  } else if (days < 365) {
    when = '${days ~/ 30} bulan lalu';
  } else {
    when = '${days ~/ 365} tahun lalu';
  }
  return 'Dipakai ${usageCount}x, terakhir $when';
}
