import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../models/cart_item.dart';
import '../models/member_profile.dart';
import '../models/shipping_rate.dart';
import '../utils/read_only_mode.dart';
import 'api_client.dart';

/// Order detail + actions (cancel, upload payment proof, reorder).
class OrderService {
  OrderService._();

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
    int refundBalanceUsed = 0,
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
        if (refundBalanceUsed > 0) 'refundBalanceUsed': refundBalanceUsed,
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
      status: data['status']?.toString(),
      paymentStatus: data['paymentStatus']?.toString(),
      paymentProvider: data['paymentProvider']?.toString(),
      manualBank: data['manualBank']?.toString(),
      uniqueCode: data['uniqueCode'] is num
          ? (data['uniqueCode'] as num).round()
          : int.tryParse(data['uniqueCode']?.toString() ?? ''),
      paymentDeadline: DateTime.tryParse(
        data['paymentDeadline']?.toString() ?? '',
      ),
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

  /// Cancel pesanan user. Match endpoint POST /api/orders/{number}/cancel
  /// dengan body `{reason}`. Server validate status (hanya PENDING/PAID/
  /// PROCESSING — "sebelum paket dikirim" — yang bisa di-cancel;
  /// SHIPPED/DELIVERED ditolak).
  ///
  /// Return [CancelOrderResult] dengan `autoRefundedAmount` dan
  /// `reversedSaldo`:
  ///   - kalau paymentStatus != "PAID" saat cancel, autoRefundedAmount = 0
  ///     (user belum bayar / admin belum konfirmasi → no refund)
  ///   - kalau paymentStatus == "PAID", server otomatis kredit total
  ///     order ke Saldo Refund user; nominal di field autoRefundedAmount.
  /// UI pakai value ini untuk tampilkan toast informatif.
  Future<CancelOrderResult> cancelOrder({
    required String orderNumber,
    String? reason,
  }) async {
    readOnlyMode.assertWritable('cancel_order');
    final response = await apiClient.postJson(
      '/api/orders/${Uri.encodeComponent(orderNumber)}/cancel',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    final data = response is Map<String, dynamic> ? response : const <String, dynamic>{};
    final auto = data['autoRefundedAmount'];
    final reversed = data['reversedSaldo'];
    final modeRaw = data['mode'];
    final awaitingApproval = data['awaitingApproval'] == true;
    final alreadyRequested = data['alreadyRequested'] == true;
    final message = data['message'];
    final mode = modeRaw is String
        ? modeRaw
        : (awaitingApproval ? 'requested' : 'instant');
    return CancelOrderResult(
      mode: mode,
      autoRefundedAmount: auto is num ? auto.toInt() : 0,
      reversedSaldo: reversed is num ? reversed.toInt() : 0,
      alreadyRequested: alreadyRequested,
      serverMessage: message is String ? message : null,
    );
  }

  /// User konfirmasi paket sudah diterima. Match endpoint POST
  /// /api/orders/{number}/confirm-delivered. Server transit status
  /// SHIPPED → DELIVERED, kirim notif "Pesanan selesai" ke email + push.
  ///
  /// Idempotent: kalau order sudah DELIVERED, return result dengan
  /// `alreadyConfirmed = true` (bukan error) — client jangan show pesan
  /// gagal kalau user double-tap tombolnya.
  Future<ConfirmDeliveredResult> confirmDelivered({
    required String orderNumber,
  }) async {
    readOnlyMode.assertWritable('confirm_delivered');
    final response = await apiClient.postJson(
      '/api/orders/${Uri.encodeComponent(orderNumber)}/confirm-delivered',
    );
    final data = response is Map<String, dynamic>
        ? response
        : const <String, dynamic>{};
    return ConfirmDeliveredResult(
      alreadyConfirmed: data['alreadyConfirmed'] == true,
      message: data['message'] is String
          ? data['message'] as String
          : 'Pesanan ditandai selesai.',
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

  Future<MidtransPaymentToken?> initiateMidtrans({
    required String orderNumber,
  }) async {
    try {
      final data = await apiClient.postJson(
        '/api/orders/${Uri.encodeComponent(orderNumber)}/midtrans',
        body: const {},
      );
      if (data is! Map<String, dynamic>) return null;
      final redirectUrl =
          (data['redirectUrl'] ?? data['redirect_url'] ?? data['paymentUrl'])
              ?.toString();
      if (redirectUrl == null || redirectUrl.isEmpty) return null;
      return MidtransPaymentToken(
        token: data['token']?.toString(),
        redirectUrl: redirectUrl,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[orderService.initiateMidtrans] $e');
      return null;
    }
  }
}

final OrderService orderService = OrderService._();

// ── Helpers untuk reorder parsing ──
//
// Backend response shape (lib/reorder.ts):
//   {
//     added: [
//       {
//         status: "added",
//         item: { productId, variantId, variantLabel, name, price,
//                 quantity, weightGram, stock, imageUrl },
//         priceChanged: bool,
//         previousPrice: number,
//       },
//       ...
//     ],
//     adjusted: [...same shape with requestedQuantity + availableStock],
//     skipped: [...]
//   }
//
// Entry-nya WRAPPED dengan `status` + `item` subobject — bukan flat
// OrderItemSummary. Plus `id` field tidak ada di ReorderCartItem
// (Flutter expects `id` as required String) → langsung crash dengan
// "type 'Null' is not a subtype of type 'String' in type cast"
// kalau pass ke OrderItemSummary.fromJson tanpa unwrap.
//
// Fix: unwrap `entry['item']`, lalu synthesize `id` dari productId +
// variantId fallback supaya OrderItemSummary.fromJson punya valid id.
List<OrderItemSummary> _parseReorderEntries(dynamic raw,
    {required bool adjusted}) {
  if (raw is! List) return const [];
  final result = <OrderItemSummary>[];
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) continue;
    // Backend bisa kasih item di `entry['item']` (canonical) atau flat
    // (legacy). Handle keduanya — coba unwrap dulu, fallback ke flat.
    final rawItem = entry['item'];
    final itemMap = rawItem is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawItem)
        : Map<String, dynamic>.from(entry);

    // Synthesize id kalau tidak ada — pakai productId + variantId
    // (deterministic, OK untuk dedupe di cart). Tanpa ini, fromJson
    // crash di line `json['id'] as String`.
    if (itemMap['id'] == null) {
      final productId = itemMap['productId']?.toString() ?? '';
      final variantId = itemMap['variantId']?.toString();
      itemMap['id'] = variantId != null && variantId.isNotEmpty
          ? '$productId:$variantId'
          : productId;
    }
    try {
      result.add(OrderItemSummary.fromJson(itemMap));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[reorder] skip malformed entry: $e — raw: $entry');
      }
      // Skip entry yang gagal parse, jangan throw — supaya item lain
      // yang valid tetap bisa di-reorder.
    }
  }
  return result;
}

/// Parse backend skipped reorder items menjadi friendly Indonesian message.
///
/// Bug fix: sebelumnya `e.toString()` di Map JS-style produce raw JSON
/// dump yang user-hostile:
///   "{status: skipped, productId: cmpb..., reason: Stok habis.,
///     reasonCode: OUT_OF_STOCK, availableStock: 0}"
///
/// Sekarang extract field `name` + `reason` jadi clean message:
///   "Akari Premium Blue Red Yellow 160g — Stok habis."
///
/// Backend schema (lib/reorder.ts ReorderSkippedResult):
///   { status, productId, variantId, variantLabel, name, reason,
///     reasonCode, availableStock? }
List<String> _parseSkippedReasons(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) {
        if (e is Map) {
          final name = (e['name'] ?? '').toString().trim();
          final reason =
              (e['reason'] ?? 'Tidak bisa dibeli lagi').toString().trim();
          // Variant info kalau ada (e.g. "4kg / Beef") supaya user tau
          // varian spesifik yang gak available.
          final variant = (e['variantLabel'] ?? '').toString().trim();
          final productLabel = variant.isNotEmpty && name.isNotEmpty
              ? '$name ($variant)'
              : name;
          if (productLabel.isEmpty) return reason;
          // Strip trailing period dari reason supaya format konsisten dgn dash.
          final cleanReason = reason.endsWith('.')
              ? reason.substring(0, reason.length - 1)
              : reason;
          return '$productLabel — $cleanReason';
        }
        return e.toString();
      })
      .where((s) => s.isNotEmpty)
      .toList();
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
  final String? status;
  final String? paymentStatus;
  final String? paymentProvider;
  final String? manualBank;
  final int? uniqueCode;
  final DateTime? paymentDeadline;

  const OrderResult({
    required this.orderNumber,
    this.message = '',
    this.detailUrl,
    this.paymentUrl,
    this.trackingToken,
    this.status,
    this.paymentStatus,
    this.paymentProvider,
    this.manualBank,
    this.uniqueCode,
    this.paymentDeadline,
  });
}

class MidtransPaymentToken {
  final String? token;
  final String redirectUrl;

  const MidtransPaymentToken({
    this.token,
    required this.redirectUrl,
  });
}

/// Result dari [OrderService.confirmDelivered].
/// - [alreadyConfirmed]: true kalau order sudah DELIVERED sebelumnya (idempotent
///   response — bukan error). UI bisa skip toast atau pakai message yang beda.
/// - [message]: text dari server untuk toast / dialog success.
class ConfirmDeliveredResult {
  final bool alreadyConfirmed;
  final String message;

  const ConfirmDeliveredResult({
    required this.alreadyConfirmed,
    required this.message,
  });
}

/// Result dari [OrderService.cancelOrder]. Dua mode possible:
///
/// 1) `mode == "instant"` (paymentStatus belum PAID):
///    Order langsung di-cancel server. [autoRefundedAmount] biasanya 0
///    (tidak ada duit masuk), [reversedSaldo] bisa > 0 kalau user pakai
///    saldo untuk order yang belum dikonfirmasi bayar.
///
/// 2) `mode == "requested"` (paymentStatus === PAID):
///    Server bikin pending request, status order BELUM berubah. User
///    nunggu admin Approve/Reject. UI tampilkan banner "Menunggu
///    konfirmasi admin". Kalau request sebelumnya udah PENDING,
///    [alreadyRequested] = true (response idempotent).
class CancelOrderResult {
  /// "instant" atau "requested". Lihat doc di atas.
  final String mode;
  final int autoRefundedAmount;
  final int reversedSaldo;
  final bool alreadyRequested;

  /// Pesan dari server (kalau ada) — untuk requested mode biasanya
  /// "Permintaan pembatalan dikirim. Menunggu konfirmasi admin."
  final String? serverMessage;

  const CancelOrderResult({
    required this.mode,
    required this.autoRefundedAmount,
    required this.reversedSaldo,
    this.alreadyRequested = false,
    this.serverMessage,
  });

  /// True kalau pembatalan instan (langsung sukses di server). False
  /// untuk request mode (menunggu approval admin).
  bool get isInstant => mode == 'instant';

  /// True kalau pembatalan butuh approval admin (paymentStatus PAID).
  bool get isRequested => mode == 'requested';

  /// Total kredit ke saldo dari instant cancel (auto-refund + reversal
  /// saldo). Selalu 0 untuk request mode (belum ada cancel actual).
  int get totalCredited => autoRefundedAmount + reversedSaldo;
}
