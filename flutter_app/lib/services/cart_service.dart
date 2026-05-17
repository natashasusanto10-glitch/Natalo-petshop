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
      final price = _asDouble(item['price']);
      final product = Product(
        id: (item['productId'] ?? '').toString(),
        slug: (item['productId'] ?? '').toString(),
        title: (item['name'] ?? 'Produk Natalo').toString(),
        category: 'Produk',
        brand: 'Natalo',
        imageUrl: (item['imageUrl'] ?? '').toString(),
        price: price,
        rating: 0,
        reviewCount: 0,
        stock: _asInt(item['stock'], fallback: 999),
        weightGram: _asInt(item['weightGram'], fallback: 500),
        description: '',
      );
      return CartItem(
        product: product,
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
            'name': item.product.title,
            'price': item.product.finalPrice.round(),
            'quantity': item.quantity,
            'weightGram': item.product.weightGram,
            'imageUrl': item.product.imageUrl,
            'stock': item.product.stock,
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
          'items': items.map((item) => {
                'productId': item.product.id,
                'quantity': item.quantity,
                'price': item.product.finalPrice.round(),
              }).toList(),
        },
      );
      final issues = data['issues'];
      return CartValidationResult(
        valid: data['valid'] != false,
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
  }) async {
    try {
      final data = await apiClient.postJson(
        '/api/cart/vouchers/validate-private',
        body: {'code': code.trim(), 'subtotal': subtotal},
      );
      return CartPrivateVoucherResult(
        valid: data['valid'] == true,
        code: (data['code'] ?? code).toString(),
        discountAmount: _asInt(data['discountAmount']),
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

class CartValidationIssue {
  final String productId;
  final String code; // mis. "OUT_OF_STOCK", "PRICE_CHANGED", "DISABLED"
  final String message;
  final int? newStock;
  final num? newPrice;

  const CartValidationIssue({
    required this.productId,
    required this.code,
    required this.message,
    this.newStock,
    this.newPrice,
  });

  factory CartValidationIssue.fromJson(Map<String, dynamic> json) {
    return CartValidationIssue(
      productId: (json['productId'] ?? '').toString(),
      code: (json['code'] ?? 'UNKNOWN').toString(),
      message: (json['message'] ?? '').toString(),
      newStock: _asInt(json['newStock'], fallback: 0),
      newPrice: json['newPrice'] is num ? json['newPrice'] as num : null,
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
