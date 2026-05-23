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
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 116),
      children: const [
        // Unpaid order alert banner — visible HANYA kalau ada pesanan
        // status UNPAID/PENDING (non-cancelled + non-expired). Auto-hide
        // sendiri kalau no data via SizedBox.shrink di build. Banner
        // ini mengganti pola "Perlu Tindakan" section lama supaya UI
        // halaman Transaksi tetap compact + premium.
        _UnpaidOrderBanner(),
        _OrderStatusCard(),
        SizedBox(height: 24),
        _SectionTitle('Menu Transaksi'),
        SizedBox(height: 12),
        _MenuGrid(),
      ],
    );
  }
}

/// Compact banner di atas "Pesanan Saya" untuk surface pesanan yang
/// belum dibayar (status UNPAID/PENDING) — dengan countdown sisa waktu
/// pembayaran (24 jam dari createdAt).
///
/// Behavior:
/// - Fetch orders sendiri via memberService.fetchOrders() — independent
///   dari _OrderStatusCard (acceptable duplication karena 2 widget life
///   cycle berbeda + cache memberStore.orders shared antar fetch).
/// - Filter: paymentStatus UNPAID/PENDING ATAU status PENDING/UNPAID,
///   skip CANCELLED/REFUNDED. Match logic _OrderStatusCounts.fromOrders.
/// - Skip expired (>24h dari createdAt) — assume backend auto-cancel.
/// - Sort ASC by createdAt → ambil paling urgent (paling dekat deadline).
/// - Countdown ticker 30s — format "XXj YYm" cukup, no per-second update.
/// - Tap routing: 1 unpaid → buka detail order; ≥2 unpaid → buka list
///   filter status=unpaid.
/// - Auto-hide kalau no valid unpaid order.
class _UnpaidOrderBanner extends StatefulWidget {
  const _UnpaidOrderBanner();

  @override
  State<_UnpaidOrderBanner> createState() => _UnpaidOrderBannerState();
}

class _UnpaidOrderBannerState extends State<_UnpaidOrderBanner> {
  /// Total durasi pembayaran sejak order dibuat. Match server-side window.
  static const _paymentWindow = Duration(hours: 24);

  /// Refresh interval countdown display. 30 detik cukup karena format
  /// jam+menit tidak butuh granularity per-detik.
  static const _tickInterval = Duration(seconds: 30);

  Future<List<OrderSummary>>? _ordersFuture;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (memberStore.isLoggedIn) {
      _ordersFuture = _loadOrders();
    }
    // Tick periodic supaya countdown update tanpa harus reload data.
    _tick = Timer.periodic(_tickInterval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<List<OrderSummary>> _loadOrders() async {
    try {
      return await memberService.fetchOrders();
    } catch (_) {
      return memberStore.orders;
    }
  }

  /// Identifies orders dalam status belum bayar yang masih valid
  /// (belum expired + bukan cancelled). Mirror _OrderStatusCounts logic
  /// di-tambah expiration check.
  List<OrderSummary> _unpaidOrders(List<OrderSummary> orders) {
    final now = DateTime.now();
    return orders.where((order) {
      final status = order.status.toUpperCase();
      final payment = order.paymentStatus.toUpperCase();
      if (status == 'CANCELLED' || status == 'REFUNDED') return false;
      final isUnpaid = status == 'PENDING' ||
          status == 'UNPAID' ||
          payment == 'UNPAID' ||
          payment == 'PENDING';
      if (!isUnpaid) return false;
      // Skip expired — anggap backend auto-cancel order yang lewat 24h.
      final deadline = order.createdAt.add(_paymentWindow);
      return deadline.isAfter(now);
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Format countdown "XXj YYm" untuk deadline pembayaran. Saat sisa <1
  /// jam, ubah ke "YYm" supaya angka jam tidak "0j" awkward.
  String _formatCountdown(Duration remaining) {
    if (remaining.isNegative) return '0m';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours <= 0) return '${minutes}m';
    return '${hours}j ${minutes}m';
  }

  void _handleTap(List<OrderSummary> unpaid) {
    AppHaptics.tap();
    if (unpaid.isEmpty) return;
    if (unpaid.length == 1) {
      // Single unpaid → langsung buka detail order.
      Navigator.pushNamed(
        context,
        '/member/order-detail',
        arguments: unpaid.first,
      );
    } else {
      // Multiple unpaid → buka list filter status=unpaid.
      Navigator.pushNamed(context, '/member/orders', arguments: 'unpaid');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!memberStore.isLoggedIn) return const SizedBox.shrink();
    return FutureBuilder<List<OrderSummary>>(
      future: _ordersFuture,
      initialData: memberStore.orders,
      builder: (context, snapshot) {
        final orders = snapshot.data ?? const <OrderSummary>[];
        final unpaid = _unpaidOrders(orders);
        if (unpaid.isEmpty) return const SizedBox.shrink();

        final mostUrgent = unpaid.first;
        final deadline = mostUrgent.createdAt.add(_paymentWindow);
        final remaining = deadline.difference(DateTime.now());
        if (remaining.isNegative) {
          // Defensive: edge case kalau order expire di antara filter +
          // build (race condition). Hide banner.
          return const SizedBox.shrink();
        }

        final count = unpaid.length;
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _handleTap(unpaid),
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: BoxDecoration(
                  // Soft warm tint (cream/orange) — match mockup user.
                  // Tidak terlalu agresif seperti red error, tetap feel
                  // premium + ramah.
                  color: const Color(0xFFFFF7EC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFFE0B0),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Icon wallet di kiri — soft orange container.
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBC9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Color(0xFFF59E0B),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Text column — main + secondary.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$count pesanan belum dibayar',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Selesaikan pembayaran dalam 24 jam',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Countdown pill — orange emphasis.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE0B0),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: Color(0xFFB45309),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatCountdown(remaining),
                              style: const TextStyle(
                                color: Color(0xFFB45309),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF94A3B8),
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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

      // BUG FIX: skip order yang sudah CANCELLED/REFUNDED. Tanpa cek ini,
      // order dibatalkan dengan paymentStatus UNPAID/PENDING ikut ke-count
      // sebagai "Belum Bayar" — badge angka jadi salah.
      if (status == 'CANCELLED' || status == 'REFUNDED') {
        continue;
      }

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
