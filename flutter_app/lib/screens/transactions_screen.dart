import 'dart:async';

import 'package:flutter/material.dart';

import '../models/member_profile.dart';
import '../services/member_service.dart';
import '../state/member_store.dart';
import '../utils/haptics.dart';
import '../widgets/app_cart_button.dart';
import '../widgets/app_ui.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/glass_surface.dart';

/// Halaman Transaksi — hub utama untuk semua transaksi user.
///
/// Berisi:
///  - Card "Pesanan Saya" dengan 4 status shortcut + badge count real-time
///  - Grid "Menu Transaksi" 2 kolom: Voucher / Wishlist / Ulasan / Alamat
///    / Tukar Poin / Riwayat Poin
///
/// Konten ini sebelumnya ada di MemberScreen (Akun tab). Sekarang
/// di-pindahkan ke tab Transaksi tersendiri supaya Akun bisa fokus
/// jadi halaman profil sosial / postingan user (roadmap user).
///
/// CATATAN: code di file ini DUPLIKAT dari member_screen.dart sesuai
/// instruksi user (jangan touch MemberScreen sampai redesign formal).
/// Saat MemberScreen di-redesign nanti, section Pesanan Saya + menu
/// grid di sana bisa dihapus, ini tetap berdiri sendiri.
const _brandBlue = Color(0xFF0B7FEA);
const _pageBg = Color(0xFFF8FAFC);

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Login required — mirip MemberScreen, kalau belum login redirect
    // ke /member/login. Pakai memberStore.isLoggedIn live listener
    // supaya kalau user logout dari halaman lain, screen auto-respond.
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        if (!memberStore.isLoggedIn) {
          return _LoginRequiredScaffold();
        }
        return Scaffold(
          backgroundColor: _pageBg,
          appBar: _TransactionsHeader(),
          body: const SafeArea(
            top: false,
            child: _TransactionsBody(),
          ),
          bottomNavigationBar: const BottomNavBar(currentIndex: 3),
        );
      },
    );
  }
}

class _TransactionsHeader extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: _pageBg,
      surfaceTintColor: _pageBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      title: const Text(
        'Transaksi',
        style: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      actions: const [
        // Cart icon dengan item count badge — reuse komponen existing yang
        // listen cartStore + auto-update saat item add/remove. Tap → /cart.
        AppCartButton(),
        SizedBox(width: 8),
      ],
    );
  }
}

class _TransactionsBody extends StatelessWidget {
  const _TransactionsBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 116),
      children: const [
        _OrderStatusCard(),
        SizedBox(height: 24),
        _SectionTitle('Menu Transaksi'),
        SizedBox(height: 12),
        _MenuGrid(),
      ],
    );
  }
}

class _LoginRequiredScaffold extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        surfaceTintColor: _pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const Text(
          'Transaksi',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              color: _brandBlue,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Login dulu yuk',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Masuk untuk lihat pesanan, voucher, dan menu transaksi lainnya.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
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
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
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
    );
  }
}

// ─── Order status card — duplikat dari member_screen.dart ───────────

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

// ─── Menu card — duplikat dari member_screen.dart ──────────────────

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
