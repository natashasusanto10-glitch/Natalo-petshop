import 'product.dart';

class CartItem {
  final Product product;
  final int quantity;
  /// Variant terpilih (kalau produk multi-varian). Null untuk single-variant.
  final ProductVariant? variant;

  const CartItem({
    required this.product,
    required this.quantity,
    this.variant,
  });

  /// Cart key — beda untuk tiap variant berbeda dari product yang sama,
  /// supaya user bisa tambah 2 varian dari produk yang sama.
  String get key =>
      variant != null ? '${product.id}::${variant!.id}' : product.id;

  /// Harga effektif — varian price kalau ada, else product.finalPrice.
  double get effectivePrice =>
      variant?.price ?? product.finalPrice;

  /// Stok effektif — varian stock kalau ada, else product.stock.
  int get effectiveStock => variant?.stock ?? product.stock;

  /// Label varian untuk display ("Ukuran: 1kg" / "Warna: Merah").
  /// Resolve dari product.variantAttrs + variant.optionIds.
  String? get variantLabel {
    final v = variant;
    if (v == null) return null;
    final parts = <String>[];
    for (final attr in product.variantAttrs) {
      for (final opt in attr.options) {
        if (v.optionIds.contains(opt.id)) {
          parts.add(opt.value);
        }
      }
    }
    return parts.isEmpty ? null : parts.join(' / ');
  }

  double get lineTotal => effectivePrice * quantity;

  CartItem copyWith({
    Product? product,
    int? quantity,
    ProductVariant? variant,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      variant: variant ?? this.variant,
    );
  }

  /// Serialize ke local storage untuk persist cart antar app session.
  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'quantity': quantity,
        if (variant != null) 'variant': variant!.toJson(),
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final productRaw = json['product'];
    final variantRaw = json['variant'];
    return CartItem(
      product: productRaw is Map<String, dynamic>
          ? Product.fromApiJson(productRaw)
          : throw ArgumentError('Invalid product json in CartItem'),
      quantity: (json['quantity'] is num)
          ? (json['quantity'] as num).round()
          : int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      variant: variantRaw is Map<String, dynamic>
          ? ProductVariant.fromJson(variantRaw)
          : null,
    );
  }
}
