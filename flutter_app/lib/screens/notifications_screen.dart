import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/natalo_colors.dart';

import '../config/api_config.dart';
import '../models/app_notification.dart';
import '../models/feed_comment.dart';
import '../models/feed_post.dart';
import '../models/member_profile.dart' show OrderSummary;
import '../models/product.dart';
import '../services/api_client.dart';
import '../services/deep_link_service.dart' show openFeedPostSmart;
import '../services/feed_service.dart';
import '../services/follow_service.dart';
import '../services/notification_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import '../services/profile_service.dart';
import '../services/push_notification_service.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_login_gate.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_ui.dart';
import '../widgets/official_brand_avatar.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/heart_pump_button.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import '../widgets/notification_reply_composer.dart';
import 'announcement_detail_screen.dart';
import 'in_app_browser_screen.dart';

const _brandBlue = NataloColors.primary;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NotificationResult? _result;
  Object? _error;
  NotificationTab _tab = NotificationTab.all;
  bool _loading = true;
  bool _markingAll = false;

  // Cache filtered list — avoid O(n) where().toList() di setiap build.
  // Diinvalidasi (set null) saat _result atau _tab berubah.
  List<AppNotification>? _cachedVisibleItems;

  Timer? _tickDebounce;

  // Debounce 500ms — hindari refetch beruntun kalau beberapa push masuk
  // berdekatan; _load(silent:true) tak reset scroll/spinner.
  void _tickListener() {
    _tickDebounce?.cancel();
    _tickDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
    pushNotificationService.notificationRefreshTick.addListener(_tickListener);
  }

  @override
  void dispose() {
    pushNotificationService.notificationRefreshTick.removeListener(
      _tickListener,
    );
    _tickDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final result = await notificationService.fetchMine();
      if (!mounted) return;
      setState(() {
        _result = result;
        _cachedVisibleItems = null; // invalidate — items berubah
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() => _load(silent: true);

  List<AppNotification> get _visibleItems {
    // Memoize — cuma re-filter saat invalidate (set null) di _load/setFilter.
    // Sebelum perbaikan: setiap build (mark-read, mark-all, scroll trigger
    // setState, dll) → O(n) filter ulang. Dengan 200+ notif dan filter
    // "Disebut" yang regex-heavy, ini noticeable lag.
    final cached = _cachedVisibleItems;
    if (cached != null) return cached;
    final items = _result?.items ?? const <AppNotification>[];
    final filtered = items.where(_tab.matches).toList();
    _cachedVisibleItems = filtered;
    return filtered;
  }

  Future<void> _markAllRead() async {
    if (_markingAll || (_result?.unreadCount ?? 0) == 0) return;
    AppHaptics.tap();
    setState(() => _markingAll = true);
    try {
      await notificationService.markAllRead();
      await _load(silent: true);
      if (!mounted) return;
      // Kind-inference: tidak match keyword literal → default info per rule.
      AppToast.showBanner(
        context,
        'Semua notifikasi ditandai sudah dibaca.',
        duration: const Duration(milliseconds: 1400),
      );
    } catch (error) {
      if (!mounted) return;
      // Kind-inference: catch block dari operasi gagal → error, terlepas
      // dari literal isi _errorMessage (pesan dinamis dari server/koneksi).
      AppToast.showBanner(
        context,
        _errorMessage(error),
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openNotification(AppNotification item) async {
    AppHaptics.tap();
    if (!item.read) {
      try {
        await notificationService.markRead(item.id);
      } catch (_) {
        // Best-effort: navigation tetap jalan meski endpoint read gagal.
      }
    }

    if (!mounted) return;
    await _navigateForNotification(item);
    if (mounted) await _load(silent: true);
  }

  Future<void> _navigateForNotification(AppNotification item) async {
    final url = item.url?.trim() ?? '';
    final haystack = _notificationHaystack(item);

    // EventType-based routing — paling reliable (vs substring URL/title
    // match). Server set eventType di lib/reviews.ts saat admin reply
    // review → kirim user ke detail produk + auto-scroll ke ulasan.
    final eventType = item.eventType?.trim().toLowerCase() ?? '';
    final source = item.source?.trim().toLowerCase() ?? '';
    if (eventType == 'review_reply' || source == 'review') {
      await _openReviewedProduct(item);
      return;
    }

    // User follow event → buka profile publik follower. URL pattern
    // `/u/{username}` (lihat lib/social/notifications.ts:40-42). Sebelumnya
    // fallback ke AnnouncementDetailScreen karena tidak ada handler `/u/`
    // di chain — sekarang explicit route ke PublicProfileScreen.
    if (eventType == 'user_followed') {
      final username = extractProfileUsername(item.url);
      if (username != null) {
        await Navigator.pushNamed(context, '/u', arguments: username);
        return;
      }
      // Fallback: kalau username tidak bisa ke-extract, buka feed (sebagai
      // entry point yang reasonable — daripada catch-all AnnouncementDetailScreen
      // yang tidak relevan untuk notif follow).
      await Navigator.pushNamed(context, '/feed');
      return;
    }

    // Notif terkait 1 postingan spesifik (punya feedPostId, mis. "X posting
    // baru", komentar, like, mention, ATAU broadcast feed dari admin) →
    // buka postingan itu LANGSUNG (video ke player, non-video ke layar
    // detail) — reuse infra deep-link `openFeedPostSmart`, BUKAN fallback
    // generic AnnouncementDetailScreen. Dicek SEBELUM
    // _isAnnouncementNotification/_isPromoDetailNotification: notifikasi
    // feed dari admin (mis. postingan video "broadcast") server-set
    // category/type mengandung kata "broadcast" yang ke-tangkap duluan
    // oleh _isAnnouncementNotification kalau urutan tak dibalik — akibatnya
    // postingan video tak pernah terbuka sama sekali, cuma mendarat di
    // layar teks pengumuman generik (bug: video notif → "Detail
    // Pengumuman", bukan video-nya).
    final feedPostId = item.feedPostId?.trim() ?? '';
    if (feedPostId.isNotEmpty) {
      await _openFeedPostInApp(feedPostId);
      return;
    }

    if (_isShopPromoNotification(item)) {
      await Navigator.pushNamed(
        context,
        '/products',
        arguments: const ProductCatalogArgs(discountOnly: true),
      );
      return;
    }

    if (_isPromoDetailNotification(item)) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AnnouncementDetailScreen(notification: item),
        ),
      );
      return;
    }

    if (_isFlashSaleNotification(item)) {
      await Navigator.pushNamed(
        context,
        '/products',
        arguments: const ProductCatalogArgs(flashSaleOnly: true),
      );
      return;
    }

    if (_isVoucherNotification(item)) {
      await Navigator.pushNamed(context, '/member/vouchers');
      return;
    }

    if (_isAnnouncementNotification(item)) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AnnouncementDetailScreen(notification: item),
        ),
      );
      return;
    }

    // Refund detail — URL format `/member/refund-detail?caseId=XXX`.
    // Cek SEBELUM `/orders` matcher karena URL refund juga contain
    // `/member/` yang bisa false-match ke order handler.
    if (url.contains('/member/refund-detail') ||
        url.contains('refund-detail')) {
      // Extract caseId dari query string. Defensive parse — kalau gak
      // ada caseId, fallback ke list saldo refund (user bisa cari
      // entry yang dimaksud manual).
      final uri = Uri.tryParse(url);
      final caseId = uri?.queryParameters['caseId']?.trim();
      if (caseId != null && caseId.isNotEmpty) {
        await Navigator.pushNamed(
          context,
          '/member/refund-detail',
          arguments: caseId,
        );
      } else {
        await Navigator.pushNamed(context, '/member/refund-balance');
      }
      return;
    }

    // Loyalty redeem reminder → halaman tukar poin. Cek SEBELUM /orders
    // matcher (loyalty url tidak mengandung /orders, tapi eksplisit dulu).
    if (url.contains('/member/loyalty') ||
        item.eventType?.toLowerCase() == 'loyalty_redeem_reminder') {
      await Navigator.pushNamed(context, '/member/loyalty');
      return;
    }

    // Pesanan spesifik: url `/pesanan/{orderNumber}` → buka detail pesanan itu
    // (bukan daftar). Fallback ke daftar di dalam _openOrderInApp bila fetch gagal.
    final orderNumber = extractOrderNumber(url);
    if (orderNumber != null) {
      await _openOrderInApp(orderNumber, extractOrderTrackingToken(url));
      return;
    }

    if (url.contains('/member/orders') ||
        url.contains('/orders') ||
        haystack.contains('pesanan') ||
        haystack.contains('order')) {
      await Navigator.pushNamed(context, '/member/orders');
      return;
    }

    if (url.contains('/cart') || haystack.contains('keranjang')) {
      await Navigator.pushNamed(context, '/cart');
      return;
    }

    if (url.contains('/checkout')) {
      await Navigator.pushNamed(context, '/checkout');
      return;
    }

    if (url.contains('/feed') || _NotificationFilter.feed.matches(item)) {
      await Navigator.pushNamed(context, '/feed');
      return;
    }

    if (url.contains('/produk/') || url.contains('/products/')) {
      final slug = _extractProductSlug(url);
      if (slug != null) {
        await _openProductBySlug(slug);
        return;
      }
    }
    if (url.contains('/products') || url.contains('/produk')) {
      await Navigator.pushNamed(context, '/products');
      return;
    }

    final externalUrl = _toAbsoluteUrl(url);
    if (externalUrl != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => InAppBrowserScreen(
            url: externalUrl,
            title: item.title,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AnnouncementDetailScreen(notification: item),
      ),
    );
  }

  /// Fetch postingan by ID lalu buka tujuan yang tepat — video langsung ke
  /// player fullscreen, non-video ke MemberPostDetailScreen (reuse
  /// `openFeedPostSmart`, sama dgn jalur push notification HP di
  /// `DeepLinkService`, supaya kedua jalur konsisten). isOwner dihitung
  /// dari apakah viewer == author (post sendiri → bisa edit/hapus; post
  /// orang → viewer biasa). Spinner saat fetch; fallback ke feed kalau
  /// postingan tidak ada / fetch gagal.
  /// Fetch pesanan by orderNumber lalu buka detail pesanan itu. Spinner saat
  /// fetch; fallback ke daftar pesanan kalau gagal (pesanan tidak ada / token
  /// invalid). Mirror pola _openFeedPostInApp + deep_link _openOrderByNumber.
  Future<void> _openOrderInApp(String orderNumber, String? trackingToken) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );

    OrderSummary? order;
    try {
      order = await orderService.fetchOrderDetail(
        orderNumber,
        trackingToken: trackingToken,
      );
    } catch (_) {
      order = null;
    }

    rootNav.pop(); // tutup loading dialog
    if (!mounted) return;

    if (order == null) {
      await Navigator.pushNamed(context, '/member/orders');
      return;
    }
    await Navigator.pushNamed(context, '/member/order-detail', arguments: order);
  }

  /// Fetch produk by slug lalu buka detailnya. Spinner saat fetch; fallback
  /// ke katalog kalau produk tak ada / fetch gagal. Pola sama _openReviewedProduct.
  Future<void> _openProductBySlug(String slug) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );
    Product? product;
    try {
      product = await productService.fetchProductBySlug(slug);
    } catch (_) {
      product = null;
    }
    rootNav.pop();
    if (!mounted) return;
    if (product == null) {
      await Navigator.pushNamed(context, '/products');
      return;
    }
    await Navigator.pushNamed(
      context,
      '/product-detail',
      arguments: ProductDetailArgs(product: product),
    );
  }

  Future<void> _openFeedPostInApp(String postId) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );

    FeedPost? post;
    try {
      post = await feedService.fetchPostById(postId);
    } catch (_) {
      post = null;
    }

    rootNav.pop(); // tutup loading dialog
    if (!mounted) return;

    if (post == null) {
      // Postingan dihapus / belum tayang / error. Dulu diam-diam lempar ke
      // /feed (user bingung: tap notif malah pindah ke Feed tanpa sebab).
      // Sekarang TETAP di layar Notifikasi + toast jelas — paritas IG.
      AppToast.show(
        context,
        'Postingan ini sudah dihapus.',
        kind: ToastKind.info,
        icon: Icons.delete_outline_rounded,
      );
      return;
    }

    final myId = memberStore.profile?.id;
    final isOwner = myId != null && myId == post.author.id;
    await openFeedPostSmart(context, post, isOwner: isOwner);
  }

  /// Handler untuk notif "Toko membalas ulasanmu" (eventType=review_reply).
  /// Extract slug dari url `/products/{slug}` → fetch Product → buka
  /// ProductDetailScreen dengan focusReviewSection=true (auto-scroll ke
  /// section ulasan). Fallback: kalau slug invalid atau produk dihapus
  /// admin, redirect ke /akun/ulasan supaya user tetap bisa lihat balasan
  /// di history ulasan mereka.
  Future<void> _openReviewedProduct(AppNotification item) async {
    final slug = _extractProductSlug(item.url);
    if (slug == null) {
      await Navigator.pushNamed(context, '/akun/ulasan');
      return;
    }

    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );

    Product? product;
    try {
      product = await productService.fetchProductBySlug(slug);
    } catch (_) {
      product = null;
    }

    rootNav.pop(); // tutup loading dialog
    if (!mounted) return;

    if (product == null) {
      // Produk dihapus / belum ke-fetch — fallback ke list ulasan user
      // (balasan toko tetap ke-attach ke review di sana).
      await Navigator.pushNamed(context, '/akun/ulasan');
      return;
    }

    await Navigator.pushNamed(
      context,
      '/product-detail',
      arguments: ProductDetailArgs(
        product: product,
        focusReviewSection: true,
      ),
    );
  }

  /// Extract product slug dari URL pattern `/products/{slug}` atau
  /// `/produk/{slug}`. Return null kalau URL tidak match atau slug kosong.
  /// URL-decode untuk handle slug ber-spesial-character.
  String? _extractProductSlug(String? url) {
    if (url == null || url.isEmpty) return null;
    final match = RegExp(r'/produk(?:s)?/([^/?#]+)').firstMatch(url);
    if (match == null) return null;
    final slug = match.group(1)?.trim() ?? '';
    if (slug.isEmpty) return null;
    return Uri.decodeComponent(slug);
  }

  @override
  Widget build(BuildContext context) {
    // Login gate — sebelum render apapun. Reasoning: notif page = fitur
    // member only di Natalo (lihat AppNotificationButton comment). Kalau
    // guest masuk via deep link / direct nav (mis. push notif lama saat
    // belum login), tampilkan prompt "Login dulu" daripada error/kosong.
    //
    // AnimatedBuilder listen memberStore supaya kalau user login dari
    // dalam login screen yang di-push dari sini, page auto refresh
    // tampilkan content begitu logged-in.
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        if (!memberStore.isLoggedIn) {
          return const AppLoginRequiredScaffold(
            title: 'Notifikasi',
            message:
                'Masuk member untuk lihat notifikasi pesanan, voucher, dan update lainnya.',
          );
        }
        return _buildAuthenticatedContent(context);
      },
    );
  }

  /// Render content normal untuk user logged-in. Dipisahkan dari build()
  /// supaya bisa wrap dengan AnimatedBuilder login check tanpa nested
  /// indentation yang dalam.
  Widget _buildAuthenticatedContent(BuildContext context) {
    final result = _result;
    final unread = result?.unreadCount ?? 0;

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : const Color(0xFFEEF1F5),
      // AnnotatedRegion + strip status bar heroTop — pola hero biru Beranda:
      // area notch menyatu dengan header biru, ikon status bar putih.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top,
              child: const ColoredBox(color: NataloColors.heroTop),
            ),
            SafeArea(
              child: Column(
                children: [
                  NotificationHeroHeader(
                    unreadCount: unread,
                    markingAll: _markingAll,
                    selected: _tab,
                    onTabChanged: (tab) {
                      AppHaptics.selection();
                      setState(() {
                        _tab = tab;
                        _cachedVisibleItems = null; // invalidate — tab berubah
                      });
                    },
                    onBack: () => Navigator.maybePop(context),
                    onMarkAllRead: _markAllRead,
                  ),
                  Expanded(
                    // Cross-fade skeleton → list/error/empty supaya konten tidak
                    // "pop" kasar saat data masuk.
                    child: AppFadeSwitcher(
                      stateKey: _loading && result == null
                          ? 'loading'
                          : _error != null && result == null
                              ? 'error'
                              : 'content',
                      child: _buildContent(result),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(NotificationResult? result) {
    if (_loading && result == null) {
      return const AppSkeletonList(
        itemCount: 6,
        itemHeight: 92,
        padding: EdgeInsets.fromLTRB(16, 18, 16, 24),
      );
    }

    final error = _error;
    if (error != null && result == null) {
      // #4: pakai AppErrorState (komponen tunggal) + varian DITURUNKAN dari
      // exception asli — 5xx=server, koneksi=network, 404=notFound. Tidak
      // lagi salah label "cek koneksi" untuk error server.
      return AppErrorState(
        variant: appErrorVariantFromError(error),
        title: 'Notifikasi gagal dimuat',
        description: _errorMessage(error),
        onRetry: () => _load(),
      );
    }

    final items = _visibleItems;
    if (items.isEmpty) {
      return NataloPawRefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
          children: [
            _NotificationEmptyState(tab: _tab),
          ],
        ),
      );
    }

    // Grup waktu → kartu island per grup (hairline antar baris).
    final now = DateTime.now();
    final groups = <NotificationTimeBucket, List<AppNotification>>{};
    for (final item in items) {
      groups
          .putIfAbsent(
              notificationTimeBucket(now, item.createdAt), () => [])
          .add(item);
    }
    final orderedBuckets = NotificationTimeBucket.values
        .where((b) => groups.containsKey(b))
        .toList();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return NataloPawRefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        itemCount: orderedBuckets.length,
        itemBuilder: (context, groupIndex) {
          final bucket = orderedBuckets[groupIndex];
          final groupItems = groups[bucket]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
                child: Text(
                  bucket.label,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < groupItems.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 68),
                          child: Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: isDark
                                ? cs.outlineVariant
                                : const Color(0xFFECF0F6),
                          ),
                        ),
                      NotificationRow(
                        notification: groupItems[i],
                        onTap: () => _openNotification(groupItems[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Header hero redesign: judul + counter "N baru" + "Tandai dibaca" + 4 tab
/// pill DI DALAM area gradient biru (menggantikan _NotificationTabs strip
/// putih). Publik + dipakai langsung oleh widget test.
@visibleForTesting
class NotificationHeroHeader extends StatelessWidget {
  final int unreadCount;
  final bool markingAll;
  final NotificationTab selected;
  final ValueChanged<NotificationTab> onTabChanged;
  final VoidCallback onBack;
  final VoidCallback onMarkAllRead;

  const NotificationHeroHeader({
    super.key,
    required this.unreadCount,
    required this.markingAll,
    required this.selected,
    required this.onTabChanged,
    required this.onBack,
    required this.onMarkAllRead,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: NataloColors.heroGradientV,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white,
              ),
              const Text(
                'Notifikasi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.1,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+ baru' : '$unreadCount baru',
                    style: const TextStyle(
                      color: NataloColors.onHeroBright,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed:
                    unreadCount == 0 || markingAll ? null : onMarkAllRead,
                style: TextButton.styleFrom(
                  foregroundColor: NataloColors.onHeroBright,
                  disabledForegroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                ),
                child: markingAll
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white70),
                      )
                    : const Text(
                        'Tandai dibaca',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w400),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: NotificationTab.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tab = NotificationTab.values[index];
                final active = tab == selected;
                return InkWell(
                  onTap: () => onTabChanged(tab),
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tab.label,
                      style: TextStyle(
                        color: active
                            ? NataloColors.heroTop
                            : NataloColors.onHeroBright.withValues(alpha: 0.8),
                        fontSize: 12.5,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Extract username dari URL pattern `/u/{username}` (deep link
/// public profile). Lowercase karena DB username always lowercase.
/// Top-level: dipakai routing layar DAN gate pill follow-back.
@visibleForTesting
String? extractProfileUsername(String? url) {
  if (url == null || url.isEmpty) return null;
  final match = RegExp(r'/u/([^/?#]+)').firstMatch(url);
  if (match == null) return null;
  final username = match.group(1)?.trim().toLowerCase() ?? '';
  if (username.isEmpty) return null;
  return Uri.decodeComponent(username);
}

/// Seam test: fetch profil publik by username. Default produksi memakai
/// [profileService.fetchPublicProfile]; widget test menyuntik fake.
typedef PublicProfileFetcher = Future<PublicProfileResult> Function(
    String username);

/// Seam test aksi komentar. Default produksi memakai feedService.
typedef CommentLikeSetter = Future<int> Function(
  String commentId, {
  required bool liked,
});
typedef CommentByIdFetcher = Future<FeedComment> Function(String commentId);

/// Baris notifikasi redesign: identitas kiri → kalimat+waktu tengah →
/// thumbnail kanan (opsional). Unread = bar aksen kiri. Publik untuk test.
@visibleForTesting
class NotificationRow extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final FollowService? followService;
  final PublicProfileFetcher? profileFetcher;
  final CommentLikeSetter? commentLikeSetter;
  final CommentByIdFetcher? commentByIdFetcher;
  final CommentReplyPoster? commentReplyPoster;

  const NotificationRow({
    super.key,
    required this.notification,
    required this.onTap,
    this.followService,
    this.profileFetcher,
    this.commentLikeSetter,
    this.commentByIdFetcher,
    this.commentReplyPoster,
  });

  bool get _isBrandIdentity =>
      _NotificationFilter.feed.matches(notification) ||
      _isAnnouncementNotification(notification);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visual = _NotificationVisual.from(notification);
    final ctaLabel = _notificationCtaLabel(notification);
    final imageUrl = notification.imageUrl;
    final isFollow =
        notification.eventType?.toLowerCase() == 'user_followed';
    // Avatar kiri dari field terstruktur (semua notif ber-aktor). Follow
    // tak punya konten post → sembunyikan thumbnail kanan; notif lain (mis.
    // komentar) tetap tampilkan thumbnail POST di kanan.
    final structuredActorAvatarUrl = notification.actorAvatarUrl;
    final actorAvatarUrl =
        structuredActorAvatarUrl != null &&
                structuredActorAvatarUrl.trim().isNotEmpty
            ? structuredActorAvatarUrl
            : (isFollow ? imageUrl : null);
    final showLikeBadge =
        notification.eventType?.trim().toLowerCase() == 'feed_new_like';
    final followBackUsername =
        notification.eventType?.toLowerCase() == 'user_followed'
            ? extractProfileUsername(notification.url)
            : null;
    final feedPostIdTrim = notification.feedPostId?.trim() ?? '';
    final commentIdTrim = notification.commentId?.trim() ?? '';
    // Postingan yang dirujuk sudah dihapus (server: FeedPost hilang). Baris
    // diredupkan + label pasif "Sudah dihapus" + tap dimatikan (Lapisan 2
    // ala IG). Aksi lain (pill follow / komentar / CTA) disembunyikan supaya
    // user tidak menekan tujuan yang sudah tak ada.
    final deleted = notification.postDeleted;
    final showCommentActions = !deleted &&
        notification.eventType?.trim().toLowerCase() == 'feed_new_comment' &&
        commentIdTrim.isNotEmpty &&
        feedPostIdTrim.isNotEmpty;
    final titleColor = deleted ? cs.onSurfaceVariant : cs.onSurface;

    return InkWell(
      onTap: deleted ? null : onTap,
      child: Stack(
        children: [
          if (!notification.read)
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              child: Container(
                key: const ValueKey('notification-unread-bar'),
                width: 3,
                decoration: const BoxDecoration(
                  color: NataloColors.primary,
                  borderRadius:
                      BorderRadius.horizontal(right: Radius.circular(3)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (notification.actorAvatarUrls.length >= 2)
                  StackedActorAvatars(
                    urls: notification.actorAvatarUrls,
                    visual: visual,
                    likeBadge: showLikeBadge,
                  )
                else
                  _IdentityAvatar(
                    visual: visual,
                    brandIdentity: _isBrandIdentity,
                    avatarUrl: actorAvatarUrl,
                    likeBadge: showLikeBadge,
                    actorName: notification.actorName,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: notification.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (notification.body.trim().isNotEmpty)
                              TextSpan(text: ' — ${notification.body.trim()}'),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (deleted) ...[
                            Container(
                              key: const ValueKey(
                                  'notification-post-deleted-label'),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.delete_outline_rounded,
                                      size: 13, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Sudah dihapus',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                          ] else if (followBackUsername != null) ...[
                            _NotificationFollowBackPill(
                              username: followBackUsername,
                              initialIsFollowing: notification.isFollowing,
                              followService: followService,
                              profileFetcher: profileFetcher,
                            ),
                            const SizedBox(width: 10),
                          ] else if (showCommentActions) ...[
                            _NotificationCommentActions(
                              commentId: commentIdTrim,
                              feedPostId: feedPostIdTrim,
                              initialLiked: notification.commentLiked,
                              likeSetter: commentLikeSetter,
                              fetcher: commentByIdFetcher,
                              poster: commentReplyPoster,
                            ),
                            const SizedBox(width: 8),
                          ] else if (ctaLabel != null) ...[
                            InkWell(
                              onTap: onTap,
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: NataloColors.primarySoft,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  ctaLabel,
                                  style: const TextStyle(
                                    color: NataloColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            shortRelativeTime(
                                DateTime.now(), notification.createdAt),
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (deleted && feedPostIdTrim.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Container(
                    key: const ValueKey('notification-thumb-deleted'),
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ] else if (imageUrl != null &&
                    imageUrl.trim().isNotEmpty &&
                    !isFollow) ...[
                  const SizedBox(width: 12),
                  Container(
                    key: const ValueKey('notification-thumb'),
                    height: 46,
                    width: 46,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : Container(color: cs.surfaceContainerHighest),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _FollowBackState { idle, loading, following }

/// Pill follow-balik inline utk notif follow — tap men-follow tanpa keluar
/// layar (ala IG "Follow back"). Status awal diseed dari `initialIsFollowing`
/// (server: UserFollow lewat Announcement.actorId, lihat commentLiked utk
/// pola sama) supaya pill BENAR sejak render pertama — sebelumnya selalu
/// mulai "Ikuti" walau viewer sudah follow-balik, baru benar setelah tap.
/// Null (notif lama pra-migration / server belum kirim) → fallback idle,
/// tap tetap cek fresh ke server sebelum follow (defensif, bukan asumsi).
/// SENGAJA tidak setFollowOverride pre-await (bukan optimistic lintas-widget;
/// follow() internal sudah confirm saat sukses + rollback override saat gagal).
class _NotificationFollowBackPill extends StatefulWidget {
  final String username;
  final bool? initialIsFollowing;
  final FollowService? followService;
  final PublicProfileFetcher? profileFetcher;

  const _NotificationFollowBackPill({
    required this.username,
    this.initialIsFollowing,
    this.followService,
    this.profileFetcher,
  });

  @override
  State<_NotificationFollowBackPill> createState() =>
      _NotificationFollowBackPillState();
}

class _NotificationFollowBackPillState
    extends State<_NotificationFollowBackPill> {
  late _FollowBackState _state = widget.initialIsFollowing == true
      ? _FollowBackState.following
      : _FollowBackState.idle;

  Future<void> _handleTap() async {
    if (_state != _FollowBackState.idle) return;
    AppHaptics.tap();
    setState(() => _state = _FollowBackState.loading);
    try {
      final fetch = widget.profileFetcher ??
          (String u) => profileService.fetchPublicProfile(
                username: u,
                limit: 1,
              );
      final result = await fetch(widget.username);
      if (!mounted) return;
      if (result.profile.isOwner) {
        setState(() => _state = _FollowBackState.idle);
        return;
      }
      if (result.profile.isFollowing) {
        setState(() => _state = _FollowBackState.following);
        return;
      }
      final service = widget.followService ?? followService;
      await service.follow(result.profile.id);
      if (!mounted) return;
      setState(() => _state = _FollowBackState.following);
    } on FollowSessionChangedException {
      if (mounted) setState(() => _state = _FollowBackState.idle);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _FollowBackState.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengikuti. Coba lagi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_state) {
      _FollowBackState.following => 'Mengikuti',
      _ => 'Ikuti',
    };
    return InkWell(
      key: const ValueKey('notification-follow-back-pill'),
      onTap: _state == _FollowBackState.idle ? _handleTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: NataloColors.primarySoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: _state == _FollowBackState.loading
            ? const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: NataloColors.primary,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: NataloColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

/// Baris aksi ♡ + Balas utk notif komentar (gate: feed_new_comment +
/// commentId + feedPostId). ♡ optimistik idempotent (setCommentLiked);
/// Balas → fetchCommentById → composer ringan. Nested InkWell: tap aksi
/// TIDAK memicu navigasi baris.
class _NotificationCommentActions extends StatefulWidget {
  final String commentId;
  final String feedPostId;

  /// State like awal komentar (dari server) supaya ♡ tampil merah kalau memang
  /// sudah di-like — bukan selalu kosong. Sinkron dgn sheet komentar saat load.
  final bool initialLiked;
  final CommentLikeSetter? likeSetter;
  final CommentByIdFetcher? fetcher;
  final CommentReplyPoster? poster;

  const _NotificationCommentActions({
    required this.commentId,
    required this.feedPostId,
    this.initialLiked = false,
    this.likeSetter,
    this.fetcher,
    this.poster,
  });

  @override
  State<_NotificationCommentActions> createState() =>
      _NotificationCommentActionsState();
}

class _NotificationCommentActionsState
    extends State<_NotificationCommentActions> {
  late bool _liked = widget.initialLiked;
  bool _likeBusy = false;
  bool _replyLoading = false;

  @override
  void didUpdateWidget(covariant _NotificationCommentActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refetch daftar notifikasi bawa state like terbaru dari server — ikuti,
    // KECUALI ada toggle optimistik yang belum selesai (jangan timpa).
    if (!_likeBusy && widget.initialLiked != oldWidget.initialLiked) {
      _liked = widget.initialLiked;
    }
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    // Haptic tap sudah di-fire oleh HeartPumpButton sendiri — jangan
    // duplikat di sini (pola double-haptic yang sama kita fix di toast).
    final next = !_liked;
    setState(() {
      _liked = next;
      _likeBusy = true;
    });
    final setLike = widget.likeSetter ??
        (String id, {required bool liked}) =>
            feedService.setCommentLiked(id, liked: liked);
    try {
      await setLike(widget.commentId, liked: next);
      if (!mounted) return;
      setState(() => _likeBusy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = !next; // rollback
        _likeBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menyukai komentar.')),
      );
    }
  }

  Future<void> _openReply() async {
    if (_replyLoading) return;
    AppHaptics.tap();
    setState(() => _replyLoading = true);
    final fetch =
        widget.fetcher ?? (String id) => feedService.fetchCommentById(id);
    try {
      final comment = await fetch(widget.commentId);
      if (!mounted) return;
      setState(() => _replyLoading = false);
      await showNotificationReplyComposer(
        context,
        comment: comment,
        feedPostId: widget.feedPostId,
        poster: widget.poster,
      );
    } on FeedCommentUnavailableException catch (e) {
      if (!mounted) return;
      setState(() => _replyLoading = false);
      final msg = e.reason == FeedCommentUnavailableReason.postDeleted
          ? 'Postingan sudah dihapus.'
          : 'Komentar sudah dihapus.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _replyLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal memuat komentar. Coba lagi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          width: 44,
          child: Center(
            child: HeartPumpButton(
              key: const ValueKey('notification-comment-like'),
              liked: _liked,
              onTap: _toggleLike,
              size: 18,
              likedColor: const Color(0xFFE11D48),
              unlikedColor: cs.onSurfaceVariant,
            ),
          ),
        ),
        InkWell(
          key: const ValueKey('notification-comment-reply'),
          onTap: _replyLoading ? null : _openReply,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: NataloColors.primarySoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: _replyLoading
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: NataloColors.primary,
                    ),
                  )
                : const Text(
                    'Balas',
                    style: TextStyle(
                      color: NataloColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Lencana ❤️ kecil utk notif LIKE — ditempel di sudut kanan-bawah avatar
/// BERFOTO (persis pola badge kategori brand). Hanya utk feed_new_like.
/// Return Positioned → WAJIB dipakai sebagai child langsung sebuah Stack.
Positioned _likeBadge(BuildContext context) => Positioned(
      right: -3,
      bottom: -3,
      child: Container(
        key: const ValueKey('notification-like-badge'),
        height: 17,
        width: 17,
        decoration: BoxDecoration(
          color: const Color(0xFFE11D48),
          shape: BoxShape.circle,
          border: Border.all(
              color: Theme.of(context).colorScheme.surface, width: 2),
        ),
        child: const Icon(Icons.favorite_rounded,
            color: Colors.white, size: 9),
      ),
    );

/// Avatar bertumpuk ala IG untuk notif like agregat (2 foto liker teratas
/// saling tumpang-tindih). Ukuran total 42 supaya sejajar avatar lain.
class StackedActorAvatars extends StatelessWidget {
  final List<String> urls;
  final _NotificationVisual visual;
  final bool likeBadge;
  const StackedActorAvatars(
      {super.key,
      required this.urls,
      required this.visual,
      this.likeBadge = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = urls.take(2).toList();
    Widget circle(String url, double size) => Container(
          height: size,
          width: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: visual.color.withValues(alpha: 0.12),
            border: Border.all(color: cs.surface, width: 2),
          ),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Icon(visual.icon, color: visual.color, size: 16),
          ),
        );
    return SizedBox(
      key: const ValueKey('notification-stacked-avatars'),
      height: 42,
      width: 42,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (shown.length > 1)
            Positioned(left: 0, top: 0, child: circle(shown[1], 30)),
          Positioned(right: 0, bottom: 0, child: circle(shown[0], 30)),
          if (likeBadge) _likeBadge(context),
        ],
      ),
    );
  }
}

/// Lingkaran identitas kiri: brand "NL" untuk notifikasi feed/pengumuman
/// (identitas Natalo), tint kategori + ikon untuk lainnya. Badge kategori
/// mini hanya saat identitas brand (kategori tetap terbaca).
class _IdentityAvatar extends StatelessWidget {
  final _NotificationVisual visual;
  final bool brandIdentity;
  final String? avatarUrl;
  final bool likeBadge;
  final String? actorName;

  const _IdentityAvatar({
    required this.visual,
    required this.brandIdentity,
    this.avatarUrl,
    this.likeBadge = false,
    this.actorName,
  });

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    if (url != null && url.trim().isNotEmpty) {
      final photo = Container(
        key: const ValueKey('notification-actor-avatar'),
        height: 42,
        width: 42,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: visual.color.withValues(alpha: 0.12),
        ),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(visual.icon, color: visual.color, size: 20),
        ),
      );
      if (!likeBadge) return photo;
      return Stack(
        clipBehavior: Clip.none,
        children: [photo, _likeBadge(context)],
      );
    }
    // Bug lama (sejak P2): notif ber-aktor (mis. komentar/like) tanpa foto
    // salah menampilkan logo brand Natalo — padahal aktornya user BIASA yang
    // sekadar belum pasang foto profil, bukan akun official. Server SUDAH
    // brand-safe (admin → actorName "Natalo Petshop Official", user biasa →
    // nama asli), tapi client dulu abai pada actorName dan cuma lihat
    // `brandIdentity` (kategori feed/pengumuman) — akibatnya SEMUA notif feed
    // tanpa foto (termasuk milik user biasa) dianggap identitas brand.
    // Fix: bila ada actorName NYATA (bukan brand) → avatar inisial netral
    // (ProfileAvatar, pola sama dgn avatar user di seluruh app), BUKAN logo
    // brand. Badge kategori kanan-bawah tetap ikut aturan `brandIdentity`
    // yang sudah ada (tak berubah) — jadi notif komentar/like tetap dapat
    // badge kecilnya, cuma identitas utamanya kini benar (inisial, bukan NL).
    final trimmedActorName = actorName?.trim();
    final isBrandActor = trimmedActorName == 'Natalo Petshop Official';
    final hasRealActor =
        trimmedActorName != null && trimmedActorName.isNotEmpty && !isBrandActor;
    final core = hasRealActor
        ? ProfileAvatar(
            size: 42,
            fontSize: 16,
            initial: trimmedActorName.substring(0, 1).toUpperCase(),
            plain: true,
          )
        : brandIdentity
            ? const OfficialBrandAvatar(size: 42)
            : Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(visual.icon, color: visual.color, size: 20),
              );

    if (!brandIdentity) return core;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        core,
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            height: 17,
            width: 17,
            decoration: BoxDecoration(
              color: visual.color,
              shape: BoxShape.circle,
              border: Border.all(
                  color: Theme.of(context).colorScheme.surface, width: 2),
            ),
            child: Icon(visual.icon, color: Colors.white, size: 9),
          ),
        ),
      ],
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  final NotificationTab tab;

  const _NotificationEmptyState({required this.tab});

  IconData get _icon => switch (tab) {
        NotificationTab.all => Icons.notifications_none_rounded,
        NotificationTab.activity => Icons.play_circle_outline_rounded,
        NotificationTab.transaction => Icons.receipt_long_rounded,
        NotificationTab.promo => Icons.confirmation_number_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          height: 86,
          width: 86,
          decoration: BoxDecoration(
            color: _brandBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Icon(
            _icon,
            color: _brandBlue,
            size: 40,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          tab == NotificationTab.all
              ? 'Belum ada notifikasi'
              : 'Belum ada notifikasi ${tab.label}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Update terbaru dari Natalo akan muncul di sini.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w400,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

enum _NotificationFilter {
  // Mention diletakkan di posisi #2 (priority tinggi) — match IG/TikTok
  // pattern di mana notifikasi mention lebih penting daripada like/comment
  // generic. User cek dulu siapa yang nyebutin sebelum browse lain.
  all,
  mention,
  order,
  promo,
  feed,
  announcement;

  // label/icon lama dihapus — sejak redesign, UI tab & empty state pakai
  // NotificationTab; enum ini tinggal dipakai untuk logika `matches`.

  bool matches(AppNotification item) {
    if (this == _NotificationFilter.all) return true;
    final text = _notificationHaystack(item);
    final isMention = _isMentionNotification(item);
    return switch (this) {
      // Mention match: eventType (preferred, server-set "feed_mention")
      // atau keyword fallback untuk backward-compat (notif lama tanpa
      // eventType atau dari source lain).
      _NotificationFilter.mention => isMention,
      _NotificationFilter.order => text.contains('order') ||
          text.contains('pesanan') ||
          text.contains('payment') ||
          text.contains('pembayaran') ||
          text.contains('checkout') ||
          text.contains('shipped') ||
          text.contains('dikirim'),
      _NotificationFilter.promo => text.contains('promo') ||
          text.contains('flash sale') ||
          text.contains('flashsale') ||
          text.contains('voucher') ||
          text.contains('diskon') ||
          text.contains('discount') ||
          text.contains('coupon') ||
          text.contains('gratis ongkir'),
      // Feed EXCLUDE mention — mention punya tab sendiri. Tanpa exclusion,
      // 1 mention notif muncul di 2 tab (Disebut + Feed) → confusing.
      _NotificationFilter.feed => !isMention &&
          (text.contains('feed') ||
              text.contains('video') ||
              text.contains('post') ||
              text.contains('comment') ||
              text.contains('komentar') ||
              text.contains('like') ||
              text.contains('share') ||
              text.contains('approved') ||
              text.contains('rejected')),
      _NotificationFilter.announcement => _isAnnouncementNotification(item),
      _NotificationFilter.all => true,
    };
  }
}

/// Detect notifikasi mention. Prefer eventType match (server-set
/// "feed_mention" sejak Fase 3.1), fallback ke keyword match buat row
/// lama / notif dari source lain yang gak set eventType.
bool _isMentionNotification(AppNotification item) {
  if (item.eventType?.toLowerCase() == 'feed_mention') return true;
  final text = _notificationHaystack(item);
  return text.contains('menyebut') ||
      text.contains('mentioned') ||
      text.contains('mention');
}

/// Detect refund notif (saldo refund masuk dari admin). URL pattern
/// `/member/refund-detail?caseId=...` + category "refund" di push
/// payload + title biasanya "Refund Rp...".
bool _isRefundNotification(AppNotification item) {
  final url = item.url?.toLowerCase() ?? '';
  if (url.contains('refund-detail') || url.contains('refund_detail')) {
    return true;
  }
  if (item.category?.toLowerCase() == 'refund') return true;
  if (item.eventType?.toLowerCase().contains('refund') == true) return true;
  final text = _notificationHaystack(item);
  // Match pattern title "Refund Rp..." atau "Refund X sudah masuk".
  return text.contains('refund') && text.contains('saldo') ||
      text.contains('refund') && text.contains('masuk');
}

class _NotificationVisual {
  final IconData icon;
  final Color color;
  final String label;

  const _NotificationVisual({
    required this.icon,
    required this.color,
    required this.label,
  });

  factory _NotificationVisual.from(AppNotification item) {
    final ev = item.eventType?.trim().toLowerCase() ?? '';
    // Mention visual diutamakan — dedicated icon @ supaya user tau
    // visual cepat ini notif sosial. Match brand violet.
    if (_isMentionNotification(item)) {
      return const _NotificationVisual(
        icon: Icons.alternate_email_rounded,
        color: Color(0xFF5B5BD6),
        label: 'Disebut',
      );
    }
    // Balasan ulasan toko — satu keluarga warna dgn mention ("personal
    // ke kamu"), ikon beda (bintang, bukan @) supaya tak nambah hue baru.
    if (ev == 'review_reply' || item.source?.toLowerCase() == 'review') {
      return const _NotificationVisual(
        icon: Icons.rate_review_rounded,
        color: Color(0xFF5B5BD6),
        label: 'Ulasan',
      );
    }
    // Refund notif — URL pakai `/member/refund-detail` atau title
    // contain "Refund Rp...". Dedicated icon money + label hijau
    // supaya user paham langsung ini saldo masuk.
    if (_isRefundNotification(item)) {
      return const _NotificationVisual(
        icon: Icons.account_balance_wallet_rounded,
        color: Color(0xFF10B981),
        label: 'Refund',
      );
    }
    if (_NotificationFilter.order.matches(item)) {
      return const _NotificationVisual(
        icon: Icons.receipt_long_rounded,
        color: _brandBlue,
        label: 'Pesanan',
      );
    }
    if (ev == 'voucher_freeship_published') {
      return const _NotificationVisual(
        icon: Icons.local_shipping_rounded,
        color: _brandBlue,
        label: 'Gratis Ongkir',
      );
    }
    if (ev == 'voucher_discount_published') {
      return const _NotificationVisual(
        icon: Icons.sell_rounded,
        color: Color(0xFF16A34A),
        label: 'Voucher',
      );
    }
    // Pengingat tukar poin — dicek SEBELUM voucher/promo generik karena
    // body-nya sering menyebut kata "voucher" (hadiah tukar poin), yang
    // kalau tak diprioritaskan akan salah ke-tangkap sebagai promo biasa.
    if (ev == 'loyalty_redeem_reminder' ||
        (item.url?.toLowerCase().contains('/member/loyalty') ?? false)) {
      return const _NotificationVisual(
        icon: Icons.card_giftcard_rounded,
        color: Color(0xFFD97706),
        label: 'Poin',
      );
    }
    if (_isVoucherNotification(item)) {
      return const _NotificationVisual(
        icon: Icons.confirmation_number_rounded,
        color: Color(0xFF16A34A),
        label: 'Voucher',
      );
    }
    // Flash Sale — dicek SEBELUM promo generik (helper sebelumnya cuma
    // dipakai utk CTA, tak pernah menentukan ikon) supaya tak numpang
    // tampilan voucher biasa. Warna merah = urgensi/waktu terbatas.
    if (_isFlashSaleNotification(item)) {
      return const _NotificationVisual(
        icon: Icons.bolt_rounded,
        color: Color(0xFFDC2626),
        label: 'Flash Sale',
      );
    }
    if (_isPromoDetailNotification(item)) {
      return const _NotificationVisual(
        icon: Icons.campaign_rounded,
        color: Color(0xFFE11D48),
        label: 'Promo',
      );
    }
    if (_NotificationFilter.promo.matches(item)) {
      return const _NotificationVisual(
        icon: Icons.confirmation_number_rounded,
        color: Color(0xFFE91E63),
        label: 'Promo',
      );
    }
    // Sub-tipe Feed — dicek SEBELUM branch Feed generik supaya komentar/
    // like/share/status postingan masing-masing dapat ikon berbeda
    // (badge kecil di avatar), bukan satu play-circle utk semuanya.
    // Status negatif/urgent (ditolak, gagal encode) → merah; menunggu →
    // abu netral; selain itu tetap keluarga ungu Feed (beda ikon saja).
    if (ev == 'feed_post_rejected') {
      return const _NotificationVisual(
        icon: Icons.cancel_rounded,
        color: Color(0xFFDC2626),
        label: 'Feed',
      );
    }
    if (ev == 'feed_encoding_failed') {
      return const _NotificationVisual(
        icon: Icons.error_outline_rounded,
        color: Color(0xFFDC2626),
        label: 'Feed',
      );
    }
    if (ev == 'feed_review_pending') {
      return const _NotificationVisual(
        icon: Icons.hourglass_empty_rounded,
        color: Color(0xFF6B7280),
        label: 'Feed',
      );
    }
    if (ev == 'feed_post_approved') {
      return const _NotificationVisual(
        icon: Icons.check_circle_rounded,
        color: Color(0xFF7C3AED),
        label: 'Feed',
      );
    }
    if (ev == 'feed_tagged') {
      return const _NotificationVisual(
        icon: Icons.person_pin_rounded,
        color: _brandBlue,
        label: 'Ditandai',
      );
    }
    if (ev == 'feed_new_comment') {
      return const _NotificationVisual(
        icon: Icons.chat_bubble_outline_rounded,
        color: Color(0xFF7C3AED),
        label: 'Feed',
      );
    }
    if (ev == 'feed_new_like') {
      return const _NotificationVisual(
        icon: Icons.favorite_rounded,
        color: Color(0xFFE11D48),
        label: 'Feed',
      );
    }
    if (ev == 'feed_new_share') {
      return const _NotificationVisual(
        icon: Icons.share_rounded,
        color: Color(0xFF7C3AED),
        label: 'Feed',
      );
    }
    if (_NotificationFilter.feed.matches(item)) {
      return const _NotificationVisual(
        icon: Icons.play_circle_outline_rounded,
        color: Color(0xFF7C3AED),
        label: 'Feed',
      );
    }
    return const _NotificationVisual(
      icon: Icons.campaign_rounded,
      color: Color(0xFF12A66A),
      label: 'Pengumuman',
    );
  }
}

String _notificationHaystack(AppNotification item) {
  return [
    item.type,
    item.category,
    item.source,
    item.eventType,
    item.status,
    item.url,
    item.title,
    item.body,
    item.shortDescription,
    item.ctaLabel,
  ].whereType<String>().join(' ').toLowerCase();
}

/// Ekstrak nomor pesanan (`ORD-...`) dari url notifikasi pesanan. Diikat ke
/// prefix `/pesanan/` atau `orderNumber=` (dua format url pesanan: order-status
/// pakai `/pesanan/{orderNumber}`, confirm-reminder/cancel pakai
/// `/member/order-detail?orderNumber=...`). Pengikatan ini mencegah slug produk
/// case-insensitive seperti `/products/bungee-cord-leash` salah-tangkap sebagai
/// "ord-leash" lalu misroute ke pesanan.
@visibleForTesting
String? extractOrderNumber(String? url) {
  if (url == null || url.isEmpty) return null;
  final match = RegExp(
    r'(?:/pesanan/|orderNumber=)(ORD-[A-Z0-9-]+)',
    caseSensitive: false,
  ).firstMatch(url);
  return match?.group(1);
}

/// Ekstrak trackingToken dari query `?token=` (akses order guest/non-login).
@visibleForTesting
String? extractOrderTrackingToken(String? url) {
  if (url == null || url.isEmpty) return null;
  final token = Uri.tryParse(url)?.queryParameters['token']?.trim();
  return (token == null || token.isEmpty) ? null : token;
}

/// 4 tab redesign (Semua/Aktivitas/Transaksi/Promo). Aktivitas = gabungan
/// filter lama Disebut + Feed + Pengumuman; Transaksi = Pesanan lama; Promo
/// tetap. Publik + @visibleForTesting supaya pemetaan bisa diuji unit.
@visibleForTesting
enum NotificationTab {
  all('Semua'),
  activity('Aktivitas'),
  transaction('Transaksi'),
  promo('Promo');

  final String label;
  const NotificationTab(this.label);

  bool matches(AppNotification item) {
    return switch (this) {
      NotificationTab.all => true,
      NotificationTab.activity => _isMentionNotification(item) ||
          _NotificationFilter.feed.matches(item) ||
          _isAnnouncementNotification(item),
      NotificationTab.transaction => _NotificationFilter.order.matches(item),
      NotificationTab.promo => _NotificationFilter.promo.matches(item),
    };
  }
}

/// Bucket waktu untuk header grup daftar notifikasi (berbasis HARI KALENDER
/// lokal, bukan selisih 24 jam — "kemarin 23:59" tetap KEMARIN walau baru
/// 31 menit berlalu).
@visibleForTesting
enum NotificationTimeBucket {
  today('HARI INI'),
  yesterday('KEMARIN'),
  thisWeek('MINGGU INI'),
  earlier('SEBELUMNYA');

  final String label;
  const NotificationTimeBucket(this.label);
}

@visibleForTesting
NotificationTimeBucket notificationTimeBucket(
    DateTime now, DateTime createdAt) {
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final dayDiff = today.difference(thatDay).inDays;
  if (dayDiff <= 0) return NotificationTimeBucket.today;
  if (dayDiff == 1) return NotificationTimeBucket.yesterday;
  if (dayDiff <= 7) return NotificationTimeBucket.thisWeek;
  return NotificationTimeBucket.earlier;
}

/// Waktu relatif SINGKAT ("20 jam", "3 hari") — satu-satunya timestamp baris
/// redesign. Beda dari formatRelativeTime (formatters.dart) yang berakhiran
/// "lalu"; di daftar padat, akhiran itu berulang & memanjangkan baris.
@visibleForTesting
String shortRelativeTime(DateTime now, DateTime past) {
  final diff = now.difference(past);
  if (diff.inMinutes < 1) return 'baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit';
  if (diff.inHours < 24) return '${diff.inHours} jam';
  if (diff.inDays < 7) return '${diff.inDays} hari';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} minggu';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} bulan';
  return '${(diff.inDays / 365).floor()} tahun';
}

String? _notificationCtaLabel(AppNotification item) {
  if (_isShopPromoNotification(item)) return 'Belanja Sekarang';
  if (_isPromoDetailNotification(item)) return 'Lihat Detail';
  if (_isFlashSaleNotification(item)) return 'Lihat Promo';
  if (_isVoucherNotification(item)) return 'Pakai Voucher';
  final label = item.ctaLabel?.trim();
  return label == null || label.isEmpty ? null : label;
}

bool _isAnnouncementNotification(AppNotification item) {
  final explicit = [
    item.type,
    item.category,
    item.source,
    item.eventType,
    item.status,
  ].whereType<String>().join(' ').toLowerCase();

  if (explicit.contains('announcement') ||
      explicit.contains('pengumuman') ||
      explicit.contains('broadcast') ||
      explicit.contains('newsletter')) {
    return true;
  }

  final url = item.url?.toLowerCase() ?? '';
  if (url.contains('/pengumuman') ||
      url.contains('/announcement') ||
      url.contains('/announcements')) {
    return true;
  }

  final text = [
    item.title,
    item.shortDescription,
    item.body,
    item.ctaLabel,
  ].whereType<String>().join(' ').toLowerCase();

  final looksLikeAnnouncement = text.contains('pengumuman') ||
      text.contains('perubahan jam operasional') ||
      text.contains('jam operasional');
  final announcementCta = text.contains('perbarui sekarang') ||
      text.contains('cek info') ||
      text.contains('lihat detail');
  final looksLikeOtherFlow = text.contains('pesanan') ||
      text.contains('order') ||
      text.contains('keranjang') ||
      text.contains('checkout') ||
      text.contains('feed') ||
      text.contains('komentar') ||
      text.contains('produk') ||
      text.contains('voucher') ||
      text.contains('promo');

  return looksLikeAnnouncement || (announcementCta && !looksLikeOtherFlow);
}

bool _isFlashSaleNotification(AppNotification item) {
  final text = _notificationHaystack(item);
  final url = item.url?.toLowerCase() ?? '';
  if (_isShopPromoNotification(item)) return false;
  if (_isPromoDetailNotification(item)) return false;
  return text.contains('flash sale') ||
      text.contains('flashsale') ||
      text.contains('flash_sale') ||
      url.contains('flash-sale') ||
      url.contains('flashsale');
}

bool _isPromoDetailNotification(AppNotification item) {
  final cta = item.ctaLabel?.trim().toLowerCase() ?? '';
  if (!cta.contains('lihat detail')) return false;

  final text = _notificationHaystack(item);
  return text.contains('promo') ||
      text.contains('diskon') ||
      text.contains('discount') ||
      text.contains('flash sale') ||
      text.contains('flashsale') ||
      text.contains('flash_sale');
}

bool _isShopPromoNotification(AppNotification item) {
  final cta = item.ctaLabel?.trim().toLowerCase() ?? '';
  if (!cta.contains('belanja sekarang')) return false;

  final text = _notificationHaystack(item);
  return text.contains('promo') ||
      text.contains('promosi') ||
      text.contains('diskon') ||
      text.contains('discount') ||
      text.contains('flash sale') ||
      text.contains('flashsale') ||
      text.contains('flash_sale');
}

bool _isVoucherNotification(AppNotification item) {
  final url = item.url?.toLowerCase() ?? '';
  if (url.contains('/member/vouchers') ||
      url.contains('/member/voucher') ||
      url.contains('/vouchers') ||
      url.contains('/voucher')) {
    return true;
  }

  final cta = item.ctaLabel?.trim().toLowerCase() ?? '';
  if (cta.contains('pakai voucher') ||
      cta.contains('lihat voucher') ||
      cta.contains('cek voucher')) {
    return true;
  }

  final explicit = [
    item.type,
    item.category,
    item.source,
    item.eventType,
    item.status,
  ].whereType<String>().join(' ').toLowerCase();

  return explicit.contains('voucher') && !explicit.contains('flash');
}

String? _toAbsoluteUrl(String url) {
  final value = url.trim();
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return value;
  }
  if (value.startsWith('/')) {
    return '${ApiConfig.publicSiteUrl}$value';
  }
  return '${ApiConfig.publicSiteUrl}/$value';
}

String _errorMessage(Object error) {
  if (error is ApiException) return error.message;
  final text = error.toString();
  if (text.contains('<!DOCTYPE html') ||
      text.contains('<html') ||
      text.contains('FormatException')) {
    return 'Server membalas halaman web, bukan data notifikasi. Cek API_BASE_URL atau endpoint notifikasi.';
  }
  return 'Koneksi notifikasi sedang tidak stabil. Coba lagi sebentar.';
}
