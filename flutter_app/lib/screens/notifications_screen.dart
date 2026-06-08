import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/app_notification.dart';
import '../models/feed_post.dart';
import '../models/product.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../services/notification_service.dart';
import '../services/product_service.dart';
import '../state/member_store.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import 'announcement_detail_screen.dart';
import 'in_app_browser_screen.dart';
import 'member_post_detail_screen.dart';

const _brandBlue = Color(0xFF1677FF);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NotificationResult? _result;
  Object? _error;
  _NotificationFilter _filter = _NotificationFilter.all;
  bool _loading = true;
  bool _markingAll = false;

  // Cache filtered list — avoid O(n) where().toList() di setiap build.
  // Diinvalidasi (set null) saat _result atau _filter berubah.
  List<AppNotification>? _cachedVisibleItems;

  @override
  void initState() {
    super.initState();
    _load();
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
    final filtered = items.where(_filter.matches).toList();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semua notifikasi ditandai sudah dibaca.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1400),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(error)),
          behavior: SnackBarBehavior.floating,
        ),
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
      final username = _extractProfileUsername(item.url);
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

    // Notif terkait 1 postingan spesifik (punya feedPostId, mis. "X
    // posting baru", komentar, like, mention) → buka postingan itu
    // langsung di dalam app, BUKAN feed utama / webview. Reuse infra
    // fetchPostById + MemberPostDetailScreen. Fallback ke feed kalau
    // postId kosong / fetch gagal.
    final feedPostId = item.feedPostId?.trim() ?? '';
    if (feedPostId.isNotEmpty) {
      await _openFeedPostInApp(feedPostId);
      return;
    }

    if (url.contains('/feed') || _NotificationFilter.feed.matches(item)) {
      await Navigator.pushNamed(context, '/feed');
      return;
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

  /// Fetch postingan by ID lalu buka MemberPostDetailScreen di dalam app.
  /// isOwner dihitung dari apakah viewer == author (post sendiri → bisa
  /// edit/hapus; post orang → viewer). Spinner saat fetch; fallback ke
  /// feed kalau postingan tidak ada / fetch gagal. Reuse infra deep-link.
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
      // Postingan dihapus / belum tayang / error → fallback ke feed utama.
      await Navigator.pushNamed(context, '/feed');
      return;
    }

    final myId = memberStore.profile?.id;
    final isOwner = myId != null && myId == post.author.id;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MemberPostDetailScreen(
          post: post!,
          authorName: post.author.displayName,
          authorPhotoUrl: post.author.profilePhotoUrl,
          authorInitial: post.author.initial,
          isOwner: isOwner,
        ),
      ),
    );
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

  /// Extract username dari URL pattern `/u/{username}` (deep link
  /// public profile). Lowercase karena DB username always lowercase.
  String? _extractProfileUsername(String? url) {
    if (url == null || url.isEmpty) return null;
    final match = RegExp(r'/u/([^/?#]+)').firstMatch(url);
    if (match == null) return null;
    final username = match.group(1)?.trim().toLowerCase() ?? '';
    if (username.isEmpty) return null;
    return Uri.decodeComponent(username);
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
          return const _NotifLoginRequiredScaffold();
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _NotificationHeader(
              unreadCount: unread,
              markingAll: _markingAll,
              onBack: () => Navigator.maybePop(context),
              onMarkAllRead: _markAllRead,
            ),
            _NotificationTabs(
              selected: _filter,
              onChanged: (filter) {
                AppHaptics.selection();
                setState(() {
                  _filter = filter;
                  _cachedVisibleItems = null; // invalidate — filter berubah
                });
              },
            ),
            Expanded(
              child: _buildContent(result),
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
      return _NotificationErrorState(
        message: _errorMessage(error),
        onRetry: _load,
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
            _NotificationEmptyState(filter: _filter),
          ],
        ),
      );
    }

    return NataloPawRefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return AppAnimatedEntrance(
            index: index,
            child: _NotificationTile(
              notification: item,
              onTap: () => _openNotification(item),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationHeader extends StatelessWidget {
  final int unreadCount;
  final bool markingAll;
  final VoidCallback onBack;
  final VoidCallback onMarkAllRead;

  const _NotificationHeader({
    required this.unreadCount,
    required this.markingAll,
    required this.onBack,
    required this.onMarkAllRead,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(6, 10, 12, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: cs.onSurface,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Notifikasi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Badge(
                        label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                        backgroundColor: const Color(0xFFE91E63),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Update pesanan, promo, dan pengumuman dari Natalo Petshop.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: unreadCount == 0 || markingAll ? null : onMarkAllRead,
            tooltip: 'Tandai semua sudah dibaca',
            icon: markingAll
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.done_all_rounded),
            color: unreadCount == 0 ? cs.onSurfaceVariant : cs.onSurface,
          ),
        ],
      ),
    );
  }
}

class _NotificationTabs extends StatelessWidget {
  final _NotificationFilter selected;
  final ValueChanged<_NotificationFilter> onChanged;

  const _NotificationTabs({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? cs.outlineVariant
                : const Color(0xFFE8EEF7),
          ),
        ),
      ),
      child: SizedBox(
        height: 54,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _NotificationFilter.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 18),
          itemBuilder: (context, index) {
            final filter = _NotificationFilter.values[index];
            final active = selected == filter;
            return InkWell(
              onTap: () => onChanged(filter),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      filter.label,
                      style: TextStyle(
                        color: active ? _brandBlue : cs.onSurfaceVariant,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    height: 3,
                    width: active ? 54 : 0,
                    decoration: BoxDecoration(
                      color: _brandBlue,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visual = _NotificationVisual.from(notification);
    final ctaLabel = _notificationCtaLabel(notification);
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: notification.read
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? cs.outlineVariant
                      : const Color(0xFFE8EEF7))
                  : _brandBlue.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(visual.icon, color: visual.color, size: 24),
                  ),
                  if (!notification.read)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        height: 10,
                        width: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE91E63),
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatRelativeTime(notification.createdAt),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (notification.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppStatusPill(
                          label: visual.label,
                          color: visual.color,
                          size: 10.5,
                        ),
                        Text(
                          formatDateTime(notification.createdAt),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (ctaLabel != null)
                          Text(
                            ctaLabel,
                            style: const TextStyle(
                              color: _brandBlue,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  final _NotificationFilter filter;

  const _NotificationEmptyState({required this.filter});

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
            filter.icon,
            color: _brandBlue,
            size: 40,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          filter == _NotificationFilter.all
              ? 'Belum ada notifikasi'
              : 'Belum ada ${filter.label.toLowerCase()}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Update terbaru dari Natalo akan muncul di sini.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _NotificationErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _NotificationErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 82,
              width: 82,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEF1),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.notifications_off_rounded,
                color: Color(0xFFE11D48),
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Notifikasi gagal dimuat',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _NotificationFilter {
  // Mention diletakkan di posisi #2 (priority tinggi) — match IG/TikTok
  // pattern di mana notifikasi mention lebih penting daripada like/comment
  // generic. User cek dulu siapa yang nyebutin sebelum browse lain.
  all('Semua', Icons.notifications_none_rounded),
  mention('Disebut', Icons.alternate_email_rounded),
  order('Pesanan', Icons.receipt_long_rounded),
  promo('Promo', Icons.confirmation_number_rounded),
  feed('Feed', Icons.play_circle_outline_rounded),
  announcement('Pengumuman', Icons.campaign_rounded);

  final String label;
  final IconData icon;

  const _NotificationFilter(this.label, this.icon);

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
      _NotificationFilter.feed => !isMention && (text.contains('feed') ||
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
    // Mention visual diutamakan — dedicated icon @ supaya user tau
    // visual cepat ini notif sosial. Match brand violet.
    if (_isMentionNotification(item)) {
      return const _NotificationVisual(
        icon: Icons.alternate_email_rounded,
        color: Color(0xFF5B5BD6),
        label: 'Disebut',
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
    if (_isVoucherNotification(item)) {
      return const _NotificationVisual(
        icon: Icons.confirmation_number_rounded,
        color: Color(0xFF16A34A),
        label: 'Voucher',
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

/// Login prompt yang tampil saat guest user masuk /notifications.
/// Pattern sama dengan _LoginRequiredScaffold di transactions_screen
/// — consistent UX cross-screen. Tap "Masuk Member" → pushNamed
/// /member/login, lalu AnimatedBuilder di parent screen auto-refresh
/// begitu login sukses.
class _NotifLoginRequiredScaffold extends StatelessWidget {
  const _NotifLoginRequiredScaffold();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? cs.surface : const Color(0xFFF6F9FF),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: cs.onSurface,
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Notifikasi',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _brandBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: _brandBlue,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Login dulu yuk',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Masuk member untuk lihat notifikasi pesanan, voucher, dan update lainnya.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/member/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Masuk Member',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
