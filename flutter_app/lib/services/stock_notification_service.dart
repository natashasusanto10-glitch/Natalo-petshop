import 'package:flutter/foundation.dart';

import '../utils/read_only_mode.dart';
import 'api_client.dart';

/// Service untuk fitur "Pre-Order Out-of-Stock" / "Beri tahu saat tersedia".
///
/// User di product detail dengan stock=0 bisa tap tombol → backend record
/// StockNotification subscription. Saat admin restock product/variant
/// (stock 0 → >0), backend fire push ke semua subscriber via FCM/APNs/
/// Web Push. User dapat notif → tap → deep link buka product detail.
///
/// API:
/// - GET    /api/products/{productId}/stock-notification?variantId=X
/// - POST   /api/products/{productId}/stock-notification {variantId?}
/// - DELETE /api/products/{productId}/stock-notification?variantId=X
class StockNotificationService {
  StockNotificationService._();

  /// Cek apakah user sudah subscribe ke restock notification untuk produk
  /// ini (dan variant tertentu kalau di-set). Return null kalau guest /
  /// unauthenticated (UI handle dengan prompt login).
  Future<bool?> isSubscribed({
    required String productId,
    String? variantId,
  }) async {
    try {
      final data = await apiClient.getJson(
        '/api/products/${Uri.encodeComponent(productId)}/stock-notification',
        query: variantId != null ? {'variantId': variantId} : null,
      );
      if (data is Map<String, dynamic>) {
        // Backend return { subscribed: true/false, notifiedAt: ISO|null }
        return data['subscribed'] == true;
      }
      return false;
    } on ApiException catch (e) {
      if (e.statusCode == 401) return null; // not logged in
      if (kDebugMode) debugPrint('[stockNotif.isSubscribed] $e');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[stockNotif.isSubscribed] $e');
      return false;
    }
  }

  /// Subscribe — backend upsert StockNotification row dengan notifiedAt
  /// reset ke null. Return true kalau sukses, false kalau gagal/already
  /// in stock. Throw [ApiException] dengan statusCode 401 kalau belum
  /// login (caller handle redirect ke login).
  Future<({bool ok, String message})> subscribe({
    required String productId,
    String? variantId,
  }) async {
    readOnlyMode.assertWritable('stock_notification_subscribe');
    try {
      final data = await apiClient.postJson(
        '/api/products/${Uri.encodeComponent(productId)}/stock-notification',
        body: variantId != null ? {'variantId': variantId} : <String, Object?>{},
      );
      if (data is Map<String, dynamic>) {
        return (
          ok: data['ok'] == true,
          message: (data['message'] ?? '').toString(),
        );
      }
      return (ok: false, message: 'Gagal subscribe notifikasi restock.');
    } on ApiException catch (e) {
      if (e.statusCode == 401) rethrow;
      if (kDebugMode) debugPrint('[stockNotif.subscribe] $e');
      return (
        ok: false,
        message: e.statusCode == 400
            ? 'Produk sudah tersedia — tidak perlu subscribe.'
            : 'Gagal subscribe notifikasi.',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[stockNotif.subscribe] $e');
      return (ok: false, message: 'Gagal subscribe notifikasi.');
    }
  }

  /// Unsubscribe — backend deleteMany row matching userId+productId+variantId.
  Future<({bool ok, String message})> unsubscribe({
    required String productId,
    String? variantId,
  }) async {
    readOnlyMode.assertWritable('stock_notification_unsubscribe');
    try {
      final data = await apiClient.deleteJson(
        '/api/products/${Uri.encodeComponent(productId)}/stock-notification',
        query: variantId != null ? {'variantId': variantId} : null,
      );
      if (data is Map<String, dynamic>) {
        return (
          ok: data['ok'] == true,
          message: (data['message'] ?? '').toString(),
        );
      }
      return (ok: false, message: 'Gagal unsubscribe.');
    } on ApiException catch (e) {
      if (e.statusCode == 401) rethrow;
      if (kDebugMode) debugPrint('[stockNotif.unsubscribe] $e');
      return (ok: false, message: 'Gagal unsubscribe notifikasi.');
    } catch (e) {
      if (kDebugMode) debugPrint('[stockNotif.unsubscribe] $e');
      return (ok: false, message: 'Gagal unsubscribe notifikasi.');
    }
  }
}

final stockNotificationService = StockNotificationService._();
