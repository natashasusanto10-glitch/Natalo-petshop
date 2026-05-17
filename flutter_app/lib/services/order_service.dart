import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/member_profile.dart';
import '../state/member_store.dart';

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

  /// Stub reorder — POST /api/orders/{orderNumber}/reorder. Server balikin
  /// daftar item yang berhasil + alasan kalau ada yang skip (stock habis, dll).
  Future<ReorderResult> reorder({required String orderNumber}) async {
    if (kDebugMode) {
      debugPrint('[orderService.reorder] stub: $orderNumber');
    }
    return const ReorderResult(items: [], skippedReasons: []);
  }

  /// Upload bukti transfer / pembayaran manual via multipart. Stub no-op
  /// — TODO real implementation pakai `package:http` MultipartRequest.
  Future<String?> uploadPaymentProof({
    required String orderNumber,
    required Object file,
    String? trackingToken,
  }) async {
    if (kDebugMode) {
      debugPrint('[orderService.uploadPaymentProof] stub: $orderNumber');
    }
    return null;
  }

  Future<OrderSummary> fetchOrderDetail(
    String orderNumber, {
    String? trackingToken,
  }) async {
    final uri = ApiConfig.uri('/api/orders/$orderNumber', {
      if (trackingToken != null) 'token': trackingToken,
    });
    try {
      final res = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        throw StateError('fetch order $orderNumber: ${res.statusCode}');
      }
      final body = jsonDecode(res.body);
      final data = body is Map<String, dynamic>
          ? (body['order'] ?? body['data'] ?? body)
          : null;
      if (data is Map<String, dynamic>) return OrderSummary.fromJson(data);
      throw StateError('fetch order $orderNumber: malformed response');
    } catch (e) {
      if (kDebugMode) debugPrint('[orderService.fetchOrderDetail] $e');
      rethrow;
    }
  }
}

final OrderService orderService = OrderService._();

/// Result reorder — list item yang berhasil di-add + alasan skip kalau ada.
class ReorderResult {
  final List<OrderItemSummary> items;
  final List<String> skippedReasons;
  const ReorderResult({this.items = const [], this.skippedReasons = const []});

  bool get hasPartialChanges => skippedReasons.isNotEmpty;
}
