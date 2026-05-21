import 'dart:async';

import 'package:flutter/material.dart';

import '../models/member_profile.dart';
import '../services/member_service.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_notification_button.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/glass_surface.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/update_profile_photo_sheet.dart';

const _brandBlue = Color(0xFF0B7FEA);
const _pageBg = Color(0xFFF8FAFC);

class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key});

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  bool _redirectInProgress = false;

  @override
  void initState() {
    super.initState();
    memberStore.addListener(_evaluateRedirect);
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluateRedirect());
  }

  @override
  void dispose() {
    memberStore.removeListener(_evaluateRedirect);
    super.dispose();
  }

  Future<void> _evaluateRedirect() async {
    if (!mounted) return;
    if (memberStore.initializing && !memberStore.initialized) return;
    if (memberStore.isLoggedIn) {
      _redirectInProgress = false;
      return;
    }
    if (_redirectInProgress) return;
    _redirectInProgress = true;
    await Navigator.pushNamed(context, '/member/login');
    if (!mounted) return;
    _redirectInProgress = false;
    if (!memberStore.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _pageBg,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 1,
            shadowColor: Colors.black.withValues(alpha: 0.08),
            title: const Text(
              'Akun',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            actions: [
              const AppNotificationButton(),
              const SizedBox(width: 6),
              AppHeaderIconButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/account/settings'),
                tooltip: 'Pengaturan',
                child: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: memberStore.isLoggedIn
              ? const _MemberDashboard()
              : const _MemberLoadingView(),
          bottomNavigationBar: const BottomNavBar(currentIndex: 4),
        );
      },
    );
  }
}

class _MemberLoadingView extends StatelessWidget {
  const _MemberLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: _brandBlue, strokeWidth: 2.4),
    );
  }
}

class _MemberDashboard extends StatelessWidget {
  const _MemberDashboard();

  @override
  Widget build(BuildContext context) {
    final profile = memberStore.profile!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 116),
      children: [
        _MemberProfileCard(profile: profile),
        const SizedBox(height: 22),
        const _OrderStatusCard(),
        const SizedBox(height: 24),
        const _SectionTitle('Menu Transaksi'),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.18,
          children: const [
            _MenuCard(
              route: '/member/vouchers',
              icon: Icons.confirmation_number_rounded,
              iconColor: Color(0xFFF59E0B),
              iconBg: Color(0xFFFFF7E0),
              title: 'Voucher',
              subtitle: 'Promo member',
            ),
            _MenuCard(
              route: '/wishlist',
              icon: Icons.favorite_rounded,
              iconColor: Color(0xFFEF4444),
              iconBg: Color(0xFFFFE4E6),
              title: 'Wishlist',
              subtitle: 'Produk favorit',
            ),
            _MenuCard(
              route: '/member/reviews',
              icon: Icons.rate_review_rounded,
              iconColor: Color(0xFF8B5CF6),
              iconBg: Color(0xFFF3E8FF),
              title: 'Ulasan',
              subtitle: 'Ulas produk',
            ),
            _MenuCard(
              route: '/member/addresses',
              icon: Icons.location_on_rounded,
              iconColor: Color(0xFF22C55E),
              iconBg: Color(0xFFE8F8EC),
              title: 'Alamat',
              subtitle: 'Kelola pengiriman',
            ),
            _MenuCard(
              route: '/member/loyalty',
              icon: Icons.stars_rounded,
              iconColor: Color(0xFFFBBF24),
              iconBg: Color(0xFFFFF6CC),
              title: 'Tukar Poin',
              subtitle: 'Poin jadi voucher',
            ),
            _MenuCard(
              route: '/member/loyalty/history',
              icon: Icons.history_rounded,
              iconColor: Color(0xFF0EA5E9),
              iconBg: Color(0xFFE0F2FE),
              title: 'Riwayat Poin',
              subtitle: 'Riwayat masuk & tukar',
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _MyPostsCard(),
      ],
    );
  }
}

class _MemberProfileCard extends StatefulWidget {
  final MemberProfile profile;

  const _MemberProfileCard({required this.profile});

  @override
  State<_MemberProfileCard> createState() => _MemberProfileCardState();
}

class _MemberProfileCardState extends State<_MemberProfileCard> {
  late Future<int> _voucherCountFuture;

  @override
  void initState() {
    super.initState();
    _voucherCountFuture = _loadVoucherCount();
  }

  Future<int> _loadVoucherCount() async {
    try {
      final vouchers = await memberService.fetchVouchers();
      // Count yang masih applicable (belum expired + cukup minimum order
      // global = bisa dipakai). UI hanya butuh angka aktif.
      final now = DateTime.now();
      return vouchers
          .where((v) => v.applicable && v.expiresAt.isAfter(now))
          .length;
    } catch (_) {
      return 0;
    }
  }

  void _openUpdatePhoto() {
    AppHaptics.tap();
    showUpdateProfilePhotoSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final firstName = profile.name.split(' ').first;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B7FEA), Color(0xFF075CB5)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: _brandBlue.withValues(alpha: 0.26),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProfileAvatar(
                initial: profile.initial,
                imageUrl: profile.profilePhotoUrl,
                size: 72,
                fontSize: 28,
                showCameraBadge: true,
                // Tap avatar (atau camera badge) → buka bottom sheet
                // "Ubah Foto Profil". Single tappable area covering both
                // circle + camera icon via ProfileAvatar.onTap.
                onTap: _openUpdatePhoto,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Member Natalo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Halo, $firstName!',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Terima kasih sudah menjadi bagian dari Natalo Petshop.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.20),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ProfileStat(
                  value: '${profile.points}',
                  label: 'Poin loyalti',
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: Colors.white.withValues(alpha: 0.18),
              ),
              Expanded(
                child: FutureBuilder<int>(
                  future: _voucherCountFuture,
                  initialData: 0,
                  builder: (context, snapshot) {
                    return _ProfileStat(
                      value: '${snapshot.data ?? 0}',
                      label: 'Voucher aktif',
                      alignCenter: true,
                    );
                  },
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: Colors.white.withValues(alpha: 0.18),
              ),
              Expanded(
                child: _ProfileStat(
                  value: _formatMonthYear(profile.memberSince),
                  label: 'Member sejak',
                  alignRight: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  final bool alignRight;
  final bool alignCenter;

  const _ProfileStat({
    required this.value,
    required this.label,
    this.alignRight = false,
    this.alignCenter = false,
  });

  @override
  Widget build(BuildContext context) {
    final cross = alignCenter
        ? CrossAxisAlignment.center
        : (alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start);
    return Column(
      crossAxisAlignment: cross,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _OrderStatusCard extends StatefulWidget {
  const _OrderStatusCard();

  @override
  State<_OrderStatusCard> createState() => _OrderStatusCardState();
}

class _OrderStatusCardState extends State<_OrderStatusCard> {
  static const _pollInterval = Duration(seconds: 30);

  late Future<List<OrderSummary>> _ordersFuture;
  Timer? _pollTimer;
  bool _pollingRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _loadOrders();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refreshOrdersSilently());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<List<OrderSummary>> _loadOrders() async {
    try {
      return await memberService.fetchOrders();
    } catch (_) {
      return memberStore.orders;
    }
  }

  Future<void> _refreshOrdersSilently() async {
    if (!mounted || _pollingRefreshInFlight || !memberStore.isLoggedIn) return;
    _pollingRefreshInFlight = true;
    try {
      final orders = await _loadOrders();
      if (!mounted) return;
      setState(() {
        _ordersFuture = Future.value(orders);
      });
    } finally {
      _pollingRefreshInFlight = false;
    }
  }

  void _openOrdersByStatus(BuildContext context, String status) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/member/orders', arguments: status);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OrderSummary>>(
      future: _ordersFuture,
      initialData: memberStore.orders,
      builder: (context, snapshot) {
        final orders = snapshot.data ?? const <OrderSummary>[];
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final counts = loading && orders.isEmpty
            ? const _OrderStatusCounts.empty()
            : _OrderStatusCounts.fromOrders(orders);

        return GlassSurface(
          radius: 22,
          padding: const EdgeInsets.all(16),
          tint: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(child: _SectionTitle('Pesanan Saya')),
                  if (loading)
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/member/orders'),
                    child: const Text('Lihat semua'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _OrderStatusItem(
                    icon: Icons.account_balance_wallet_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    iconBg: const Color(0xFFFFF7E0),
                    label: 'Belum Bayar',
                    count: counts.unpaid,
                    onTap: () => _openOrdersByStatus(context, 'unpaid'),
                  ),
                  _OrderStatusItem(
                    icon: Icons.inventory_2_rounded,
                    iconColor: const Color(0xFF0B7FEA),
                    iconBg: const Color(0xFFEAF5FF),
                    label: 'Diproses',
                    count: counts.processing,
                    onTap: () => _openOrdersByStatus(context, 'processing'),
                  ),
                  _OrderStatusItem(
                    icon: Icons.local_shipping_rounded,
                    iconColor: const Color(0xFF22C55E),
                    iconBg: const Color(0xFFE8F8EC),
                    label: 'Dikirim',
                    count: counts.shipped,
                    onTap: () => _openOrdersByStatus(context, 'shipped'),
                  ),
                  _OrderStatusItem(
                    icon: Icons.check_circle_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                    iconBg: const Color(0xFFF3E8FF),
                    label: 'Selesai',
                    count: counts.recentCompleted,
                    onTap: () => _openOrdersByStatus(context, 'delivered'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderStatusCounts {
  final int unpaid;
  final int processing;
  final int shipped;
  final int recentCompleted;

  const _OrderStatusCounts({
    required this.unpaid,
    required this.processing,
    required this.shipped,
    required this.recentCompleted,
  });

  const _OrderStatusCounts.empty()
      : unpaid = 0,
        processing = 0,
        shipped = 0,
        recentCompleted = 0;

  factory _OrderStatusCounts.fromOrders(List<OrderSummary> orders) {
    final now = DateTime.now();
    var unpaid = 0;
    var processing = 0;
    var shipped = 0;
    var recentCompleted = 0;

    for (final order in orders) {
      final status = order.status.toUpperCase();
      final payment = order.paymentStatus.toUpperCase();

      if (status == 'PENDING' ||
          status == 'UNPAID' ||
          payment == 'UNPAID' ||
          payment == 'PENDING') {
        unpaid++;
        continue;
      }

      if (status == 'PAID' || status == 'PROCESSING') {
        processing++;
        continue;
      }

      if (status == 'SHIPPED') {
        shipped++;
        continue;
      }

      if (status == 'DELIVERED' || status == 'COMPLETED') {
        final completedDate = order.deliveredAt ??
            order.completedAt ??
            order.statusUpdatedAt ??
            order.updatedAt;
        if (completedDate != null) {
          final ageInDays = now.difference(completedDate).inDays;
          if (ageInDays >= 0 && ageInDays <= 7) {
            recentCompleted++;
          }
        }
      }
    }

    return _OrderStatusCounts(
      unpaid: unpaid,
      processing: processing,
      shipped: shipped,
      recentCompleted: recentCompleted,
    );
  }
}

class _OrderStatusItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _OrderStatusItem({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: _brandBlue.withValues(alpha: 0.08),
          highlightColor: _brandBlue.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: iconColor, size: 26),
                    ),
                    Positioned(
                      right: -5,
                      top: -5,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) {
                          return ScaleTransition(
                            scale: CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutBack,
                            ),
                            child: child,
                          );
                        },
                        child: count > 0
                            ? _OrderStatusBadge(
                                key: ValueKey(count),
                                count: count,
                              )
                            : const SizedBox.shrink(key: ValueKey('empty')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  final int count;

  const _OrderStatusBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      // Spec: badge angka di kanan atas WAJIB merah solid (#FF3B30 iOS-style),
      // bukan biru — biru sudah dipakai brand/active state.
      decoration: const BoxDecoration(
        color: Color(0xFFFF3B30),
        shape: BoxShape.circle,
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

/// Card menu transaksi — 2D colorful icon di tile pastel kecil.
/// Per spec: ukuran icon 24-30px, container 44-52px, label 13-14px.
class _MenuCard extends StatelessWidget {
  final String route;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color iconBg;

  const _MenuCard({
    required this.route,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = _brandBlue,
    this.iconBg = const Color(0xFFEAF5FF),
  });

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: () => Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(20),
      child: GlassSurface(
        radius: 20,
        padding: const EdgeInsets.all(14),
        tint: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF17202A),
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section "Galeri Feed Saya" — card compact yang mengarah ke halaman
/// daftar postingan user sendiri (BUKAN feed publik). Per user spec:
/// jangan empty state besar dengan "Belum ada postingan" + CTA "Buat
/// Postingan". Fokus utama section ini = arahkan user ke halaman miliknya.
///
/// Tap CTA → /member/posts → MemberPostsScreen yang punya tab/filter
/// untuk: tayang, menunggu review, ditolak, dll. Kondisi kosong di-handle
/// di halaman tujuan, BUKAN di section ini.
class _MyPostsCard extends StatelessWidget {
  const _MyPostsCard();

  static const _brandSoft = Color(0xFFDDEBFF); // border soft blue
  static const _ctaTextSize = 15.5;

  void _openMyPosts(BuildContext context) {
    AppHaptics.tap();
    Navigator.pushNamed(context, '/member/posts');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _brandSoft, width: 1),
        boxShadow: [
          BoxShadow(
            color: _brandBlue.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _FeedGalleryIcon(),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Galeri Feed Saya',
                      style: TextStyle(
                        color: Color(0xFF17202A),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Koleksi foto & video Feed kamu tersimpan rapi di sini.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // CTA outlined button — soft block tipis, BUKAN tombol biru
          // primary penuh. Text sedikit lebih besar 15.5px supaya readable
          // dan obvious sebagai action utama section ini.
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: () => _openMyPosts(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brandBlue,
                backgroundColor: const Color(0xFFF6FAFF),
                side: const BorderSide(color: _brandBlue, width: 1.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.format_list_bulleted_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Lihat Feed Saya',
                    style: TextStyle(
                      fontSize: _ctaTextSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedGalleryIcon extends StatelessWidget {
  const _FeedGalleryIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _brandBlue, width: 2),
            ),
            child: const Icon(
              Icons.image_rounded,
              color: _brandBlue,
              size: 22,
            ),
          ),
          Positioned(
            right: 7,
            bottom: 7,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF17202A),
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

String _formatMonthYear(DateTime date) {
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
  return '${months[date.month - 1]} ${date.year}';
}
