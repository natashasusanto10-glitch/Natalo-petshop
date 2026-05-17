import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Deep link handler — terima link share (mis. wa.me share product) dari
/// native intent → buka langsung ke screen yang sesuai.
/// Path mapping (sementara minimal):
///   /products/<slug>       → /product-detail (need product fetch — TODO)
///   /akun/pesanan/<no>     → /member/orders (then deep into detail — TODO)
///   /feed                  → /feed
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

  void _handle(Uri uri) {
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
      case 'akun':
        if (segments.length > 1 && segments[1] == 'pesanan') {
          nav.pushNamed('/member/orders');
        } else {
          nav.pushNamed('/member');
        }
        break;
      case 'products':
        // TODO: fetch product by slug lalu push /product-detail dengan args.
        nav.pushNamed('/products');
        break;
      default:
        nav.pushNamed('/');
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
