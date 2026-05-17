import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/deep_link_service.dart';
import '../services/notification_service.dart';
import '../utils/haptics.dart';
import '../widgets/app_motion.dart';
import '../widgets/app_ui.dart';
import 'announcement_detail_screen.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _accentPurple = Color(0xFF8B5CF6);

/// Notifications screen — match Capacitor APK screenshot:
/// - Custom title "Notifikasi" + subtitle
/// - 5 tab bar: Semua / Pesanan / Promo / Feed / Pengumuman (active dengan underline biru)
/// - Notification cards dengan PURPLE left-border accent + megaphone/icon ungu
/// - Dark pill "Lihat Detail >" button di setiap card
/// - Blue dot indicator kalau unread (di kanan atas)
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<NotificationResult> _future;
  int _tabIndex = 0;

  static const _tabs = [
    _NotifTab(label: 'Semua', filter: null),
    _NotifTab(label: 'Pesanan', filter: 'order'),
    _NotifTab(label: 'Promo', filter: 'promo'),
    _NotifTab(label: 'Feed', filter: 'feed'),
    _NotifTab(label: 'Pengumuman', filter: 'announcement'),
  ];

  @override
  void initState() {
    super.initState();
    _future = notificationService.fetchMine();
  }

  Future<void> _refresh() async {
    setState(() => _future = notificationService.fetchMine());
    await _future;
  }

  Future<void> _markAllRead() async {
    AppHaptics.tap();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await notificationService.markAllRead();
      if (!mounted) return;
      AppHaptics.success();
      setState(() => _future = notificationService.fetchMine());
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Semua notifikasi ditandai sudah dibaca.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openNotification(AppNotification item) {
    AppHaptics.tap();
    unawaited(notificationService.markRead(item.id).catchError((_) {}));
    final routed = _routeNotification(item);
    setState(() => _future = notificationService.fetchMine());
    if (routed) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AnnouncementDetailScreen(notification: item),
      ),
    );
  }

  bool _routeNotification(AppNotification item) {
    final url = item.url?.trim();
    if (url != null && url.isNotEmpty) {
      try {
        unawaited(
          deepLinkService.handleExternalUri(Uri.parse(url)).catchError((_) {}),
        );
        return true;
      } catch (_) {}
    }

    final haystack = [
      item.type,
      item.category,
      item.source,
      item.eventType,
      item.status,
      item.title,
      item.body,
    ].whereType<String>().join(' ').toLowerCase();

    if (item.feedPostId != null ||
        haystack.contains('feed') ||
        haystack.contains('comment') ||
        haystack.contains('komentar')) {
      Navigator.pushNamed(context, '/feed');
      return true;
    }
    if (haystack.contains('order') ||
        haystack.contains('pesanan') ||
        haystack.contains('payment') ||
        haystack.contains('pembayaran')) {
      Navigator.pushNamed(context, '/member/orders');
      return true;
    }
    if (haystack.contains('voucher') || haystack.contains('promo')) {
      Navigator.pushNamed(context, '/member/vouchers');
      return true;
    }
    if (haystack.contains('review') || haystack.contains('ulasan')) {
      Navigator.pushNamed(context, '/member/reviews');
      return true;
    }
    if (haystack.contains('point') ||
        haystack.contains('poin') ||
        haystack.contains('loyalty')) {
      Navigator.pushNamed(context, '/member/loyalty');
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF17202A)),
          onPressed: () => Navigator.maybePop(context),
        ),
        toolbarHeight: 72,
        titleSpacing: 0,
        actions: [
          IconButton(
            onPressed: _markAllRead,
            tooltip: 'Tandai semua dibaca',
            icon: const Icon(
              Icons.done_all_rounded,
              color: Color(0xFF17202A),
            ),
          ),
        ],
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Notifikasi',
              style: TextStyle(
                color: Color(0xFF17202A),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Update pesanan, promo, dan pengumuman dari Natalo Petshop.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<NotificationResult>(
        future: _future,
        builder: (context, snapshot) {
          final result = snapshot.data;
          final isLoading =
              snapshot.connectionState == ConnectionState.waiting &&
                  result == null;
          final items = result?.items ?? [];
          final activeFilter = _tabs[_tabIndex].filter;
          final filtered = activeFilter == null
              ? items
              : items
                  .where(
                      (item) => item.type.toLowerCase().contains(activeFilter))
                  .toList();

          return Column(
            children: [
              // ── Tab bar horizontal scroll ──
              _NotifTabBar(
                tabs: _tabs,
                activeIndex: _tabIndex,
                onTap: (index) {
                  AppHaptics.tap();
                  setState(() => _tabIndex = index);
                },
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(
                child: isLoading
                    ? const AppSkeletonList(itemCount: 5)
                    : snapshot.hasError
                        ? _NotificationMessage(
                            title: 'Notifikasi belum tersedia',
                            body: snapshot.error.toString(),
                            onRefresh: _refresh,
                          )
                        : filtered.isEmpty
                            ? _NotificationMessage(
                                title: activeFilter == null
                                    ? 'Belum ada notifikasi'
                                    : 'Belum ada di tab ini',
                                body: activeFilter == null
                                    ? 'Update promo dan pesanan akan muncul di sini.'
                                    : 'Pindah tab atau cek lagi nanti.',
                                onRefresh: _refresh,
                              )
                            : RefreshIndicator(
                                onRefresh: _refresh,
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 14, 16, 28),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    return _NotificationCard(
                                      item: filtered[index],
                                      index: index,
                                      onOpen: _openNotification,
                                    );
                                  },
                                ),
                              ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotifTab {
  final String label;
  final String? filter;
  const _NotifTab({required this.label, required this.filter});
}

class _NotifTabBar extends StatelessWidget {
  final List<_NotifTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTap;

  const _NotifTabBar({
    required this.tabs,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final active = index == activeIndex;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active ? _brandBlue : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Center(
                  child: Text(
                    tabs[index].label,
                    style: TextStyle(
                      color: active ? _brandBlue : const Color(0xFF9CA3AF),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification item;
  final int index;

  /// Callback ke parent untuk handle tap "Lihat Detail" — parent yang
  /// punya navigation context + mark-read state.
  final ValueChanged<AppNotification> onOpen;

  const _NotificationCard({
    required this.item,
    required this.index,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    // Notifikasi pengumuman pakai purple accent, lainnya brand-blue.
    final isAnnouncement = item.type.toLowerCase().contains('announcement') ||
        item.type.toLowerCase().contains('pengumuman');
    final accent = isAnnouncement ? _accentPurple : _brandBlue;
    final icon = _iconFor(item.type);

    return AppAnimatedEntrance(
      index: index,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEF3FB)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF111111).withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Purple/blue left-border strip — accent visual ala PWA ──
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 38,
                          width: 38,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, color: accent, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  color: Color(0xFF17202A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _typeLabel(item.type),
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!item.read)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            height: 10,
                            width: 10,
                            decoration: const BoxDecoration(
                              color: _brandBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.body,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _formatRelativeDate(item.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── Dark pill "Lihat Detail >" ──
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () => onOpen(item),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF111111),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Lihat Detail'),
                            SizedBox(width: 4),
                            Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationMessage extends StatelessWidget {
  final String title;
  final String body;
  final Future<void> Function() onRefresh;

  const _NotificationMessage({
    required this.title,
    required this.body,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const AppLottieAsset(
            asset: 'assets/lottie/empty_box.json',
            size: 132,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF17202A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(String type) {
  final normalized = type.toLowerCase();
  if (normalized.contains('order')) return Icons.receipt_long_outlined;
  if (normalized.contains('promo')) return Icons.local_offer_outlined;
  if (normalized.contains('feed')) return Icons.play_circle_outline_rounded;
  return Icons.campaign_outlined;
}

String _typeLabel(String type) {
  final normalized = type.toLowerCase();
  if (normalized.contains('order')) return 'Update Pesanan';
  if (normalized.contains('promo')) return 'Promo Spesial';
  if (normalized.contains('feed')) return 'Konten Feed';
  return 'Pengumuman dari Admin';
}

/// Format tanggal relatif singkat (kemarin / X hari lalu / tanggal lengkap).
String _formatRelativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 1) return 'baru saja';
  if (diff.inHours < 1) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays == 1) return 'kemarin';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
