import 'package:image_picker/image_picker.dart';

import '../models/cart_item.dart';
import '../models/member_profile.dart';
import '../models/product.dart';
import '../models/shipping_rate.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

class ReorderCartLine {
  final Product product;
  final int quantity;
  final String? variantLabel;
  final bool adjusted;
  final bool priceChanged;

  const ReorderCartLine({
    required this.product,
    required this.quantity,
    this.variantLabel,
    this.adjusted = false,
    this.priceChanged = false,
  });
}

class ReorderResult {
  final List<ReorderCartLine> items;
  final List<String> skippedReasons;
  final int adjustedCount;

  const ReorderResult({
    required this.items,
    required this.skippedReasons,
    required this.adjustedCount,
  });

  bool get hasPartialChanges => adjustedCount > 0 || skippedReasons.isNotEmpty;
}

class OrderResult {
  final String orderNumber;
  final String message;
  final String? detailUrl;
  final String? paymentUrl;
  final String? trackingToken;

  const OrderResult({
    required this.orderNumber,
    required this.message,
    this.detailUrl,
    this.paymentUrl,
    this.trackingToken,
  });
}

class OrderService {
  Future<OrderSummary> fetchOrderDetail(
    String orderNumber, {
    String? trackingToken,
  }) async {
    final data = await apiClient.getJson(
      '/api/orders/${Uri.encodeComponent(orderNumber)}',
      query: {
        if (trackingToken != null && trackingToken.isNotEmpty)
          'token': trackingToken,
      },
    );
    final raw = data['order'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Detail pesanan tidak ditemukan.');
    }
    return OrderSummary.fromApiJson(raw);
  }

  Future<OrderResult> createOrder({
    required List<CartItem> items,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
    required MemberAddress address,
    required ShippingRate shippingRate,
    required String paymentProvider,
    String? voucherCode,
    String? manualVoucherCode,
    String? notes,
  }) async {
    // Guard: blok di read-only mode supaya Capacitor database tidak
    // dapat order test dari Flutter.
    readOnlyMode.assertWritable('checkout');
    final selfPickup = shippingRate.isSelfPickup;
    const selfPickupAddress =
        'Jln MT. Haryono No 103 B C D, Pusat Pasar, Medan Kota';
    const selfPickupCity = 'Medan Kota';
    final data = await apiClient.postJson(
      '/api/orders',
      body: {
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerEmail': customerEmail,
        'orderType': selfPickup ? 'SELF_PICKUP' : 'DELIVERY',
        'shippingMethod': selfPickup ? 'SELF_PICKUP' : 'DELIVERY',
        'shippingAddress': selfPickup ? selfPickupAddress : address.address,
        'shippingCity': selfPickup ? selfPickupCity : address.city ?? '',
        'shippingPostalCode': selfPickup ? '' : address.postalCode ?? '',
        'shippingLatitude': selfPickup ? null : address.latitude,
        'shippingLongitude': selfPickup ? null : address.longitude,
        'shippingPinpointAddress': selfPickup ? null : address.pinpointAddress,
        'shippingAreaId': selfPickup ? '' : address.areaId,
        'shippingAreaLabel': selfPickup ? '' : address.areaLabel ?? '',
        'shippingProvinceName': selfPickup ? '' : address.provinceName ?? '',
        'shippingDistrictName': selfPickup ? '' : address.districtName ?? '',
        'courierCode': selfPickup ? '' : shippingRate.courierCode,
        'courierService': selfPickup ? '' : shippingRate.serviceCode,
        'shippingCost': shippingRate.price,
        'paymentProvider': paymentProvider,
        'manualBank': paymentProvider == 'MANUAL' ? 'BCA_NATASHA' : null,
        if (voucherCode != null && voucherCode.isNotEmpty)
          'voucherCode': voucherCode,
        if (manualVoucherCode != null && manualVoucherCode.isNotEmpty)
          'manualVoucherCode': manualVoucherCode,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'items': items.map((item) {
          // Pakai effectivePrice + variant.weightGram kalau varian dipilih,
          // supaya server tahu varian mana yang dipesan + harga match.
          final variant = item.variant;
          return {
            'productId': item.product.id,
            if (variant != null) 'variantId': variant.id,
            if (variant != null) 'variantLabel': item.variantLabel,
            'name': item.product.title,
            'price': item.effectivePrice.round(),
            'quantity': item.quantity,
            'weightGram': variant?.weightGram ?? item.product.weightGram,
          };
        }).toList(),
      },
    );

    return OrderResult(
      orderNumber: (data['orderNumber'] ?? '').toString(),
      message: (data['message'] ?? 'Order dibuat.').toString(),
      detailUrl: data['detailUrl']?.toString(),
      paymentUrl: data['paymentUrl']?.toString(),
      trackingToken: data['trackingToken']?.toString(),
    );
  }

  Future<String> uploadPaymentProof({
    required String orderNumber,
    required XFile file,
    String? trackingToken,
  }) async {
    readOnlyMode.assertWritable('payment_proof');
    final data = await apiClient.postMultipartFile(
      '/api/orders/${Uri.encodeComponent(orderNumber)}/payment-proof',
      query: {
        if (trackingToken != null && trackingToken.isNotEmpty)
          'token': trackingToken,
      },
      fieldName: 'file',
      filePath: file.path,
      filename: file.name,
      contentType: file.mimeType ?? _mimeTypeFromPath(file.path),
    );

    return (data['url'] ?? '').toString();
  }

  Future<ReorderResult> reorder({
    required String orderNumber,
    String? itemId,
  }) async {
    // Reorder POST endpoint — di-skip di read-only meskipun side effect
    // di server umumnya read+suggest, bukan write hard data.
    readOnlyMode.assertWritable('reorder');
    final data = await apiClient.postJson(
      '/api/orders/${Uri.encodeComponent(orderNumber)}/reorder',
      body: {
        if (itemId != null && itemId.isNotEmpty) 'itemId': itemId,
      },
    );

    final added = _parseReorderEntries(data['added'], adjusted: false);
    final adjusted = _parseReorderEntries(data['adjusted'], adjusted: true);
    final skipped = _parseSkippedReasons(data['skipped']);

    return ReorderResult(
      items: [...added, ...adjusted],
      skippedReasons: skipped,
      adjustedCount: adjusted.length,
    );
  }

  /// Cancel pesanan user. Match endpoint PWA POST /api/orders/{number}/cancel
  /// dengan body `{reason}`. Server validate status (hanya PENDING/PAID
  /// yang bisa di-cancel; SHIPPED/DELIVERED ditolak).
  ///
  /// Return updated OrderSummary dengan status='CANCELLED'.
  Future<void> cancelOrder({
    required String orderNumber,
    String? reason,
  }) async {
    readOnlyMode.assertWritable('cancel_order');
    await apiClient.postJson(
      '/api/orders/${Uri.encodeComponent(orderNumber)}/cancel',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  /// Bulk status check untuk multiple orders. Match endpoint PWA
  /// GET /api/orders/status?numbers=NAT-001,NAT-002,...
  ///
  /// Dipakai untuk refresh status order list tanpa fetch full detail.
  /// Return map orderNumber → status.
  Future<Map<String, String>> bulkStatus(List<String> orderNumbers) async {
    if (orderNumbers.isEmpty) return const {};
    try {
      final data = await apiClient.getJson('/api/orders/status', query: {
        'numbers': orderNumbers.join(','),
      });
      final raw = data['statuses'] ?? data['data'];
      if (raw is! Map<String, dynamic>) return const {};
      return raw.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return const {};
    }
  }

  /// Initiate Midtrans payment gateway. Match endpoint PWA
  /// POST /api/payment/midtrans dengan body `{orderNumber}`.
  /// Return Snap token untuk launch Midtrans Snap dialog.
  Future<MidtransPaymentToken?> initiateMidtrans({
    required String orderNumber,
  }) async {
    readOnlyMode.assertWritable('payment_midtrans');
    try {
      final data = await apiClient.postJson(
        '/api/payment/midtrans',
        body: {'orderNumber': orderNumber},
      );
      final token = data['token']?.toString();
      final redirectUrl =
          data['redirectUrl']?.toString() ?? data['redirect_url']?.toString();
      if (token == null || token.isEmpty) return null;
      return MidtransPaymentToken(
        token: token,
        redirectUrl: redirectUrl ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  String _mimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  List<ReorderCartLine> _parseReorderEntries(
    Object? raw, {
    required bool adjusted,
  }) {
    if (raw is! List) return const [];

    return raw
        .whereType<Map<String, dynamic>>()
        .map((entry) {
          final item = entry['item'];
          if (item is! Map<String, dynamic>) return null;

          final product = Product.fromApiJson({
            'id': item['productId'],
            'slug': item['productId'],
            'name': item['name'],
            'imageUrl': item['imageUrl'],
            'price': item['price'],
            'stock': item['stock'],
            'weightGram': item['weightGram'],
            'category_name': 'Produk',
            'brand_name': 'Natalo',
          });

          return ReorderCartLine(
            product: product,
            quantity: _asInt(item['quantity'], fallback: 1),
            variantLabel: item['variantLabel']?.toString(),
            adjusted: adjusted,
            priceChanged: entry['priceChanged'] == true,
          );
        })
        .whereType<ReorderCartLine>()
        .toList();
  }

  List<String> _parseSkippedReasons(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((item) => (item['reason'] ?? '').toString())
        .where((reason) => reason.isNotEmpty)
        .toList();
  }

  int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

final orderService = OrderService();

/// Result dari /api/payment/midtrans — token untuk launch Snap dialog.
class MidtransPaymentToken {
  final String token;
  final String redirectUrl;

  const MidtransPaymentToken({
    required this.token,
    required this.redirectUrl,
  });
}
