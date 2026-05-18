import 'product.dart';

/// Cart item — embeds Product reference + optional variant + per-line qty.
/// Disimpan di disk via CartStore. Sync ke server saat user login + online.
class CartItem {
  final Product product;
  final ProductVariant? variant;
  /// Snapshot label varian ("4KG / Beef") — tidak berubah meski varian diedit.
  final String? variantLabel;
  /// Override price kalau dikasih — kalau null, derive dari variant.price ?? product.finalPrice.
  final int _unitPriceOverride;
  /// Override stock kalau dikasih — kalau null, derive dari variant.stock ?? product.stock.
  final int _effectiveStockOverride;
  final int quantity;

  /// Constructor primary — boleh pass variant lengkap atau override per field.
  CartItem({
    required this.product,
    this.variant,
    this.variantLabel,
    required this.quantity,
    int? unitPrice,
    int? effectiveStock,
  })  : _unitPriceOverride =
            unitPrice ?? variant?.price ?? product.finalPrice.round(),
        _effectiveStockOverride =
            effectiveStock ?? variant?.stock ?? product.stock;

  String? get variantId => variant?.id;

  int get unitPrice => _unitPriceOverride;
  int get effectiveStock => _effectiveStockOverride;
  /// Alias `unitPrice` — beberapa code pakai `effectivePrice` literal.
  /// Returns double untuk konsistensi dengan Product.finalPrice.
  double get effectivePrice => _unitPriceOverride.toDouble();

  /// Identitas unik per line.
  String get key => variantId == null ? product.id : '${product.id}:$variantId';

  /// Subtotal harga × jumlah.
  int get lineTotal => unitPrice * quantity;

  /// Backward-compat aliases.
  int get subtotal => lineTotal;
  String get lineKey => key;
  String get name => product.title;
  String? get imageUrl => product.imageUrl;
  String? get slug => product.slug;
  String get productId => product.id;
  int get weightGram => product.weightGram;

  CartItem copyWith({
    int? quantity,
    int? unitPrice,
    int? effectiveStock,
  }) {
    return CartItem(
      product: product,
      variant: variant,
      variantLabel: variantLabel,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      effectiveStock: effectiveStock ?? this.effectiveStock,
    );
  }

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        if (variantId != null) 'variantId': variantId,
        if (variantLabel != null) 'variantLabel': variantLabel,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'effectiveStock': effectiveStock,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final productJson = json['product'];
    final product = productJson is Map<String, dynamic>
        ? Product.fromJson(productJson)
        : Product(
            id: json['productId'] as String? ?? '',
            title: json['name'] as String? ?? '',
            slug: json['slug'] as String? ?? '',
            category: '',
            brand: '',
            description: '',
            price: (json['unitPrice'] as num?)?.toDouble() ?? 0,
            imageUrl: (json['imageUrl'] as String?) ?? '',
            weightGram: (json['weightGram'] as num?)?.toInt() ?? 500,
            stock: (json['stock'] as num?)?.toInt() ?? 0,
            rating: 0,
            reviewCount: 0,
          );
    return CartItem(
      product: product,
      variantLabel: json['variantLabel'] as String?,
      unitPrice:
          (json['unitPrice'] as num?)?.toInt() ?? product.finalPrice.round(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      effectiveStock:
          (json['effectiveStock'] as num?)?.toInt() ?? product.stock,
    );
  }
}
