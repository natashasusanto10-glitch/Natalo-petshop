import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/member_profile.dart';
import '../state/cart_store.dart';

/// Android home screen widget bridge — push cart count + last order status
/// ke launcher widget. iOS silent no-op (iOS widget kit di luar scope).
class AppHomeWidgetService {
  AppHomeWidgetService._();

  static const _androidAppGroup = 'com.natalo.petshop.widget';

  static Future<void> _setData(String key, Object? value) async {
    if (!Platform.isAndroid) return;
    try {
      await HomeWidget.setAppGroupId(_androidAppGroup);
      await HomeWidget.saveWidgetData(key, value);
      await HomeWidget.updateWidget(
        name: 'NataloWidgetProvider',
        androidName: 'NataloWidgetProvider',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[HomeWidget] $key error: $e');
    }
  }

  static Future<void> updateCartCount() =>
      _setData('cart_count', cartStore.count);

  static Future<void> updateLastOrder(OrderSummary? order) async {
    if (order == null) {
      await _setData('last_order_number', '');
      await _setData('last_order_status', '');
      return;
    }
    await _setData('last_order_number', order.orderNumber);
    await _setData('last_order_status', order.status);
  }
}
