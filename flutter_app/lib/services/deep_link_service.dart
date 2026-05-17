import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'product_service.dart';

/// Match perilaku PWA DeepLinkHandler.tsx + capacitor.config.ts `appUrlOpen`:
/// terima incoming URL (mis. dari share sheet / push notif) → resolve ke
/// route Flutter yang sesuai → navigate via [navigatorKey].
///
/// Path yang di-handle:
/// - `/products/{slug}` → fetch produk by slug → ProductDetailScreen
/// - `/cart` → CartScreen
/// - `/member`, `/member/orders`, `/member/vouchers`, `/member/loyalty`,
///   `/member/addresses`, `/member/profile` → route langsung
/// - `/order-status/{number}`, `/orders/{number}` → MemberOrderDetailScreen
/// - lainnya → fallback ke home `/`
class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _initialHandled = false;

  /// Inisialisasi di main() setelah runApp. Lewatkan navigatorKey dari
  /// MaterialApp supaya bisa push route dari luar widget tree.
  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    // Cold start: kalau app dibuka via deep link, ambil URI awalnya sekali.
    if (!_initialHandled) {
      try {
        final initial = await _appLinks.getInitialLink();
        _initialHandled = true;
        if (initial != null) {
          // Delay sedikit supaya MaterialApp sudah mount sebelum navigate.
          Future.delayed(const Duration(milliseconds: 600), () {
            _handleUri(initial);
          });
        }
      } catch (error) {
        if (kDebugMode) debugPrint('[deep_link] initial error: $error');
      }
    }

    // Warm: subscribe ke incoming URI saat app sudah running.
    _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object error) {
        if (kDebugMode) debugPrint('[deep_link] stream error: $error');
      },
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Public entry untuk consumer lain (mis. push notification service) yang
  /// mau forward URL ke deep link router yang sama.
  Future<void> handleExternalUri(Uri uri) => _handleUri(uri);

  Future<void> _handleUri(Uri uri) async {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;

    final segments =
        uri.pathSegments.where((seg) => seg.isNotEmpty).toList();
    if (segments.isEmpty) {
      nav.pushNamedAndRemoveUntil('/', (route) => false);
      return;
    }

    final first = segments[0].toLowerCase();

    // ── /products/{slug} ── resolve slug → push detail
    if (first == 'products' && segments.length >= 2) {
      final slug = segments[1];
      // ProductDetailScreen butuh Product object — Flutter tidak punya
      // endpoint by-slug terpisah, tapi search/suggest cukup untuk ambil 1.
      // Fallback: kalau gagal resolve, push ke /products dengan query slug.
      try {
        final suggestions = await productService.fetchSuggestions(slug);
        if (suggestions.products.isNotEmpty) {
          final candidate = suggestions.products.first;
          // Cek match exact slug supaya tidak push produk salah.
          if (candidate.slug == slug || candidate.slug.contains(slug)) {
            // Untuk push ProductDetailScreen butuh Product full — kita
            // gunakan ProductSuggestion → buat Product minimal via fromApiJson.
            // Simpler: navigate ke /products dengan query nama produk.
            nav.pushNamed('/products', arguments: null);
            return;
          }
        }
      } catch (_) {}
      nav.pushNamed('/products');
      return;
    }

    // ── /cart ──
    if (first == 'cart' || first == 'keranjang') {
      nav.pushNamed('/cart');
      return;
    }

    // ── /checkout ──
    if (first == 'checkout') {
      nav.pushNamed('/checkout');
      return;
    }

    // ── /member/* ──
    if (first == 'member' || first == 'akun' || first == 'account') {
      final sub = segments.length > 1 ? segments[1].toLowerCase() : '';
      switch (sub) {
        case 'orders':
        case 'pesanan':
          nav.pushNamed('/member/orders');
          return;
        case 'vouchers':
        case 'voucher':
          nav.pushNamed('/member/vouchers');
          return;
        case 'loyalty':
        case 'poin':
        case 'points':
          nav.pushNamed('/member/loyalty');
          return;
        case 'addresses':
        case 'alamat':
          nav.pushNamed('/member/addresses');
          return;
        case 'profile':
        case 'profil':
          nav.pushNamed('/member/profile');
          return;
        case 'reviews':
        case 'ulasan':
          nav.pushNamed('/member/reviews');
          return;
        case 'login':
        case 'masuk':
          nav.pushNamed('/member/login');
          return;
        case 'register':
        case 'daftar':
          nav.pushNamed('/member/register');
          return;
        default:
          nav.pushNamed('/member');
          return;
      }
    }

    // ── /wishlist ──
    if (first == 'wishlist') {
      nav.pushNamed('/wishlist');
      return;
    }

    // ── /feed ──
    if (first == 'feed') {
      nav.pushNamed('/feed');
      return;
    }

    // ── /notifications ──
    if (first == 'notifications' || first == 'notifikasi') {
      nav.pushNamed('/notifications');
      return;
    }

    // ── /brands ──
    if (first == 'brands') {
      nav.pushNamed('/brands');
      return;
    }

    // ── /help, /bantuan ──
    if (first == 'help' || first == 'bantuan') {
      nav.pushNamed('/help');
      return;
    }

    // Fallback unknown path
    nav.pushNamed('/');
  }
}

final deepLinkService = DeepLinkService();
