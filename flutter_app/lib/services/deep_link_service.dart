import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screens/member_post_detail_screen.dart';
import 'feed_service.dart';
import 'order_service.dart';
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
///   /u/<username>          → public profile (PublicProfileScreen)
///   /chat, /chat/<chatId>  → /chat (room spesifik kalau ada chatId)
class DeepLinkService {
  DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _initialized = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  /// True bila app cold-start dipicu tap deep-link (bukan buka app biasa).
  /// Dibaca LaunchPromoGate untuk skip popup agar tidak menutupi tujuan link.
  bool launchedFromDeepLink = false;

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;
    try {
      // Initial link — kalau app dibuka via tap link (cold start).
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        launchedFromDeepLink = true;
        _handle(initial);
      }
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
        // /feed/<postId> → buka 1 postingan (deep-link notif "X posting
        // baru"). /feed saja → buka feed utama.
        if (segments.length > 1 && segments[1].isNotEmpty) {
          await _openPostById(nav, segments[1]);
        } else {
          nav.pushNamed('/feed');
        }
        break;
      case 'cart':
      case 'keranjang':
        nav.pushNamed('/cart');
        break;
      case 'wishlist':
        nav.pushNamed('/wishlist');
        break;
      case 'chat':
        // /chat/<chatId> → buka room spesifik (dipakai push notif chat
        // "balasan baru dari staff"). /chat saja → resolve room milik
        // sesi login di server (chatId null).
        if (segments.length > 1 && segments[1].isNotEmpty) {
          nav.pushNamed('/chat', arguments: segments[1]);
        } else {
          nav.pushNamed('/chat');
        }
        break;
      case 'akun':
        if (segments.length > 1 && segments[1] == 'pesanan') {
          // /akun/pesanan/<orderNumber> → open order detail
          // /akun/pesanan → orders list
          if (segments.length > 2 && segments[2].isNotEmpty) {
            await _openOrderByNumber(nav, segments[2], uri.queryParameters['token']);
          } else {
            nav.pushNamed('/member/orders');
          }
        } else {
          nav.pushNamed('/member');
        }
        break;
      case 'pesanan':
        // /pesanan/<orderNumber>?token=X — URL pattern dari push notif
        // order status update (lib/push.ts:115 buildOrderDetailPath).
        // Sebelumnya jatuh ke default case (push '/') → user dump ke home,
        // tidak tahu pesanan mana yang ada update.
        if (segments.length > 1 && segments[1].isNotEmpty) {
          await _openOrderByNumber(nav, segments[1], uri.queryParameters['token']);
        } else {
          nav.pushNamed('/member/orders');
        }
        break;
      case 'member':
        // /member/loyalty → halaman tukar poin (deep-link notif reminder
        // poin). /member/orders → daftar pesanan. /member/order-detail
        // ?orderNumber=X → detail order (push notif confirm_reminder dan
        // cancellation_rejected, lihat lib/push.ts:353 + lib/push-refund.ts:175).
        // /member → halaman akun.
        if (segments.length > 1 && segments[1] == 'loyalty') {
          nav.pushNamed('/member/loyalty');
        } else if (segments.length > 1 && segments[1] == 'orders') {
          nav.pushNamed('/member/orders');
        } else if (segments.length > 1 && segments[1] == 'order-detail') {
          final orderNumber = uri.queryParameters['orderNumber']?.trim() ?? '';
          if (orderNumber.isNotEmpty) {
            await _openOrderByNumber(nav, orderNumber, uri.queryParameters['token']);
          } else {
            nav.pushNamed('/member/orders');
          }
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
      case 'u':
        // Public profile — /u/<username> deep link target. Lowercase
        // di sini supaya konsisten dengan format DB (username always
        // lowercase). Empty segment → fallback ke /feed (open feed
        // sebagai entry point reasonable).
        if (segments.length > 1 && segments[1].isNotEmpty) {
          nav.pushNamed('/u', arguments: segments[1].toLowerCase());
        } else {
          nav.pushNamed('/feed');
        }
        break;
      default:
        nav.pushNamed('/');
    }
  }

  /// Fetch postingan by ID lalu buka MemberPostDetailScreen sebagai viewer
  /// (isOwner: false → sembunyikan menu edit/hapus, pakai author info dari
  /// post bukan memberStore). Fallback ke /feed kalau post tidak ada
  /// (dihapus / belum tayang) atau fetch gagal.
  Future<void> _openPostById(NavigatorState nav, String postId) async {
    try {
      final post = await feedService.fetchPostById(postId);
      if (post == null) {
        nav.pushNamed('/feed');
        return;
      }
      nav.push(
        MaterialPageRoute(
          builder: (_) => MemberPostDetailScreen(
            post: post,
            authorName: post.author.displayName,
            authorPhotoUrl: post.author.profilePhotoUrl,
            authorInitial: post.author.initial,
            isOwner: false,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLink] fetchPostById failed: $e');
      nav.pushNamed('/feed');
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

  /// Fetch order by orderNumber (+ optional trackingToken untuk akses
  /// guest/non-login) lalu push /member/order-detail dengan OrderSummary
  /// arg. Fallback ke /member/orders list kalau fetch gagal (order
  /// dihapus / token invalid / user belum login).
  Future<void> _openOrderByNumber(
    NavigatorState nav,
    String orderNumber,
    String? trackingToken,
  ) async {
    try {
      final order = await orderService.fetchOrderDetail(
        orderNumber,
        trackingToken: trackingToken,
      );
      nav.pushNamed('/member/order-detail', arguments: order);
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLink] fetchOrderDetail failed: $e');
      nav.pushNamed('/member/orders');
    }
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
