import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show XFile;

import '../config/api_config.dart';
import '../models/cart_item.dart';
import '../models/member_address.dart';
import '../models/member_profile.dart';
import '../models/shipping_rate.dart';
import '../state/member_store.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

/// Order detail + actions (cancel, upload payment proof, reorder).
class OrderService {
  OrderService._();

  Map<String, String> _headers({bool json = false}) {
    final token = memberStore.sessionToken;
    return {
      if (json) 'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
      if (token != null) 'cookie': 'member_session=$token',
    };
  }

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
    String? freeShippingVoucherCode,
    String? productVoucherCode,
    String? loyaltyVoucherCode,
    String? privateVoucherCode,
    String? notes,
  }) async {
    // Guard: blok di read-only mode supaya Capacitor database tidak
    // dapat order test dari Flutter.
    readOnlyMode.assertWritable('checkout');
    final selfPickup = shippingRate.isSelfPickup;
    const selfPickupCity = 'Medan Kota';
    final data = await apiClient.postJson(
      '/api/orders',
      body: {
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerEmail': customerEmail,
        'orderType': selfPickup ? 'SELF_PICKUP' : 'DELIVERY',
        'shippingMethod': selfPickup ? 'SELF_PICKUP' : 'DELIVERY',
        if (selfPickup) 'pickupLocationId': PickupStoreInfo.id,
        if (selfPickup) 'pickup_location_id': PickupStoreInfo.id,
        if (selfPickup) 'pickupLocationName': PickupStoreInfo.name,
        if (selfPickup) 'pickupAddress': PickupStoreInfo.address,
        if (selfPickup) 'pickupHours': PickupStoreInfo.hours,
        if (selfPickup) 'pickupMapsUrl': PickupStoreInfo.mapsUrl,
        'shippingAddress':
            selfPickup ? PickupStoreInfo.address : address.address,
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
        if (freeShippingVoucherCode != null &&
            freeShippingVoucherCode.isNotEmpty)
          'freeShippingVoucherCode': freeShippingVoucherCode,
        if (productVoucherCode != null && productVoucherCode.isNotEmpty)
          'productVoucherCode': productVoucherCode,
        if (loyaltyVoucherCode != null && loyaltyVoucherCode.isNotEmpty)
          'loyaltyVoucherCode': loyaltyVoucherCode,
        if (privateVoucherCode != null && privateVoucherCode.isNotEmpty)
          'privateVoucherCode': privateVoucherCode,
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
      final data = await apiClient.getJson(
        '/api/orders/status',
        query: {'numbers': orderNumbers.join(',')},
      );
      if (data is Map<String, dynamic>) {
        return data.map((k, v) => MapEntry(k, v.toString()));
      }
      return const {};
    } catch (e) {
      if (kDebugMode) debugPrint('[orderService.bulkStatus] $e');
      return const {};
    }
  }
}

final OrderService orderService = OrderService._();

// ── Helpers untuk reorder parsing ──
List<OrderItemSummary> _parseReorderEntries(dynamic raw, {required bool adjusted}) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(OrderItemSummary.fromJson)
      .toList();
}

List<String> _parseSkippedReasons(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((e) => e.toString()).toList();
}

String _mimeTypeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  return 'image/jpeg'; // default
}

/// Result reorder — list item yang berhasil di-add + alasan skip kalau ada.
class ReorderResult {
  final List<OrderItemSummary> items;
  final List<String> skippedReasons;
  /// Jumlah item yang di-adjust (qty dikurangi karena stock kurang).
  final int adjustedCount;
  const ReorderResult({
    this.items = const [],
    this.skippedReasons = const [],
    this.adjustedCount = 0,
  });

  bool get hasPartialChanges => skippedReasons.isNotEmpty || adjustedCount > 0;
}

/// Result create order — kembali dari POST /api/orders.
class OrderResult {
  final String orderNumber;
  final String message;
  final String? detailUrl;
  final String? paymentUrl;
  final String? trackingToken;
  final String? paymentProvider;
  final String? manualBank;

  const OrderResult({
    required this.orderNumber,
    this.message = '',
    this.detailUrl,
    this.paymentUrl,
    this.trackingToken,
    this.paymentProvider,
    this.manualBank,
  });
}

