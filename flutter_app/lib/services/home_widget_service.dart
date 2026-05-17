import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/member_profile.dart';

/// Sync data ke Android home screen widget (long-press launcher → "Widget" →
/// drag "Natalo Petshop"). Widget tampilkan:
/// - Jumlah item di cart
/// - Status pesanan terakhir
///
/// Update flow:
/// 1. Flutter set value via HomeWidget.saveWidgetData(...)
/// 2. Trigger HomeWidget.updateWidget(...) → broadcast intent ke native
/// 3. AppWidgetProvider Kotlin read SharedPreferences → render TextView
///
/// PWA WebView tidak bisa: tidak ada API untuk write ke widget host.
class AppHomeWidgetService {
  static const _kAndroidWidgetName = 'NataloHomeWidget';
  static const _kAndroidProvider = 'NataloHomeWidget';

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Update cart count di widget. Call dari cart_store setiap kali
  /// items berubah (fire-and-forget, silent fail kalau widget belum
  /// di-pin user).
  static Future<void> updateCartCount(int count) async {
    if (!_supported) return;
    try {
      await HomeWidget.saveWidgetData<int>('cart_count', count);
      await HomeWidget.updateWidget(
        name: _kAndroidWidgetName,
        androidName: _kAndroidProvider,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[home_widget] cart update failed: $e');
    }
  }

  /// Update last order status. Pass null untuk clear (mis. saat logout).
  static Future<void> updateLastOrder(OrderSummary? order) async {
    if (!_supported) return;
    try {
      if (order == null) {
        await HomeWidget.saveWidgetData<String>('last_order_number', '');
        await HomeWidget.saveWidgetData<String>('last_order_status', '');
      } else {
        await HomeWidget.saveWidgetData<String>(
          'last_order_number',
          order.orderNumber,
        );
        await HomeWidget.saveWidgetData<String>(
          'last_order_status',
          _statusLabel(order.status),
        );
      }
      await HomeWidget.updateWidget(
        name: _kAndroidWidgetName,
        androidName: _kAndroidProvider,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[home_widget] order update failed: $e');
    }
  }

  static String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return 'Menunggu Bayar';
      case 'PROCESSING':
        return 'Diproses';
      case 'SHIPPED':
        return 'Dikirim';
      case 'DELIVERED':
      case 'COMPLETED':
        return 'Selesai';
      case 'CANCELLED':
        return 'Dibatalkan';
      default:
        return status;
    }
  }
}
