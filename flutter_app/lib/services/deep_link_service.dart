import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/feed_post.dart';
import '../screens/member_post_detail_screen.dart';
import '../screens/scoped_video_feed_screen.dart';
import '../state/member_store.dart';
import '../widgets/scaled_video_feed_route.dart';
import 'feed_service.dart';
import 'order_service.dart';
import 'product_service.dart';
import 'deep_link_router.dart';

/// Test seam for the public share-link lifecycle. Production navigation still
/// goes through the root [NavigatorState], while tests can prove pending and
/// dedupe behavior without mounting product or Feed screens.
abstract interface class DeepLinkTargetDispatcher {
  bool get isReady;

  Future<void> dispatch(NataloDeepLinkTarget target);
}

/// Buka satu postingan feed dengan tujuan yang TEPAT sesuai jenis kontennya
/// — video langsung ke player fullscreen (bukan berhenti di layar detail
/// yang butuh tap kedua), non-video tetap ke [MemberPostDetailScreen]
/// seperti biasa. Dipakai bersama oleh [DeepLinkService] (push notification
/// HP) dan `NotificationsScreen` (list notifikasi dalam-app) supaya kedua
/// jalur konsisten.
///
/// [ScopedVideoFeedScreen] di-push dengan daftar SATU post saja (bukan
/// semua video author itu) — notifikasi memang menunjuk SATU postingan
/// spesifik, beda dari alur "tap video di profil" yang scoped ke semua
/// video user tsb. `GlobalKey()` baru (tak pernah attached ke widget apa
/// pun) dipakai sebagai `thumbnailKey` — [pushScaledVideoFeed] null-safe
/// terhadap ini (origin null → fade-in polos tanpa morph-scale), karena
/// tidak ada thumbnail nyata di layar sumber (list notifikasi/cold-start).
Future<void> openFeedPostSmart(
  BuildContext context,
  FeedPost post, {
  bool isOwner = false,
}) async {
  if (post.isVideo) {
    await pushScaledVideoFeed(
      context,
      thumbnailKey: GlobalKey(),
      thumbnailImageUrl: post.thumbnailUrl ?? '',
      thumbnailBorderRadius: 0,
      destinationBuilder: (_) => ScopedVideoFeedScreen(
        posts: [post],
        initialIndex: 0,
      ),
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MemberPostDetailScreen(
        post: post,
        authorName: post.author.displayName,
        authorPhotoUrl: post.author.profilePhotoUrl,
        authorInitial: post.author.initial,
        authorIsOfficial: post.author.isOfficialAccount,
        isOwner: isOwner,
      ),
    ),
  );
}

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
  DeepLinkService._()
      : _appLinks = AppLinks(),
        _now = DateTime.now,
        _dedupeWindow = _defaultDedupeWindow,
        _testDispatcher = null;

  /// Instance TERPISAH dari singleton [deepLinkService] — dipakai test untuk
  /// reproduksi race navigator tanpa terikat guard `_initialized` singleton
  /// (yang cuma boleh initialize() sekali seumur proses) atau plugin channel
  /// `AppLinks()` asli.
  @visibleForTesting
  DeepLinkService.test({
    DeepLinkTargetDispatcher? dispatcher,
    DateTime Function()? now,
    Duration dedupeWindow = _defaultDedupeWindow,
  })  : _appLinks = AppLinks(),
        _testDispatcher = dispatcher,
        _now = now ?? DateTime.now,
        _dedupeWindow = dedupeWindow;

  static const _defaultDedupeWindow = Duration(seconds: 2);

  final AppLinks _appLinks;
  final DeepLinkTargetDispatcher? _testDispatcher;
  final DateTime Function() _now;
  final Duration _dedupeWindow;
  StreamSubscription<Uri>? _sub;
  bool _initialized = false;
  GlobalKey<NavigatorState>? _navigatorKey;
  NataloDeepLinkTarget? _pendingPublicTarget;
  String? _lastDispatchedKey;
  DateTime? _lastDispatchedAt;
  bool _isPublicDispatching = false;
  bool _navigatorRetryScheduled = false;

  /// Set langsung tanpa lewat [initialize] — test bisa attach [GlobalKey]
  /// yang BELUM ter-mount ke widget tree apa pun (`currentState == null`)
  /// untuk simulasi race cold-start, lalu mount tree-nya belakangan.
  @visibleForTesting
  set navigatorKeyForTesting(GlobalKey<NavigatorState> key) =>
      _navigatorKey = key;

  /// True bila app cold-start dipicu tap deep-link (bukan buka app biasa).
  /// Dibaca LaunchPromoGate untuk skip popup agar tidak menutupi tujuan link.
  bool launchedFromDeepLink = false;

  /// Batas tunggu Navigator ter-mount — lihat [_waitForNavigator]. 40 x 50ms
  /// = 2 detik, cukup longgar utk cold-start (splash/onboarding gate) tapi
  /// tak menggantung selamanya kalau memang navigator tak pernah muncul.
  static const _maxNavigatorWaitAttempts = 40;
  static const _navigatorWaitInterval = Duration(milliseconds: 50);

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

  /// `_navigatorKey.currentState` BELUM TENTU ter-mount saat link cold-start
  /// diproses: `initialize()` dipanggil sebelum `runApp()` selesai membangun
  /// widget tree (main.dart), jadi `getInitialLink()` yang resolve duluan
  /// menemukan Navigator masih null. Dulu `_handle` langsung `return` diam-
  /// diam kalau null → deep link DIBUANG, user cuma lihat initialRoute
  /// default (Beranda) — gejala device: share profil/produk buka app tapi
  /// SELALU jatuh ke Beranda, utk SEMUA jenis link (bukan bug per-case).
  /// Poll bounded sampai Navigator ter-mount alih-alih menyerah di percobaan
  /// pertama.
  Future<NavigatorState?> _waitForNavigator() async {
    for (var attempt = 0; attempt < _maxNavigatorWaitAttempts; attempt++) {
      final nav = _navigatorKey?.currentState;
      if (nav != null) return nav;
      await Future.delayed(_navigatorWaitInterval);
    }
    return _navigatorKey?.currentState;
  }

  /// Called immediately after the root navigator is mounted. This is the
  /// deterministic cold-start handoff; the bounded navigator retry remains a
  /// fallback for embeds/tests that cannot call this lifecycle point.
  Future<void> onNavigatorReady() => _flushPendingPublicTarget();

  Future<void> _handle(Uri uri) async {
    final publicTarget = parseNataloDeepLink(uri);
    if (publicTarget != null) {
      _enqueuePublicTarget(publicTarget);
      return;
    }

    // Never let a similar-looking external host drive internal navigation.
    // Existing internal/path-only notification links continue through the
    // legacy router below, so auth/deferred navigation behavior is preserved.
    if (uri.scheme.isNotEmpty && !isOfficialNataloHttpsUrl(uri)) return;

    // A malformed canonical public URL must be a no-op, not a surprising
    // fallback to Feed or Home. Keep `/feed` and `/products` entry routes.
    final segments = uri.pathSegments;
    if (_isMalformedPublicSharePath(segments)) return;

    await _handleLegacy(uri);
  }

  bool _isMalformedPublicSharePath(List<String> segments) {
    if (segments.isEmpty) return false;
    final first = segments.first;
    if (first == 'u') return true;
    return (first == 'feed' || first == 'products') && segments.length > 1;
  }

  void _enqueuePublicTarget(NataloDeepLinkTarget target) {
    if (_isDuplicatePublicTarget(target)) return;
    _pendingPublicTarget = target;
    unawaited(_flushPendingPublicTarget());
    _scheduleNavigatorRetry();
  }

  bool _isDuplicatePublicTarget(NataloDeepLinkTarget target) {
    if (_pendingPublicTarget?.dedupeKey == target.dedupeKey) return true;
    final lastAt = _lastDispatchedAt;
    return lastAt != null &&
        _lastDispatchedKey == target.dedupeKey &&
        _now().isBefore(lastAt.add(_dedupeWindow));
  }

  void _scheduleNavigatorRetry() {
    if (_testDispatcher != null ||
        _navigatorKey?.currentState != null ||
        _navigatorRetryScheduled) {
      return;
    }
    _navigatorRetryScheduled = true;
    unawaited(() async {
      await _waitForNavigator();
      _navigatorRetryScheduled = false;
      await _flushPendingPublicTarget();
    }());
  }

  Future<void> _flushPendingPublicTarget() async {
    if (_isPublicDispatching) return;
    final target = _pendingPublicTarget;
    if (target == null) return;

    final dispatcher = _testDispatcher;
    final nav = dispatcher == null ? _navigatorKey?.currentState : null;
    if (dispatcher != null && !dispatcher.isReady) return;
    if (dispatcher == null && nav == null) return;

    _pendingPublicTarget = null;
    _isPublicDispatching = true;
    _lastDispatchedKey = target.dedupeKey;
    _lastDispatchedAt = _now();
    try {
      if (dispatcher != null) {
        await dispatcher.dispatch(target);
      } else {
        await _dispatchPublicTarget(nav!, target);
      }
    } catch (error) {
      if (kDebugMode) debugPrint('[DeepLink] dispatch failed: $error');
    } finally {
      _isPublicDispatching = false;
    }

    if (_pendingPublicTarget != null) {
      await _flushPendingPublicTarget();
    }
  }

  Future<void> _dispatchPublicTarget(
    NavigatorState nav,
    NataloDeepLinkTarget target,
  ) async {
    switch (target) {
      case FeedPostDeepLink(:final postId):
        await _openPostById(nav, postId);
      case ProductDeepLink(:final slug):
        await _openProductBySlug(nav, slug);
      case ProfileDeepLink(:final username):
        nav.pushNamed('/u', arguments: username);
    }
  }

  Future<void> _handleLegacy(Uri uri) async {
    final nav = await _waitForNavigator();
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
            await _openOrderByNumber(
                nav, segments[2], uri.queryParameters['token']);
          } else {
            nav.pushNamed('/member/orders');
          }
        } else if (segments.length > 2 &&
            segments[1] == 'postingan-saya' &&
            segments[2].isNotEmpty) {
          // /akun/postingan-saya/<postId> — URL dari SEMUA notif aktivitas
          // feed (komentar/balas/mention/like/share; feedPostOwnerUrl di
          // lib/feed/notification-center.ts). SEBELUMNYA jatuh ke `else` →
          // /member (halaman Akun), jadi tap notif komentar tak pernah buka
          // postingannya = "notif masuk tapi komentar tidak muncul". Kini
          // buka postingannya langsung (komentar sejangkauan satu tap),
          // sama perilaku dengan tap notif dari bell dalam app.
          await _openPostById(nav, segments[2]);
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
          await _openOrderByNumber(
              nav, segments[1], uri.queryParameters['token']);
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
            await _openOrderByNumber(
                nav, orderNumber, uri.queryParameters['token']);
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
        if (kDebugMode) debugPrint('[DeepLink] ignored unknown path: $uri');
    }
  }

  /// Fetch postingan by ID lalu buka tujuan yang tepat — video langsung ke
  /// player fullscreen, non-video ke MemberPostDetailScreen. `isOwner`
  /// di-resolve dari memberStore (viewer == author) supaya owner yang buka
  /// notif aktivitas di postingannya sendiri tetap dapat menu edit/hapus —
  /// paritas dgn jalur bell (_openFeedPostInApp). Fallback ke /feed kalau
  /// post tidak ada (dihapus / belum tayang) atau fetch gagal.
  Future<void> _openPostById(NavigatorState nav, String postId) async {
    try {
      final post = await feedService.fetchPostById(postId);
      if (post == null) {
        nav.pushNamed('/feed');
        return;
      }
      // `nav` = State<Navigator> — `mounted` guard SEBELUM pakai `nav.context`
      // lagi setelah await (fetchPostById), cegah lint use_build_context_
      // synchronously (route/navigator bisa saja sudah di-dispose selama fetch).
      if (!nav.mounted) return;
      final myId = memberStore.profile?.id;
      final isOwner = myId != null && myId == post.author.id;
      await openFeedPostSmart(nav.context, post, isOwner: isOwner);
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
    final uri =
        input is Uri ? input : (input is String ? Uri.tryParse(input) : null);
    if (uri != null) _handle(uri);
  }

  void dispose() {
    _sub?.cancel();
  }
}

final DeepLinkService deepLinkService = DeepLinkService._();
