import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/app_notification.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/natalo_paw_refresh_indicator.dart';
import 'announcement_detail_screen.dart';
import 'in_app_browser_screen.dart';

const _brandBlue = Color(0xFF1677FF);
const _textDark = Color(0xFF111827);
const _textGray = Color(0xFF667085);
const _pageBg = Color(0xFFF6F9FF);
const _border = Color(0xFFE8EEF7);

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
    final items = _result?.items ?? const <AppNotification>[];
    return items.where(_filter.matches).toList();
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

    if (_isAnnouncementNotification(item)) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AnnouncementDetailScreen(notification: item),
        ),
      );
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

    if (url.contains('/feed') ||
        item.feedPostId?.isNotEmpty == true ||
        _NotificationFilter.feed.matches(item)) {
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

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final unread = result?.unreadCount ?? 0;

    return Scaffold(
      backgroundColor: _pageBg,
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
                setState(() => _filter = filter);
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
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(6, 10, 12, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: _textDark,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Notifikasi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textDark,
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
                const Text(
                  'Update pesanan, promo, dan pengumuman dari Natalo Petshop.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textGray,
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
            color: unreadCount == 0 ? const Color(0xFF98A2B3) : _textDark,
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _border)),
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
                        color: active ? _brandBlue : const Color(0xFF98A2B3),
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

    return Material(
      color: Colors.white,
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
                  ? _border
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
                          border: Border.all(color: Colors.white, width: 2),
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
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatRelativeTime(notification.createdAt),
                          style: const TextStyle(
                            color: Color(0xFF98A2B3),
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
                        style: const TextStyle(
                          color: _textGray,
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
                          style: const TextStyle(
                            color: Color(0xFF98A2B3),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (notification.ctaLabel?.trim().isNotEmpty == true)
                          Text(
                            notification.ctaLabel!,
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
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF98A2B3),
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
          style: const TextStyle(
            color: _textDark,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Update terbaru dari Natalo akan muncul di sini.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _textGray,
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
            const Text(
              'Notifikasi gagal dimuat',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textDark,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textGray,
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
  all('Semua', Icons.notifications_none_rounded),
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
    return switch (this) {
      _NotificationFilter.order => text.contains('order') ||
          text.contains('pesanan') ||
          text.contains('payment') ||
          text.contains('pembayaran') ||
          text.contains('checkout') ||
          text.contains('shipped') ||
          text.contains('dikirim'),
      _NotificationFilter.promo => text.contains('promo') ||
          text.contains('voucher') ||
          text.contains('diskon') ||
          text.contains('discount') ||
          text.contains('coupon') ||
          text.contains('gratis ongkir'),
      _NotificationFilter.feed => text.contains('feed') ||
          text.contains('video') ||
          text.contains('post') ||
          text.contains('comment') ||
          text.contains('komentar') ||
          text.contains('like') ||
          text.contains('share') ||
          text.contains('approved') ||
          text.contains('rejected'),
      _NotificationFilter.announcement => _isAnnouncementNotification(item),
      _NotificationFilter.all => true,
    };
  }
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
    if (_NotificationFilter.order.matches(item)) {
      return const _NotificationVisual(
        icon: Icons.receipt_long_rounded,
        color: _brandBlue,
        label: 'Pesanan',
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
