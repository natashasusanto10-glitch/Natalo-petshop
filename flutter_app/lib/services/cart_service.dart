import '../models/cart_item.dart';
import '../models/product.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

class CartService {
  Future<List<CartItem>> fetchCart() async {
    final data = await apiClient.getJson('/api/cart');
    final rawItems = data['items'];
    if (rawItems is! List) return [];

    return rawItems.whereType<Map<String, dynamic>>().map((item) {
      // Product.price = double. Cart endpoint return number — convert
      // via _asDouble untuk handle int/double/string uniformly.
      final price = _asDouble(item['price']);
      final originalPrice = _asDouble(item['originalPrice']);
      final displayPrice = originalPrice > price ? originalPrice : price;
      final variantId = item['variantId']?.toString();
      final stock = _asInt(item['stock'], fallback: 999);
      final weightGram = _asInt(item['weightGram'], fallback: 500);
      final product = Product(
        id: (item['productId'] ?? '').toString(),
        slug: (item['productId'] ?? '').toString(),
        title: (item['name'] ?? 'Produk Natalo').toString(),
        category: 'Produk',
        brand: 'Natalo',
        imageUrl: (item['imageUrl'] ?? '').toString(),
        price: displayPrice.toDouble(),
        discountPrice: originalPrice > price ? price.toDouble() : null,
        rating: 0,
        reviewCount: 0,
        stock: stock,
        weightGram: weightGram,
        description: '',
      );
      final variant = variantId == null || variantId.isEmpty
          ? null
          : ProductVariant(
              id: variantId,
              price: displayPrice.round(),
              stock: stock,
              weightGram: weightGram,
            );
      return CartItem(
        product: product,
        variant: variant,
        variantLabel: item['variantLabel']?.toString(),
        unitPrice: price.round(),
        effectiveStock: stock,
        quantity: _asInt(item['quantity'], fallback: 1),
      );
    }).toList();
  }

  Future<void> replaceCart(List<CartItem> items) async {
    // Cart sync write — block di read-only supaya cart user yang
    // login di Capacitor tidak ke-overwrite oleh state Flutter.
    readOnlyMode.assertWritable('cart_sync');
    await apiClient.putJson(
      '/api/cart',
      body: {
        'items': items.map((item) {
          return {
            'productId': item.product.id,
            if (item.variantId != null) 'variantId': item.variantId,
            if (item.variantLabel != null) 'variantLabel': item.variantLabel,
            'name': item.product.title,
            'price': item.effectivePrice.round(),
            'quantity': item.quantity,
            'weightGram': item.weightGram,
            'imageUrl': item.product.imageUrl,
            'stock': item.effectiveStock,
          };
        }).toList(),
      },
    );
  }

  /// Validate cart sebelum checkout. Match endpoint PWA POST /api/cart/validate.
  /// Server cek: stok masih cukup, harga masih sama, produk belum di-disable.
  /// Return list issues kalau ada (mis. stok kurang, harga berubah).
  Future<CartValidationResult> validate(List<CartItem> items) async {
    try {
      final data = await apiClient.postJson(
        '/api/cart/validate',
        body: {
          'items': items
              .map((item) => {
                    'productId': item.product.id,
                    if (item.variantId != null) 'variantId': item.variantId,
                    if (item.variantLabel != null)
                      'variantLabel': item.variantLabel,
                    'quantity': item.quantity,
                    'price': item.effectivePrice.round(),
                    'weightGram': item.weightGram,
                  })
              .toList(),
        },
      );
      final issues = data['issues'];
      // Backend (reconcileCartItemsWithStock) balikin `ok`, bukan `valid`.
      return CartValidationResult(
        valid: (data['ok'] ?? data['valid']) != false,
        issues: issues is List
            ? issues
                .whereType<Map<String, dynamic>>()
                .map(CartValidationIssue.fromJson)
                .toList()
            : const [],
      );
    } catch (_) {
      // Anggap valid kalau endpoint error — caller masih bisa proceed.
      return const CartValidationResult(valid: true, issues: []);
    }
  }

  /// Validate private voucher code (SELLER_MANUAL type yang rahasia).
  /// Match endpoint PWA POST /api/cart/vouchers/validate-private.
  /// Public voucher cukup pakai /api/cart/vouchers GET (sudah ada).
  Future<CartPrivateVoucherResult> validatePrivateVoucher({
    required String code,
    required int subtotal,
    List<String>? productIds,
  }) async {
    try {
      final data = await apiClient.postJson(
        '/api/cart/vouchers/validate-private',
        body: {
          'code': code.trim(),
          'subtotal': subtotal,
          if (productIds != null && productIds.isNotEmpty)
            'productIds': productIds,
        },
      );
      final voucher = data['voucher'];
      final voucherJson = voucher is Map<String, dynamic> ? voucher : data;
      return CartPrivateVoucherResult(
        valid: data['ok'] == true || data['valid'] == true,
        code: (voucherJson['code'] ?? data['code'] ?? code).toString(),
        discountAmount: _asInt(
          voucherJson['discount'] ??
              voucherJson['discountAmount'] ??
              data['discountAmount'],
        ),
        message: data['message']?.toString(),
      );
    } catch (error) {
      return CartPrivateVoucherResult(
        valid: false,
        code: code,
        discountAmount: 0,
        message: error.toString(),
      );
    }
  }
}

class CartValidationResult {
  final bool valid;
  final List<CartValidationIssue> issues;

  const CartValidationResult({required this.valid, required this.issues});
}

/// Isu stok per item dari POST /api/cart/validate (reconcileCartItemsWithStock).
/// Backend balikin per item bermasalah: action "removed" (stok habis /
/// produk tidak tersedia) atau "reduced" (stok < qty diminta, qty perlu
/// disesuaikan ke availableStock).
class CartValidationIssue {
  final String productId;
  final String? variantId;

  /// "removed" = stok habis / produk nonaktif (tidak bisa checkout).
  /// "reduced" = stok tersisa < qty di cart (availableStock = sisa).
  final String action;
  final int availableStock;
  final String message;

  const CartValidationIssue({
    required this.productId,
    this.variantId,
    required this.action,
    required this.availableStock,
    required this.message,
  });

  /// Tidak bisa di-checkout sama sekali (stok 0 / nonaktif).
  bool get isOutOfStock => action == 'removed' || availableStock <= 0;

  /// Stok berkurang tapi masih ada — qty harus disesuaikan.
  bool get isReduced => action == 'reduced' && availableStock > 0;

  /// Key konsisten productId:variantId (variantId kosong = produk tanpa
  /// varian). Dipakai cart_screen untuk map issue → item.
  String get matchKey => '$productId:${variantId ?? ''}';

  factory CartValidationIssue.fromJson(Map<String, dynamic> json) {
    final rawVariant = json['variantId']?.toString() ?? '';
    return CartValidationIssue(
      productId: (json['productId'] ?? '').toString(),
      variantId: rawVariant.isEmpty ? null : rawVariant,
      action: (json['action'] ?? 'removed').toString(),
      availableStock: _asInt(json['availableStock'], fallback: 0),
      message: (json['message'] ?? '').toString(),
    );
  }
}

class CartPrivateVoucherResult {
  final bool valid;
  final String code;
  final int discountAmount;
  final String? message;

  const CartPrivateVoucherResult({
    required this.valid,
    required this.code,
    required this.discountAmount,
    this.message,
  });
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

final cartService = CartService();
