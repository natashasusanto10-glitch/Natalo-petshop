import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'product_service.dart';

/// Deep link handler — terima link share (mis. wa.me share product) dari
/// native intent → buka langsung ke screen yang sesuai.
///
/// Path mapping:
///   /products/<slug>       → product detail (fetch by slug)
///   /produk/<slug>         → product detail (alias Indonesian)
///   /products              → product list
///   /akun/pesanan/<no>     → /member/orders (filter by no — TODO)
///   /akun/pesanan          → /member/orders
///   /feed                  → /feed
///   /cart, /keranjang      → /cart
///   /wishlist              → /wishlist
class DeepLinkService {
  DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _initialized = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;
    try {
      // Initial link — kalau app dibuka via tap link (cold start).
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
      // Subsequent links — saat app sudah running.
      _sub = _appLinks.uriLinkStream.listen(_handle);
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLink] init error: $e');
    }
  }

  Future<void> _handle(Uri uri) async {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;
    final segments = uri.pathSegments;
    if (segments.isEmpty) {
      nav.pushNamed('/');
      return;
    }
    switch (segments.first) {
      case 'feed':
        nav.pushNamed('/feed');
        break;
      case 'cart':
      case 'keranjang':
        nav.pushNamed('/cart');
        break;
      case 'wishlist':
        nav.pushNamed('/wishlist');
        break;
      case 'akun':
        if (segments.length > 1 && segments[1] == 'pesanan') {
          // /akun/pesanan or /akun/pesanan/<orderNumber>
          // Future: pass order number as arg untuk auto-open detail.
          nav.pushNamed('/member/orders');
        } else {
          nav.pushNamed('/member');
        }
        break;
      case 'products':
      case 'produk':
        if (segments.length > 1) {
          await _openProductBySlug(nav, segments[1]);
        } else {
          nav.pushNamed('/products');
        }
        break;
      default:
        nav.pushNamed('/');
    }
  }

  /// Fetch product by slug lalu push /product-detail dengan Product arg.
  /// Fallback ke /products dengan initialQuery kalau slug tidak ketemu —
  /// user tetap bisa cari manual instead of dump ke home.
  Future<void> _openProductBySlug(
    NavigatorState nav,
    String slug,
  ) async {
    try {
      final product = await productService.fetchProductBySlug(slug);
      if (product != null) {
        nav.pushNamed('/product-detail', arguments: product);
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLink] fetchProductBySlug failed: $e');
    }
    // Slug-to-keyword fallback — replace dash dengan spasi sebagai
    // search query hint (mis. `royal-canin-kitten` → `royal canin kitten`).
    final keyword = slug.replaceAll('-', ' ').trim();
    nav.pushNamed('/products', arguments: {'initialQuery': keyword});
  }

  /// Handle URI dari source eksternal (push notification deep link, dll).
  /// Boleh kasih String atau Uri. Idempotent — bisa dipanggil ulang.
  void handleExternalUri(dynamic input) {
    final uri = input is Uri
        ? input
        : (input is String ? Uri.tryParse(input) : null);
    if (uri != null) _handle(uri);
  }

  void dispose() {
    _sub?.cancel();
  }
}

final DeepLinkService deepLinkService = DeepLinkService._();
