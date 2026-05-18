package com.natalo.petshop

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Android home-screen widget untuk Natalo Petshop.
 *
 * Tampilkan:
 * - Jumlah item di cart (bullet besar)
 * - Order terakhir + status
 *
 * Data di-baca dari SharedPreferences yang di-write oleh Flutter via
 * `home_widget` package (lihat lib/services/home_widget_service.dart).
 *
 * Tap widget → buka app (deep link ke `/cart` kalau ada cart, ke
 * `/member/orders` kalau ada last order, atau ke `/` (home) default).
 */
class NataloHomeWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.natalo_home_widget)

            // Baca data dari Flutter SharedPreferences (via home_widget plugin).
            val prefs = HomeWidgetPlugin.getData(context)
            val cartCount = prefs.getInt("cart_count", 0)
            val orderNumber = prefs.getString("last_order_number", "") ?: ""
            val orderStatus = prefs.getString("last_order_status", "") ?: ""

            views.setTextViewText(R.id.widget_cart_count, cartCount.toString())
            views.setTextViewText(
                R.id.widget_cart_label,
                if (cartCount == 0) "Cart kosong" else "Item di cart"
            )

            if (orderNumber.isNotEmpty()) {
                views.setTextViewText(R.id.widget_order_number, orderNumber)
                views.setTextViewText(R.id.widget_order_status, orderStatus)
                views.setViewVisibility(R.id.widget_order_block, android.view.View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_order_block, android.view.View.GONE)
            }

            // Tap widget → buka app dengan deep link route.
            val targetUri = when {
                orderNumber.isNotEmpty() -> "natalo://member/orders"
                cartCount > 0 -> "natalo://cart"
                else -> "natalo://"
            }
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(targetUri)).apply {
                setPackage(context.packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                widgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
