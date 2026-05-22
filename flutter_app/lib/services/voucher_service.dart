import 'package:flutter/foundation.dart';

import '../models/member_profile.dart';
import '../models/shipping_rate.dart';
import 'api_client.dart';

/// Validate voucher code generic (bukan cart-context). Match endpoint PWA
/// POST /api/vouchers/validate dengan body `{code, subtotal?}`.
///
/// Berbeda dari `cart/vouchers/validate-private`:
/// - `vouchers/validate` — general (cek code valid + applicable rules)
/// - `cart/vouchers/validate-private` — cart-specific dengan subtotal context
///   untuk private SELLER_MANUAL voucher
class VoucherValidationResult {
  final bool valid;
  final String code;
  final String? title;
  final String? description;
  final int discountAmount;
  final int? minSubtotal;
  final String? message;

  const VoucherValidationResult({
    required this.valid,
    required this.code,
    this.title,
    this.description,
    this.discountAmount = 0,
    this.minSubtotal,
    this.message,
  });

  factory VoucherValidationResult.fromJson(
    Map<String, dynamic> json, {
    required String requestedCode,
  }) {
    final amount = json['discountAmount'] ?? json['amount'];
    return VoucherValidationResult(
      valid: json['valid'] == true,
      code: (json['code'] ?? requestedCode).toString(),
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      discountAmount: amount is num
          ? amount.round()
          : int.tryParse(amount?.toString() ?? '') ?? 0,
      minSubtotal: json['minSubtotal'] is num
          ? (json['minSubtotal'] as num).round()
          : null,
      message: json['message']?.toString(),
    );
  }
}

class VoucherService {
  Future<VoucherValidationResult> validate({
    required String code,
    int? subtotal,
  }) async {
    if (code.trim().isEmpty) {
      return VoucherValidationResult(
        valid: false,
        code: code,
        message: 'Kode voucher kosong.',
      );
    }
    try {
      final data = await apiClient.postJson(
        '/api/vouchers/validate',
        body: {
          'code': code.trim(),
          if (subtotal != null) 'subtotal': subtotal,
        },
      );
      return VoucherValidationResult.fromJson(data, requestedCode: code);
    } catch (error) {
      return VoucherValidationResult(
        valid: false,
        code: code,
        message: error.toString(),
      );
    }
  }
}

final voucherService = VoucherService();

/// Recalc cart totals server-side. Match endpoint PWA
/// POST /api/checkout/recalculate dengan body items + voucherCode + shipping.
/// Server return: subtotal, discount, shipping, tax, total (otoritatif).
///
/// Wajib di-call sebelum create order supaya angka di UI = angka di server.
class CheckoutRecalcResult {
  final num subtotal;
  final num discountAmount;
  final num productDiscount;
  final num shippingDiscount;
  final num shippingCost;
  final num originalShippingCost;
  final num insuranceCost;
  final num protectionFee;
  final num tax;
  final num total;
  final MemberVoucher? appliedCustomerVoucher;
  final MemberVoucher? appliedManualVoucher;
  final MemberVoucher? appliedFreeShippingVoucher;
  final MemberVoucher? appliedProductVoucher;
  final MemberVoucher? appliedLoyaltyVoucher;
  final MemberVoucher? appliedPrivateVoucher;
  final List<MemberVoucher> availableVouchers;
  final List<MemberVoucher> unavailableVouchers;
  final bool voucherInvalidated;
  final String? invalidatedMessage;
  final String? customerVoucherError;
  final String? manualVoucherError;
  final Map<String, dynamic> raw;

  const CheckoutRecalcResult({
    required this.subtotal,
    required this.discountAmount,
    required this.productDiscount,
    required this.shippingDiscount,
    required this.shippingCost,
    required this.originalShippingCost,
    required this.insuranceCost,
    required this.protectionFee,
    required this.tax,
    required this.total,
    this.appliedCustomerVoucher,
    this.appliedManualVoucher,
    this.appliedFreeShippingVoucher,
    this.appliedProductVoucher,
    this.appliedLoyaltyVoucher,
    this.appliedPrivateVoucher,
    this.availableVouchers = const [],
    this.unavailableVouchers = const [],
    this.voucherInvalidated = false,
    this.invalidatedMessage,
    this.customerVoucherError,
    this.manualVoucherError,
    this.raw = const {},
  });

  factory CheckoutRecalcResult.fromJson(Map<String, dynamic> json) {
    num pick(String key) {
      final v = json[key];
      if (v is num) return v;
      return num.tryParse(v?.toString() ?? '') ?? 0;
    }

    MemberVoucher? parseVoucher(Object? value) {
      if (value is! Map<String, dynamic>) return null;
      return MemberVoucher.fromApiJson(value);
    }

    List<MemberVoucher> parseVoucherList(Object? value) {
      if (value is! List) return const [];
      return value
          .whereType<Map<String, dynamic>>()
          .map(MemberVoucher.fromApiJson)
          .toList();
    }

    return CheckoutRecalcResult(
      subtotal: pick('subtotal'),
      discountAmount: pick('productDiscount') == 0
          ? (pick('discount') == 0 ? pick('discountAmount') : pick('discount'))
          : pick('productDiscount'),
      productDiscount: pick('productDiscount') == 0
          ? (pick('discount') == 0 ? pick('discountAmount') : pick('discount'))
          : pick('productDiscount'),
      shippingDiscount: pick('shippingDiscount'),
      shippingCost: json.containsKey('shipping_fee')
          ? pick('shipping_fee')
          : pick('shippingCost'),
      originalShippingCost: pick('originalShippingCost') == 0
          ? (json.containsKey('shipping_fee')
              ? pick('shipping_fee')
              : pick('shippingCost'))
          : pick('originalShippingCost'),
      insuranceCost: pick('insuranceCost'),
      protectionFee: pick('protectionFee'),
      tax: pick('tax'),
      total: pick('total'),
      appliedCustomerVoucher: parseVoucher(
        json['applied_customer_voucher'] ?? json['applied_voucher'],
      ),
      appliedManualVoucher: parseVoucher(json['applied_manual_voucher']),
      appliedFreeShippingVoucher:
          parseVoucher(json['applied_free_shipping_voucher']),
      appliedProductVoucher: parseVoucher(json['applied_product_voucher']),
      appliedLoyaltyVoucher: parseVoucher(json['applied_loyalty_voucher']),
      appliedPrivateVoucher: parseVoucher(
        json['applied_private_voucher'] ?? json['applied_manual_voucher'],
      ),
      availableVouchers: parseVoucherList(json['available_vouchers']),
      unavailableVouchers: parseVoucherList(json['unavailable_vouchers']),
      voucherInvalidated: json['voucher_invalidated'] == true,
      invalidatedMessage: json['invalidated_message']?.toString(),
      customerVoucherError: json['customer_voucher_error']?.toString(),
      manualVoucherError: json['manual_voucher_error']?.toString(),
      raw: json,
    );
  }
}

class CheckoutService {
  Object? lastRecalculateError;

  Future<CheckoutRecalcResult?> recalculate({
    required List<Map<String, dynamic>> items,
    required int shippingFee,
    String? voucherCode,
    String? customerVoucherCode,
    String? manualVoucherCode,
    String? freeShippingVoucherCode,
    String? productVoucherCode,
    String? loyaltyVoucherCode,
    String? privateVoucherCode,
    bool autoApply = true,
    MemberAddress? address,
    ShippingRate? shippingRate,
    String? paymentProvider,
    bool? useProtection,
  }) async {
    try {
      lastRecalculateError = null;
      final selfPickup = shippingRate?.isSelfPickup == true;
      final data = await apiClient.postJson(
        '/api/checkout/recalculate',
        body: {
          'items': items,
          'shipping_fee': shippingFee,
          'voucherCode': customerVoucherCode ?? voucherCode,
          'customerVoucherCode': customerVoucherCode ?? voucherCode,
          'manualVoucherCode': manualVoucherCode,
          'freeShippingVoucherCode': freeShippingVoucherCode,
          'productVoucherCode': productVoucherCode,
          'loyaltyVoucherCode': loyaltyVoucherCode,
          'privateVoucherCode': privateVoucherCode ?? manualVoucherCode,
          'autoApply': autoApply,
          'address': {
            'areaId': address?.areaId,
            'postalCode': address?.postalCode,
            'latitude': address?.latitude,
            'longitude': address?.longitude,
            'city': address?.city,
          },
          'shippingMethod': {
            'courierCode': selfPickup ? null : shippingRate?.courierCode,
            'courierService': selfPickup ? null : shippingRate?.serviceCode,
          },
          'paymentProvider': paymentProvider,
          if (useProtection != null) 'useProtection': useProtection,
        },
      );
      return CheckoutRecalcResult.fromJson(data);
    } catch (error, stackTrace) {
      lastRecalculateError = error;
      if (kDebugMode) {
        debugPrint('[checkoutService.recalculate] $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return null;
    }
  }
}

final checkoutService = CheckoutService();
