import 'package:flutter/material.dart';

import '../models/member_profile.dart';
import '../services/member_service.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/glass_surface.dart';
import '../widgets/profile_avatar.dart';

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
              AppHeaderIconButton(
                onPressed: () => Navigator.pushNamed(context, '/notifications'),
                tooltip: 'Notifikasi',
                child: const Icon(Icons.notifications_none_rounded),
              ),
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
          bottomNavigationBar: const BottomNavBar(currentIndex: 3),
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
              icon: Icons.confirmation_number_outlined,
              title: 'Voucher',
              subtitle: 'Promo member',
            ),
            _MenuCard(
              route: '/wishlist',
              icon: Icons.favorite_border_rounded,
              title: 'Wishlist',
              subtitle: 'Produk favorit',
            ),
            _MenuCard(
              route: '/member/reviews',
              icon: Icons.rate_review_outlined,
              title: 'Review',
              subtitle: 'Ulas produk',
            ),
            _MenuCard(
              route: '/member/addresses',
              icon: Icons.location_on_outlined,
              title: 'Alamat',
              subtitle: 'Kelola pengiriman',
            ),
            _MenuCard(
              route: '/member/loyalty',
              icon: Icons.stars_rounded,
              title: 'Tukar Poin',
              subtitle: 'Poin jadi voucher',
            ),
            _MenuCard(
              route: '/member/loyalty/history',
              icon: Icons.history_rounded,
              title: 'Riwayat Poin',
              subtitle: 'Earn & redeem',
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Feed Saya'),
        const SizedBox(height: 12),
        _FeedTile(
          icon: Icons.play_circle_outline_rounded,
          title: 'Postingan Saya',
          subtitle: 'Kelola video Feed yang kamu upload',
          onTap: () => Navigator.pushNamed(context, '/member/postingan'),
        ),
        const SizedBox(height: 12),
        const _UploadVideoCta(),
      ],
    );
  }
}

class _MemberProfileCard extends StatelessWidget {
  final MemberProfile profile;

  const _MemberProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
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
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProfileAvatar(
                initial: profile.initial,
                imageUrl: profile.profilePhotoUrl,
                size: 70,
                fontSize: 26,
                showCameraBadge: true,
                onTap: () => Navigator.pushNamed(context, '/member/profile'),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Halo, $firstName!',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Senang melihatmu kembali di Natalo',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.20),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ProfileStat(
                  value: '${profile.points}',
                  label: 'Loyalty point',
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

  const _ProfileStat({
    required this.value,
    required this.label,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 12,
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
  late Future<List<OrderSummary>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _loadOrders();
  }

  Future<List<OrderSummary>> _loadOrders() async {
    try {
      return await memberService.fetchOrders();
    } catch (_) {
      return memberStore.orders;
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
                    icon: Icons.credit_card_rounded,
                    label: 'Belum Bayar',
                    count: counts.unpaid,
                    onTap: () => _openOrdersByStatus(context, 'unpaid'),
                  ),
                  _OrderStatusItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Diproses',
                    count: counts.processing,
                    onTap: () => _openOrdersByStatus(context, 'processing'),
                  ),
                  _OrderStatusItem(
                    icon: Icons.local_shipping_outlined,
                    label: 'Dikirim',
                    count: counts.shipped,
                    onTap: () => _openOrdersByStatus(context, 'shipped'),
                  ),
                  _OrderStatusItem(
                    icon: Icons.check_circle_outline_rounded,
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
  final String label;
  final int count;
  final VoidCallback onTap;

  const _OrderStatusItem({
    required this.icon,
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
                      height: 46,
                      width: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF5FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: _brandBlue, size: 23),
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
      decoration: const BoxDecoration(
        color: Color(0xFFFF2D3D),
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

class _MenuCard extends StatelessWidget {
  final String route;
  final IconData icon;
  final String title;
  final String subtitle;

  const _MenuCard({
    required this.route,
    required this.icon,
    required this.title,
    required this.subtitle,
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
            SoftIconTile(icon: icon, color: _brandBlue, size: 42),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF17202A),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
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

class _FeedTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: GlassSurface(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        tint: Colors.white,
        child: Row(
          children: [
            SoftIconTile(icon: icon, color: _brandBlue, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF17202A),
                      fontSize: 15,
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
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _UploadVideoCta extends StatelessWidget {
  const _UploadVideoCta();

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: () {
        AppHaptics.tap();
        Navigator.pushNamed(context, '/feed', arguments: {'openUpload': true});
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B7FEA), Color(0xFF075CB5)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _brandBlue.withValues(alpha: 0.26),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.videocam_rounded,
                color: Colors.white,
                size: 23,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Upload Video',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Bagikan momen seru hewan peliharaanmu',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ],
        ),
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
